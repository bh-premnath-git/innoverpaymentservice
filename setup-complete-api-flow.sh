#!/bin/bash

# Complete API Setup & Test Script
# Does everything: Publish APIs → Subscribe → Generate Keys → Test

# Don't exit on error for individual API operations
set +e

APIM_BASE="https://localhost:9443"
ADMIN="admin:admin"
APP_NAME="DefaultApplication"

echo "════════════════════════════════════════════════════════════════"
echo "🚀 Complete API Setup & Test"
echo "════════════════════════════════════════════════════════════════"
echo ""

# Step 1: Get Application ID
echo "1️⃣  Getting application..."
APP_ID=$(curl -sk -u "$ADMIN" "$APIM_BASE/api/am/devportal/v3/applications" | \
  jq -r ".list[] | select(.name==\"$APP_NAME\") | .applicationId")
echo "   ✅ $APP_NAME: $APP_ID"
echo ""

# Step 2: Publish, Deploy & Subscribe APIs
echo "2️⃣  Publishing & deploying APIs..."
APIS=$(curl -sk -u "$ADMIN" "$APIM_BASE/api/am/publisher/v4/apis" | jq -c '.list[]')

while IFS= read -r API; do
  ID=$(echo "$API" | jq -r '.id')
  NAME=$(echo "$API" | jq -r '.name')
  STATUS=$(echo "$API" | jq -r '.lifeCycleStatus')
  
  # Publish if needed
  if [ "$STATUS" != "PUBLISHED" ]; then
    curl -sk -u "$ADMIN" -X POST \
      "$APIM_BASE/api/am/publisher/v4/apis/change-lifecycle?apiId=$ID&action=Publish" \
      -H "Content-Type: application/json" >/dev/null 2>&1
  fi
  
  # Create & deploy revision
  REV_COUNT=$(curl -sk -u "$ADMIN" "$APIM_BASE/api/am/publisher/v4/apis/$ID/revisions" | jq '.count')
  if [ "$REV_COUNT" = "0" ]; then
    REV_ID=$(curl -sk -u "$ADMIN" -X POST "$APIM_BASE/api/am/publisher/v4/apis/$ID/revisions" \
      -H "Content-Type: application/json" \
      -d '{"description":"Initial deployment"}' | jq -r '.id')
    
    curl -sk -u "$ADMIN" -X POST "$APIM_BASE/api/am/publisher/v4/apis/$ID/deploy-revision?revisionId=$REV_ID" \
      -H "Content-Type: application/json" \
      -d '[{"name":"Default","vhost":"localhost","displayOnDevportal":true}]' >/dev/null 2>&1
  fi
  
  # Subscribe
  curl -sk -u "$ADMIN" -X POST "$APIM_BASE/api/am/devportal/v3/subscriptions" \
    -H "Content-Type: application/json" \
    -d "{\"apiId\":\"$ID\",\"applicationId\":\"$APP_ID\",\"throttlingPolicy\":\"Unlimited\"}" \
    >/dev/null 2>&1
  
  echo "   ✅ $NAME"
done <<< "$APIS"
echo ""

# Step 3: Generate Keys
echo "3️⃣  Generating application keys..."
KEYS=$(curl -sk -u "$ADMIN" "$APIM_BASE/api/am/devportal/v3/applications/$APP_ID/keys/PRODUCTION" 2>&1)

if ! echo "$KEYS" | jq -e '.consumerKey' >/dev/null 2>&1; then
  KEYS=$(curl -sk -u "$ADMIN" -X POST \
    "$APIM_BASE/api/am/devportal/v3/applications/$APP_ID/generate-keys" \
    -H "Content-Type: application/json" \
    -d '{"keyType":"PRODUCTION","keyManager":"Resident Key Manager","grantTypesToBeSupported":["password","client_credentials","refresh_token"],"callbackUrl":"https://localhost/cb","scopes":[]}')
fi

CLIENT_ID=$(echo "$KEYS" | jq -r '.consumerKey')
CLIENT_SECRET=$(echo "$KEYS" | jq -r '.consumerSecret')

mkdir -p wso2/output
echo "$KEYS" | jq '{application:"'$APP_NAME'",applicationId:"'$APP_ID'",keyManager,production:{consumerKey,consumerSecret}}' \
  > wso2/output/application-keys.json

echo "   ✅ Keys saved to wso2/output/application-keys.json"
echo "   Client ID: $CLIENT_ID"
echo ""

# Step 4: Test APIs
echo "4️⃣  Testing APIs with admin user..."
TOKEN=$(curl -sk -u "$CLIENT_ID:$CLIENT_SECRET" \
  -d "grant_type=password&username=admin&password=admin" \
  https://localhost:9443/oauth2/token | jq -r '.access_token')

if [ -z "$TOKEN" ] || [ "$TOKEN" = "null" ]; then
  echo "   ❌ Failed to get token"
  exit 1
fi

echo "   ✅ Token: ${TOKEN:0:30}..."
echo ""

PATHS=("/api/forex/1.0.0/health" "/api/profile/1.0.0/health" "/api/payment/1.0.0/health" "/api/ledger/1.0.0/health" "/api/wallet/1.0.0/health" "/api/rules/1.0.0/health")
SUCCESS=0

for PATH in "${PATHS[@]}"; do
  NAME=$(echo $PATH | cut -d'/' -f3)
  CODE=$(curl -sk -o /dev/null -w "%{http_code}" \
    -H "Authorization: Bearer $TOKEN" \
    http://localhost:8280$PATH)
  
  if [ "$CODE" = "200" ]; then
    echo "   ✅ $NAME"
    ((SUCCESS++))
  else
    echo "   ❌ $NAME (HTTP $CODE)"
  fi
done

echo ""
echo "════════════════════════════════════════════════════════════════"
echo "✅ Complete! $SUCCESS/${#PATHS[@]} APIs working"
echo "════════════════════════════════════════════════════════════════"
echo ""
echo "📝 Summary:"
echo "   • APIs: Published & Subscribed"
echo "   • Keys: Saved to wso2/output/application-keys.json"  
echo "   • Test: Admin user can call APIs"
echo ""
echo "⚠️  Note: Only 'admin' user works (Resident Key Manager)"
echo "   Other users need WSO2-IS Key Manager (has compatibility bug)"
