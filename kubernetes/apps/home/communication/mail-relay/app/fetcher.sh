#!/bin/sh
set -e

# Install required tools
apk add --no-cache aws-cli curl jq > /dev/null 2>&1

# Required ENV Vars:
# R2_ENDPOINT: e.g. https://<account_id>.r2.cloudflarestorage.com
# R2_BUCKET: e.g. home-ops-email-inbox
# AWS_ACCESS_KEY_ID: Cloudflare R2 Access Key
# AWS_SECRET_ACCESS_KEY: Cloudflare R2 Secret Key
# AWS_DEFAULT_REGION: auto
# STALWART_URL: e.g. http://stalwart.home-system.svc.cluster.local:8080/.well-known/jmap
# STALWART_TOKEN: Stalwart App Password or Token
# STALWART_ACCOUNT_ID: e.g. admin

echo "Fetching JMAP Session from $STALWART_URL..."
SESSION=$(curl -s -L -f -u "$STALWART_ACCOUNT_ID:$STALWART_TOKEN" "$STALWART_URL")
API_URL=$(echo "$SESSION" | jq -r '.apiUrl')
UPLOAD_URL=$(echo "$SESSION" | jq -r '.uploadUrl' | sed "s/{accountId}/$STALWART_ACCOUNT_ID/g")

echo "Fetching Mailbox IDs..."
MAILBOXES_RES=$(curl -s -L -X POST -u "$STALWART_ACCOUNT_ID:$STALWART_TOKEN" -H "Content-Type: application/json" -d '{
  "using": ["urn:ietf:params:jmap:core", "urn:ietf:params:jmap:mail"],
  "methodCalls": [
    ["Mailbox/get", {"accountId": "'$STALWART_ACCOUNT_ID'"}, "0"]
  ]
}' "$API_URL")

INBOX_ID=$(echo $MAILBOXES_RES | jq -r '.methodResponses[0][1].list[] | select(.role == "inbox") | .id')

if [ -z "$INBOX_ID" ] || [ "$INBOX_ID" == "null" ]; then
  echo "Error: Could not find Inbox ID"
  exit 1
fi
echo "Inbox ID: $INBOX_ID"

echo "Listing objects in R2 bucket $R2_BUCKET..."
# Use aws s3api to list keys. We disable pager to prevent hanging.
export AWS_PAGER=""
OBJECTS=$(aws s3api list-objects-v2 --bucket "$R2_BUCKET" --endpoint-url "$R2_ENDPOINT" --query 'Contents[].Key' --output text || echo "NONE")

if [ "$OBJECTS" == "NONE" ] || [ -z "$OBJECTS" ]; then
  echo "No emails found in R2."
  exit 0
fi

for obj in $OBJECTS; do
  if [ "$obj" == "None" ] || [ -z "$obj" ]; then continue; fi
  
  echo "Processing $obj..."
  # 1. Download
  aws s3 cp "s3://$R2_BUCKET/$obj" "/tmp/$obj" --endpoint-url "$R2_ENDPOINT"
  
  # 2. Upload to Stalwart Blob Storage
  BLOB_RES=$(curl -s -L -X POST -u "$STALWART_ACCOUNT_ID:$STALWART_TOKEN" -H "Content-Type: message/rfc822" --data-binary @"/tmp/$obj" "$UPLOAD_URL")
  BLOB_ID=$(echo "$BLOB_RES" | jq -r '.blobId')
  
  if [ -z "$BLOB_ID" ] || [ "$BLOB_ID" == "null" ]; then
    echo "Error uploading $obj to Stalwart. Response: $BLOB_RES"
    rm -f "/tmp/$obj"
    continue
  fi
  
  # 3. Import Email into Inbox
  JMAP_PAYLOAD=$(jq -n --arg acc "$STALWART_ACCOUNT_ID" --arg blob "$BLOB_ID" --arg inbox "$INBOX_ID" '{
    "using": ["urn:ietf:params:jmap:core", "urn:ietf:params:jmap:mail"],
    "methodCalls": [
      [
        "Email/import",
        {
          "accountId": $acc,
          "emails": {
            "email1": {
              "blobId": $blob,
              "mailboxIds": { ($inbox): true } 
            }
          }
        },
        "0"
      ]
    ]
  }')
  
  IMPORT_RES=$(curl -s -L -X POST -u "$STALWART_ACCOUNT_ID:$STALWART_TOKEN" -H "Content-Type: application/json" -d "$JMAP_PAYLOAD" "$API_URL")
  
  # Check if successful
  CREATED_ID=$(echo "$IMPORT_RES" | jq -r '.methodResponses[0][1].created.email1.id')
  
  if [ -n "$CREATED_ID" ] && [ "$CREATED_ID" != "null" ]; then
    echo "Successfully imported $obj to Stalwart (ID: $CREATED_ID)"
    # 4. Delete from R2
    aws s3 rm "s3://$R2_BUCKET/$obj" --endpoint-url "$R2_ENDPOINT"
  else
    echo "Failed to import $obj. Response: $IMPORT_RES"
  fi
  
  rm -f "/tmp/$obj"
done

echo "Done!"
