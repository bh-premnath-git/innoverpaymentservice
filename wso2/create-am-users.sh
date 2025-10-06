#!/bin/bash
# Create users in WSO2 AM user store

echo "Creating users in WSO2 API Manager..."

USERS=(
  "ops_user:OpsUser123"
  "finance:Finance123"
  "auditor:Auditor123"
  "user:User1234"
)

for user_pass in "${USERS[@]}"; do
  username="${user_pass%%:*}"
  password="${user_pass##*:}"
  
  echo "Creating user: $username"
  
  curl -k -s -X POST "https://localhost:9443/scim2/Users" \
    -u admin:admin \
    -H "Content-Type: application/scim+json" \
    -d "{
      \"schemas\": [\"urn:ietf:params:scim:schemas:core:2.0:User\"],
      \"userName\": \"${username}\",
      \"password\": \"${password}\",
      \"name\": {
        \"givenName\": \"${username}\",
        \"familyName\": \"User\"
      },
      \"emails\": [{
        \"value\": \"${username}@innover.local\",
        \"primary\": true
      }]
    }" > /dev/null 2>&1
  
  echo "  ✓ Created $username"
done

echo "✅ All users created in WSO2 AM"
