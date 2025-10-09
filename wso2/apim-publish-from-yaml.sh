#!/usr/bin/env bash
# Bootstraps WSO2 API-M 4.5.0 using your YAML:
#  - Creates REST APIs
#  - Creates a revision, deploys it to the Gateway, and publishes the API
#  - Creates a devportal application, subscribes to all APIs, generates keys
#  - Prints a gateway curl for each API (HTTPS 8243)
#
# Usage: ./apim-publish-from-yaml.sh /path/to/config.yaml
#
# Requires: curl, jq, yq (installs via apk if missing)

set -euo pipefail

CFG="${1:-}"
[ -f "$CFG" ] || { echo "Config YAML not found: $CFG"; exit 1; }

need() { command -v "$1" >/dev/null 2>&1 || apk add --no-cache "$1" >/dev/null; }
need curl; need jq; need yq

# ---------- Config (override via env) ----------
AM_HOST="${AM_HOST:-localhost}"
AM_PORT="${AM_PORT:-9443}"
AM_BASE="https://${AM_HOST}:${AM_PORT}"
AM_ADMIN_USER="${AM_ADMIN_USER:-admin}"
AM_ADMIN_PASS="${AM_ADMIN_PASS:-admin}"
GW_HOST="${GW_HOST:-${AM_HOST}}"
GW_PORT="${GW_PORT:-8243}"
VHOST="${VHOST:-localhost}"
KEY_MANAGER_NAME="${KEY_MANAGER_NAME:-Resident Key Manager}"  # Use "WSO2-IS" for external IS
KM_TOKEN_ENDPOINT="${KM_TOKEN_ENDPOINT:-https://wso2is:9443/oauth2/token}"  # Token endpoint for external KM

# ---------- DCR for REST API access ----------
echo "▶ Registering API-M REST client (DCR)"
DCR_PAYLOAD='{"callbackUrl":"https://localhost/cb","clientName":"apim-automation-client","grantType":"password refresh_token","owner":"'"${AM_ADMIN_USER}"'","saasApp":true}'
DCR_RESP="$(curl -sk -u "${AM_ADMIN_USER}:${AM_ADMIN_PASS}" -H "Content-Type: application/json" \
  -d "${DCR_PAYLOAD}" "${AM_BASE}/client-registration/v0.17/register")"
CK="$(echo "$DCR_RESP" | jq -r '.clientId // .client_id')"
CS="$(echo "$DCR_RESP" | jq -r '.clientSecret // .client_secret')"
[ -n "$CK" ] && [ -n "$CS" ] || { echo "!! DCR failed"; echo "$DCR_RESP" | jq .; exit 1; }

echo "▶ Getting admin access token (password grant)"
SCOPES="apim:api_view apim:api_create apim:api_publish apim:tier_view apim:app_manage apim:sub_manage apim:subscribe"
TOKEN_RESP="$(curl -sk -u "${CK}:${CS}" -d "grant_type=password&username=${AM_ADMIN_USER}&password=${AM_ADMIN_PASS}&scope=${SCOPES}" \
  "${AM_BASE}/oauth2/token")"
TOKEN="$(echo "$TOKEN_RESP" | jq -r '.access_token // empty')"

if [ -z "$TOKEN" ] || [ "$TOKEN" = "null" ]; then
  echo "!! Token generation failed. Response:"
  echo "$TOKEN_RESP" | jq .
  exit 1
fi

# Set up auth headers for API calls
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
  echo "$code" "$tmp"
}

get_api_id_by_name() {
  local name="$1"
  # URL-encode query to handle API names with spaces and special characters
  curl -sk --get "${pub}/apis" -H "Authorization: Bearer ${TOKEN}" \
    --data-urlencode "query=name:${name}" | jq -r '.list[0].id // empty'
}

create_api() {
  local name="$1" ctx="$2" ver="$3" be="$4" desc="$5" tags_json="$6"
  echo "  - creating API ${name}"
  local payload
  payload="$(jq -nc --arg name "$name" --arg ctx "$ctx" --arg ver "$ver" --arg be "$be" --arg desc "$desc" \
    --argjson tags "$tags_json" '{
      name:$name,
      context:$ctx,
      version:$ver,
      type:"HTTP",
      description:$desc,
      tags:$tags,
      endpointConfig:{
        endpoint_type:"http",
        sandbox_endpoints:{url:$be},
        production_endpoints:{url:$be}
      },
      transport:["http","https"],
      policies:["Unlimited"],
      apiThrottlingPolicy:"Unlimited",
      operations:[
        {target:"/*", verb:"GET",    throttlingPolicy:"Unlimited", authType:"Application & Application User"},
        {target:"/*", verb:"POST",   throttlingPolicy:"Unlimited", authType:"Application & Application User"},
        {target:"/*", verb:"PUT",    throttlingPolicy:"Unlimited", authType:"Application & Application User"},
        {target:"/*", verb:"DELETE", throttlingPolicy:"Unlimited", authType:"Application & Application User"}
      ]
    }')"
  
  read -r code tmp < <(call POST "${pub}/apis" "$payload")
  if [ "$code" != "201" ]; then
    echo "  !! Create failed (HTTP ${code})"
    echo "     Response:"; jq . "$tmp" 2>/dev/null || cat "$tmp"
    rm -f "$tmp"; return 1
  fi
  jq -r '.id' "$tmp"; rm -f "$tmp"
}

deploy_and_publish() {
  local api_id="$1"
  
  echo "  - creating revision"
  read -r code tmp < <(call POST "${pub}/apis/${api_id}/revisions" '{"description":"initial"}')
  if [ "$code" != "201" ]; then
    echo "  !! Revision failed (HTTP ${code})"
    jq . "$tmp" 2>/dev/null || cat "$tmp"
    rm -f "$tmp"; return 1
  fi
  
  # Extract both revision UUID and numeric ID with proper handling
  local rev_uuid rev_num dep_payload
  rev_uuid="$(jq -r '.id // .revisionUUID // empty' "$tmp")"
  rev_num="$(jq -r '.revisionId // empty' "$tmp")"
  rm -f "$tmp"
  
  # Determine which identifier to use and build appropriate payload
  if [ -n "$rev_uuid" ] && [ "$rev_uuid" != "null" ]; then
    if [[ "$rev_uuid" =~ ^[0-9]+$ ]]; then
      # Numeric ID - use revisionId field
      dep_payload="$(jq -nc --argjson rid "$rev_uuid" --arg vhost "$VHOST" '[{revisionId:$rid,name:"Default",vhost:$vhost,displayOnDevportal:true}]')"
      echo "  - deploying revision ${rev_uuid} (numeric) to Default@${VHOST}"
    else
      # UUID - use revisionUuid field
      dep_payload="$(jq -nc --arg rid "$rev_uuid" --arg vhost "$VHOST" '[{revisionUuid:$rid,name:"Default",vhost:$vhost,displayOnDevportal:true}]')"
      echo "  - deploying revision ${rev_uuid} to Default@${VHOST}"
    fi
  elif [ -n "$rev_num" ] && [ "$rev_num" != "null" ]; then
    if [[ "$rev_num" =~ ^[0-9]+$ ]]; then
      # Numeric ID from revisionId field
      dep_payload="$(jq -nc --argjson rid "$rev_num" --arg vhost "$VHOST" '[{revisionId:$rid,name:"Default",vhost:$vhost,displayOnDevportal:true}]')"
      echo "  - deploying revision ${rev_num} to Default@${VHOST}"
    else
      # UUID from revisionId field (unlikely but handle it)
      dep_payload="$(jq -nc --arg rid "$rev_num" --arg vhost "$VHOST" '[{revisionUuid:$rid,name:"Default",vhost:$vhost,displayOnDevportal:true}]')"
      echo "  - deploying revision ${rev_num} to Default@${VHOST}"
    fi
  else
    echo "  !! Could not determine revision identifier from create response"
    return 1
  fi
  
  # Deploy with revisionId query parameter (use first available identifier)
  local rev_id_param="${rev_uuid:-$rev_num}"
  read -r code tmp < <(call POST "${pub}/apis/${api_id}/deploy-revision?revisionId=${rev_id_param}" "$dep_payload")
  if [ "$code" != "201" ] && [ "$code" != "200" ]; then
    echo "  !! Deploy failed (HTTP ${code})"
    jq . "$tmp" 2>/dev/null || cat "$tmp"
    rm -f "$tmp"; return 1
  fi
  rm -f "$tmp"
  
  echo "  - publishing API"
  read -r code tmp < <(call POST "${pub}/apis/change-lifecycle?apiId=${api_id}&action=PUBLISH" '{}')
  if [ "$code" != "200" ]; then
    echo "  !! Publish failed (HTTP ${code})"
    jq . "$tmp" 2>/dev/null || cat "$tmp"
    rm -f "$tmp"; return 1
  fi
  rm -f "$tmp"
}

# ---------- Parse YAML and create APIs ----------
APIS_LEN="$(yq eval '.rest_apis | length' "$CFG")"
echo "▶ Creating ${APIS_LEN} APIs from ${CFG}"

# Temporarily disable exit on error for API creation loop
set +e
for i in $(seq 0 $((APIS_LEN-1))); do
  name="$(yq eval ".rest_apis[$i].name" "$CFG")"
  ctx="$(yq eval ".rest_apis[$i].context" "$CFG")"
  ver="$(yq eval ".rest_apis[$i].version" "$CFG")"
  be="$(yq eval ".rest_apis[$i].backend_url" "$CFG")"
  desc="$(yq eval ".rest_apis[$i].description" "$CFG")"
  tags_json="$(yq eval ".rest_apis[$i].tags" "$CFG" -o=json | jq -c '.')"
  
  echo "  [${i}/$((APIS_LEN-1))] Processing: ${name}"
  
  api_id="$(get_api_id_by_name "${name}")"
  if [ -z "$api_id" ] || [ "$api_id" = "null" ]; then
    echo "  - creating API ${name}"
    api_id="$(create_api "${name}" "${ctx}" "${ver}" "${be}" "${desc}" "${tags_json}")"
    if [ -z "$api_id" ] || [ "$api_id" = "null" ]; then
      echo "  !! Failed to create API ${name}"
      continue
    fi
    echo "  - created with ID: ${api_id}"
  else
    echo "  - API ${name} exists (${api_id})"
  fi
  
  deploy_and_publish "${api_id}" || echo "  !! Failed to deploy/publish ${name}"
done
# Re-enable exit on error
set -e

echo ""
echo "✅ API creation phase complete"

# ---------- Create application (idempotent, handle 409) ----------
APP_NAME="$(yq eval '.application.name' "$CFG")"
APP_TIER="$(yq eval '.application.throttling_policy' "$CFG")"
echo "▶ Ensuring application '${APP_NAME}'"
APP_QRY="$(curl -sk "${dev}/applications" "${AUTH_HDR[@]}" --get --data-urlencode "query=name:${APP_NAME}")"
APP_ID="$(echo "$APP_QRY" | jq -r '.list[0].applicationId // empty')"

if [ -z "${APP_ID}" ]; then
  APP_PAYLOAD='{"name":"'"${APP_NAME}"'","throttlingPolicy":"'"${APP_TIER}"'","description":"autocreated","tokenType":"JWT","groups":[],"attributes":{}}'
  # Try create, tolerate 409 (already exists)
  TMP="$(mktemp)"
  CODE=$(curl -sk -o "$TMP" -w '%{http_code}' "${dev}/applications" "${AUTH_HDR[@]}" -d "${APP_PAYLOAD}")
  if [ "$CODE" = "201" ]; then
    APP_ID="$(jq -r '.applicationId' "$TMP")"
    echo "  - created application"
  elif [ "$CODE" = "409" ]; then
    # Already exists (e.g., DefaultApplication) → read again
    echo "  - application already exists, fetching ID"
    APP_QRY="$(curl -sk "${dev}/applications" "${AUTH_HDR[@]}" --get --data-urlencode "query=name:${APP_NAME}")"
    APP_ID="$(echo "$APP_QRY" | jq -r '.list[0].applicationId // empty')"
  else
    echo "!! applications POST failed (HTTP ${CODE})"
    jq . "$TMP" 2>/dev/null || cat "$TMP"
    rm -f "$TMP"
    exit 1
  fi
  rm -f "$TMP"
else
  echo "  - application found"
fi
echo "  - applicationId=${APP_ID}"

# ---------- Subscriptions ----------
echo "▶ Subscribing ${APP_NAME} to APIs"
SUBS_LEN="$(yq eval '.subscriptions | length' "$CFG")"
for i in $(seq 0 $((SUBS_LEN-1))); do
  s_name="$(yq eval ".subscriptions[$i].api_name" "$CFG")"
  s_tier="$(yq eval ".subscriptions[$i].throttling_policy" "$CFG")"
  s_api="$(get_api_id_by_name "${s_name}")"
  if [ -z "${s_api}" ]; then echo "  ! API not found for subscription: ${s_name}"; continue; fi
  curl -sk "${dev}/subscriptions" "${AUTH_HDR[@]}" -d "{\"apiId\":\"${s_api}\",\"applicationId\":\"${APP_ID}\",\"throttlingPolicy\":\"${s_tier}\"}" >/dev/null 2>&1 || echo "  - already subscribed to ${s_name}"
  echo "  - subscribed ${s_name}"
done

# ---------- Generate keys ----------
echo "▶ Generating PRODUCTION keys for ${APP_NAME} (Key Manager: ${KEY_MANAGER_NAME})"
GEN_RESP="$(curl -sk "${dev}/applications/${APP_ID}/generate-keys" "${AUTH_HDR[@]}" -d @- <<EOF
{
  "keyType": "PRODUCTION",
  "keyManager": "${KEY_MANAGER_NAME}",
  "grantTypesToBeSupported": ["client_credentials","password","refresh_token"],
  "callbackUrl": "https://localhost/cb",
  "scopes": []
}
EOF
)"
CK_APP="$(echo "${GEN_RESP}" | jq -r '.consumerKey // .keyMappingResponse.consumerKey // empty')"
CS_APP="$(echo "${GEN_RESP}" | jq -r '.consumerSecret // .keyMappingResponse.consumerSecret // empty')"
if [ -z "${CK_APP}" ] || [ -z "${CS_APP}" ]; then
  echo "  ! Could not get new keys, checking existing..."
  KEYS_RESP="$(curl -sk "${dev}/applications/${APP_ID}/keys/PRODUCTION" "${AUTH_HDR[@]}")"
  CK_APP="$(echo "${KEYS_RESP}" | jq -r '.consumerKey // empty')"
  CS_APP="$(echo "${KEYS_RESP}" | jq -r '.consumerSecret // empty')"
fi
if [ -z "${CK_APP}" ] || [ -z "${CS_APP}" ]; then
  echo "!! Could not get consumerKey/consumerSecret"; exit 1
fi
echo "  - consumerKey=${CK_APP}"

# Determine correct token endpoint based on Key Manager
if [ "${KEY_MANAGER_NAME}" = "Resident Key Manager" ]; then
  TOKEN_EP="${AM_BASE}/oauth2/token"
else
  TOKEN_EP="${KM_TOKEN_ENDPOINT}"
fi
echo "  - tokenEndpoint=${TOKEN_EP}"

# Save keys to JSON file
cat > /config/application-keys.json <<EOF
{
  "application": "${APP_NAME}",
  "applicationId": "${APP_ID}",
  "production": {
    "consumerKey": "${CK_APP}",
    "consumerSecret": "${CS_APP}",
    "keyManager": "${KEY_MANAGER_NAME}",
    "tokenEndpoint": "${TOKEN_EP}"
  }
}
EOF
echo "  - keys saved to /config/application-keys.json"

# ---------- Print ready-to-run Gateway curls ----------
echo ""
echo "============================================================"
echo "✅ Setup Complete!"
echo "============================================================"
echo ""
echo "📊 Summary:"
echo "  APIs created: ${APIS_LEN}"
echo "  Application: ${APP_NAME}"
echo "  Consumer Key: ${CK_APP}"
echo ""
echo "🌐 Sample invocation (Gateway https://${GW_HOST}:${GW_PORT}):"
echo ""
echo "# Get token from ${KEY_MANAGER_NAME}"
echo "# Using client_credentials grant (recommended for service-to-service)"
echo "TOKEN=\$(curl -sk -u ${CK_APP}:${CS_APP} -d 'grant_type=client_credentials' ${TOKEN_EP} | jq -r .access_token)"
echo ""
echo "# Or using password grant (requires user credentials):"
echo "# TOKEN=\$(curl -sk -u ${CK_APP}:${CS_APP} -d 'grant_type=password&username=admin&password=admin' ${TOKEN_EP} | jq -r .access_token)"
echo ""
for i in $(seq 0 $((APIS_LEN-1))); do
  name="$(yq eval ".rest_apis[$i].name" "$CFG")"
  ctx="$(yq eval ".rest_apis[$i].context" "$CFG")"
  ver="$(yq eval ".rest_apis[$i].version" "$CFG")"
  echo "# ${name}"
  echo "curl -sk -H \"Authorization: Bearer \$TOKEN\" https://${GW_HOST}:${GW_PORT}${ctx}/${ver}/health"
  echo ""
done
echo "============================================================"
