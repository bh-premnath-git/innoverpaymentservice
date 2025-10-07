# WSO2 Identity Server 7.1.0 + API Manager 4.5.0 Integration Guide

This guide explains how WSO2 Identity Server (IS) 7.1.0 is configured as an external Key Manager for WSO2 API Manager (API-M) 4.5.0 in containerized environments.

## Table of Contents

1. [Overview](#overview)
2. [Architecture](#architecture)
3. [Prerequisites](#prerequisites)
4. [Configuration Components](#configuration-components)
5. [Setup Steps](#setup-steps)
6. [Verification](#verification)
7. [Troubleshooting](#troubleshooting)
8. [References](#references)

---

## Overview

By default, WSO2 API Manager uses its built-in **Resident Key Manager** for OAuth2/OIDC token operations. This setup configures WSO2 IS 7.1.0 as an **external Key Manager**, enabling:

- **Centralized identity management**: Users, roles, and applications managed in IS
- **Token issuance by IS**: OAuth2/OIDC tokens issued by IS instead of API-M
- **Token revocation events**: IS notifies API-M when tokens are revoked
- **Cross-tenant SCIM2 access**: API-M can read user info from IS via `/scim2/Me`

---

## Architecture

```
┌─────────────────────┐              ┌─────────────────────┐
│  WSO2 API Manager   │              │  WSO2 Identity      │
│      4.5.0          │◄────────────►│  Server 7.1.0       │
│                     │   HTTPS      │                     │
│  - Publisher        │   (mutual    │  - OAuth2/OIDC      │
│  - Developer Portal │    TLS       │  - SCIM2            │
│  - Gateway          │    trust)    │  - DCR              │
│  - Admin Portal     │              │  - Token Revocation │
└─────────────────────┘              └─────────────────────┘
         │                                    │
         │                                    │
         └────────── Token Operations ────────┘
           (authorize, token, introspect,
            revoke, userinfo, jwks)
```

**Key Manager Endpoints (Docker network):**
- Well-known: `https://wso2is:9443/oauth2/token/.well-known/openid-configuration`
- Issuer: `https://wso2is:9443/oauth2/token`
- Token: `https://wso2is:9443/oauth2/token`
- Authorize: `https://wso2is:9443/oauth2/authorize`
- UserInfo: `https://wso2is:9443/scim2/Me` ⚠️ (NOT `/oauth2/userInfo`)
- Revoke: `https://wso2is:9443/oauth2/revoke`
- Introspect: `https://wso2is:9443/oauth2/introspect`
- JWKS: `https://wso2is:9443/oauth2/jwks`
- DCR: `https://wso2is:9443/api/identity/oauth2/dcr/v1.1/register`
- Scopes: `https://wso2is:9443/api/identity/oauth2/v1.0/scopes`
- Roles: `https://wso2is:9443/scim2/v2/Roles`
- API Resources: `https://wso2is:9443/api/server/v1/api-resources`

---

## Prerequisites

- Docker and Docker Compose
- WSO2 IS 7.1.0 container running and healthy
- WSO2 API-M 4.5.0 container running and healthy
- Both containers on the same Docker network (`edge`)
- Admin credentials for both products (default: `admin/admin`)

---

## Configuration Components

### 1. WSO2 IS Configuration (`wso2is/deployment.toml`)

The IS container includes these APIM-specific configurations:

```toml
# Allow APIM to authorize all scopes
[oauth]
authorize_all_scopes = true

# Allow APIM to read /scim2/Me cross-tenant (UserInfo endpoint)
[[resource.access_control]]
context = "(.*)/scim2/Me"
secure = true
http_method = "GET"
cross_tenant = true
permissions = []
scopes = []

# Send token revocation events to APIM
[[event_listener]]
id = "token_revocation"
type = "org.wso2.carbon.identity.core.handler.AbstractIdentityHandler"
name = "org.wso2.is.notification.ApimOauthEventInterceptor"
order = 1
[event_listener.properties]
notification_endpoint = "https://wso2am:9443/internal/data/v1/notify"
username = "${admin.username}"
password = "${admin.password}"
'header.X-WSO2-KEY-MANAGER' = "WSO2-IS"

# Allow APIM to create roles with system_primary_* prefix
[role_mgt]
allow_system_prefix_for_role = true
```

### 2. Token Revocation Handler JAR

The IS Dockerfile automatically downloads the required event handler:

```dockerfile
RUN curl -L -o /home/wso2carbon/wso2is-7.1.0/repository/components/dropins/notification.event.handlers-2.0.5.jar \
    https://maven.wso2.org/nexus/service/local/repositories/releases/content/org/wso2/is/notification.event.handlers/2.0.5/notification.event.handlers-2.0.5.jar
```

This JAR enables IS to send token revocation events to API-M's `/internal/data/v1/notify` endpoint.

### 3. Mutual TLS Trust

Both containers must trust each other's TLS certificates for HTTPS communication.

**Why:** WSO2 products use self-signed certificates by default. Without mutual trust:
- API-M cannot call IS endpoints (DCR, token, userinfo, etc.)
- IS cannot send revocation events to API-M

### 4. API Automation Script Fixes

**a) URL-encoded queries (`apim-publish-from-yaml.sh`)**

The script now properly encodes API names with spaces:

```bash
get_api_id_by_name() {
  local name="$1"
  curl -sk --get "${pub}/apis" -H "Authorization: Bearer ${TOKEN}" \
    --data-urlencode "query=name:${name}" | jq -r '.list[0].id // empty'
}
```

**Before:** `?query=name:Payment API` (breaks on spaces)  
**After:** `?query=name%3APayment%20API` (properly encoded)

**b) Configurable Key Manager with correct token endpoint (`apim-publish-from-yaml.sh`)**

The script now supports choosing which Key Manager to use **and automatically uses the correct token endpoint**:

```bash
KEY_MANAGER_NAME="${KEY_MANAGER_NAME:-Resident Key Manager}"  # Use "WSO2-IS" for external IS
KM_TOKEN_ENDPOINT="${KM_TOKEN_ENDPOINT:-https://wso2is:9443/oauth2/token}"  # Token endpoint for external KM

# In generate-keys call:
{
  "keyType": "PRODUCTION",
  "keyManager": "${KEY_MANAGER_NAME}",  # ← Uses env variable
  "grantTypesToBeSupported": ["client_credentials","password","refresh_token"],
  ...
}

# Automatically determines correct token endpoint:
if [ "${KEY_MANAGER_NAME}" = "Resident Key Manager" ]; then
  TOKEN_EP="${AM_BASE}/oauth2/token"
else
  TOKEN_EP="${KM_TOKEN_ENDPOINT}"
fi
```

**Why this matters:** The Gateway rejects tokens issued by the wrong Key Manager. If your application uses WSO2 IS as Key Manager, you must get tokens from IS's `/oauth2/token` endpoint, not API-M's.

**Usage:**
```bash
# Use Resident Key Manager (default, APIM issues tokens)
./apim-publish-from-yaml.sh /config/api-config.yaml

# Use WSO2 IS Key Manager (IS issues tokens)
KEY_MANAGER_NAME="WSO2-IS" ./apim-publish-from-yaml.sh /config/api-config.yaml

# Custom IS endpoint
KEY_MANAGER_NAME="WSO2-IS" KM_TOKEN_ENDPOINT="https://custom-is:9443/oauth2/token" \
  ./apim-publish-from-yaml.sh /config/api-config.yaml
```

**c) Idempotent application creation (handle 409 conflicts)**

The script now properly handles the case where `DefaultApplication` already exists:

```bash
# Try create, tolerate 409 (already exists)
CODE=$(curl -sk -o "$TMP" -w '%{http_code}' "${dev}/applications" ...)
if [ "$CODE" = "201" ]; then
  APP_ID="$(jq -r '.applicationId' "$TMP")"
elif [ "$CODE" = "409" ]; then
  # Already exists (e.g., DefaultApplication) → read again
  APP_QRY="$(curl -sk "${dev}/applications" --get --data-urlencode "query=name:${APP_NAME}")"
  APP_ID="$(echo "$APP_QRY" | jq -r '.list[0].applicationId')"
else
  echo "!! applications POST failed (HTTP ${CODE})"
  exit 1
fi
```

This prevents failures when DefaultApplication is pre-created by API-M.

**d) Enhanced health checks**

The API-M entrypoint now waits for proper health indicators before attempting API setup:

1. **Server ready**: `GET /services/Version`
2. **Gateway ready**: `GET /api/am/gateway/v2/server-startup-healthcheck`
3. **Publisher ready**: `GET /publisher`

This prevents race conditions where the Publisher UI responds before the underlying APIs are fully initialized.

---

## Setup Steps

### Step 1: Build and Start Containers

```bash
# Build containers with IS+APIM integration configs
docker-compose build wso2is wso2am

# Start containers
docker-compose up -d wso2is wso2am

# Wait for containers to be healthy
docker-compose ps
```

**What happens:**
- IS starts with `deployment.toml` extensions and revocation handler JAR
- API-M starts and waits for IS to be healthy (dependency)
- API-M runs API setup script with Resident Key Manager (default)

### Step 2: Exchange TLS Certificates

```bash
cd wso2
./exchange-certs.sh
```

**What it does:**
1. Exports IS's public cert from `wso2carbon.jks`
2. Imports it into API-M's `client-truststore.jks` (alias: `wso2is`)
3. Exports API-M's public cert from `wso2carbon.jks`
4. Imports it into IS's `client-truststore.jks` (alias: `wso2am`)

**⚠️ IMPORTANT:** Restart both containers after certificate exchange:
```bash
docker restart innover-wso2is-1 innover-wso2am-1
```

### Step 3: Register IS as Key Manager

**Option A: Automated (recommended)**

```bash
cd wso2
./register-keymanager.sh
```

**Option B: Manual (Admin Portal UI)**

1. Open Admin Portal: https://localhost:9443/admin
2. Login with admin credentials
3. Navigate to **Settings > Key Managers > Add Key Manager**
4. Select **WSO2 Identity Server 7** preset
5. Enter Well-known URL:
   ```
   https://wso2is:9443/oauth2/token/.well-known/openid-configuration
   ```
6. Click **Import**
7. **⚠️ CRITICAL FIX:** Override UserInfo Endpoint:
   ```
   https://wso2is:9443/scim2/Me
   ```
   (Auto-import sets `/oauth2/userInfo` which is wrong for IS7)
8. Fill connector credentials:
   - **Username**: `admin`
   - **Password**: `admin`
9. Click **Add**

### Step 4: Generate Application Keys with WSO2 IS

After registering the Key Manager, you can generate keys using IS:

```bash
# Set environment variable
export KEY_MANAGER_NAME="WSO2-IS"

# Run API setup (or generate keys for existing apps)
docker exec innover-wso2am-1 bash -c "
  KEY_MANAGER_NAME=WSO2-IS \
  /home/wso2carbon/apim-publish-from-yaml.sh /config/api-config.yaml
"
```

Or regenerate keys for an existing application via Developer Portal:
1. Go to https://localhost:9443/devportal
2. Navigate to **Applications > [Your App] > Production Keys**
3. Select **Key Manager: WSO2-IS**
4. Click **Generate Keys**

---

## Verification

### 1. Check Key Manager Registration

```bash
# Via REST API
curl -sk -u admin:admin https://localhost:9443/api/am/admin/v4/key-managers | jq '.list[] | {name, type, enabled}'
```

Expected output:
```json
{
  "name": "Resident Key Manager",
  "type": "default",
  "enabled": true
}
{
  "name": "WSO2-IS",
  "type": "WSO2-IS",
  "enabled": true
}
```

### 2. Verify Certificate Trust

```bash
# Check API-M trusts IS
docker exec innover-wso2am-1 keytool -list \
  -keystore /home/wso2carbon/wso2am-4.5.0/repository/resources/security/client-truststore.jks \
  -storepass wso2carbon | grep wso2is

# Check IS trusts API-M
docker exec innover-wso2is-1 keytool -list \
  -keystore /home/wso2carbon/wso2is-7.1.0/repository/resources/security/client-truststore.jks \
  -storepass wso2carbon | grep wso2am
```

### 3. Test Token Issuance from IS

```bash
# Get application credentials (should show keyManager: WSO2-IS)
cat wso2/output/application-keys.json | jq .

# Get token from IS (via API-M Gateway)
TOKEN=$(curl -sk -u <consumer_key>:<consumer_secret> \
  -d "grant_type=password&username=admin&password=admin" \
  https://localhost:9443/oauth2/token | jq -r .access_token)

# Decode JWT to verify issuer
echo $TOKEN | cut -d. -f2 | base64 -d 2>/dev/null | jq .

# Expected: "iss": "https://wso2is:9443/oauth2/token"
```

### 4. Test API Gateway with IS Token

```bash
# Call an API using token issued by IS
curl -sk -H "Authorization: Bearer $TOKEN" \
  https://localhost:8243/payment/v1/health
```

---

## Troubleshooting

### Issue: "API setup failed" during startup

**Symptoms:**
- API creation fails with "already exists" errors
- Script exits with generic "setup failed" message

**Root causes:**
1. **Publisher not fully ready**: `/publisher` endpoint responds before API operations are ready
2. **Missing URL encoding**: API names with spaces not found, causing duplicate creation attempts
3. **DefaultApplication conflict**: Application already exists, returns 409

**Solutions:**
- ✅ **Fixed in latest script**: 
  - Now waits for `/services/Version` and `/api/am/gateway/v2/server-startup-healthcheck` (proper health checks)
  - Uses URL-encoded queries for API name searches
  - Handles 409 conflicts gracefully (idempotent app creation)
- If still failing, increase `start_period` in `docker-compose.yml`:
  ```yaml
  wso2am:
    healthcheck:
      start_period: 600s  # Increase to 10 minutes
  ```

### Issue: "OAuthOpaqueAuthenticatorImpl... ACTIVE access token is not found"

**Symptoms:**
- Gateway rejects valid-looking tokens with 401 Unauthorized
- Error in logs: `ACTIVE access token is not found in database`

**Root causes:**
1. **Wrong token endpoint**: Token issued by Resident Key Manager but application uses WSO2 IS Key Manager (or vice versa)
2. **Token/KM mismatch**: Application keys generated with one Key Manager, token obtained from different Key Manager

**Solutions:**
- ✅ **Fixed in latest script**: Automatically determines correct token endpoint based on `KEY_MANAGER_NAME`
- **Manual verification**:
  ```bash
  # Check application's Key Manager
  cat wso2/output/application-keys.json | jq '.production.keyManager'
  # Should output: "WSO2-IS" (if using IS) or "Resident Key Manager"
  
  # Get token from CORRECT endpoint
  # For WSO2-IS:
  TOKEN=$(curl -sk -u <key>:<secret> -d 'grant_type=client_credentials' \
    https://wso2is:9443/oauth2/token | jq -r .access_token)
  
  # For Resident:
  TOKEN=$(curl -sk -u <key>:<secret> -d 'grant_type=client_credentials' \
    https://localhost:9443/oauth2/token | jq -r .access_token)
  ```
- **Regenerate keys if needed**:
  ```bash
  KEY_MANAGER_NAME="WSO2-IS" ./wso2/apim-publish-from-yaml.sh /config/api-config.yaml
  ```

### Issue: DefaultApplication conflict (409)

**Symptoms:**
- Application creation fails with HTTP 409 Conflict
- Error: "Application with name 'DefaultApplication' already exists"

**Root cause:**
API-M pre-creates DefaultApplication for admin user

**Solution:**
✅ **Fixed in latest script**: Now handles 409 gracefully and fetches existing application ID

### Issue: Certificate validation errors

**Symptoms:**
```
unable to find valid certification path to requested target
javax.net.ssl.SSLHandshakeException
```

**Solutions:**
1. Verify certificates are imported:
   ```bash
   ./wso2/exchange-certs.sh
   ```
2. **Restart containers** (critical step):
   ```bash
   docker restart innover-wso2is-1 innover-wso2am-1
   ```
3. Check truststore:
   ```bash
   docker exec innover-wso2am-1 keytool -list \
     -keystore /home/wso2carbon/wso2am-4.5.0/repository/resources/security/client-truststore.jks \
     -storepass wso2carbon
   ```

### Issue: Token issued by Resident Key Manager instead of IS

**Symptoms:**
- Token `iss` claim shows `https://localhost:9443/oauth2/token` (API-M)
- Expected: `https://wso2is:9443/oauth2/token` (IS)

**Solutions:**
1. Verify Key Manager is registered and enabled:
   ```bash
   curl -sk -u admin:admin https://localhost:9443/api/am/admin/v4/key-managers | jq '.list[] | select(.name == "WSO2-IS")'
   ```
2. Check application keys were generated with correct Key Manager:
   ```bash
   cat wso2/output/application-keys.json | jq '.production.keyManager'
   # Should output: "WSO2-IS"
   ```
3. If wrong, regenerate keys:
   ```bash
   KEY_MANAGER_NAME="WSO2-IS" ./wso2/apim-publish-from-yaml.sh /config/api-config.yaml
   ```

### Issue: UserInfo endpoint returns 401/403

**Symptoms:**
- API-M cannot retrieve user info from IS
- Token validation fails

**Solutions:**
1. ⚠️ **Critical:** Ensure UserInfo endpoint is set to `/scim2/Me`, NOT `/oauth2/userInfo`
2. Check `deployment.toml` has SCIM2 access control (already configured)
3. Verify in Admin Portal: **Key Managers > WSO2-IS > Edit > UserInfo Endpoint**

### Issue: Token revocation not working

**Symptoms:**
- Tokens revoked in IS still work in API-M Gateway

**Solutions:**
1. Check revocation handler JAR is present:
   ```bash
   docker exec innover-wso2is-1 ls -lh \
     /home/wso2carbon/wso2is-7.1.0/repository/components/dropins/ | grep notification
   ```
2. Verify event listener config in `deployment.toml`
3. Check IS logs for notification attempts:
   ```bash
   docker logs innover-wso2is-1 | grep -i "notify\|revocation"
   ```
4. Test API-M notification endpoint:
   ```bash
   curl -k -u admin:admin -X POST \
     https://localhost:9443/internal/data/v1/notify \
     -H "X-WSO2-KEY-MANAGER: WSO2-IS" \
     -H "Content-Type: application/json" \
     -d '{"event":"token_revocation"}'
   ```

---

## Environment Variables

### API Setup Script (`apim-publish-from-yaml.sh`)

| Variable | Default | Description |
|----------|---------|-------------|
| `AM_HOST` | `localhost` | API-M hostname |
| `AM_PORT` | `9443` | API-M HTTPS port |
| `AM_ADMIN_USER` | `admin` | API-M admin username |
| `AM_ADMIN_PASS` | `admin` | API-M admin password |
| `GW_HOST` | `${AM_HOST}` | Gateway hostname |
| `GW_PORT` | `8243` | Gateway HTTPS port |
| `VHOST` | `localhost` | Virtual host for Gateway |
| `KEY_MANAGER_NAME` | `Resident Key Manager` | Key Manager to use (set to `WSO2-IS` for external IS) |
| `KM_TOKEN_ENDPOINT` | `https://wso2is:9443/oauth2/token` | Token endpoint for external Key Manager (used when KEY_MANAGER_NAME != "Resident Key Manager") |

### Key Manager Registration (`register-keymanager.sh`)

| Variable | Default | Description |
|----------|---------|-------------|
| `AM_HOST` | `localhost` | API-M hostname |
| `AM_PORT` | `9443` | API-M HTTPS port |
| `AM_ADMIN_USER` | `admin` | API-M admin username |
| `AM_ADMIN_PASS` | `admin` | API-M admin password |
| `IS_HOST` | `wso2is` | IS hostname (Docker network) |
| `IS_PORT` | `9443` | IS HTTPS port |
| `IS_ADMIN_USER` | `admin` | IS admin username |
| `IS_ADMIN_PASS` | `admin` | IS admin password |
| `KM_NAME` | `WSO2-IS` | Key Manager display name |

### Certificate Exchange (`exchange-certs.sh`)

| Variable | Default | Description |
|----------|---------|-------------|
| `IS_CONTAINER` | `innover-wso2is-1` | IS container name |
| `AM_CONTAINER` | `innover-wso2am-1` | API-M container name |
| `KEYSTORE_PASS` | `wso2carbon` | Keystore password |
| `TRUSTSTORE_PASS` | `wso2carbon` | Truststore password |

---

## Quick Start Checklist

- [ ] Build containers: `docker-compose build wso2is wso2am`
- [ ] Start containers: `docker-compose up -d wso2is wso2am`
- [ ] Wait for healthy status: `docker-compose ps`
- [ ] Exchange certificates: `./wso2/exchange-certs.sh`
- [ ] Restart containers: `docker restart innover-wso2is-1 innover-wso2am-1`
- [ ] Register Key Manager: `./wso2/register-keymanager.sh`
- [ ] Verify registration: Check Admin Portal or REST API
- [ ] Generate keys with IS: `KEY_MANAGER_NAME=WSO2-IS ./wso2/apim-publish-from-yaml.sh ...`
- [ ] Test token issuance: Verify JWT `iss` claim
- [ ] Test API Gateway: Call APIs with IS-issued tokens

---

## References

- [WSO2 API-M 4.5.0 - Configure WSO2 IS as a Key Manager](https://apim.docs.wso2.com/en/4.5.0/administer/key-managers/configure-wso2is-connector/)
- [WSO2 IS 7.1.0 Documentation](https://is.docs.wso2.com/en/7.1.0/)
- [WSO2 API-M Admin REST API](https://apim.docs.wso2.com/en/4.5.0/reference/admin-rest-api/)
- [OAuth2 Token Revocation (RFC 7009)](https://tools.ietf.org/html/rfc7009)
- [SCIM2 Protocol](https://tools.ietf.org/html/rfc7644)

---

## Support

For issues specific to this integration:
1. Check container logs: `docker logs innover-wso2is-1` and `docker logs innover-wso2am-1`
2. Review the [Troubleshooting](#troubleshooting) section
3. Verify all checklist items are completed
4. Check WSO2 documentation for version-specific issues

For WSO2 product issues:
- WSO2 API Manager: https://github.com/wso2/product-apim
- WSO2 Identity Server: https://github.com/wso2/product-is
