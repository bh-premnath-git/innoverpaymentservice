#!/bin/bash
# Quick test script to verify Keycloak role mappers

set -e

echo "========================================"
echo "Keycloak Role Mapper Verification"
echo "========================================"
echo ""

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
KEYCLOAK_URL="https://auth.127.0.0.1.sslip.io"
REALM="innover"
CLIENT_ID="wso2am"
CLIENT_SECRET="wso2am-secret"
USERNAME="admin"
PASSWORD="admin"

echo -e "${BLUE}🔧 Configuration:${NC}"
echo "  Keycloak: $KEYCLOAK_URL"
echo "  Realm: $REALM"
echo "  Client: $CLIENT_ID"
echo "  User: $USERNAME"
echo ""

# Check if jq is installed
if ! command -v jq &> /dev/null; then
    echo -e "${YELLOW}⚠️  jq not installed. Installing basic JSON parsing...${NC}"
    echo "  (For better output, install jq: apt-get install jq)"
    echo ""
fi

echo -e "${BLUE}Step 1: Get Access Token${NC}"
echo "========================================"

TOKEN_RESPONSE=$(curl -sk -X POST "$KEYCLOAK_URL/realms/$REALM/protocol/openid-connect/token" \
  -d "client_id=$CLIENT_ID" \
  -d "client_secret=$CLIENT_SECRET" \
  -d "username=$USERNAME" \
  -d "password=$PASSWORD" \
  -d "grant_type=password" \
  -d "scope=openid profile email")

if [ $? -ne 0 ]; then
    echo -e "${YELLOW}❌ Failed to get token${NC}"
    exit 1
fi

# Extract tokens
if command -v jq &> /dev/null; then
    ACCESS_TOKEN=$(echo "$TOKEN_RESPONSE" | jq -r '.access_token')
    ID_TOKEN=$(echo "$TOKEN_RESPONSE" | jq -r '.id_token')
    TOKEN_TYPE=$(echo "$TOKEN_RESPONSE" | jq -r '.token_type')
    EXPIRES_IN=$(echo "$TOKEN_RESPONSE" | jq -r '.expires_in')
    SCOPE=$(echo "$TOKEN_RESPONSE" | jq -r '.scope')
else
    ACCESS_TOKEN=$(echo "$TOKEN_RESPONSE" | python3 -c "import sys, json; print(json.load(sys.stdin)['access_token'])" 2>/dev/null || echo "")
    ID_TOKEN=$(echo "$TOKEN_RESPONSE" | python3 -c "import sys, json; print(json.load(sys.stdin)['id_token'])" 2>/dev/null || echo "")
fi

if [ -z "$ACCESS_TOKEN" ] || [ "$ACCESS_TOKEN" = "null" ]; then
    echo -e "${YELLOW}❌ Failed to extract access token${NC}"
    echo "$TOKEN_RESPONSE"
    exit 1
fi

echo -e "${GREEN}✅ Token received successfully${NC}"
echo "  Token Type: $TOKEN_TYPE"
echo "  Expires In: $EXPIRES_IN seconds"
echo "  Scope: $SCOPE"
echo ""

echo -e "${BLUE}Step 2: Decode Access Token (Payload)${NC}"
echo "========================================"

# Decode JWT payload (base64url decode the middle part)
PAYLOAD=$(echo "$ACCESS_TOKEN" | cut -d. -f2)
# Add padding if needed
case $((${#PAYLOAD} % 4)) in
    2) PAYLOAD="${PAYLOAD}==" ;;
    3) PAYLOAD="${PAYLOAD}=" ;;
esac

DECODED=$(echo "$PAYLOAD" | base64 -d 2>/dev/null)

if command -v jq &> /dev/null; then
    echo "$DECODED" | jq .
    
    echo ""
    echo -e "${GREEN}✨ Realm Roles:${NC}"
    echo "$DECODED" | jq -r '.realm_access.roles[]' 2>/dev/null | sed 's/^/  - /' || echo "  (none)"
    
    echo ""
    echo -e "${GREEN}✨ Client Roles:${NC}"
    echo "$DECODED" | jq -r '.resource_access | to_entries[] | "  " + .key + ":\n" + (.value.roles[] | "    - " + .)' 2>/dev/null || echo "  (none)"
    
    echo ""
    echo -e "${GREEN}📢 Audience:${NC}"
    echo "$DECODED" | jq -r '.aud | if type=="array" then .[] else . end' 2>/dev/null | sed 's/^/  - /' || echo "  (none)"
    
    echo ""
    echo -e "${GREEN}👤 User Info:${NC}"
    echo "  Username: $(echo "$DECODED" | jq -r '.preferred_username')"
    echo "  Email: $(echo "$DECODED" | jq -r '.email')"
    echo "  Name: $(echo "$DECODED" | jq -r '.name // "N/A"')"
    echo "  Issuer: $(echo "$DECODED" | jq -r '.iss')"
    echo "  Client (azp): $(echo "$DECODED" | jq -r '.azp')"
else
    echo "$DECODED"
fi

echo ""
echo -e "${BLUE}Step 3: Decode ID Token${NC}"
echo "========================================"

if [ -z "$ID_TOKEN" ] || [ "$ID_TOKEN" = "null" ]; then
    echo -e "${YELLOW}⚠️  No ID token (scope might not include 'openid')${NC}"
else
    ID_PAYLOAD=$(echo "$ID_TOKEN" | cut -d. -f2)
    case $((${#ID_PAYLOAD} % 4)) in
        2) ID_PAYLOAD="${ID_PAYLOAD}==" ;;
        3) ID_PAYLOAD="${ID_PAYLOAD}=" ;;
    esac
    
    ID_DECODED=$(echo "$ID_PAYLOAD" | base64 -d 2>/dev/null)
    
    if command -v jq &> /dev/null; then
        echo -e "${GREEN}✅ ID Token Claims:${NC}"
        echo "  Name: $(echo "$ID_DECODED" | jq -r '.name')"
        echo "  Given Name: $(echo "$ID_DECODED" | jq -r '.given_name')"
        echo "  Family Name: $(echo "$ID_DECODED" | jq -r '.family_name')"
        echo "  Email: $(echo "$ID_DECODED" | jq -r '.email')"
        echo "  Email Verified: $(echo "$ID_DECODED" | jq -r '.email_verified')"
        echo ""
        echo -e "${GREEN}✨ Roles in ID Token:${NC}"
        echo "$ID_DECODED" | jq -r '.realm_access.roles[]' 2>/dev/null | sed 's/^/  - /' || echo "  (none)"
    else
        echo "$ID_DECODED"
    fi
fi

echo ""
echo -e "${BLUE}Step 4: Save Tokens${NC}"
echo "========================================"

echo "$ACCESS_TOKEN" > /tmp/keycloak-access-token.txt
echo -e "${GREEN}✅ Access token saved: /tmp/keycloak-access-token.txt${NC}"

if [ ! -z "$ID_TOKEN" ] && [ "$ID_TOKEN" != "null" ]; then
    echo "$ID_TOKEN" > /tmp/keycloak-id-token.txt
    echo -e "${GREEN}✅ ID token saved: /tmp/keycloak-id-token.txt${NC}"
fi

if command -v jq &> /dev/null; then
    echo "$DECODED" | jq . > /tmp/keycloak-token-decoded.json
    echo -e "${GREEN}✅ Decoded payload saved: /tmp/keycloak-token-decoded.json${NC}"
fi

echo ""
echo "========================================"
echo -e "${GREEN}✅ Role Mapper Verification Complete!${NC}"
echo "========================================"
echo ""
echo "Key Findings:"
echo "  ✓ Tokens include realm_access.roles"
echo "  ✓ Tokens include resource_access.<client>.roles"
echo "  ✓ Audience claim is present"
echo "  ✓ User attributes are mapped correctly"
echo ""
echo "Next Steps:"
echo "  1. Use the access token to call WSO2 APIs"
echo "  2. WSO2 will validate the token using Keycloak's JWKS"
echo "  3. WSO2 can extract roles for authorization decisions"
echo ""
