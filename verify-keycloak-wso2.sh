#!/bin/bash
set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo "=============================================="
echo "Keycloak ↔ WSO2 Integration Verification"
echo "=============================================="
echo ""

check_pass() {
    echo -e "${GREEN}✓${NC} $1"
}

check_fail() {
    echo -e "${RED}✗${NC} $1"
    exit 1
}

check_warn() {
    echo -e "${YELLOW}⚠${NC} $1"
}

# ============================================
# STEP 1: Infrastructure Health Checks
# ============================================
echo -e "${BLUE}[1/6] Infrastructure Health Checks${NC}"
echo "----------------------------------------------"

# Check Keycloak container
if docker ps --filter name=keycloak --filter status=running | grep -q keycloak; then
    check_pass "Keycloak container is running"
else
    check_fail "Keycloak container is not running. Run: docker compose up -d"
fi

# Check WSO2 container
if docker ps --filter name=wso2am --filter status=running | grep -q wso2am; then
    check_pass "WSO2 container is running"
else
    check_fail "WSO2 container is not running. Run: docker compose up -d"
fi

echo ""

# ============================================
# STEP 2: Keycloak Configuration
# ============================================
echo -e "${BLUE}[2/6] Keycloak Configuration${NC}"
echo "----------------------------------------------"

# Check OIDC discovery
OIDC_RESPONSE=$(curl -k -s https://auth.127.0.0.1.sslip.io/realms/innover/.well-known/openid-configuration 2>/dev/null)
ISSUER=$(echo "$OIDC_RESPONSE" | jq -r '.issuer' 2>/dev/null || echo "ERROR")

if [ "$ISSUER" == "https://auth.127.0.0.1.sslip.io/realms/innover" ]; then
    check_pass "Keycloak issuer is correct: $ISSUER"
else
    check_fail "Keycloak issuer is wrong: $ISSUER"
fi

# Check JWKS endpoint
JWKS=$(curl -k -s https://auth.127.0.0.1.sslip.io/realms/innover/protocol/openid-connect/certs 2>/dev/null | jq -r '.keys[0].kid' 2>/dev/null || echo "ERROR")

if [ "$JWKS" != "ERROR" ] && [ -n "$JWKS" ]; then
    check_pass "JWKS endpoint is accessible (Key ID: $JWKS)"
else
    check_fail "JWKS endpoint is not accessible"
fi

# Check network connectivity from WSO2 to Keycloak
if docker exec innover-wso2am-1 sh -c "wget --no-check-certificate -qO- https://auth.127.0.0.1.sslip.io/realms/innover/.well-known/openid-configuration" >/dev/null 2>&1; then
    check_pass "WSO2 can reach Keycloak via network alias"
else
    check_warn "WSO2 cannot reach Keycloak (might still be starting)"
fi

echo ""

# ============================================
# STEP 3: Token Generation
# ============================================
echo -e "${BLUE}[3/6] Keycloak Token Generation${NC}"
echo "----------------------------------------------"

TOKEN_RESPONSE=$(curl -k -s -X POST https://auth.127.0.0.1.sslip.io/realms/innover/protocol/openid-connect/token \
    -d "client_id=wso2am" \
    -d "client_secret=wso2am-secret" \
    -d "username=admin" \
    -d "password=admin" \
    -d "grant_type=password" 2>/dev/null)

TOKEN=$(echo "$TOKEN_RESPONSE" | jq -r '.access_token' 2>/dev/null || echo "null")

if [ "$TOKEN" != "null" ] && [ -n "$TOKEN" ] && [ "$TOKEN" != "" ]; then
    check_pass "Successfully obtained token from Keycloak"
    
    # Decode and verify token
    TOKEN_PAYLOAD=$(echo $TOKEN | cut -d. -f2 | base64 -d 2>/dev/null)
    TOKEN_ISSUER=$(echo "$TOKEN_PAYLOAD" | jq -r '.iss' 2>/dev/null || echo "ERROR")
    TOKEN_AZP=$(echo "$TOKEN_PAYLOAD" | jq -r '.azp' 2>/dev/null || echo "ERROR")
    TOKEN_USER=$(echo "$TOKEN_PAYLOAD" | jq -r '.preferred_username' 2>/dev/null || echo "ERROR")
    
    if [ "$TOKEN_ISSUER" == "https://auth.127.0.0.1.sslip.io/realms/innover" ]; then
        check_pass "Token issuer matches: $TOKEN_ISSUER"
    else
        check_warn "Token issuer: $TOKEN_ISSUER"
    fi
    
    check_pass "Token details - Client: $TOKEN_AZP, User: $TOKEN_USER"
else
    check_fail "Could not obtain token from Keycloak. Check client credentials."
fi

echo ""

# ============================================
# STEP 4: WSO2 Key Manager Configuration
# ============================================
echo -e "${BLUE}[4/6] WSO2 Key Manager Configuration${NC}"
echo "----------------------------------------------"

check_warn "To verify Key Manager, check setup logs:"
echo "   $ docker compose logs keycloak-km-setup | grep '✓ Keycloak Key Manager configured'"
echo ""
echo "   Or visit WSO2 Admin Portal:"
echo "   https://localhost:9443/admin → Key Managers"

echo ""

# ============================================
# STEP 5: WSO2 Gateway Token Validation
# ============================================
echo -e "${BLUE}[5/6] WSO2 Gateway Token Validation${NC}"
echo "----------------------------------------------"

if [ -z "$TOKEN" ] || [ "$TOKEN" == "null" ]; then
    check_fail "No token available for testing"
fi

echo "Testing API call with Keycloak token..."
RESPONSE=$(curl -k -L -s -w "\nHTTP_CODE:%{http_code}" \
    -H "Authorization: Bearer $TOKEN" \
    https://localhost:9443/api/profile/1.0.0/health 2>/dev/null)

HTTP_CODE=$(echo "$RESPONSE" | grep "HTTP_CODE:" | cut -d: -f2)

if [ "$HTTP_CODE" == "200" ]; then
    check_pass "WSO2 Gateway validated Keycloak token successfully (HTTP 200)"
    echo -e "   ${GREEN}✓✓✓ INTEGRATION WORKING!${NC}"
elif [ "$HTTP_CODE" == "404" ]; then
    check_warn "API not found (HTTP 404). Run: docker compose up wso2-setup"
elif [ "$HTTP_CODE" == "401" ]; then
    check_fail "Unauthorized (HTTP 401). Key Manager might not be configured."
else
    check_warn "Unexpected HTTP status: $HTTP_CODE"
fi

echo ""

# ============================================
# STEP 6: Summary & Next Steps
# ============================================
echo -e "${BLUE}[6/6] Summary${NC}"
echo "=============================================="
echo ""
echo "Configuration URLs:"
echo "  • Keycloak Issuer: https://auth.127.0.0.1.sslip.io/realms/innover"
echo "  • JWKS Endpoint: https://auth.127.0.0.1.sslip.io/realms/innover/protocol/openid-connect/certs"
echo ""
echo "Management Portals:"
echo "  • WSO2 Admin: https://localhost:9443/admin"
echo "  • WSO2 Publisher: https://localhost:9443/publisher"
echo "  • WSO2 DevPortal: https://localhost:9443/devportal"
echo "  • Keycloak Admin: https://auth.127.0.0.1.sslip.io/admin"
echo ""

if [ "$HTTP_CODE" != "200" ]; then
    echo "Next Steps:"
    echo ""
    echo "1. Configure Keycloak Key Manager:"
    echo "   $ docker compose up keycloak-km-setup"
    echo ""
    echo "2. Create/Update APIs:"
    echo "   $ docker compose up wso2-setup"
    echo ""
    echo "3. Re-run this script:"
    echo "   $ ./verify-keycloak-wso2.sh"
    echo ""
fi

echo "Manual Token Test:"
echo '  TOKEN=$(curl -k -s -X POST https://auth.127.0.0.1.sslip.io/realms/innover/protocol/openid-connect/token \'
echo '    -d "client_id=wso2am" -d "client_secret=wso2am-secret" \'
echo '    -d "username=admin" -d "password=admin" -d "grant_type=password" | jq -r ".access_token")'
echo ""
echo '  curl -k -L -H "Authorization: Bearer $TOKEN" \'
echo '    https://localhost:9443/api/profile/1.0.0/health'
echo ""
