# Kong + Keycloak Authentication Setup - Final Configuration

## Current Status

### ✅ What's Working
1. **Keycloak** is running and healthy at `http://localhost:8081`
2. **Kong** is running and can resolve Keycloak internally
3. **Backend services** (profile, ledger, etc.) are healthy
4. **Docker networking** is properly configured with extra_hosts
5. **Test client** `postman-test` is created in Keycloak

### ❌ Remaining Issue
**Token audience mismatch**: Kong's OIDC plugin expects `client_id=kong` but tokens from `postman-test` have `aud=account,kong` and `azp=postman-test`.

## Configuration Summary

### Keycloak Configuration
- **External URL**: `http://localhost:8081`
- **Internal URL**: `http://keycloak:8080`
- **Hostname settings**: Configured to issue tokens with `localhost:8081` as issuer
- **Admin credentials**: `admin / admin`

### Kong Configuration
- **Proxy**: `http://localhost:8000`
- **Admin**: `http://localhost:8001`
- **OIDC Issuer**: `http://localhost:8081/realms/innover`
- **Discovery URL**: `http://keycloak-external:8081/realms/innover/.well-known/openid-configuration`
- **Client ID**: `kong`
- **Client Secret**: `kong-secret`

### Docker Network
- Kong has `extra_hosts` mapping:
  - `host.docker.internal:host-gateway`
  - `keycloak-external:host-gateway` (points to `172.17.0.1`)

## Test Client Setup

### Client: `postman-test`
- **Client ID**: `postman-test`
- **Client Secret**: `postman-secret`
- **Direct Access Grants**: Enabled
- **Audience Mapper**: Includes `kong` in audience

### Test Users
Created by `create-users.sh`:
- `admin / admin`
- `user / user`
- `ops_user / ops_user`
- `finance / finance`
- `auditor / auditor`

## How to Get a Working Token

### Option 1: Using the postman-test client (Current Setup)
```bash
curl -X POST http://localhost:8081/realms/innover/protocol/openid-connect/token \
  -H 'Content-Type: application/x-www-form-urlencoded' \
  -d 'client_id=postman-test' \
  -d 'client_secret=postman-secret' \
  -d 'grant_type=password' \
  -d 'username=user' \
  -d 'password=user' \
  -d 'scope=openid profile' | jq -r '.access_token'
```

### Option 2: Using Postman OAuth 2.0
1. In Postman, go to Authorization tab
2. Select Type: OAuth 2.0
3. Configure:
   - Grant Type: Authorization Code
   - Auth URL: `http://localhost:8081/realms/innover/protocol/openid-connect/auth`
   - Access Token URL: `http://localhost:8081/realms/innover/protocol/openid-connect/token`
   - Client ID: `postman-test`
   - Client Secret: `postman-secret`
   - Scope: `openid profile`
4. Click "Get New Access Token"

## Testing the API

```bash
# Get token
TOKEN=$(curl -s -X POST http://localhost:8081/realms/innover/protocol/openid-connect/token \
  -H 'Content-Type: application/x-www-form-urlencoded' \
  -d 'client_id=postman-test' \
  -d 'client_secret=postman-secret' \
  -d 'grant_type=password' \
  -d 'username=user' \
  -d 'password=user' \
  -d 'scope=openid profile' | jq -r '.access_token')

# Test API
curl -H "Authorization: Bearer $TOKEN" http://localhost:8000/api/profile/health
```

## Scripts Created

1. **`create-test-client.sh`**: Creates the `postman-test` client
2. **`update-test-client.sh`**: Adds `kong` to the audience mapper
3. **`create-test-user.sh`**: Creates a test user (optional, users already exist)

## Key Files Modified

1. **`docker-compose.yml`**:
   - Added `extra_hosts` to Kong service
   - Configured Keycloak hostname settings

2. **`kong/kong.yml`**:
   - Set `issuer: http://localhost:8081/realms/innover`
   - Set `discovery: http://keycloak-external:8081/realms/innover/.well-known/openid-configuration`

3. **`.env`**:
   - `OIDC_ISSUER=http://keycloak:8080/realms/innover` (for backend services)

## Troubleshooting

### If you get "getaddrinfo ENOTFOUND keycloak"
- Ensure `/etc/hosts` has: `127.0.0.1 host.docker.internal`
- Restart Kong: `docker compose restart kong`

### If you get 302 redirects with Bearer token
- Check token issuer matches: `http://localhost:8081/realms/innover`
- Verify token audience includes `kong`
- Ensure user account is fully set up (no required actions)

### If Kong can't reach Keycloak
```bash
# Verify DNS resolution
docker compose exec kong getent hosts keycloak-external

# Test connectivity
docker compose exec kong curl -sf http://keycloak-external:8081/realms/innover/.well-known/openid-configuration
```

## Next Steps

The current blocker is that the `user` account may have required actions or the password wasn't set correctly. To fix:

1. **Reset user password via Keycloak Admin Console**:
   - Go to http://localhost:8081/admin
   - Login with admin/admin
   - Go to Users → user
   - Go to Credentials tab
   - Set password to `user` (temporary: OFF)
   - Go to Details tab
   - Ensure "Email Verified" is ON
   - Clear any "Required Actions"

2. **Or use the admin account** (if it's configured for direct access grants)

3. **Or create a fresh user** via the Admin Console with all settings correct

Once you have a valid token with the correct audience, the API should work!
