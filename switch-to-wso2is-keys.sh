#!/usr/bin/env bash
set -euo pipefail

echo "════════════════════════════════════════════════════════════════"
echo "🔄 Switching to WSO2-IS Key Manager"
echo "════════════════════════════════════════════════════════════════"
echo ""

APP_ID=$(curl -sk -u admin:admin 'https://localhost:9443/api/am/devportal/v3/applications' | jq -r '.list[0].applicationId')
APP_NAME=$(curl -sk -u admin:admin 'https://localhost:9443/api/am/devportal/v3/applications' | jq -r '.list[0].name')

echo "Application: ${APP_NAME}"
echo "Application ID: ${APP_ID}"
echo ""

echo "▶ Step 1: Deleting Resident Key Manager keys..."
DELETE_RESP=$(curl -sk -u admin:admin -X DELETE -w "\n%{http_code}" \
  "https://localhost:9443/api/am/devportal/v3/applications/${APP_ID}/keys/PRODUCTION")
DELETE_CODE=$(echo "$DELETE_RESP" | tail -1)

if [ "$DELETE_CODE" = "200" ] || [ "$DELETE_CODE" = "204" ]; then
  echo "  ✅ Resident Key Manager keys deleted"
else
  echo "  ⚠️  Delete returned HTTP ${DELETE_CODE} (may already be deleted)"
fi
echo ""

echo "▶ Step 2: Generating keys with WSO2-IS Key Manager..."
GEN_RESP=$(curl -sk -u admin:admin -X POST \
  "https://localhost:9443/api/am/devportal/v3/applications/${APP_ID}/generate-keys" \
  -H 'Content-Type: application/json' \
  -d '{"keyType":"PRODUCTION","keyManager":"WSO2-IS","grantTypesToBeSupported":["password","client_credentials","refresh_token"],"validityTime":86400}')

CK=$(echo "$GEN_RESP" | jq -r '.consumerKey // .keyMappingInfo.consumerKey // empty')
CS=$(echo "$GEN_RESP" | jq -r '.consumerSecret // .keyMappingInfo.consumerSecret // empty')

if [ -n "$CK" ] && [ "$CK" != "null" ] && [ -n "$CS" ] && [ "$CS" != "null" ]; then
  echo "  ✅ Keys generated with WSO2-IS"
  echo ""
  echo "  Consumer Key:    ${CK}"
  echo "  Consumer Secret: ${CS}"
  echo ""
  
  # Save to file
  cat > /tmp/wso2is-keys.txt <<EOF
# WSO2-IS Key Manager Credentials
# Generated: $(date)
export APP_CK="${CK}"
export APP_CS="${CS}"
export TOKEN_ENDPOINT="https://wso2is:9443/oauth2/token"
EOF
  
  echo "  💾 Keys saved to /tmp/wso2is-keys.txt"
  echo ""
  
  # Test token generation
  echo "▶ Step 3: Testing token generation with admin user..."
  TOKEN_RESP=$(curl -sk -u "${CK}:${CS}" \
    -d "grant_type=password&username=admin&password=admin" \
    "https://localhost:9443/oauth2/token" 2>/dev/null)
  
  TOKEN=$(echo "$TOKEN_RESP" | jq -r '.access_token // empty')
  
  if [ -n "$TOKEN" ] && [ "$TOKEN" != "null" ]; then
    echo "  ✅ Token generated successfully with admin"
    echo "     Token: ${TOKEN:0:40}..."
  else
    ERROR=$(echo "$TOKEN_RESP" | jq -r '.error_description // .error')
    echo "  ⚠️  Token generation failed: ${ERROR}"
  fi
  echo ""
  
  # Test with WSO2-IS user (finance)
  echo "▶ Step 4: Testing with WSO2-IS user (finance)..."
  TOKEN_RESP=$(curl -sk -u "${CK}:${CS}" \
    -d "grant_type=password&username=finance&password=finance123" \
    "https://wso2is:9443/oauth2/token" 2>/dev/null)
  
  TOKEN=$(echo "$TOKEN_RESP" | jq -r '.access_token // empty')
  
  if [ -n "$TOKEN" ] && [ "$TOKEN" != "null" ]; then
    echo "  ✅ Token generated successfully with finance user!"
    echo "     Token: ${TOKEN:0:40}..."
    echo ""
    echo "  🎉 WSO2-IS Key Manager is working!"
  else
    ERROR=$(echo "$TOKEN_RESP" | jq -r '.error_description // .error')
    echo "  ❌ Token generation failed: ${ERROR}"
    echo ""
    echo "  This may indicate WSO2-IS integration issues."
    echo "  Check APIM logs for SSL/certificate errors."
  fi
  
else
  echo "  ❌ Key generation failed"
  echo ""
  echo "Response:"
  echo "$GEN_RESP" | jq .
  exit 1
fi

echo ""
echo "════════════════════════════════════════════════════════════════"
echo "✅ Key Manager Switch Complete"
echo "════════════════════════════════════════════════════════════════"
echo ""
echo "To use these keys, run:"
echo "  source /tmp/wso2is-keys.txt"
echo ""
echo "To test all users:"
echo "  ./test-quick.sh"
echo ""
