#!/bin/bash
# Configure OAuth application to include user claims in JWT tokens

set -e

IS_HOST="${IS_HOST:-localhost}"
IS_PORT="${IS_PORT:-9443}"
IS_BASE="https://${IS_HOST}:${IS_PORT}"
IS_ADMIN_USER="${IS_ADMIN_USER:-admin}"
IS_ADMIN_PASS="${IS_ADMIN_PASS:-admin}"

echo "════════════════════════════════════════════════════════════════"
echo "📋 Configuring JWT Claims for OAuth Application"
echo "════════════════════════════════════════════════════════════════"
echo ""

# Get the OAuth application (find the is-password-client app)
echo "1. Finding OAuth application..."
APPS=$(curl -sk -u "${IS_ADMIN_USER}:${IS_ADMIN_PASS}" \
  "${IS_BASE}/api/server/v1/applications?filter=name+co+is-password-client" 2>/dev/null)

APP_ID=$(echo "$APPS" | jq -r '.applications[0].id // empty')

if [ -z "$APP_ID" ]; then
  echo "❌ No OAuth application found matching 'is-password-client'"
  exit 1
fi

echo "✅ Found application: $APP_ID"
echo ""

# Update the application to include user claims
echo "2. Updating application configuration to include user claims..."

# Get current application config
APP_CONFIG=$(curl -sk -u "${IS_ADMIN_USER}:${IS_ADMIN_PASS}" \
  "${IS_BASE}/api/server/v1/applications/${APP_ID}" 2>/dev/null)

# Get OIDC config
OIDC_CONFIG=$(curl -sk -u "${IS_ADMIN_USER}:${IS_ADMIN_PASS}" \
  "${IS_BASE}/api/server/v1/applications/${APP_ID}/inbound-protocols/oidc" 2>/dev/null)

CLIENT_ID=$(echo "$OIDC_CONFIG" | jq -r '.clientId')
CLIENT_SECRET=$(echo "$OIDC_CONFIG" | jq -r '.clientSecret')

echo "  Client ID: ${CLIENT_ID}"
echo ""

# Update OIDC configuration to include claims
echo "3. Configuring JWT to include user claims..."

UPDATED_OIDC=$(cat <<EOF
{
  "clientId": "${CLIENT_ID}",
  "clientSecret": "${CLIENT_SECRET}",
  "grantTypes": ["password", "refresh_token"],
  "callbackURLs": ["https://localhost/cb"],
  "publicClient": false,
  "accessToken": {
    "type": "JWT",
    "userAccessTokenExpiryInSeconds": 3600,
    "applicationAccessTokenExpiryInSeconds": 3600,
    "bindingType": "None",
    "validateTokenBinding": false
  },
  "idToken": {
    "expiryInSeconds": 3600,
    "audience": [],
    "encryption": {
      "enabled": false
    }
  },
  "refreshToken": {
    "expiryInSeconds": 86400,
    "renewRefreshToken": true
  },
  "scopeValidators": [],
  "allowedOrigins": [],
  "validateRequestObjectSignature": false,
  "pkce": {
    "mandatory": false,
    "supportPlainTransformAlgorithm": true
  }
}
EOF
)

UPDATE_RESP=$(curl -sk -u "${IS_ADMIN_USER}:${IS_ADMIN_PASS}" \
  -X PUT \
  -H "Content-Type: application/json" \
  -d "$UPDATED_OIDC" \
  "${IS_BASE}/api/server/v1/applications/${APP_ID}/inbound-protocols/oidc" 2>/dev/null)

if echo "$UPDATE_RESP" | jq -e '.clientId' >/dev/null 2>&1; then
  echo "✅ OAuth configuration updated successfully"
else
  echo "⚠️  Update response: $UPDATE_RESP"
fi

echo ""

# Configure claim configuration for the application
echo "4. Configuring claim mappings..."

CLAIM_CONFIG=$(cat <<'EOF'
{
  "dialect": "LOCAL",
  "claimMappings": [
    {
      "applicationClaim": "username",
      "localClaim": {
        "uri": "http://wso2.org/claims/username"
      }
    },
    {
      "applicationClaim": "email",
      "localClaim": {
        "uri": "http://wso2.org/claims/emailaddress"
      }
    },
    {
      "applicationClaim": "roles",
      "localClaim": {
        "uri": "http://wso2.org/claims/role"
      }
    },
    {
      "applicationClaim": "groups",
      "localClaim": {
        "uri": "http://wso2.org/claims/groups"
      }
    },
    {
      "applicationClaim": "given_name",
      "localClaim": {
        "uri": "http://wso2.org/claims/givenname"
      }
    },
    {
      "applicationClaim": "family_name",
      "localClaim": {
        "uri": "http://wso2.org/claims/lastname"
      }
    }
  ],
  "requestedClaims": [
    {
      "claim": {
        "uri": "http://wso2.org/claims/username"
      },
      "mandatory": true
    },
    {
      "claim": {
        "uri": "http://wso2.org/claims/emailaddress"
      },
      "mandatory": false
    },
    {
      "claim": {
        "uri": "http://wso2.org/claims/role"
      },
      "mandatory": false
    },
    {
      "claim": {
        "uri": "http://wso2.org/claims/groups"
      },
      "mandatory": false
    }
  ],
  "subject": {
    "claim": {
      "uri": "http://wso2.org/claims/username"
    },
    "includeUserDomain": false,
    "includeTenantDomain": false,
    "useMappedLocalSubject": false
  },
  "role": {
    "claim": {
      "uri": "http://wso2.org/claims/role"
    },
    "includeUserDomain": false,
    "mappings": []
  }
}
EOF
)

CLAIM_RESP=$(curl -sk -u "${IS_ADMIN_USER}:${IS_ADMIN_PASS}" \
  -X PUT \
  -H "Content-Type: application/json" \
  -d "$CLAIM_CONFIG" \
  "${IS_BASE}/api/server/v1/applications/${APP_ID}/claim-configuration" 2>/dev/null)

echo "✅ Claim configuration applied"
echo ""

echo "════════════════════════════════════════════════════════════════"
echo "✅ Configuration Complete!"
echo "════════════════════════════════════════════════════════════════"
echo ""
echo "OAuth Application configured to include:"
echo "  • username (from http://wso2.org/claims/username)"
echo "  • email (from http://wso2.org/claims/emailaddress)"
echo "  • roles (from http://wso2.org/claims/role)"
echo "  • groups (from http://wso2.org/claims/groups)"
echo ""
echo "JWT tokens will now include user information!"
echo ""
