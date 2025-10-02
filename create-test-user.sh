#!/bin/bash

# Get admin token
ADMIN_TOKEN=$(curl -s -X POST http://localhost:8081/realms/master/protocol/openid-connect/token \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "username=admin" \
  -d "password=admin" \
  -d "grant_type=password" \
  -d "client_id=admin-cli" | jq -r '.access_token')

# Create test user
curl -s -X POST http://localhost:8081/admin/realms/innover/users \
  -H "Authorization: Bearer $ADMIN_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "username": "testuser",
    "enabled": true,
    "emailVerified": true,
    "email": "test@example.com",
    "credentials": [{
      "type": "password",
      "value": "testpass",
      "temporary": false
    }]
  }'

echo "Test user created: testuser / testpass"
