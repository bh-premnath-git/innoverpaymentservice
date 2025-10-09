#!/bin/bash

echo "════════════════════════════════════════════════════════════════"
echo "🔑 Generating Application Keys"
echo "════════════════════════════════════════════════════════════════"
echo ""

APIM_BASE="https://localhost:9443"
ADMIN_USER="admin"
ADMIN_PASS="admin"
APP_NAME="DefaultApplication"

# Get application ID
echo "📋 Getting application ID..."
APP_ID=$(curl -sk -u "$ADMIN_USER:$ADMIN_PASS" \
  "$APIM_BASE/api/am/devportal/v3/applications" | \
  jq -r ".list[] | select(.name==\"$APP_NAME\") | .applicationId")

if [ -z "$APP_ID" ] || [ "$APP_ID" = "null" ]; then
  echo "❌ Application '$APP_NAME' not found"
  exit 1
fi

echo "✅ Application: $APP_NAME (ID: $APP_ID)"
echo ""

# Check if keys already exist
echo "🔍 Checking for existing keys..."
EXISTING_KEYS=$(curl -sk -u "$ADMIN_USER:$ADMIN_PASS" \
  "$APIM_BASE/api/am/devportal/v3/applications/$APP_ID/keys/PRODUCTION" 2>&1)

if echo "$EXISTING_KEYS" | jq -e '.consumerKey' >/dev/null 2>&1; then
  echo "✅ Keys already exist!"
  CLIENT_KEY=$(echo "$EXISTING_KEYS" | jq -r '.consumerKey')
  CLIENT_SECRET=$(echo "$EXISTING_KEYS" | jq -r '.consumerSecret')
  KEY_MANAGER=$(echo "$EXISTING_KEYS" | jq -r '.keyManager')
  
  echo ""
  echo "════════════════════════════════════════════════════════════════"
  echo "🔑 Application Keys (Existing)"
  echo "════════════════════════════════════════════════════════════════"
  echo "Application:    $APP_NAME"
  echo "Key Manager:    $KEY_MANAGER"
  echo "Consumer Key:   $CLIENT_KEY"
  echo "Consumer Secret: $CLIENT_SECRET"
  echo "════════════════════════════════════════════════════════════════"
  
  # Save to file
  cat > wso2/output/application-keys.json <<EOF
{
  "application": "$APP_NAME",
  "applicationId": "$APP_ID",
  "keyManager": "$KEY_MANAGER",
  "production": {
    "consumerKey": "$CLIENT_KEY",
    "consumerSecret": "$CLIENT_SECRET"
  }
}
EOF
  
  echo ""
  echo "💾 Saved to: wso2/output/application-keys.json"
  exit 0
fi

# Generate new keys
echo "🔄 Generating new PRODUCTION keys with WSO2-IS Key Manager..."
KEYS_RESPONSE=$(curl -sk -u "$ADMIN_USER:$ADMIN_PASS" -X POST \
  "$APIM_BASE/api/am/devportal/v3/applications/$APP_ID/generate-keys" \
  -H "Content-Type: application/json" \
  -d '{
    "keyType": "PRODUCTION",
    "keyManager": "WSO2-IS",
    "grantTypesToBeSupported": [
      "password",
      "client_credentials",
      "refresh_token"
    ],
    "callbackUrl": "https://localhost/callback",
    "scopes": []
  }')

# Extract keys
CLIENT_KEY=$(echo "$KEYS_RESPONSE" | jq -r '.consumerKey')
CLIENT_SECRET=$(echo "$KEYS_RESPONSE" | jq -r '.consumerSecret')
KEY_MANAGER=$(echo "$KEYS_RESPONSE" | jq -r '.keyManager')

if [ -z "$CLIENT_KEY" ] || [ "$CLIENT_KEY" = "null" ]; then
  echo "❌ Failed to generate keys"
  echo "$KEYS_RESPONSE" | jq '.'
  exit 1
fi

echo "✅ Keys generated successfully!"
echo ""
echo "════════════════════════════════════════════════════════════════"
echo "🔑 Application Keys"
echo "════════════════════════════════════════════════════════════════"
echo "Application:    $APP_NAME"
echo "Key Manager:    $KEY_MANAGER"
echo "Consumer Key:   $CLIENT_KEY"
echo "Consumer Secret: $CLIENT_SECRET"
echo "════════════════════════════════════════════════════════════════"
echo ""

# Save to file
mkdir -p wso2/output
cat > wso2/output/application-keys.json <<EOF
{
  "application": "$APP_NAME",
  "applicationId": "$APP_ID",
  "keyManager": "$KEY_MANAGER",
  "production": {
    "consumerKey": "$CLIENT_KEY",
    "consumerSecret": "$CLIENT_SECRET"
  }
}
EOF

echo "💾 Saved to: wso2/output/application-keys.json"
echo ""
echo "Next step: Test API calls"
echo "Run: ./test-api-call.sh"
