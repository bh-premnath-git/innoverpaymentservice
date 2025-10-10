#!/bin/bash

source /tmp/wso2is-app-credentials.sh

echo "Generating tokens for all users..."
echo ""

# Create output file
OUTPUT_FILE="/tmp/all-user-tokens.txt"
> $OUTPUT_FILE

declare -A USERS=(
  ["admin"]="admin"
  ["finance"]="Finance123"
  ["auditor"]="Auditor123"
  ["ops_user"]="OpsUser123"
  ["user"]="User1234"
)

for username in admin finance auditor ops_user user; do
  password="${USERS[$username]}"
  
  echo "Getting token for: ${username}..."
  
  TOKEN_RESPONSE=$(docker exec innover-wso2is-1 curl -sk -u "${IS_CLIENT_ID}:${IS_CLIENT_SECRET}" \
    -d "grant_type=password&username=${username}&password=${password}&scope=openid email profile groups roles" \
    "https://localhost:9443/oauth2/token" 2>/dev/null)
  
  ACCESS_TOKEN=$(echo "$TOKEN_RESPONSE" | jq -r '.access_token')
  EXPIRES_IN=$(echo "$TOKEN_RESPONSE" | jq -r '.expires_in')
  
  if [ -n "$ACCESS_TOKEN" ] && [ "$ACCESS_TOKEN" != "null" ]; then
    echo "  ✅ Success"
    
    # Save to file
    cat >> $OUTPUT_FILE <<EOF
════════════════════════════════════════════════════════════════
User: ${username}
Password: ${password}
════════════════════════════════════════════════════════════════

Access Token:
${ACCESS_TOKEN}

Expires In: ${EXPIRES_IN} seconds (60 minutes)

Curl Example:
curl -H "Authorization: Bearer ${ACCESS_TOKEN}" \\
  http://localhost:8280/api/forex/1.0.0/health

Postman:
  Headers → Key: Authorization
           Value: Bearer ${ACCESS_TOKEN}


EOF
  else
    echo "  ❌ Failed"
  fi
done

echo ""
echo "✅ All tokens generated!"
echo ""
echo "Tokens saved to: $OUTPUT_FILE"
echo ""
echo "View tokens:"
echo "  cat $OUTPUT_FILE"
echo ""
