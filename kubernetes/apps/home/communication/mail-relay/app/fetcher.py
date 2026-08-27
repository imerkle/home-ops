import os
import sys
import time
import logging
import requests
import boto3
from botocore.config import Config
from urllib.parse import urljoin, urlparse

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s [%(levelname)s] %(message)s',
    datefmt='%Y-%m-%d %H:%M:%S',
    stream=sys.stdout
)
logger = logging.getLogger("email-fetcher")

R2_ACCOUNT_ID = os.environ.get('R2_ACCOUNT_ID')
R2_BUCKET = os.environ.get('R2_BUCKET', 'home-ops-email-inbox')
AWS_ACCESS_KEY_ID = os.environ.get('AWS_ACCESS_KEY_ID')
AWS_SECRET_ACCESS_KEY = os.environ.get('AWS_SECRET_ACCESS_KEY')
AWS_DEFAULT_REGION = os.environ.get('AWS_DEFAULT_REGION', 'auto')

STALWART_URL = os.environ.get('STALWART_URL', 'http://stalwart-stalwart-mail.home-system.svc.cluster.local:80/.well-known/jmap')
STALWART_TOKEN = os.environ.get('STALWART_TOKEN', '')
STALWART_LOGIN_USER = os.environ.get('STALWART_LOGIN_USER', 'admin')
POLL_INTERVAL = int(os.environ.get('POLL_INTERVAL', '30'))

R2_ENDPOINT = f"https://{R2_ACCOUNT_ID}.r2.cloudflarestorage.com" if R2_ACCOUNT_ID else None

# Setup S3 / R2 client
s3_client = None
if AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY and R2_ENDPOINT:
    s3_client = boto3.client(
        's3',
        endpoint_url=R2_ENDPOINT,
        aws_access_key_id=AWS_ACCESS_KEY_ID,
        aws_secret_access_key=AWS_SECRET_ACCESS_KEY,
        region_name=AWS_DEFAULT_REGION,
        config=Config(signature_version='s3v4')
    )
else:
    logger.warning("R2 credentials not fully initialized; waiting for secrets.")

def get_auth_headers_and_auth():
    headers = {}
    auth = None
    if STALWART_LOGIN_USER and STALWART_TOKEN:
        auth = (STALWART_LOGIN_USER, STALWART_TOKEN)
    elif STALWART_TOKEN:
        headers["Authorization"] = f"Bearer {STALWART_TOKEN}"
    return headers, auth

def get_jmap_session():
    headers, auth = get_auth_headers_and_auth()
    logger.info(f"Connecting to Stalwart JMAP at {STALWART_URL}...")
    resp = requests.get(STALWART_URL, auth=auth, headers=headers, timeout=15, allow_redirects=True)
    if resp.status_code != 200:
        logger.error(f"Failed to fetch JMAP session. Status: {resp.status_code}, Response: {resp.text}")
        return None

    session = resp.json()
    account_id = session.get('primaryAccounts', {}).get('urn:ietf:params:jmap:mail')
    if not account_id:
        # Fallback to first available mail account in accounts map
        accounts = session.get('accounts', {})
        for acc_id, acc_data in accounts.items():
            if 'urn:ietf:params:jmap:mail' in acc_data.get('accountCapabilities', {}):
                account_id = acc_id
                break

    if not account_id:
        logger.error("No mail account ID found in Stalwart JMAP session response.")
        return None

    # Base URL handling
    api_url_raw = session.get('apiUrl', '')
    upload_url_raw = session.get('uploadUrl', '')
    
    # Check if relative path or absolute URL
    if api_url_raw.startswith('/'):
        stalwart_base = STALWART_URL.split('/.well-known')[0]
        api_url = urljoin(stalwart_base, api_url_raw)
        upload_url = urljoin(stalwart_base, upload_url_raw).replace("{accountId}", account_id)
    else:
        api_url = api_url_raw
        upload_url = upload_url_raw.replace("{accountId}", account_id)

    return {
        "account_id": account_id,
        "api_url": api_url,
        "upload_url": upload_url
    }

def get_inbox_id(session_info):
    headers, auth = get_auth_headers_and_auth()
    headers["Content-Type"] = "application/json"
    
    payload = {
        "using": ["urn:ietf:params:jmap:core", "urn:ietf:params:jmap:mail"],
        "methodCalls": [
            ["Mailbox/get", {"accountId": session_info["account_id"]}, "0"]
        ]
    }

    resp = requests.post(session_info["api_url"], auth=auth, headers=headers, json=payload, timeout=15)
    if resp.status_code != 200:
        logger.error(f"Failed to fetch mailboxes. Status: {resp.status_code}")
        return None

    mb_data = resp.json()
    try:
        mailboxes = mb_data['methodResponses'][0][1].get('list', [])
        for mb in mailboxes:
            if mb.get('role') == 'inbox' or mb.get('name', '').lower() == 'inbox':
                return mb['id']
        # If no explicit inbox found, return the first mailbox
        if mailboxes:
            return mailboxes[0]['id']
    except Exception as e:
        logger.error(f"Error parsing mailbox list: {e}")
        return None

    return None

def fetch_and_process_emails():
    global s3_client
    if not s3_client:
        if AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY and R2_ENDPOINT:
            s3_client = boto3.client(
                's3',
                endpoint_url=R2_ENDPOINT,
                aws_access_key_id=AWS_ACCESS_KEY_ID,
                aws_secret_access_key=AWS_SECRET_ACCESS_KEY,
                region_name=AWS_DEFAULT_REGION,
                config=Config(signature_version='s3v4')
            )
        else:
            logger.warning("R2 credentials not set. Skipping fetch cycle.")
            return

    session_info = get_jmap_session()
    if not session_info:
        return

    inbox_id = get_inbox_id(session_info)
    if not inbox_id:
        logger.error("Could not find a valid Inbox ID in Stalwart.")
        return

    # List objects in R2
    try:
        objects_resp = s3_client.list_objects_v2(Bucket=R2_BUCKET)
    except Exception as e:
        logger.error(f"Failed to list objects in R2 bucket {R2_BUCKET}: {e}")
        return

    contents = objects_resp.get('Contents', [])
    if not contents:
        logger.debug("No new emails in R2 bucket.")
        return

    logger.info(f"Found {len(contents)} email(s) in R2 bucket. Processing...")
    headers, auth = get_auth_headers_and_auth()

    for obj in contents:
        file_key = obj['Key']
        logger.info(f"Processing email: {file_key}")

        # Download from R2
        try:
            r2_obj = s3_client.get_object(Bucket=R2_BUCKET, Key=file_key)
            blob_data = r2_obj['Body'].read()
        except Exception as e:
            logger.error(f"Failed to download {file_key} from R2: {e}")
            continue

        # Upload blob to Stalwart
        up_headers = dict(headers)
        up_headers["Content-Type"] = "message/rfc822"
        try:
            up_resp = requests.post(session_info["upload_url"], auth=auth, headers=up_headers, data=blob_data, timeout=30)
        except Exception as e:
            logger.error(f"Failed to upload blob {file_key} to Stalwart: {e}")
            continue

        if up_resp.status_code not in (200, 201):
            logger.error(f"Stalwart upload error for {file_key}. Status: {up_resp.status_code}, Response: {up_resp.text}")
            continue

        up_data = up_resp.json()
        blob_id = up_data.get('blobId')
        if not blob_id:
            logger.error(f"No blobId returned from Stalwart for {file_key}")
            continue

        # Import blob into Inbox
        import_headers = dict(headers)
        import_headers["Content-Type"] = "application/json"
        import_payload = {
            "using": ["urn:ietf:params:jmap:core", "urn:ietf:params:jmap:mail"],
            "methodCalls": [
                ["Email/import", {
                    "accountId": session_info["account_id"],
                    "emails": {
                        file_key: {
                            "blobId": blob_id,
                            "mailboxIds": {inbox_id: True}
                        }
                    }
                }, "0"]
            ]
        }

        try:
            imp_resp = requests.post(session_info["api_url"], auth=auth, headers=import_headers, json=import_payload, timeout=20)
        except Exception as e:
            logger.error(f"Failed to import email {file_key}: {e}")
            continue

        if imp_resp.status_code != 200:
            logger.error(f"Email/import call failed for {file_key}. Status: {imp_resp.status_code}, Body: {imp_resp.text}")
            continue

        logger.info(f"Successfully imported {file_key} into Stalwart Inbox (Blob: {blob_id}).")

        # Delete object from R2 after successful import
        try:
            s3_client.delete_object(Bucket=R2_BUCKET, Key=file_key)
            logger.info(f"Cleaned up {file_key} from R2 bucket.")
        except Exception as e:
            logger.warning(f"Failed to delete {file_key} from R2 after import: {e}")

def main():
    logger.info("Starting Stalwart Email Fetcher daemon...")
    while True:
        try:
            fetch_and_process_emails()
        except Exception as e:
            logger.error(f"Unhandled exception in fetch loop: {e}", exc_info=True)

        time.sleep(POLL_INTERVAL)

if __name__ == "__main__":
    main()
