#!/bin/bash
set -e

IS_HOST="localhost"
IS_PORT="9443"
IS_BASE="https://${IS_HOST}:${IS_PORT}"
ADMIN_USER="admin"
ADMIN_PASS="admin"

echo "════════════════════════════════════════════════════════════════"
echo "🔧 Fixing User Claims in JWT Tokens"
echo "════════════════════════════════════════════════════════════════"
echo ""

# Step 1: Delete existing non-admin users and recreate with proper role mapping
echo "Step 1: Recreating users with proper role assignments..."
echo ""

declare -A USERS=(
  ["finance"]="Finance123:finance"
  ["auditor"]="Auditor123:auditor"
  ["ops_user"]="OpsUser123:ops_users"
  ["user"]="User1234:user"
)

for username in "${!USERS[@]}"; do
  IFS=':' read -r password role <<< "${USERS[$username]}"
  
  echo "Processing user: ${username}"
  
  # Check if user exists
  USER_ID=$(docker exec innover-wso2is-1 curl -sk -u "${ADMIN_USER}:${ADMIN_PASS}" \
    "${IS_BASE}/scim2/Users?filter=userName+eq+${username}" 2>/dev/null | jq -r '.Resources[0].id // empty')
  
  if [ -n "$USER_ID" ]; then
    echo "  - Deleting existing user: ${USER_ID}"
    docker exec innover-wso2is-1 curl -sk -u "${ADMIN_USER}:${ADMIN_PASS}" \
      -X DELETE "${IS_BASE}/scim2/Users/${USER_ID}" 2>/dev/null || true
  fi
  
  # Get role ID
  ROLE_ID=$(docker exec innover-wso2is-1 curl -sk -u "${ADMIN_USER}:${ADMIN_PASS}" \
    "${IS_BASE}/scim2/Roles?filter=displayName+eq+${role}" 2>/dev/null | jq -r '.Resources[0].id // empty')
  
  if [ -z "$ROLE_ID" ]; then
    echo "  ⚠️  Role '${role}' not found, creating it..."
    ROLE_RESP=$(docker exec innover-wso2is-1 curl -sk -u "${ADMIN_USER}:${ADMIN_PASS}" \
      -H "Content-Type: application/json" \
      -d "{\"displayName\":\"${role}\"}" \
      "${IS_BASE}/scim2/Roles" 2>/dev/null)
    ROLE_ID=$(echo "$ROLE_RESP" | jq -r '.id')
  fi
  
  echo "  - Role ID: ${ROLE_ID}"
  
  # Create user with groups (WSO2 IS 7.x uses groups for role-based access)
  USER_DATA=$(cat <<EOF
{
  "schemas": ["urn:ietf:params:scim:schemas:core:2.0:User"],
  "userName": "${username}",
  "password": "${password}",
  "name": {
    "givenName": "${username}",
    "familyName": "User"
  },
  "emails": [{
    "value": "${username}@innover.local",
    "primary": true
  }],
  "urn:ietf:params:scim:schemas:extension:enterprise:2.0:User": {
    "employeeNumber": "EMP-${username}"
  }
}
EOF
)
  
  USER_RESP=$(docker exec innover-wso2is-1 curl -sk -u "${ADMIN_USER}:${ADMIN_PASS}" \
    -H "Content-Type: application/json" \
    -d "$USER_DATA" \
    "${IS_BASE}/scim2/Users" 2>/dev/null)
  
  NEW_USER_ID=$(echo "$USER_RESP" | jq -r '.id // empty')
  
  if [ -n "$NEW_USER_ID" ]; then
    echo "  ✅ User created: ${NEW_USER_ID}"
    
    # Assign role using PATCH on role endpoint
    echo "  - Assigning role '${role}'..."
    PATCH_ROLE=$(cat <<EOF
{
  "schemas": ["urn:ietf:params:scim:api:messages:2.0:PatchOp"],
  "Operations": [{
    "op": "add",
    "path": "users",
    "value": [{"value": "${NEW_USER_ID}"}]
  }]
}
EOF
)
    
    docker exec innover-wso2is-1 curl -sk -u "${ADMIN_USER}:${ADMIN_PASS}" \
      -X PATCH \
      -H "Content-Type: application/json" \
      -d "$PATCH_ROLE" \
      "${IS_BASE}/scim2/v2/Roles/${ROLE_ID}" 2>/dev/null >/dev/null || echo "    (role assignment may need manual verification)"
    
  else
    echo "  ❌ Failed to create user"
    echo "     $(echo "$USER_RESP" | jq -r '.detail // empty')"
  fi
  echo ""
done

echo "════════════════════════════════════════════════════════════════"
echo "Step 2: Configuring OAuth App to Include Claims"
echo "════════════════════════════════════════════════════════════════"
echo ""

# Get OAuth app
APP_ID=$(docker exec innover-wso2is-1 curl -sk -u "${ADMIN_USER}:${ADMIN_PASS}" \
  "${IS_BASE}/api/server/v1/applications?filter=name+co+is-password-client" 2>/dev/null | jq -r '.applications[0].id // empty')

if [ -z "$APP_ID" ]; then
  echo "❌ OAuth application not found"
  exit 1
fi

echo "OAuth App ID: ${APP_ID}"
echo ""

# Update claim configuration
CLAIM_CONFIG=$(cat <<'EOF'
{
  "dialect": "LOCAL",
  "claimMappings": [
    {
      "applicationClaim": "username",
      "localClaim": {"uri": "http://wso2.org/claims/username"}
    },
    {
      "applicationClaim": "email",
      "localClaim": {"uri": "http://wso2.org/claims/emailaddress"}
    },
    {
      "applicationClaim": "given_name",
      "localClaim": {"uri": "http://wso2.org/claims/givenname"}
    },
    {
      "applicationClaim": "family_name",
      "localClaim": {"uri": "http://wso2.org/claims/lastname"}
    },
    {
      "applicationClaim": "roles",
      "localClaim": {"uri": "http://wso2.org/claims/role"}
    },
    {
      "applicationClaim": "groups",
      "localClaim": {"uri": "http://wso2.org/claims/groups"}
    }
  ],
  "requestedClaims": [
    {"claim": {"uri": "http://wso2.org/claims/username"}, "mandatory": true},
    {"claim": {"uri": "http://wso2.org/claims/emailaddress"}, "mandatory": false},
    {"claim": {"uri": "http://wso2.org/claims/givenname"}, "mandatory": false},
    {"claim": {"uri": "http://wso2.org/claims/lastname"}, "mandatory": false},
    {"claim": {"uri": "http://wso2.org/claims/role"}, "mandatory": false},
    {"claim": {"uri": "http://wso2.org/claims/groups"}, "mandatory": false}
  ],
  "subject": {
    "claim": {"uri": "http://wso2.org/claims/username"},
    "includeUserDomain": false,
    "includeTenantDomain": false,
    "useMappedLocalSubject": true
  },
  "role": {
    "claim": {"uri": "http://wso2.org/claims/role"},
    "includeUserDomain": false,
    "mappings": []
  }
}
EOF
)

docker exec innover-wso2is-1 curl -sk -u "${ADMIN_USER}:${ADMIN_PASS}" \
  -X PUT \
  -H "Content-Type: application/json" \
  -d "$CLAIM_CONFIG" \
  "${IS_BASE}/api/server/v1/applications/${APP_ID}/claim-configuration" 2>/dev/null >/dev/null

echo "✅ Claim configuration updated"
echo ""

echo "════════════════════════════════════════════════════════════════"
echo "Step 3: Testing Token with Claims"
echo "════════════════════════════════════════════════════════════════"
echo ""

source /tmp/wso2is-app-credentials.sh

TOKEN_RESP=$(docker exec innover-wso2is-1 curl -sk -u "${IS_CLIENT_ID}:${IS_CLIENT_SECRET}" \
  -d "grant_type=password&username=finance&password=Finance123&scope=openid email profile" \
  "${IS_BASE}/oauth2/token" 2>/dev/null)

ACCESS_TOKEN=$(echo "$TOKEN_RESP" | jq -r '.access_token')

if [ -n "$ACCESS_TOKEN" ] && [ "$ACCESS_TOKEN" != "null" ]; then
  echo "JWT Payload:"
  echo "$ACCESS_TOKEN" | cut -d'.' -f2 | base64 -d 2>/dev/null | jq '.'
  echo ""
  
  # Test with userinfo endpoint
  echo "UserInfo Endpoint Response:"
  docker exec innover-wso2is-1 curl -sk -H "Authorization: Bearer ${ACCESS_TOKEN}" \
    "${IS_BASE}/oauth2/userinfo" 2>/dev/null | jq '.'
  echo ""
  
  echo "✅ Token generation successful"
  echo ""
  echo "Testing API call..."
  curl -s -H "Authorization: Bearer ${ACCESS_TOKEN}" \
    http://localhost:8280/api/forex/1.0.0/health | jq '.'
else
  echo "❌ Failed to get token"
  echo "$TOKEN_RESP" | jq '.'
fi

echo ""
echo "════════════════════════════════════════════════════════════════"
echo "✅ Configuration Complete!"
echo "════════════════════════════════════════════════════════════════"
