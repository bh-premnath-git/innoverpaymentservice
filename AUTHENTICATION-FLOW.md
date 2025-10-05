# Authentication Flow - Complete Story

## 🎯 Overview

This document describes the complete authentication flow from user login through API access in the Innover platform.

## Architecture Diagram

```
┌─────────────┐     ┌──────────┐     ┌──────────┐     ┌────────────┐
│   Browser   │────▶│ Keycloak │────▶│   WSO2   │────▶│ Microservice│
│   /Client   │     │  (IdP)   │     │ Gateway  │     │  Backend    │
└─────────────┘     └──────────┘     └──────────┘     └────────────┘
      │                   │                 │                  │
      │ 1. Login Request  │                 │                  │
      │──────────────────▶│                 │                  │
      │                   │                 │                  │
      │ 2. JWT Token      │                 │                  │
      │◀──────────────────│                 │                  │
      │                   │                 │                  │
      │ 3. Exchange Token │                 │                  │
      │───────────────────┼────────────────▶│                  │
      │                   │                 │                  │
      │ 4. WSO2 Token     │                 │                  │
      │◀──────────────────┼─────────────────│                  │
      │                   │                 │                  │
      │ 5. API Call + Token                 │                  │
      │─────────────────────────────────────┼─────────────────▶│
      │                   │                 │                  │
      │ 6. Response       │                 │                  │
      │◀────────────────────────────────────┼──────────────────│
```

## Step-by-Step Flow

### Step 1: Keycloak Authentication

**User authenticates with Keycloak:**
```bash
POST https://auth.127.0.0.1.sslip.io/realms/innover/protocol/openid-connect/token
Content-Type: application/x-www-form-urlencoded

client_id=wso2am
client_secret=wso2am-secret
username=admin
password=admin
grant_type=password
```

**Response from Keycloak:**
```json
{
  "access_token": "eyJhbGciOiJSUzI1NiIsInR5cCI...",
  "expires_in": 300,
  "refresh_expires_in": 1800,
  "refresh_token": "eyJhbGciOiJIUzUxMiIsInR5cCI...",
  "token_type": "Bearer",
  "scope": "openid email profile"
}
```

**Token Contains:**
```json
{
  "iss": "https://auth.127.0.0.1.sslip.io/realms/innover",
  "sub": "e708998e-4571-4916-8923-7b97581a25a4",
  "preferred_username": "admin",
  "email": "admin@innover.local",
  "email_verified": true,
  "name": "admin admin",
  "given_name": "admin",
  "family_name": "admin",
  "realm_access": {
    "roles": ["admin", "user"]
  },
  "resource_access": {
    "wso2am": {
      "roles": []
    }
  },
  "azp": "wso2am"
}
```

### Step 2: WSO2 Token Exchange

**Exchange credentials for WSO2 token:**
```bash
POST https://localhost:9443/oauth2/token
Authorization: Basic <base64(consumer_key:consumer_secret)>
Content-Type: application/x-www-form-urlencoded

grant_type=password
username=admin
password=admin
```

**Get Consumer Key/Secret:**
```bash
cat wso2/output/application-keys.json | jq '.production'
```

**Response from WSO2:**
```json
{
  "access_token": "eyJ4NXQiOiJNell4TW1Ga09HWXdNV0kwWldObU5EY3hOR1l3WW1...",
  "scope": "default",
  "token_type": "Bearer",
  "expires_in": 3600
}
```

### Step 3: API Access

**Call API through WSO2 Gateway:**
```bash
GET http://localhost:8280/api/forex/health
Authorization: Bearer <wso2_token>
```

**WSO2 Gateway Processing:**
1. Validates token signature
2. Checks token expiration
3. Enforces rate limiting
4. Routes to backend service: `http://forex:8000/health`
5. Returns response to client

### Step 4: Backend Response

**Backend service processes request:**
```json
{
  "status": "ok",
  "service": "svc-forex"
}
```

## Test Script

Run the complete flow:
```bash
python3 test_complete_flow.py
```

**Expected Output:**
```
======================================================================
Complete Authentication Flow: Keycloak → WSO2 → API
======================================================================

📋 Using WSO2 Client ID: fqLZpQif0l58OfKRSOmw...

🔐 Step 1: Keycloak Authentication (HTTPS)...
   ✅ Keycloak token obtained
   👤 User: admin
   📧 Email: admin@innover.local
   🎭 Roles: admin, user

🎫 Step 2: WSO2 Token Exchange...
   ✅ WSO2 token obtained
   Token type: Bearer
   Expires in: 3600s

📡 Step 3: API Access Test...
   With auth: HTTP 404  # ⚠️ Known issue
   Without auth: HTTP 404

🔧 Step 4: Backend Direct Test...
   ✅ Backend healthy: {'status': 'ok', 'service': 'svc-forex'}

======================================================================
Summary:
  ✅ SSL Certificates working (mkcert)
  ✅ Keycloak accessible via HTTPS
  ✅ WSO2 token exchange
  ❌ API Gateway routing (WSO2 bug)
  ✅ Backend services healthy
======================================================================
```

## Why Hybrid Approach?

### Original Plan
- Use Keycloak JWT directly with WSO2
- WSO2 validates via JWKS endpoint
- Single token for everything

### Issues Encountered
- Scope validation failures
- Token format mismatches
- Complex debugging

### Current Solution
- **Keycloak**: Identity and user management
- **WSO2**: API-specific authorization
- **Two tokens**: Clear separation of concerns
- **Better debugging**: Can isolate issues

## Security Considerations

### Token Lifetimes
- **Keycloak Access Token**: 5 minutes (300s)
- **Keycloak Refresh Token**: 30 minutes (1800s)
- **WSO2 Access Token**: 1 hour (3600s)

### Token Storage
- Store Keycloak refresh token securely (HttpOnly cookie)
- WSO2 token can be in memory (frontend)
- Never expose tokens in URLs or logs

### Best Practices
1. Use HTTPS for all communication
2. Rotate secrets regularly
3. Implement token refresh flow
4. Monitor failed authentication attempts
5. Use short-lived tokens
6. Implement proper CORS policies

---

## 🛠️ Issues Faced & Solutions

### Issue #1: Missing SSL Certificates for Nginx

**Problem:**
```
nginx: [emerg] cannot load certificate "/etc/nginx/certs/local.crt": 
BIO_new_file() failed (SSL: error:80000002:system library::No such file or directory)
```

**Root Cause:**
- Nginx configured for HTTPS but no certificates existed
- Let's Encrypt not suitable (requires public domain)
- Local development needs self-signed certificates

**Solution: mkcert**

Created `mkcert-setup` service in docker-compose.yml:
```yaml
mkcert-setup:
  image: alpine:latest
  volumes:
    - ./nginx/certs:/certs
    - ./scripts/init-mkcert.sh:/init-mkcert.sh:ro
  environment:
    - DOMAINS=auth.127.0.0.1.sslip.io,localhost,127.0.0.1
  command: ["/bin/sh", "/init-mkcert.sh"]
  restart: "no"
```

Created `/scripts/init-mkcert.sh`:
```bash
#!/bin/sh
# Download mkcert
curl -L https://github.com/FiloSottile/mkcert/releases/download/v1.4.4/mkcert-v1.4.4-linux-amd64 \
  -o /usr/local/bin/mkcert
chmod +x /usr/local/bin/mkcert

# Generate certificates
mkcert -key-file /certs/key.pem -cert-file /certs/cert.pem \
  auth.127.0.0.1.sslip.io localhost 127.0.0.1

# Copy with standard names
cp /certs/cert.pem /certs/local.crt
cp /certs/key.pem /certs/local.key
```

**Result:**
```
✅ Certificates valid until January 5, 2028
✅ Nginx running with HTTPS
✅ Keycloak accessible at https://auth.127.0.0.1.sslip.io
```

---

### Issue #2: WSO2 Gateway API Routing (404 Errors)

**Problem:**
```bash
curl http://localhost:8280/api/forex/health
# Response: HTTP 404 Not Found

# Even with valid token:
curl -H "Authorization: Bearer <token>" http://localhost:8280/api/forex/health
# Response: HTTP 404 Not Found
```

**Investigation:**

1. **APIs exist in WSO2:**
```bash
curl -k -u admin:admin "https://localhost:9443/api/am/publisher/v4/apis" | jq
```
```json
{
  "name": "Forex Service API",
  "context": "/api/forex",
  "version": "1.0.0",
  "operations": 5,
  "lifeCycleStatus": "PUBLISHED"
}
```

2. **Backend services work:**
```bash
curl http://localhost:8006/health
# Response: {"status":"ok","service":"svc-forex"}
```

3. **Operations are defined:**
```json
{
  "operations": [
    {"verb": "GET", "target": "/*", "authType": "Application & Application User"},
    {"verb": "POST", "target": "/*", "authType": "Application & Application User"},
    {"verb": "PUT", "target": "/*", "authType": "Application & Application User"},
    {"verb": "DELETE", "target": "/*", "authType": "Application & Application User"},
    {"verb": "PATCH", "target": "/*", "authType": "Application & Application User"}
  ]
}
```

**Root Cause: WSO2 4.6.0-alpha3 Bugs**

Attempted programmatic fixes all failed:

1. **Update API via REST API:**
```python
# Trying to change authType to "None"
api['operations'][0]['authType'] = "None"
response = session.put(f"{base}/apis/{api_id}", json=api)
# Result: 500 Internal Server Error
```

Error in WSO2 logs:
```
java.lang.NullPointerException: Cannot invoke 
"org.wso2.carbon.apimgt.rest.api.publisher.v1.dto.AdvertiseInfoDTO.isAdvertised()" 
because the return value of 
"org.wso2.carbon.apimgt.rest.api.publisher.v1.dto.APIDTO.getAdvertiseInfo()" is null
```

2. **Update Swagger/OpenAPI:**
```python
swagger["paths"]["/*"]["get"]["security"] = []
response = session.put(f"{base}/apis/{api_id}/swagger", json=swagger)
# Result: 415 Unsupported Media Type
```

3. **Deploy Revisions:**
```python
response = session.post(f"{base}/apis/{api_id}/deploy-revision", 
                       params={"revisionId": "1"})
# Result: 500 Internal Server Error
```

**Current Status:**
- ❌ APIs not routable via gateway (404 errors)
- ✅ APIs exist and are published
- ✅ Backend services working perfectly
- ✅ Token exchange working
- ❌ WSO2 4.6.0-alpha3 REST API has critical bugs

**Workaround:**

**Option 1: Manual Configuration via UI**
1. Open WSO2 Publisher Portal: https://localhost:9443/publisher
2. Login as admin/admin
3. Select API → Edit → Resources
4. Change Auth Type from "Application & Application User" to "None"
5. Save and Deploy Revision

**Option 2: Downgrade to WSO2 4.5.0**
```yaml
# docker-compose.yml
wso2am:
  image: wso2/wso2am:4.5.0  # More stable
```

**Option 3: Wait for WSO2 4.6.0 Stable Release**

---

### Issue #3: WSO2 Application Keys Changing

**Problem:**
- Consumer keys/secrets changing between runs
- Hardcoded credentials becoming invalid
- Token exchange failing with 401

**Root Cause:**
- WSO2 generates new keys on each setup run
- Keys stored in `/wso2/output/application-keys.json`
- File not version controlled (gitignored)

**Solution:**

Created `test_complete_flow.py` that dynamically loads keys:

```python
def load_wso2_credentials():
    """Load current WSO2 application credentials"""
    with open('wso2/output/application-keys.json', 'r') as f:
        data = json.load(f)
        return data['production']['consumerKey'], data['production']['consumerSecret']

# Usage
wso2_client_id, wso2_client_secret = load_wso2_credentials()
```

**Test:**
```bash
python3 test_complete_flow.py

# Output:
# 📋 Using WSO2 Client ID: fqLZpQif0l58OfKRSOmw...
# ✅ Keycloak token obtained
# ✅ WSO2 token obtained
```

---

### Issue #4: Scope Validation Failures

**Problem:**
```
wso2am-1 | ERROR - OAuthOpaqueAuthenticatorImpl 
wso2am-1 | You cannot access API as scope validation failed
```

**Root Cause:**
- Application keys generated with only `default` scope
- APIs required specific scopes not granted
- Mismatch between token scopes and API requirements

**Attempted Solutions:**

1. **Using `apim:subscribe` scope:**
```python
scopes = ["apim:subscribe"]  # ❌ Not sufficient for API access
```

2. **Using empty scopes:**
```python
scopes = []  # ❌ Token generation failed
```

3. **Using `default` scope:**
```python
scopes = ["default"]  # ✅ Works but APIs still validate
```

**Code Change in `wso2/setup.py`:**
```python
def get_application_scopes(self, app_id: str) -> List[str]:
    """Get scopes for application"""
    # Changed from apim:subscribe to default
    return ["default"]
```

**Result:**
- Scope validation errors reduced from 100+ to ~5 during setup
- Token generation works
- But API-level scope requirements still cause issues

**Why This Happens:**
- WSO2 validates scopes at TWO levels:
  1. Token generation (application level) ✅
  2. API invocation (resource level) ❌ Still failing

---

### Issue #5: WSO2 Setup Script Running Too Early

**Problem:**
- Setup script running before services fully ready
- Docker "healthy" status ≠ API endpoints ready
- Connection timeouts and failures

**Root Cause:**
Docker healthchecks only verify service is running, not that APIs are ready to accept requests.

**Solution: Enhanced Wait Logic**

Updated `wso2/setup.py` with 3-phase wait:

```python
def wait_for_ready(self, max_attempts: int = 80):
    """Wait for WSO2 to be FULLY ready - not just healthy"""
    
    # Step 1: Wait for basic service
    print("   Step 1/3: Waiting for WSO2 service...")
    for attempt in range(max_attempts):
        try:
            response = self.session.get(f"{self.host}/services/Version", timeout=5)
            if response.status_code == 200:
                print("   ✓ WSO2 service is up")
                break
        except Exception:
            pass
        time.sleep(10)
    
    # Step 2: Wait for Publisher API
    print("   Step 2/3: Waiting for Publisher API...")
    for attempt in range(30):
        try:
            token_response = self.session.post(
                f"{self.host}/oauth2/token",
                data={
                    "grant_type": "password",
                    "username": self.username,
                    "password": self.password,
                    "scope": "apim:api_view apim:api_create"
                },
                timeout=5
            )
            if token_response.status_code == 200:
                # Verify Publisher API works
                api_response = self.session.get(
                    f"{self.publisher_api}/apis?limit=1",
                    timeout=5
                )
                if api_response.status_code in [200, 401]:
                    print("   ✓ Publisher API is ready")
                    break
        except Exception:
            pass
        time.sleep(10)
    
    # Step 3: Final stability wait
    print("   Step 3/3: Waiting for full initialization...")
    time.sleep(15)
    print("✓ WSO2 API Manager is FULLY ready")
```

**Similar for Keycloak:**
```python
def wait_for_keycloak_ready(keycloak_issuer: str, max_attempts: int = 80):
    """Wait for Keycloak to be FULLY ready"""
    
    # Step 1: Service responding
    print("   Step 1/2: Waiting for Keycloak service...")
    # Try to get token with admin credentials
    
    # Step 2: Stability wait
    print("   Step 2/2: Waiting for Keycloak to stabilize...")
    time.sleep(10)
```

**Result:**
```
⏳ Waiting for Keycloak to be FULLY initialized...
   Step 1/2: Waiting for Keycloak service...
   ✓ Keycloak is responding and users are created
   Step 2/2: Waiting for Keycloak to stabilize...
✓ Keycloak is FULLY ready

⏳ Waiting for WSO2 API Manager to be FULLY ready...
   Step 1/3: Waiting for WSO2 service...
   ✓ WSO2 service is up
   Step 2/3: Waiting for Publisher API...
   ✓ Publisher API is ready
   Step 3/3: Waiting for full initialization...
✓ WSO2 API Manager is FULLY ready
```

---

### Issue #6: Mediation Sequence File Missing

**Problem:**
```
Docker build error:
failed to solve: "/skip_scope_validation.xml": not found
```

**Root Cause:**
- Dockerfile referenced external XML file
- File was deleted/moved
- Build failing

**Solution: Embed Sequence in Python**

Removed file dependency and embedded XML directly:

```python
def create_mediation_sequence(self, api_id: str) -> bool:
    """Upload inline mediation sequence to bypass scope validation"""
    
    sequence_xml = '''<?xml version="1.0" encoding="UTF-8"?>
<sequence xmlns="http://ws.apache.org/ns/synapse" name="skip_scope_validation">
    <log level="custom">
        <property name="message" value="Bypassing scope validation"/>
    </log>
    <property name="api.ut.scopesValidated" value="true" scope="default"/>
    <property name="SCOPE_VALIDATION_FAILED" action="remove" scope="default"/>
</sequence>'''
    
    files = {
        'file': ('skip_scope_validation.xml', sequence_xml.encode(), 'application/xml')
    }
    
    response = self.session.post(
        f"{self.publisher_api}/apis/{api_id}/mediation-policies",
        params={"type": "in"},
        files=files
    )
    
    return response.status_code in [200, 201]
```

**Updated Dockerfile:**
```dockerfile
# Removed: COPY skip_scope_validation.xml /app/
# Sequence now embedded in setup.py
```

---

## 📊 Current Status Summary

### ✅ Working Components

1. **SSL/TLS Certificates**
   - ✅ mkcert generating trusted local certificates
   - ✅ Valid until January 5, 2028
   - ✅ Nginx serving HTTPS on port 443

2. **Identity Layer**
   - ✅ Keycloak fully configured with realm and users
   - ✅ HTTPS access at https://auth.127.0.0.1.sslip.io
   - ✅ JWT tokens with user info and roles

3. **Authentication Flow**
   - ✅ Keycloak authentication working
   - ✅ JWT token generation
   - ✅ WSO2 token exchange working
   - ✅ Tokens contain correct user information

4. **Backend Services**
   - ✅ All 6 microservices running
   - ✅ Health endpoints responding
   - ✅ Direct HTTP access working

5. **Infrastructure**
   - ✅ PostgreSQL, Redis, RabbitMQ
   - ✅ OpenTelemetry + Jaeger
   - ✅ All containers healthy

### ❌ Known Issues

1. **WSO2 Gateway Routing**
   - ❌ APIs return 404 even with valid tokens
   - ❌ WSO2 4.6.0-alpha3 has critical REST API bugs
   - ❌ Cannot update APIs programmatically
   - ⚠️  Requires manual configuration via UI

2. **API Security**
   - ❌ Cannot disable security programmatically
   - ❌ Scope validation still enforced
   - ⚠️  Need manual intervention per API

### 🔧 Recommended Actions

**For Development:**
1. Use backend services directly (bypass gateway)
2. Configure APIs manually via WSO2 Publisher UI
3. Or wait for WSO2 4.6.0 stable release

**For Production:**
1. Consider WSO2 4.5.0 (more stable)
2. Or use alternative API gateway (Kong, Tyk, Traefik)
3. Or implement custom routing layer

---

## 📁 Key Files Created

```
innover/
├── test_complete_flow.py              # Automated authentication test
├── AUTHENTICATION-FLOW.md             # This complete guide
│
├── scripts/
│   └── init-mkcert.sh                 # SSL certificate generation
│
├── nginx/
│   └── certs/
│       ├── local.crt                  # SSL certificate
│       ├── local.key                  # Private key
│       └── certificate.info           # Metadata
│
├── wso2/
│   ├── setup.py                       # Enhanced setup script
│   └── output/
│       └── application-keys.json      # OAuth2 credentials (gitignored)
│
└── docker-compose.yml                 # Added mkcert-setup service
```

---

## 🧪 Testing Commands

### Complete Flow Test
```bash
python3 test_complete_flow.py
```

### Manual Testing
```bash
# 1. Test Keycloak
curl -k -X POST https://auth.127.0.0.1.sslip.io/realms/innover/protocol/openid-connect/token \
  -d "client_id=wso2am" \
  -d "client_secret=wso2am-secret" \
  -d "username=admin" \
  -d "password=admin" \
  -d "grant_type=password" | jq

# 2. Test WSO2 Token Exchange
KEYS=$(cat wso2/output/application-keys.json)
CONSUMER_KEY=$(echo $KEYS | jq -r '.production.consumerKey')
CONSUMER_SECRET=$(echo $KEYS | jq -r '.production.consumerSecret')

curl -k -X POST https://localhost:9443/oauth2/token \
  -u "${CONSUMER_KEY}:${CONSUMER_SECRET}" \
  -d "grant_type=password" \
  -d "username=admin" \
  -d "password=admin" | jq

# 3. Test Backend Services
curl http://localhost:8006/health | jq  # Forex
curl http://localhost:8001/health | jq  # Profile
curl http://localhost:8002/health | jq  # Payment
curl http://localhost:8003/health | jq  # Ledger
curl http://localhost:8004/health | jq  # Wallet
curl http://localhost:8005/health | jq  # Rule Engine
```

---

## 📞 Next Steps

1. **Fix WSO2 Gateway Routing:**
   - Manual configuration via Publisher UI
   - Or upgrade to stable WSO2 version
   - Or implement alternative gateway

2. **Implement Business Logic:**
   - Payment processing workflows
   - Forex rate calculations
   - Transaction recording
   - Balance management

3. **Add Persistence:**
   - Database schemas
   - Migrations
   - Caching strategies

4. **Production Readiness:**
   - Kubernetes deployment
   - Proper SSL certificates
   - Monitoring & alerting
   - Security hardening
