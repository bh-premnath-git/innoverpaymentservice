#!/bin/bash

echo "════════════════════════════════════════════════════════════════"
echo "🧪 Testing API Calls with APIM Token"
echo "════════════════════════════════════════════════════════════════"
echo ""

# Load credentials
if [ ! -f "wso2/output/application-keys.json" ]; then
  echo "❌ Keys file not found!"
  echo "Run: ./generate-app-keys.sh first"
  exit 1
fi

CLIENT_KEY=$(jq -r '.production.consumerKey' wso2/output/application-keys.json)
CLIENT_SECRET=$(jq -r '.production.consumerSecret' wso2/output/application-keys.json)
KEY_MANAGER=$(jq -r '.keyManager' wso2/output/application-keys.json)

echo "🔑 Using Application Keys:"
echo "   Key Manager: $KEY_MANAGER"
echo "   Client ID: $CLIENT_KEY"
echo ""

# Get token for admin user
echo "1️⃣  Getting OAuth token (admin user)..."
TOKEN_RESPONSE=$(curl -sk -u "$CLIENT_KEY:$CLIENT_SECRET" \
  -d "grant_type=password&username=admin&password=admin" \
  https://localhost:9443/oauth2/token 2>/dev/null)

TOKEN=$(echo "$TOKEN_RESPONSE" | jq -r '.access_token')

if [ "$TOKEN" = "null" ] || [ -z "$TOKEN" ]; then
  echo "❌ Failed to get token"
  echo "$TOKEN_RESPONSE" | jq '.'
  exit 1
fi

echo "✅ Token obtained: ${TOKEN:0:40}..."
echo ""

# Test all APIs
APIS=(
  "forex:/api/forex/1.0.0/health"
  "profile:/api/profile/1.0.0/health"
  "payment:/api/payment/1.0.0/health"
  "ledger:/api/ledger/1.0.0/health"
  "wallet:/api/wallet/1.0.0/health"
  "rules:/api/rules/1.0.0/health"
)

echo "2️⃣  Testing APIs via Gateway..."
echo ""

SUCCESS=0
FAILED=0

for API in "${APIS[@]}"; do
  NAME="${API%%:*}"
  PATH="${API#*:}"
  
  echo -n "   Testing $NAME... "
  
  RESPONSE=$(curl -s -w "\n%{http_code}" \
    -H "Authorization: Bearer $TOKEN" \
    http://localhost:8280$PATH 2>/dev/null)
  
  HTTP_CODE=$(echo "$RESPONSE" | tail -1)
  BODY=$(echo "$RESPONSE" | head -n -1)
  
  if [ "$HTTP_CODE" = "200" ]; then
    echo "✅ Success"
    ((SUCCESS++))
  else
    echo "❌ Failed (HTTP $HTTP_CODE)"
    echo "      $BODY"
    ((FAILED++))
  fi
done

echo ""
echo "════════════════════════════════════════════════════════════════"
echo "📊 Results"
echo "════════════════════════════════════════════════════════════════"
echo "✅ Successful: $SUCCESS"
echo "❌ Failed: $FAILED"
echo ""

if [ $SUCCESS -eq ${#APIS[@]} ]; then
  echo "🎉 All APIs working!"
  echo ""
  echo "Example API call:"
  echo "curl -H 'Authorization: Bearer $TOKEN' \\"
  echo "  http://localhost:8280/api/forex/1.0.0/health"
else
  echo "⚠️  Some APIs failed. Check APIM logs:"
  echo "docker logs innover-wso2am-1"
fi
