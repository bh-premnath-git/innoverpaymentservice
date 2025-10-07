#!/bin/bash

# Get or create OAuth credentials for your app

echo "🔑 Getting OAuth Client Credentials..."
echo ""

# Check if app already exists
EXISTING_APP=$(docker exec innover-wso2is-1 sh -c 'curl -sk -u admin:admin "https://localhost:9443/api/server/v1/applications?filter=name%20eq%20InNoverApp" | jq -r ".applications[0].id"')

if [ "$EXISTING_APP" != "null" ] && [ -n "$EXISTING_APP" ]; then
  echo "✅ Found existing OAuth app 'InNoverApp'"
  APP_ID="$EXISTING_APP"
else
  echo "📝 Creating new OAuth app 'InNoverApp'..."
  
  # Create new OAuth client
  RESPONSE=$(docker exec innover-wso2is-1 sh -c 'curl -sk -u admin:admin -H "Content-Type: application/json" \
    -d "{\"client_name\":\"InNoverApp\",\"grant_types\":[\"password\",\"refresh_token\",\"authorization_code\"],\"redirect_uris\":[\"https://localhost/callback\"]}" \
    https://localhost:9443/api/identity/oauth2/dcr/v1.1/register')
  
  CLIENT_ID=$(echo "$RESPONSE" | jq -r '.client_id')
  CLIENT_SECRET=$(echo "$RESPONSE" | jq -r '.client_secret')
  
  echo ""
  echo "✅ Created OAuth Application"
  echo ""
  echo "════════════════════════════════════════════"
  echo "CLIENT_ID:     $CLIENT_ID"
  echo "CLIENT_SECRET: $CLIENT_SECRET"
  echo "════════════════════════════════════════════"
  echo ""
  echo "💾 Save these credentials - you'll need them for all API calls!"
  exit 0
fi

# Get credentials for existing app
echo "📋 Fetching credentials..."
CREDS=$(docker exec innover-wso2is-1 sh -c "curl -sk -u admin:admin https://localhost:9443/api/server/v1/applications/$APP_ID/inbound-protocols/oidc")

CLIENT_ID=$(echo "$CREDS" | jq -r '.clientId')
CLIENT_SECRET=$(echo "$CREDS" | jq -r '.clientSecret')

echo ""
echo "✅ OAuth Application 'InNoverApp'"
echo ""
echo "════════════════════════════════════════════"
echo "CLIENT_ID:     $CLIENT_ID"
echo "CLIENT_SECRET: $CLIENT_SECRET"
echo "════════════════════════════════════════════"
echo ""
echo "🔐 Use these credentials to login ALL users:"
echo "   - finance, auditor, app_admin, ops_user, user"
echo ""
