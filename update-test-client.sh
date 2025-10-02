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

# Get the postman-test client ID
CLIENT_UUID=$(curl -s -X GET "http://localhost:8081/admin/realms/innover/clients?clientId=postman-test" \
  -H "Authorization: Bearer $ADMIN_TOKEN" | jq -r '.[0].id')

echo "Client UUID: $CLIENT_UUID"

# Update the client to add audience mapper
curl -s -X POST "http://localhost:8081/admin/realms/innover/clients/$CLIENT_UUID/protocol-mappers/models" \
  -H "Authorization: Bearer $ADMIN_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "kong-audience",
    "protocol": "openid-connect",
    "protocolMapper": "oidc-audience-mapper",
    "config": {
      "included.client.audience": "kong",
      "id.token.claim": "false",
      "access.token.claim": "true"
    }
  }'

echo ""
echo "Added kong to audience for postman-test client"
