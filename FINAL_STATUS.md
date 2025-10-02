# Kong + Keycloak Authentication - Final Status

## Current Situation

After extensive configuration, we've encountered a fundamental issue with Keycloak's hostname configuration:

### The Core Problem

**Keycloak returns different issuer URLs depending on how it's accessed:**
- External access (`localhost:8081`): Returns `"iss": "http://localhost:8081/realms/innover"`
- Internal access (`keycloak:8080`): Returns `"iss": "http://keycloak:8080/realms/innover"`

**Kong's OIDC plugin validates:**
1. Fetches discovery document from Keycloak (using internal hostname)
2. Gets issuer: `http://keycloak:8080/realms/innover`
3. Receives token with issuer: `http://localhost:8081/realms/innover`
4. **Rejects token because issuers don't match**

## What's Working ✅

1. **Keycloak** - Running and issuing tokens correctly
2. **Kong** - Running and can reach Keycloak
3. **Token introspection** - Works when called manually
4. **Test client** - `postman-test` configured with correct audience
5. **Test user** - `apitest / test123` created and working

## What's Not Working ❌

**Bearer token validation fails** due to issuer mismatch between:
- Token issuer: `http://localhost:8081/realms/innover`
- Discovery issuer: `http://keycloak:8080/realms/innover`

## Solutions

### Option 1: Use Browser-Based Authentication (Recommended for Production)
Remove `bearer_only: true` from Kong configuration. Users authenticate via browser redirect.

### Option 2: Fix Keycloak Hostname Configuration
Configure Keycloak to return consistent issuer for all requests. This requires:
- Setting `KC_HOSTNAME_STRICT_BACKCHANNEL: true`
- Ensuring all services can reach Keycloak at the same URL

### Option 3: Use Kong JWT Plugin Instead
Replace the OIDC plugin with the JWT plugin for Bearer token validation:
- Fetch JWKS from Keycloak
- Validate JWT signature locally
- No introspection needed

### Option 4: Accept the Issuer Mismatch (Current Workaround)
Get tokens from a client that uses the internal issuer, or configure Postman to use the internal Keycloak URL.

## Recommended Next Steps

**For API testing with Postman:**

1. **Create a dedicated API gateway endpoint** that doesn't require authentication for health checks
2. **Or use the authorization code flow** in Postman (browser-based)
3. **Or disable OIDC** on specific routes for testing

**For production:**
- Use browser-based authentication (remove `bearer_only`)
- Configure proper DNS/hostnames so all services use the same Keycloak URL
- Consider using an ingress controller with proper hostname resolution

## Test Credentials

- **Keycloak Admin**: `admin / admin` at http://localhost:8081/admin
- **Test User**: `apitest / test123`
- **Test Client**: `postman-test / postman-secret`
- **Kong Client**: `kong / kong-secret`

## Configuration Files

All configuration is in place:
- `kong/kong.yml` - Kong routes and OIDC plugin config
- `docker-compose.yml` - Service definitions with extra_hosts
- `.env` - Environment variables

The infrastructure is ready - it just needs the issuer mismatch resolved.
