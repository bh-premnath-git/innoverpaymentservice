#!/bin/bash
set -euo pipefail

# ============================================================================
# Register WSO2 IS 7.1.0 as Third-Party Key Manager in APIM 4.5.0
# ============================================================================
# This script configures WSO2 Identity Server as a Key Manager in APIM
# so that users created in IS can authenticate via APIM Gateway.
#
# Prerequisites:
# - WSO2 IS must be running and healthy
# - WSO2 AM must be running and healthy
# - IS7 must have deployment.toml configured (see wso2is/deployment.toml)
# ============================================================================

AM_HOST="${AM_HOST:-wso2am}"
AM_PORT="${AM_PORT:-9443}"
AM_BASE="https://${AM_HOST}:${AM_PORT}"
AM_ADMIN_USER="${AM_ADMIN_USER:-admin}"
AM_ADMIN_PASS="${AM_ADMIN_PASS:-admin}"

KM_NAME="WSO2-IS"
KM_CONFIG_FILE="/home/wso2carbon/is7-key-manager.json"

echo "════════════════════════════════════════════════════════════════"
echo "Registering WSO2 IS 7 as Third-Party Key Manager"
echo "════════════════════════════════════════════════════════════════"
echo ""

# Wait for APIM Admin API to be ready
echo "⏳ Waiting for APIM Admin API..."
MAX_WAIT=300
ELAPSED=0
until curl -sk -u "${AM_ADMIN_USER}:${AM_ADMIN_PASS}" \
  "${AM_BASE}/api/am/admin/v4/key-managers" >/dev/null 2>&1; do
  if [ $ELAPSED -ge $MAX_WAIT ]; then
    echo "❌ APIM Admin API not ready after ${MAX_WAIT}s"
    exit 1
  fi
  sleep 5
  ELAPSED=$((ELAPSED + 5))
  echo "   ... waiting (${ELAPSED}/${MAX_WAIT}s)"
done
echo "✅ APIM Admin API ready"
echo ""

# Check if Key Manager already exists
echo "🔍 Checking if Key Manager '${KM_NAME}' exists..."
EXISTING_KM=$(curl -sk -u "${AM_ADMIN_USER}:${AM_ADMIN_PASS}" \
  "${AM_BASE}/api/am/admin/v4/key-managers" | \
  jq -r ".list[] | select(.name==\"${KM_NAME}\") | .id" 2>/dev/null || echo "")

if [ -n "$EXISTING_KM" ]; then
  echo "✅ Key Manager '${KM_NAME}' already exists (ID: ${EXISTING_KM})"
  echo ""
  echo "To update, delete first:"
  echo "  curl -sk -u admin:admin -X DELETE \\"
  echo "    ${AM_BASE}/api/am/admin/v4/key-managers/${EXISTING_KM}"
  echo ""
  exit 0
fi

echo "📝 Key Manager not found, creating..."
echo ""

# Register IS7 as Key Manager
if [ ! -f "$KM_CONFIG_FILE" ]; then
  echo "❌ Key Manager config file not found: $KM_CONFIG_FILE"
  exit 1
fi

echo "📤 Registering Key Manager from: $KM_CONFIG_FILE"
RESPONSE=$(curl -sk -u "${AM_ADMIN_USER}:${AM_ADMIN_PASS}" \
  -H "Content-Type: application/json" \
  -d @"${KM_CONFIG_FILE}" \
  -w "\n%{http_code}" \
  "${AM_BASE}/api/am/admin/v4/key-managers")

HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
BODY=$(echo "$RESPONSE" | head -n-1)

if [ "$HTTP_CODE" = "201" ] || [ "$HTTP_CODE" = "200" ]; then
  KM_ID=$(echo "$BODY" | jq -r '.id' 2>/dev/null || echo "")
  echo "✅ Key Manager registered successfully!"
  echo "   ID: ${KM_ID}"
  echo "   Name: ${KM_NAME}"
  echo ""
  echo "════════════════════════════════════════════════════════════════"
  echo "✅ WSO2 IS 7 Key Manager Configuration Complete"
  echo "════════════════════════════════════════════════════════════════"
  echo ""
  echo "📋 Next Steps:"
  echo "   1. Verify in Admin Portal: ${AM_BASE}/admin"
  echo "   2. Update apim-publish-from-yaml.sh to use keyManager: 'WSO2-IS'"
  echo "   3. Test with IS users: finance, auditor, ops_user, etc."
  echo ""
else
  echo "❌ Failed to register Key Manager (HTTP ${HTTP_CODE})"
  echo ""
  echo "Response:"
  echo "$BODY" | jq '.' 2>/dev/null || echo "$BODY"
  echo ""
  
  # Check for common errors
  if echo "$BODY" | grep -q "already exists"; then
    echo "💡 Key Manager might already exist. Check Admin Portal."
  elif echo "$BODY" | grep -q "well-known"; then
    echo "💡 Cannot reach IS well-known endpoint. Check:"
    echo "   - IS is running: docker ps | grep wso2is"
    echo "   - IS health: curl -k https://wso2is:9443/oauth2/token/.well-known/openid-configuration"
  fi
  
  exit 1
fi
