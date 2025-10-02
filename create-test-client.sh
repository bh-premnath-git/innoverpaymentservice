#!/bin/bash

# Get admin token
ADMIN_TOKEN=$(curl -s -X POST http://localhost:8081/realms/master/protocol/openid-connect/token \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "username=admin" \
  -d "password=admin" \
  -d "grant_type=password" \
  -d "client_id=admin-cli" | jq -r '.access_token')

if [ "$ADMIN_TOKEN" == "null" ] || [ -z "$ADMIN_TOKEN" ]; then
  echo "Failed to get admin token"
  exit 1
fi

echo "Got admin token"

# Create postman-test client
curl -s -X POST http://localhost:8081/admin/realms/innover/clients \
  -H "Authorization: Bearer $ADMIN_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "clientId": "postman-test",
    "enabled": true,
    "publicClient": false,
    "secret": "postman-secret",
    "directAccessGrantsEnabled": true,
    "serviceAccountsEnabled": true,
    "standardFlowEnabled": true,
    "implicitFlowEnabled": false,
    "redirectUris": ["*"],
    "webOrigins": ["*"],
    "protocol": "openid-connect"
  }'

echo ""
echo "Client 'postman-test' created with secret 'postman-secret'"
echo ""
echo "Get a token with:"
echo "curl -X POST http://localhost:8081/realms/innover/protocol/openid-connect/token \\"
echo "  -H 'Content-Type: application/x-www-form-urlencoded' \\"
echo "  -d 'client_id=postman-test' \\"
echo "  -d 'client_secret=postman-secret' \\"
echo "  -d 'grant_type=password' \\"
echo "  -d 'username=admin' \\"
echo "  -d 'password=admin' \\"
echo "  -d 'scope=openid profile'"
