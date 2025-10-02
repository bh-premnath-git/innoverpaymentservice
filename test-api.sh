#!/bin/bash

echo "=========================================="
echo "Testing Kong + Keycloak Authentication"
echo "=========================================="
echo ""

# Step 1: Get a token from postman-test client
echo "1. Getting token from postman-test client..."
TOKEN_RESPONSE=$(curl -s -X POST http://localhost:8081/realms/innover/protocol/openid-connect/token \
  -H 'Content-Type: application/x-www-form-urlencoded' \
  -d 'client_id=postman-test' \
  -d 'client_secret=postman-secret' \
  -d 'grant_type=password' \
  -d 'username=user' \
  -d 'password=user' \
  -d 'scope=openid profile')

# Check if we got an error
if echo "$TOKEN_RESPONSE" | grep -q "error"; then
  echo "❌ Failed to get token:"
  echo "$TOKEN_RESPONSE" | jq '.'
  echo ""
  echo "Trying to fix user account..."
  
  # Get admin token
  ADMIN_TOKEN=$(curl -s -X POST http://localhost:8081/realms/master/protocol/openid-connect/token \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -d "username=admin" \
    -d "password=admin" \
    -d "grant_type=password" \
    -d "client_id=admin-cli" | jq -r '.access_token')
  
  # Get user ID
  USER_ID=$(curl -s -X GET "http://localhost:8081/admin/realms/innover/users?username=user" \
    -H "Authorization: Bearer $ADMIN_TOKEN" | jq -r '.[0].id')
  
  # Reset password
  curl -s -X PUT "http://localhost:8081/admin/realms/innover/users/$USER_ID/reset-password" \
    -H "Authorization: Bearer $ADMIN_TOKEN" \
    -H "Content-Type: application/json" \
    -d '{"type":"password","value":"user","temporary":false}'
  
  # Remove required actions
  curl -s -X PUT "http://localhost:8081/admin/realms/innover/users/$USER_ID" \
    -H "Authorization: Bearer $ADMIN_TOKEN" \
    -H "Content-Type: application/json" \
    -d '{"emailVerified":true,"requiredActions":[]}'
  
  echo "✅ User account fixed. Trying again..."
  
  TOKEN_RESPONSE=$(curl -s -X POST http://localhost:8081/realms/innover/protocol/openid-connect/token \
    -H 'Content-Type: application/x-www-form-urlencoded' \
    -d 'client_id=postman-test' \
    -d 'client_secret=postman-secret' \
    -d 'grant_type=password' \
    -d 'username=user' \
    -d 'password=user' \
    -d 'scope=openid profile')
fi

TOKEN=$(echo "$TOKEN_RESPONSE" | jq -r '.access_token')

if [ "$TOKEN" == "null" ] || [ -z "$TOKEN" ]; then
  echo "❌ Still failed to get token:"
  echo "$TOKEN_RESPONSE" | jq '.'
  exit 1
fi

echo "✅ Got token successfully!"
echo ""

# Step 2: Decode and show token claims
echo "2. Token claims:"
echo "$TOKEN" | cut -d'.' -f2 | base64 -d 2>/dev/null | jq '{iss, aud, azp, sub, preferred_username}'
echo ""

# Step 3: Test API
echo "3. Testing API endpoint..."
API_RESPONSE=$(curl -s -w "\n%{http_code}" -H "Authorization: Bearer $TOKEN" http://localhost:8000/api/profile/health)
HTTP_CODE=$(echo "$API_RESPONSE" | tail -n1)
BODY=$(echo "$API_RESPONSE" | head -n-1)

echo "HTTP Status: $HTTP_CODE"
echo "Response:"
echo "$BODY" | jq '.' 2>/dev/null || echo "$BODY"
echo ""

if [ "$HTTP_CODE" == "200" ]; then
  echo "=========================================="
  echo "✅ SUCCESS! Authentication is working!"
  echo "=========================================="
  echo ""
  echo "Use this token in Postman:"
  echo "$TOKEN"
else
  echo "=========================================="
  echo "❌ Authentication failed"
  echo "=========================================="
  echo ""
  echo "Checking Kong logs..."
  docker compose -f /home/premnath/innover/docker-compose.yml logs kong --tail 5
fi
