#!/usr/bin/env bash
# Creates roles + one user per role in WSO2 IS 7.1.0 via SCIM2.
# Also registers an OAuth client in IS and prints a password-grant token per user.
# Requires: curl, jq (installs via apk if missing)
# Refs: SCIM2 Users & Roles v2 APIs (create/list/filter) and default admin/admin creds. 
# IS OAuth DCR v1.1 for client registration.

set -euo pipefail

# ---------- Config (hardcoded for simplicity) ----------
IS_HOST="${IS_HOST:-localhost}"
IS_PORT="${IS_PORT:-9443}"
IS_BASE="https://${IS_HOST}:${IS_PORT}"
# Hardcoded admin credentials (default WSO2 IS credentials)
IS_ADMIN_USER="admin"
IS_ADMIN_PASS="admin"

# roles and one username per role
declare -A USER_OF_ROLE=( \
  [ops_users]="ops_user" \
  [finance]="finance" \
  [auditor]="auditor" \
  [user]="user" \
  [app_admin]="app_admin" \
)

# simple demo passwords (meet IS policy). Override with env if you want.
PASS_DEFAULT="${PASS_DEFAULT:-P@ssw0rd123!}"
declare -A PASS_OF_USER=(
  [ops_user]="${OPS_USER_PASS:-OpsUser123}"
  [finance]="${FINANCE_PASS:-Finance123}"
  [auditor]="${AUDITOR_PASS:-Auditor123}"
  [user]="${USER_PASS:-User1234}"
  [app_admin]="${APP_ADMIN_PASS:-AppAdmin123}"
)

# Whether to mint password-grant tokens for each created user (uses DCR client)
MINT_TOKENS="${MINT_TOKENS:-true}"

# ---------- Helpers ----------
need_bin() { command -v "$1" >/dev/null 2>&1 || apk add --no-cache "$1" >/dev/null; }
need_bin curl
need_bin jq

# Use arrays for proper argument passing to curl
auth_basic=(-u "${IS_ADMIN_USER}:${IS_ADMIN_PASS}")
json_hdr=(-H "Content-Type: application/json")
scim_users="${IS_BASE}/scim2/Users"
scim_roles="${IS_BASE}/scim2/Roles"

say() { printf "\n▶ %s\n" "$*" >&2; }

exists_role() { 
  local response
  response=$(curl -sk "${auth_basic[@]}" "${scim_roles}?filter=displayName%20eq%20%22${1}%22" 2>/dev/null)
  echo "$response" | jq -e '.totalResults>=1' >/dev/null 2>&1
}

create_role() {
  local role="$1"
  say "Ensuring role '${role}'"
  if exists_role "${role}"; then
    echo "  - role exists"
    return 0
  fi
  
  # Create role (no audience needed for simple roles)
  local response
  response=$(curl -sk "${auth_basic[@]}" "${json_hdr[@]}" -d "{\"displayName\":\"${role}\"}" "${scim_roles}" 2>/dev/null)
  
  if echo "$response" | jq -e '.id' >/dev/null 2>&1; then
    local role_id
    role_id=$(echo "$response" | jq -r '.id')
    echo "  ✅ created: ${role_id}"
    return 0
  else
    echo "  ❌ failed to create role"
    local error
    error=$(echo "$response" | jq -r '.detail // .scimType // .error_description // empty' 2>/dev/null)
    [ -n "$error" ] && echo "     Error: $error"
    echo "     Response: ${response:0:200}"
    return 1
  fi
}

find_user_id() {
  local uname="$1"
  local response
  response=$(curl -sk "${auth_basic[@]}" "${scim_users}?filter=userName%20eq%20%22${uname}%22" 2>/dev/null)
  echo "$response" | jq -r '.Resources[0].id // empty' 2>/dev/null || echo ""
}
create_user_with_role() {
  local uname="$1" pass="$2" role="$3"
  say "Ensuring user '${uname}' with role '${role}'"
  local uid
  uid="$(find_user_id "${uname}")"
  if [ -n "${uid}" ]; then
    echo "  - user exists (${uid})"
    return 0
  fi
  # Assign the custom role + Internal/everyone (required for authentication)
  local response
  response=$(curl -sk "${auth_basic[@]}" "${json_hdr[@]}" -d @- "${scim_users}" 2>/dev/null <<EOF
{
  "userName": "${uname}",
  "password": "${pass}",
  "name": { "givenName": "${uname}", "familyName": "User" },
  "emails": [ { "primary": true, "value": "${uname}@innover.local" } ],
  "roles": [ 
    { "display": "${role}" },
    { "display": "Internal/everyone" }
  ]
}
EOF
)
  if echo "$response" | jq -e '.id' >/dev/null 2>&1; then
    local user_id
    user_id=$(echo "$response" | jq -r '.id')
    echo "  ✅ created: ${user_id}"
    return 0
  else
    echo "  ❌ failed to create user"
    local error
    error=$(echo "$response" | jq -r '.detail // .scimType // .error_description // empty' 2>/dev/null)
    [ -n "$error" ] && echo "     Error: $error"
    echo "     Response: ${response:0:300}"
    return 1
  fi
}

# ---------- Create roles + users ----------
for role in "${!USER_OF_ROLE[@]}"; do
  create_role "${role}"
done

for role in "${!USER_OF_ROLE[@]}"; do
  u="${USER_OF_ROLE[$role]}"
  create_user_with_role "${u}" "${PASS_OF_USER[$u]}" "${role}"
done

# ---------- (Optional) Register an OAuth client in IS and mint tokens for each user ----------
if [ "${MINT_TOKENS}" = "true" ]; then
  say "Registering OAuth client in IS (DCR) for password grant"
  # Use timestamp to make client name unique (in case of container restarts)
  CLIENT_NAME="is-password-client-$(date +%s)"
  DCR_RESP="$(curl -sk "${auth_basic[@]}" "${json_hdr[@]}" \
    -d "{\"client_name\":\"${CLIENT_NAME}\",\"grant_types\":[\"password\",\"refresh_token\"],\"redirect_uris\":[\"https://localhost/cb\"],\"saas_app\":true}" \
    "${IS_BASE}/api/identity/oauth2/dcr/v1.1/register" 2>/dev/null)"
  
  CLIENT_ID="$(echo "${DCR_RESP}" | jq -r '.client_id' 2>/dev/null || echo "")"
  CLIENT_SECRET="$(echo "${DCR_RESP}" | jq -r '.client_secret' 2>/dev/null || echo "")"
  
  if [ -z "${CLIENT_ID}" ] || [ -z "${CLIENT_SECRET}" ] || [ "${CLIENT_ID}" = "null" ] || [ "${CLIENT_SECRET}" = "null" ]; then
    echo "⚠️  Failed to register DCR app - skipping token generation"
    echo "   Response: ${DCR_RESP:0:200}"
  else
    say "Minting password-grant tokens for each user (from IS ${IS_BASE})"
    for role in "${!USER_OF_ROLE[@]}"; do
      u="${USER_OF_ROLE[$role]}"
      p="${PASS_OF_USER[$u]}"
      TOK_RESP="$(curl -sk -u "${CLIENT_ID}:${CLIENT_SECRET}" \
        -d "grant_type=password&username=${u}&password=${p}&scope=openid email profile groups roles" \
        "${IS_BASE}/oauth2/token" 2>/dev/null)"
      TOK="$(echo "${TOK_RESP}" | jq -r '.access_token' 2>/dev/null || echo "")"
      if [ -n "${TOK}" ] && [ "${TOK}" != "null" ]; then
        echo "✅ role=${role} user=${u} token=${TOK:0:30}..."
      else
        echo "❌ role=${role} user=${u} token=<failed>"
        # Show the actual error
        ERROR_DESC="$(echo "${TOK_RESP}" | jq -r '.error_description // .error // empty' 2>/dev/null)"
        [ -n "${ERROR_DESC}" ] && echo "   Error: ${ERROR_DESC}"
      fi
    done
  fi
fi

say "Done - Users created in WSO2 IS"
