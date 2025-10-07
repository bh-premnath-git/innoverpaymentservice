#!/usr/bin/env bash
# Registers WSO2 Identity Server 7.1.0 as a Key Manager in WSO2 API-M 4.5.0
# via the Admin REST API
#
# Usage: ./register-keymanager.sh
#
# Environment variables:
#   AM_HOST      - API Manager host (default: localhost)
#   AM_PORT      - API Manager port (default: 9443)
#   AM_ADMIN_USER - Admin username (default: admin)
#   AM_ADMIN_PASS - Admin password (default: admin)
#   IS_HOST      - Identity Server host (default: wso2is)
#   IS_PORT      - Identity Server port (default: 9443)
#   KM_NAME      - Key Manager name (default: WSO2-IS)
#   IS_ADMIN_USER - IS admin username (default: admin)
#   IS_ADMIN_PASS - IS admin password (default: admin)

set -euo pipefail

# ---------- Configuration ----------
AM_HOST="${AM_HOST:-localhost}"
AM_PORT="${AM_PORT:-9443}"
AM_BASE="https://${AM_HOST}:${AM_PORT}"
AM_ADMIN_USER="${AM_ADMIN_USER:-admin}"
AM_ADMIN_PASS="${AM_ADMIN_PASS:-admin}"

IS_HOST="${IS_HOST:-wso2is}"
IS_PORT="${IS_PORT:-9443}"
IS_BASE="https://${IS_HOST}:${IS_PORT}"

KM_NAME="${KM_NAME:-WSO2-IS}"
IS_ADMIN_USER="${IS_ADMIN_USER:-admin}"
IS_ADMIN_PASS="${IS_ADMIN_PASS:-admin}"

echo "▶ Registering WSO2 IS as Key Manager in API-M"
echo "  API-M: ${AM_BASE}"
echo "  WSO2 IS: ${IS_BASE}"
echo "  Key Manager Name: ${KM_NAME}"

# ---------- DCR for Admin API access ----------
echo "▶ Registering Admin API client (DCR)"
DCR_PAYLOAD='{"callbackUrl":"https://localhost/cb","clientName":"admin-api-client","grantType":"password refresh_token","owner":"'"${AM_ADMIN_USER}"'","saasApp":true}'
DCR_RESP="$(curl -sk -u "${AM_ADMIN_USER}:${AM_ADMIN_PASS}" \
  -H "Content-Type: application/json" \
  -d "${DCR_PAYLOAD}" \
  "${AM_BASE}/client-registration/v0.17/register")"

CK="$(echo "$DCR_RESP" | jq -r '.clientId // .client_id')"
CS="$(echo "$DCR_RESP" | jq -r '.clientSecret // .client_secret')"

if [ -z "$CK" ] || [ -z "$CS" ] || [ "$CK" = "null" ] || [ "$CS" = "null" ]; then
  echo "!! DCR failed. Response:"
  echo "$DCR_RESP" | jq .
  exit 1
fi

echo "  - Client registered: ${CK}"

# ---------- Get admin access token ----------
echo "▶ Getting admin access token"
SCOPES="apim:admin apim:api_key"
TOKEN_RESP="$(curl -sk -u "${CK}:${CS}" \
  -d "grant_type=password&username=${AM_ADMIN_USER}&password=${AM_ADMIN_PASS}&scope=${SCOPES}" \
  "${AM_BASE}/oauth2/token")"

TOKEN="$(echo "$TOKEN_RESP" | jq -r '.access_token // empty')"

if [ -z "$TOKEN" ] || [ "$TOKEN" = "null" ]; then
  echo "!! Token generation failed. Response:"
  echo "$TOKEN_RESP" | jq .
  exit 1
fi

echo "  - Token obtained"

# ---------- Check if Key Manager already exists ----------
echo "▶ Checking if Key Manager '${KM_NAME}' already exists"
EXISTING_KM="$(curl -sk -H "Authorization: Bearer ${TOKEN}" \
  "${AM_BASE}/api/am/admin/v4/key-managers" | jq -r --arg name "$KM_NAME" '.list[] | select(.name == $name) | .id // empty')"

if [ -n "$EXISTING_KM" ]; then
  echo "  ⚠️  Key Manager '${KM_NAME}' already exists (ID: ${EXISTING_KM})"
  echo "  - Skipping registration. Delete it via Admin Portal if you want to re-register."
  exit 0
fi

# ---------- Register Key Manager ----------
echo "▶ Registering Key Manager '${KM_NAME}'"

# Build the Key Manager configuration JSON
KM_CONFIG=$(cat <<EOF
{
  "name": "${KM_NAME}",
  "displayName": "${KM_NAME}",
  "type": "WSO2-IS",
  "description": "WSO2 Identity Server 7.1.0 as external Key Manager",
  "enabled": true,
  "issuer": "${IS_BASE}/oauth2/token",
  "endpoints": [
    {
      "name": "client_registration_endpoint",
      "value": "${IS_BASE}/api/identity/oauth2/dcr/v1.1/register"
    },
    {
      "name": "introspection_endpoint",
      "value": "${IS_BASE}/oauth2/introspect"
    },
    {
      "name": "token_endpoint",
      "value": "${IS_BASE}/oauth2/token"
    },
    {
      "name": "display_token_endpoint",
      "value": "${IS_BASE}/oauth2/token"
    },
    {
      "name": "revoke_endpoint",
      "value": "${IS_BASE}/oauth2/revoke"
    },
    {
      "name": "display_revoke_endpoint",
      "value": "${IS_BASE}/oauth2/revoke"
    },
    {
      "name": "userinfo_endpoint",
      "value": "${IS_BASE}/scim2/Me"
    },
    {
      "name": "authorize_endpoint",
      "value": "${IS_BASE}/oauth2/authorize"
    },
    {
      "name": "scope_management_endpoint",
      "value": "${IS_BASE}/api/identity/oauth2/v1.0/scopes"
    },
    {
      "name": "jwks_endpoint",
      "value": "${IS_BASE}/oauth2/jwks"
    }
  ],
  "availableGrantTypes": [
    "client_credentials",
    "password",
    "refresh_token",
    "authorization_code",
    "urn:ietf:params:oauth:grant-type:saml2-bearer",
    "urn:ietf:params:oauth:grant-type:jwt-bearer"
  ],
  "additionalProperties": {
    "Username": "${IS_ADMIN_USER}",
    "Password": "${IS_ADMIN_PASS}",
    "api_resource_mgt_endpoint": "${IS_BASE}/api/server/v1/api-resources",
    "roles_endpoint": "${IS_BASE}/scim2/v2/Roles",
    "self_validate_jwt": "true",
    "claim_mappings": [
      {
        "remoteClaim": "sub",
        "localClaim": "http://wso2.org/claims/enduser"
      },
      {
        "remoteClaim": "groups",
        "localClaim": "http://wso2.org/claims/role"
      }
    ]
  },
  "tokenType": "JWT"
}
EOF
)

# Register the Key Manager
RESP="$(curl -sk -X POST "${AM_BASE}/api/am/admin/v4/key-managers" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  -d "$KM_CONFIG")"

KM_ID="$(echo "$RESP" | jq -r '.id // empty')"

if [ -z "$KM_ID" ] || [ "$KM_ID" = "null" ]; then
  echo "!! Key Manager registration failed. Response:"
  echo "$RESP" | jq .
  exit 1
fi

echo "✅ Key Manager registered successfully!"
echo "  - ID: ${KM_ID}"
echo "  - Name: ${KM_NAME}"
echo ""
echo "📝 Next steps:"
echo "  1. Verify in Admin Portal: ${AM_BASE}/admin"
echo "  2. Set KEY_MANAGER_NAME=${KM_NAME} when running apim-publish-from-yaml.sh"
echo "  3. Ensure TLS certificates are trusted between containers"
echo ""
