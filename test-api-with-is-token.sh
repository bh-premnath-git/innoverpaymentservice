#!/bin/bash

echo "════════════════════════════════════════════════════════════════"
echo "🧪 Test: Sign in with IS → Call API"
echo "════════════════════════════════════════════════════════════════"
echo ""

# OAuth credentials from IS
CLIENT_ID="NQItnECmPD7olXUnAbYSonXEhiMa"
CLIENT_SECRET="fVaDR80GGAs2mGz5mbqE_gGjE9DrnZBk0vaeThzO8nwa"

# Test users
USERS=("admin:admin" "finance:Finance123" "auditor:Auditor123" "ops_user:OpsUser123" "user:User1234")

echo "📋 Testing ${#USERS[@]} users from WSO2 IS"
echo ""

for USER_CREDS in "${USERS[@]}"; do
  USERNAME="${USER_CREDS%:*}"
  PASSWORD="${USER_CREDS#*:}"
  
  echo "─────────────────────────────────────────────────────────────"
  echo "👤 Testing user: $USERNAME"
  echo "─────────────────────────────────────────────────────────────"
  
  # Step 1: Get token from IS
  echo "  1️⃣  Getting OAuth token from WSO2 IS..."
  TOKEN_RESPONSE=$(curl -sk -u "$CLIENT_ID:$CLIENT_SECRET" \
    -d "grant_type=password&username=$USERNAME&password=$PASSWORD" \
    https://localhost:9444/oauth2/token 2>/dev/null)
  
  TOKEN=$(echo "$TOKEN_RESPONSE" | jq -r '.access_token')
  
  if [ "$TOKEN" = "null" ] || [ -z "$TOKEN" ]; then
    echo "  ❌ Failed to get token"
    echo "     Error: $(echo "$TOKEN_RESPONSE" | jq -r '.error_description // .error')"
    echo ""
    continue
  fi
  
  echo "  ✅ Token obtained: ${TOKEN:0:30}..."
  
  # Step 2: Call API via APIM Gateway
  echo "  2️⃣  Calling API via APIM Gateway..."
  API_RESPONSE=$(curl -s -w "\n%{http_code}" \
    -H "Authorization: Bearer $TOKEN" \
    http://localhost:8280/api/forex/1.0.0/health 2>/dev/null)
  
  HTTP_CODE=$(echo "$API_RESPONSE" | tail -1)
  BODY=$(echo "$API_RESPONSE" | head -n -1)
  
  if [ "$HTTP_CODE" = "200" ]; then
    echo "  ✅ API call successful!"
    echo "     Response: $BODY"
  else
    echo "  ❌ API call failed (HTTP $HTTP_CODE)"
    echo "     Response: $BODY"
  fi
  
  echo ""
done

echo "════════════════════════════════════════════════════════════════"
echo "🏁 Test Complete"
echo "════════════════════════════════════════════════════════════════"
