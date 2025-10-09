#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# Manual API Publishing Script
# ============================================================================
# This script publishes APIs, creates subscriptions, and generates keys
# Run this AFTER WSO2 APIM has fully started
#
# Usage:
#   docker exec innover-wso2am-1 /home/wso2carbon/publish-apis-manual.sh
#   Or from host: docker compose exec wso2am /home/wso2carbon/publish-apis-manual.sh
# ============================================================================

echo "════════════════════════════════════════════════════════════════"
echo "Manual API Publishing Script"
echo "════════════════════════════════════════════════════════════════"
echo ""

# Configuration
CFG="${1:-/config/api-config.yaml}"
AM_HOST="${AM_HOST:-localhost}"
AM_PORT="${AM_PORT:-9443}"
AM_BASE="https://${AM_HOST}:${AM_PORT}"
AM_ADMIN_USER="${AM_ADMIN_USER:-admin}"
AM_ADMIN_PASS="${AM_ADMIN_PASS:-admin}"
KEY_MANAGER_NAME="${KEY_MANAGER_NAME:-WSO2-IS}"
KM_TOKEN_ENDPOINT="${KM_TOKEN_ENDPOINT:-https://wso2is:9443/oauth2/token}"

if [ ! -f "$CFG" ]; then
  echo "❌ Config file not found: $CFG"
  exit 1
fi

echo "📋 Configuration:"
echo "  Config: $CFG"
echo "  API-M: ${AM_BASE}"
echo "  Key Manager: ${KEY_MANAGER_NAME}"
echo ""

# ---------- DCR for REST API access ----------
echo "▶ Registering API-M REST client (DCR)"
DCR_PAYLOAD='{"callbackUrl":"https://localhost/cb","clientName":"apim-manual-publish","grantType":"password refresh_token","owner":"'"${AM_ADMIN_USER}"'","saasApp":true}'
DCR_RESP="$(curl -sk -u "${AM_ADMIN_USER}:${AM_ADMIN_PASS}" -H "Content-Type: application/json" \
  -d "${DCR_PAYLOAD}" "${AM_BASE}/client-registration/v0.17/register")"
CK="$(echo "$DCR_RESP" | jq -r '.clientId // .client_id')"
CS="$(echo "$DCR_RESP" | jq -r '.clientSecret // .client_secret')"
[ -n "$CK" ] && [ -n "$CS" ] || { echo "❌ DCR failed"; echo "$DCR_RESP" | jq .; exit 1; }
echo "  ✓ Client registered"

# ---------- Get access token ----------
echo "▶ Getting admin access token (1 day validity)"
SCOPES="apim:api_view apim:api_create apim:api_publish apim:tier_view apim:app_manage apim:sub_manage apim:subscribe"
TOKEN_RESP="$(curl -sk -u "${CK}:${CS}" -d "grant_type=password&username=${AM_ADMIN_USER}&password=${AM_ADMIN_PASS}&scope=${SCOPES}&validity_period=86400" \
  "${AM_BASE}/oauth2/token")"
TOKEN="$(echo "$TOKEN_RESP" | jq -r '.access_token // empty')"

if [ -z "$TOKEN" ] || [ "$TOKEN" = "null" ]; then
  echo "❌ Token generation failed. Response:"
  echo "$TOKEN_RESP" | jq .
  exit 1
fi
echo "  ✓ Token obtained"

# Set up auth headers
AUTH_HDR=(-H "Authorization: Bearer ${TOKEN}" -H "Content-Type: application/json")
pub="${AM_BASE}/api/am/publisher/v4"
dev="${AM_BASE}/api/am/devportal/v3"

# Helper: call API and capture HTTP status + body
call() {
  local method="$1" url="$2" body="${3:-}"
  local tmp="$(mktemp)"
  local code
  if [ -n "$body" ]; then
    code=$(curl -sk -X "$method" "$url" "${AUTH_HDR[@]}" -d "$body" -o "$tmp" -w '%{http_code}')
  else
    code=$(curl -sk -X "$method" "$url" "${AUTH_HDR[@]}" -o "$tmp" -w '%{http_code}')
  fi
  echo "$code"
  cat "$tmp"
  rm -f "$tmp"
}

# ---------- Publish APIs ----------
echo ""
echo "▶ Publishing APIs from $CFG"
API_COUNT=$(yq eval '.apis | length' "$CFG")
echo "  Found ${API_COUNT} APIs to publish"
echo ""

for i in $(seq 0 $((API_COUNT - 1))); do
  name="$(yq eval ".apis[$i].name" "$CFG")"
  echo "[$i/$((API_COUNT-1))] Processing: $name"
  
  # Check if API exists
  API_SEARCH="$(curl -sk "${pub}/apis" "${AUTH_HDR[@]}" --get --data-urlencode "query=name:${name}")"
  api_id="$(echo "$API_SEARCH" | jq -r '.list[0].id // empty')"
  
  if [ -z "$api_id" ]; then
    echo "  ⚠️  API not found: ${name}"
    continue
  fi
  
  echo "  - API ID: ${api_id}"
  
  # Get current lifecycle state
  LIFECYCLE_STATE="$(curl -sk "${pub}/apis/${api_id}" "${AUTH_HDR[@]}" | jq -r '.lifeCycleStatus')"
  echo "  - Current state: ${LIFECYCLE_STATE}"
  
  if [ "$LIFECYCLE_STATE" = "PUBLISHED" ]; then
    echo "  ✓ Already published"
    continue
  fi
  
  # Create revision
  echo "  - Creating revision..."
  REV_RESP="$(call POST "${pub}/apis/${api_id}/revisions" '{"description":"Manual publish"}')"
  REV_CODE="$(echo "$REV_RESP" | head -1)"
  REV_BODY="$(echo "$REV_RESP" | tail -n +2)"
  
  if [ "$REV_CODE" != "201" ]; then
    echo "  ❌ Revision creation failed (HTTP ${REV_CODE})"
    echo "$REV_BODY" | jq . 2>/dev/null || echo "$REV_BODY"
    continue
  fi
  
  # Detect revision ID format (UUID vs numeric)
  REV_ID="$(echo "$REV_BODY" | jq -r '.id // empty')"
  if [[ "$REV_ID" =~ ^[0-9]+$ ]]; then
    REV_FIELD="revisionId"
  else
    REV_FIELD="revisionUuid"
  fi
  echo "  - Revision created: ${REV_ID}"
  
  # Deploy revision
  echo "  - Deploying revision to Default gateway..."
  DEPLOY_PAYLOAD='[{"'${REV_FIELD}'":"'${REV_ID}'","name":"Default","vhost":"localhost","displayOnDevportal":true}]'
  DEPLOY_RESP="$(call POST "${pub}/apis/${api_id}/deploy-revision?revisionId=${REV_ID}" "$DEPLOY_PAYLOAD")"
  DEPLOY_CODE="$(echo "$DEPLOY_RESP" | head -1)"
  
  if [ "$DEPLOY_CODE" != "201" ] && [ "$DEPLOY_CODE" != "200" ]; then
    echo "  ⚠️  Deploy failed (HTTP ${DEPLOY_CODE})"
    echo "$DEPLOY_RESP" | tail -n +2 | jq . 2>/dev/null || echo "$DEPLOY_RESP" | tail -n +2
  else
    echo "  ✓ Revision deployed"
  fi
  
  # Publish API
  echo "  - Publishing API..."
  PUB_RESP="$(call POST "${pub}/apis/change-lifecycle?apiId=${api_id}&action=Publish" "")"
  PUB_CODE="$(echo "$PUB_RESP" | head -1)"
  
  if [ "$PUB_CODE" = "200" ]; then
    echo "  ✅ Published: ${name}"
  else
    echo "  ⚠️  Publish failed (HTTP ${PUB_CODE})"
  fi
  echo ""
done

# ---------- Create subscriptions ----------
echo "▶ Creating subscriptions"
APP_NAME="$(yq eval '.application.name' "$CFG")"
APP_TIER="$(yq eval '.application.throttling_policy' "$CFG")"
echo "  Application: ${APP_NAME}"

# Find or create application
APP_QRY="$(curl -sk "${dev}/applications" "${AUTH_HDR[@]}" --get --data-urlencode "query=name:${APP_NAME}")"
APP_ID="$(echo "$APP_QRY" | jq -r '.list[0].applicationId // empty')"

if [ -z "${APP_ID}" ] || [ "${APP_ID}" = "null" ]; then
  echo "  - Creating application..."
  ALL_APPS="$(curl -sk "${dev}/applications" "${AUTH_HDR[@]}")"
  APP_ID="$(echo "$ALL_APPS" | jq -r --arg name "$APP_NAME" '.list[] | select(.name == $name) | .applicationId // empty')"
fi

if [ -z "${APP_ID}" ] || [ "${APP_ID}" = "null" ]; then
  APP_PAYLOAD='{"name":"'"${APP_NAME}"'","throttlingPolicy":"'"${APP_TIER}"'","description":"auto-created","tokenType":"JWT","groups":[],"attributes":{}}'
  TMP="$(mktemp)"
  CODE=$(curl -sk -o "$TMP" -w '%{http_code}' "${dev}/applications" "${AUTH_HDR[@]}" -d "${APP_PAYLOAD}")
  if [ "$CODE" = "201" ]; then
    APP_ID="$(jq -r '.applicationId' "$TMP")"
    echo "  ✓ Application created: ${APP_ID}"
  else
    echo "  ❌ Failed to create application (HTTP ${CODE})"
    jq . "$TMP" 2>/dev/null || cat "$TMP"
    rm -f "$TMP"
    exit 1
  fi
  rm -f "$TMP"
else
  echo "  ✓ Application found: ${APP_ID}"
fi

# Subscribe to all APIs
echo "  - Creating subscriptions..."
for i in $(seq 0 $((API_COUNT - 1))); do
  name="$(yq eval ".apis[$i].name" "$CFG")"
  tier="$(yq eval ".apis[$i].subscription_tier // \"Unlimited\"" "$CFG")"
  
  API_SEARCH="$(curl -sk "${pub}/apis" "${AUTH_HDR[@]}" --get --data-urlencode "query=name:${name}")"
  api_id="$(echo "$API_SEARCH" | jq -r '.list[0].id // empty')"
  
  if [ -z "$api_id" ]; then
    echo "    ⚠️  Skipping ${name} (not found)"
    continue
  fi
  
  SUB_PAYLOAD='{"apiId":"'"${api_id}"'","applicationId":"'"${APP_ID}"'","throttlingPolicy":"'"${tier}"'"}'
  SUB_RESP="$(call POST "${dev}/subscriptions" "$SUB_PAYLOAD")"
  SUB_CODE="$(echo "$SUB_RESP" | head -1)"
  
  if [ "$SUB_CODE" = "201" ]; then
    echo "    ✓ Subscribed to ${name}"
  elif [ "$SUB_CODE" = "409" ]; then
    echo "    ✓ Already subscribed to ${name}"
  else
    echo "    ⚠️  Failed to subscribe to ${name} (HTTP ${SUB_CODE})"
  fi
done

# ---------- Generate keys ----------
echo ""
echo "▶ Generating PRODUCTION keys for ${APP_NAME}"
echo "  Key Manager: ${KEY_MANAGER_NAME}"

GEN_PAYLOAD='{"keyType":"PRODUCTION","keyManager":"'"${KEY_MANAGER_NAME}"'","grantTypesToBeSupported":["password","client_credentials","refresh_token"],"validityTime":3600}'
GEN_RESP="$(call POST "${dev}/applications/${APP_ID}/generate-keys" "$GEN_PAYLOAD")"
GEN_CODE="$(echo "$GEN_RESP" | head -1)"
GEN_BODY="$(echo "$GEN_RESP" | tail -n +2)"

CK_APP="$(echo "${GEN_BODY}" | jq -r '.consumerKey // .keyMappingInfo.consumerKey // empty')"
CS_APP="$(echo "${GEN_BODY}" | jq -r '.consumerSecret // .keyMappingInfo.consumerSecret // empty')"

if [ -z "${CK_APP}" ] || [ -z "${CS_APP}" ]; then
  echo "  - Checking existing keys..."
  KEYS_RESP="$(curl -sk "${dev}/applications/${APP_ID}/keys/PRODUCTION" "${AUTH_HDR[@]}")"
  CK_APP="$(echo "${KEYS_RESP}" | jq -r '.consumerKey // empty')"
  CS_APP="$(echo "${KEYS_RESP}" | jq -r '.consumerSecret // empty')"
fi

if [ -z "${CK_APP}" ] || [ -z "${CS_APP}" ] || [ "${CK_APP}" = "null" ] || [ "${CS_APP}" = "null" ]; then
  echo "  ⚠️  Could not get consumer key/secret"
  echo "  You may need to generate keys manually via Developer Portal"
else
  echo "  ✅ Keys generated successfully!"
  echo ""
  echo "  Consumer Key:    ${CK_APP}"
  echo "  Consumer Secret: ${CS_APP}"
  echo ""
  
  # Test token generation
  if [ "${KEY_MANAGER_NAME}" = "Resident Key Manager" ]; then
    TOKEN_EP="${AM_BASE}/oauth2/token"
  else
    TOKEN_EP="${KM_TOKEN_ENDPOINT}"
  fi
  
  echo "  Testing token generation..."
  TEST_TOKEN_RESP="$(curl -sk -u "${CK_APP}:${CS_APP}" -d "grant_type=client_credentials" "${TOKEN_EP}")"
  TEST_TOKEN="$(echo "$TEST_TOKEN_RESP" | jq -r '.access_token // empty')"
  
  if [ -n "$TEST_TOKEN" ] && [ "$TEST_TOKEN" != "null" ]; then
    echo "  ✅ Token generated successfully!"
    echo "  Access Token: ${TEST_TOKEN:0:50}..."
  else
    echo "  ⚠️  Token generation test failed"
    echo "$TEST_TOKEN_RESP" | jq .
  fi
fi

echo ""
echo "════════════════════════════════════════════════════════════════"
echo "✅ Manual API Publishing Complete"
echo "════════════════════════════════════════════════════════════════"
echo ""
echo "📝 Summary:"
echo "  - APIs published: ${API_COUNT}"
echo "  - Application: ${APP_NAME} (${APP_ID})"
echo "  - Subscriptions created"
echo "  - Keys generated with ${KEY_MANAGER_NAME}"
echo ""
echo "🌐 Access WSO2 APIM:"
echo "  Developer Portal: ${AM_BASE}/devportal"
echo "  Publisher:        ${AM_BASE}/publisher"
echo "  Admin Portal:     ${AM_BASE}/admin"
echo ""
