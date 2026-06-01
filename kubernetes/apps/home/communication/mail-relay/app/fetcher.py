import os
import time
import requests
import boto3
from botocore.config import Config
from urllib.parse import urlparse

R2_ACCOUNT_ID = os.environ.get('R2_ACCOUNT_ID')
R2_BUCKET = os.environ.get('R2_BUCKET')
AWS_ACCESS_KEY_ID = os.environ.get('AWS_ACCESS_KEY_ID')
AWS_SECRET_ACCESS_KEY = os.environ.get('AWS_SECRET_ACCESS_KEY')
AWS_DEFAULT_REGION = os.environ.get('AWS_DEFAULT_REGION', 'auto')

STALWART_URL = os.environ.get('STALWART_URL')
STALWART_TOKEN = os.environ.get('STALWART_TOKEN')
STALWART_LOGIN_USER = os.environ.get('STALWART_LOGIN_USER')

R2_ENDPOINT = f"https://{R2_ACCOUNT_ID}.r2.cloudflarestorage.com"

# Setup boto3 client
s3_client = boto3.client('s3',
    endpoint_url=R2_ENDPOINT,
    aws_access_key_id=AWS_ACCESS_KEY_ID,
    aws_secret_access_key=AWS_SECRET_ACCESS_KEY,
    region_name=AWS_DEFAULT_REGION,
    config=Config(signature_version='s3v4')
)

def fetch_emails():
    # 1. Authenticate to Stalwart JMAP
    print(f"Fetching JMAP Session from {STALWART_URL}...")
    auth = (STALWART_LOGIN_USER, STALWART_TOKEN)
    resp = requests.get(STALWART_URL, auth=auth, allow_redirects=True)
    if resp.status_code != 200:
        print(f"Failed to fetch session. Status: {resp.status_code}, Response: {resp.text}")
        return
    
    session = resp.json()
    
    # 2. Extract Base URL and Paths
    # Because Stalwart might return internal pod names, we use the original STALWART_URL's host
    stalwart_base = STALWART_URL.split('/.well-known')[0]
    
    api_url_raw = session.get('apiUrl', '')
    api_path = urlparse(api_url_raw).path
    api_url = f"{stalwart_base}{api_path}"

    account_id = session['primaryAccounts']['urn:ietf:params:jmap:mail']
    print(f"Using Stalwart internal Account ID: {account_id}")

    upload_url_raw = session.get('uploadUrl', '')
    upload_path = urlparse(upload_url_raw).path
    upload_url = f"{stalwart_base}{upload_path}".replace("{accountId}", account_id)

    # 3. Get Inbox ID
    headers = {"Content-Type": "application/json"}
    payload = {
        "using": ["urn:ietf:params:jmap:core", "urn:ietf:params:jmap:mail"],
        "methodCalls": [
            ["Mailbox/get", {"accountId": account_id}, "0"]
        ]
    }
    
    print("Fetching Mailbox IDs...")
    mb_resp = requests.post(api_url, auth=auth, headers=headers, json=payload)
    if mb_resp.status_code != 200:
        print(f"Failed to fetch mailboxes. Status: {mb_resp.status_code}")
        return
        
    mb_data = mb_resp.json()
    inbox_id = None
    try:
        mailboxes = mb_data['methodResponses'][0][1]['list']
        for mb in mailboxes:
            if mb.get('role') == 'inbox':
                inbox_id = mb['id']
                break
    except Exception as e:
        print(f"Error parsing mailboxes: {e}")
        return
        
    if not inbox_id:
        print("Could not find Inbox ID.")
        return
        
    print(f"Inbox ID: {inbox_id}")
    
    # 4. List Objects in R2
    print(f"Listing objects in R2 bucket {R2_BUCKET}...")
    try:
        objects_resp = s3_client.list_objects_v2(Bucket=R2_BUCKET)
    except Exception as e:
        print(f"Failed to list objects in R2: {e}")
        return
        
    contents = objects_resp.get('Contents', [])
    if not contents:
        print("No objects found in bucket.")
        return
        
    for obj in contents:
        file_key = obj['Key']
        print(f"Processing object: {file_key}")
        
        # Download object to memory
        try:
            r2_obj = s3_client.get_object(Bucket=R2_BUCKET, Key=file_key)
            blob_data = r2_obj['Body'].read()
        except Exception as e:
            print(f"Failed to download {file_key} from R2: {e}")
            continue
            
        # Upload blob to Stalwart
        print(f"Uploading {file_key} to Stalwart...")
        up_headers = {"Content-Type": "message/rfc822"}
        up_resp = requests.post(upload_url, auth=auth, headers=up_headers, data=blob_data)
        
        if up_resp.status_code not in (200, 201):
            print(f"Failed to upload to Stalwart. Status: {up_resp.status_code}")
            continue
            
        up_data = up_resp.json()
        blob_id = up_data.get('blobId')
        if not blob_id:
            print("No blobId returned from Stalwart upload.")
            continue
            
        # Import blob as email
        print(f"Importing blob {blob_id} into inbox {inbox_id}...")
        import_payload = {
            "using": ["urn:ietf:params:jmap:core", "urn:ietf:params:jmap:mail"],
            "methodCalls": [
                ["Email/import", {
                    "accountId": account_id,
                    "emails": {
                        file_key: {
                            "blobId": blob_id,
                            "mailboxIds": {inbox_id: True}
                        }
                    }
                }, "0"]
            ]
        }
        
        imp_resp = requests.post(api_url, auth=auth, headers=headers, json=import_payload)
        if imp_resp.status_code != 200:
            print(f"Failed to import email. Status: {imp_resp.status_code}")
            continue
            
        print(f"Successfully imported {file_key}.")
        
        # Delete object from R2
        try:
            s3_client.delete_object(Bucket=R2_BUCKET, Key=file_key)
            print(f"Deleted {file_key} from R2 bucket.")
        except Exception as e:
            print(f"Failed to delete {file_key} from R2: {e}")

def main():
    while True:
        try:
            fetch_emails()
        except Exception as e:
            print(f"Unhandled exception during fetch loop: {e}")
            
        print("Sleeping for 60 seconds...")
        time.sleep(60)

if __name__ == "__main__":
    main()
