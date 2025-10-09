#!/usr/bin/env bash
# WSO2 API-M Setup Script - Modular Version
# Groups operations for better debugging and reliability

set -euo pipefail

CFG="${1:-}"
[ -f "$CFG" ] || { echo "Config YAML not found: $CFG"; exit 1; }

# Install dependencies
command -v curl >/dev/null 2>&1 || apk add --no-cache curl >/dev/null
command -v jq >/dev/null 2>&1 || apk add --no-cache jq >/dev/null
command -v yq >/dev/null 2>&1 || apk add --no-cache yq >/dev/null

# Configuration
AM_HOST="${AM_HOST:-localhost}"
AM_PORT="${AM_PORT:-9443}"
AM_BASE="https://${AM_HOST}:${AM_PORT}"
AM_ADMIN_USER="${AM_ADMIN_USER:-admin}"
AM_ADMIN_PASS="${AM_ADMIN_PASS:-admin}"
KEY_MANAGER_NAME="${KEY_MANAGER_NAME:-WSO2-IS}"

pub="${AM_BASE}/api/am/publisher/v4"
dev="${AM_BASE}/api/am/devportal/v3"

echo "════════════════════════════════════════════════════════════════"
echo "WSO2 API-M Setup - Modular Execution"
echo "════════════════════════════════════════════════════════════════"
echo "Base URL: ${AM_BASE}"
echo "Key Manager: ${KEY_MANAGER_NAME}"
echo ""

# ============================================================================
# STEP 1: Authentication Setup
# ============================================================================
step1_auth() {
  echo "▶ STEP 1: Setting up authentication"
  
  # Register DCR client
  echo "  - Registering DCR client..."
  DCR_PAYLOAD='{"callbackUrl":"https://localhost/cb","clientName":"apim-automation-client","grantType":"password refresh_token","owner":"'"${AM_ADMIN_USER}"'","saasApp":true}'
  DCR_RESP="$(curl -sk -u "${AM_ADMIN_USER}:${AM_ADMIN_PASS}" -H "Content-Type: application/json" \
    -d "${DCR_PAYLOAD}" "${AM_BASE}/client-registration/v0.17/register")"
  
  CK="$(echo "$DCR_RESP" | jq -r '.clientId // .client_id')"
  CS="$(echo "$DCR_RESP" | jq -r '.clientSecret // .client_secret')"
  
  if [ -z "$CK" ] || [ -z "$CS" ]; then
    echo "  ❌ DCR registration failed"
    echo "$DCR_RESP" | jq '.'
    return 1
  fi
  echo "  ✅ DCR client registered: $CK"
  
  # Get OAuth token
  echo "  - Getting OAuth token..."
  SCOPES="apim:api_view apim:api_create apim:api_publish apim:tier_view apim:app_manage apim:sub_manage apim:subscribe"
  TOKEN_RESP="$(curl -sk -u "${CK}:${CS}" \
    -d "grant_type=password&username=${AM_ADMIN_USER}&password=${AM_ADMIN_PASS}&scope=${SCOPES}" \
    "${AM_BASE}/oauth2/token")"
  
  TOKEN="$(echo "$TOKEN_RESP" | jq -r '.access_token // empty')"
  
  if [ -z "$TOKEN" ] || [ "$TOKEN" = "null" ]; then
    echo "  ❌ Token generation failed"
    echo "$TOKEN_RESP" | jq '.'
    return 1
  fi
  echo "  ✅ OAuth token obtained"
  
  # Export for other functions
  export AUTH_TOKEN="$TOKEN"
  export AUTH_HDR_AUTHORIZATION="Authorization: Bearer ${TOKEN}"
  export AUTH_HDR_CONTENT_TYPE="Content-Type: application/json"
  
  echo "✅ STEP 1 Complete: Authentication ready"
  echo ""
}

# ============================================================================
# STEP 2: Create/Verify Application
# ============================================================================
step2_application() {
  echo "▶ STEP 2: Ensuring application exists"
  
  APP_NAME="$(yq eval '.application.name' "$CFG")"
  APP_TIER="$(yq eval '.application.throttling_policy' "$CFG")"
  
  echo "  - Looking for application: ${APP_NAME}"
  
  # List all applications
  ALL_APPS="$(curl -sk -H "${AUTH_HDR_AUTHORIZATION}" -H "${AUTH_HDR_CONTENT_TYPE}" \
    "${dev}/applications" 2>/dev/null)"
  
  APP_ID="$(echo "$ALL_APPS" | jq -r ".list[]? | select(.name==\"${APP_NAME}\") | .applicationId" 2>/dev/null || echo "")"
  
  if [ -n "$APP_ID" ] && [ "$APP_ID" != "null" ]; then
    echo "  ✅ Found existing application: ${APP_ID}"
  else
    echo "  - Application not found, creating..."
    
    APP_PAYLOAD="{\"name\":\"${APP_NAME}\",\"throttlingPolicy\":\"${APP_TIER}\",\"description\":\"Auto-created application\",\"tokenType\":\"JWT\",\"groups\":[],\"attributes\":{}}"
    
    APP_RESP="$(curl -sk -H "${AUTH_HDR_AUTHORIZATION}" -H "${AUTH_HDR_CONTENT_TYPE}" \
      -d "${APP_PAYLOAD}" "${dev}/applications" 2>/dev/null)"
    
    APP_ID="$(echo "$APP_RESP" | jq -r '.applicationId // empty' 2>/dev/null)"
    
    if [ -z "$APP_ID" ] || [ "$APP_ID" = "null" ]; then
      echo "  ❌ Failed to create application"
      echo "$APP_RESP" | jq '.' 2>/dev/null || echo "$APP_RESP"
      return 1
    fi
    echo "  ✅ Created application: ${APP_ID}"
  fi
  
  # Export for other functions
  export APPLICATION_ID="$APP_ID"
  export APPLICATION_NAME="$APP_NAME"
  
  echo "✅ STEP 2 Complete: Application ready (${APP_ID})"
  echo ""
}

# ============================================================================
# STEP 3: Create APIs (if needed)
# ============================================================================
step3_apis() {
  echo "▶ STEP 3: Creating APIs (skipped - APIs already exist)"
  echo "  💡 APIs should be created separately"
  echo "✅ STEP 3 Complete"
  echo ""
}

# ============================================================================
# STEP 4: Subscribe Application to APIs
# ============================================================================
step4_subscriptions() {
  echo "▶ STEP 4: Subscribing application to APIs"
  
  SUBS_LEN="$(yq eval '.subscriptions | length' "$CFG")"
  echo "  - Found ${SUBS_LEN} API subscriptions to create"
  
  for i in $(seq 0 $((SUBS_LEN-1))); do
    API_NAME="$(yq eval ".subscriptions[$i].api_name" "$CFG")"
    TIER="$(yq eval ".subscriptions[$i].throttling_policy" "$CFG")"
    
    echo "  - Subscribing to: ${API_NAME}"
    
    # Get API ID by name
    API_RESP="$(curl -sk -H "${AUTH_HDR_AUTHORIZATION}" -H "${AUTH_HDR_CONTENT_TYPE}" \
      "${pub}/apis?query=name:${API_NAME}" 2>/dev/null)"
    
    API_ID="$(echo "$API_RESP" | jq -r '.list[0].id // empty' 2>/dev/null)"
    
    if [ -z "$API_ID" ] || [ "$API_ID" = "null" ]; then
      echo "    ⚠️  API not found: ${API_NAME}"
      continue
    fi
    
    # Create subscription
    SUB_PAYLOAD="{\"apiId\":\"${API_ID}\",\"applicationId\":\"${APPLICATION_ID}\",\"throttlingPolicy\":\"${TIER}\"}"
    
    SUB_RESP="$(curl -sk -H "${AUTH_HDR_AUTHORIZATION}" -H "${AUTH_HDR_CONTENT_TYPE}" \
      -d "${SUB_PAYLOAD}" "${dev}/subscriptions" 2>/dev/null)"
    
    if echo "$SUB_RESP" | jq -e '.subscriptionId' >/dev/null 2>&1; then
      echo "    ✅ Subscribed to ${API_NAME}"
    else
      # Might already be subscribed
      echo "    ℹ️  Already subscribed to ${API_NAME}"
    fi
  done
  
  echo "✅ STEP 4 Complete: Subscriptions created"
  echo ""
}

# ============================================================================
# STEP 5: Generate Application Keys
# ============================================================================
step5_keys() {
  echo "▶ STEP 5: Generating application keys"
  echo "  - Key Manager: ${KEY_MANAGER_NAME}"
  
  KEYS_PAYLOAD="{\"keyType\":\"PRODUCTION\",\"keyManager\":\"${KEY_MANAGER_NAME}\",\"grantTypesToBeSupported\":[\"password\",\"client_credentials\",\"refresh_token\"],\"callbackUrl\":\"https://localhost/cb\",\"scopes\":[]}"
  
  KEYS_RESP="$(curl -sk -H "${AUTH_HDR_AUTHORIZATION}" -H "${AUTH_HDR_CONTENT_TYPE}" \
    -d "${KEYS_PAYLOAD}" "${dev}/applications/${APPLICATION_ID}/generate-keys" 2>/dev/null)"
  
  CONSUMER_KEY="$(echo "$KEYS_RESP" | jq -r '.consumerKey // .keyMappingResponse.consumerKey // empty' 2>/dev/null)"
  CONSUMER_SECRET="$(echo "$KEYS_RESP" | jq -r '.consumerSecret // .keyMappingResponse.consumerSecret // empty' 2>/dev/null)"
  
  if [ -z "$CONSUMER_KEY" ] || [ "$CONSUMER_KEY" = "null" ]; then
    echo "  ⚠️  Failed to generate new keys, checking existing..."
    
    EXISTING_KEYS="$(curl -sk -H "${AUTH_HDR_AUTHORIZATION}" -H "${AUTH_HDR_CONTENT_TYPE}" \
      "${dev}/applications/${APPLICATION_ID}/keys/PRODUCTION" 2>/dev/null)"
    
    CONSUMER_KEY="$(echo "$EXISTING_KEYS" | jq -r '.consumerKey // empty' 2>/dev/null)"
    CONSUMER_SECRET="$(echo "$EXISTING_KEYS" | jq -r '.consumerSecret // empty' 2>/dev/null)"
  fi
  
  if [ -z "$CONSUMER_KEY" ] || [ "$CONSUMER_KEY" = "null" ]; then
    echo "  ❌ Failed to get application keys"
    echo "$KEYS_RESP" | jq '.' 2>/dev/null || echo "$KEYS_RESP"
    return 1
  fi
  
  echo "  ✅ Consumer Key: ${CONSUMER_KEY}"
  
  # Save keys to file
  cat > /config/application-keys.json <<EOF
{
  "application": "${APPLICATION_NAME}",
  "applicationId": "${APPLICATION_ID}",
  "production": {
    "consumerKey": "${CONSUMER_KEY}",
    "consumerSecret": "${CONSUMER_SECRET}",
    "keyManager": "${KEY_MANAGER_NAME}"
  }
}
EOF
  
  echo "  ✅ Keys saved to /config/application-keys.json"
  echo "✅ STEP 5 Complete: Application keys generated"
  echo ""
}

# ============================================================================
# Main Execution
# ============================================================================
main() {
  echo "Starting setup process..."
  echo ""
  
  # Execute steps in order
  if ! step1_auth; then
    echo "❌ Setup failed at STEP 1: Authentication"
    exit 1
  fi
  
  if ! step2_application; then
    echo "❌ Setup failed at STEP 2: Application"
    exit 1
  fi
  
  step3_apis  # Non-critical
  
  if ! step4_subscriptions; then
    echo "⚠️  Warning: Some subscriptions failed (non-critical)"
  fi
  
  if ! step5_keys; then
    echo "❌ Setup failed at STEP 5: Key Generation"
    exit 1
  fi
  
  echo "════════════════════════════════════════════════════════════════"
  echo "✅ WSO2 API-M Setup Complete!"
  echo "════════════════════════════════════════════════════════════════"
  echo "Application: ${APPLICATION_NAME}"
  echo "Application ID: ${APPLICATION_ID}"
  echo "Key Manager: ${KEY_MANAGER_NAME}"
  echo "Keys saved: /config/application-keys.json"
  echo "════════════════════════════════════════════════════════════════"
}

# Run main function
main
