#!/bin/bash

echo "════════════════════════════════════════════════════════════════"
echo "🚀 Publishing APIs and Creating Subscriptions"
echo "════════════════════════════════════════════════════════════════"
echo ""

APIM_BASE="https://localhost:9443"
ADMIN_USER="admin"
ADMIN_PASS="admin"
APP_NAME="DefaultApplication"

# Get application ID
echo "📋 Getting application ID..."
APP_ID=$(curl -sk -u "$ADMIN_USER:$ADMIN_PASS" \
  "$APIM_BASE/api/am/devportal/v3/applications" | \
  jq -r ".list[] | select(.name==\"$APP_NAME\") | .applicationId")

if [ -z "$APP_ID" ] || [ "$APP_ID" = "null" ]; then
  echo "❌ Application '$APP_NAME' not found"
  exit 1
fi

echo "✅ Application ID: $APP_ID"
echo ""

# Get all APIs
echo "📋 Fetching all APIs..."
APIS=$(curl -sk -u "$ADMIN_USER:$ADMIN_PASS" \
  "$APIM_BASE/api/am/publisher/v4/apis" | jq -c '.list[]')

API_COUNT=$(echo "$APIS" | wc -l)
echo "✅ Found $API_COUNT APIs"
echo ""

# Process each API
PUBLISHED=0
SUBSCRIBED=0

while IFS= read -r API; do
  API_ID=$(echo "$API" | jq -r '.id')
  API_NAME=$(echo "$API" | jq -r '.name')
  API_STATUS=$(echo "$API" | jq -r '.lifeCycleStatus')
  
  echo "─────────────────────────────────────────────────────────────"
  echo "📦 Processing: $API_NAME"
  echo "   ID: $API_ID"
  echo "   Status: $API_STATUS"
  
  # Publish API if not published
  if [ "$API_STATUS" != "PUBLISHED" ]; then
    echo "   🔄 Publishing API..."
    
    PUBLISH_RESULT=$(curl -sk -u "$ADMIN_USER:$ADMIN_PASS" -X POST \
      "$APIM_BASE/api/am/publisher/v4/apis/change-lifecycle?apiId=$API_ID&action=Publish" \
      -H "Content-Type: application/json" 2>&1)
    
    if echo "$PUBLISH_RESULT" | jq -e '.lifeCycleStatus == "PUBLISHED"' >/dev/null 2>&1; then
      echo "   ✅ Published successfully"
      ((PUBLISHED++))
    else
      echo "   ⚠️  Publish failed or already published"
    fi
  else
    echo "   ✅ Already published"
  fi
  
  # Create subscription
  echo "   🔗 Creating subscription..."
  
  SUB_RESULT=$(curl -sk -u "$ADMIN_USER:$ADMIN_PASS" -X POST \
    "$APIM_BASE/api/am/devportal/v3/subscriptions" \
    -H "Content-Type: application/json" \
    -d "{\"apiId\":\"$API_ID\",\"applicationId\":\"$APP_ID\",\"throttlingPolicy\":\"Unlimited\"}" 2>&1)
  
  if echo "$SUB_RESULT" | jq -e '.subscriptionId' >/dev/null 2>&1; then
    SUB_ID=$(echo "$SUB_RESULT" | jq -r '.subscriptionId')
    echo "   ✅ Subscribed (ID: $SUB_ID)"
    ((SUBSCRIBED++))
  else
    ERROR=$(echo "$SUB_RESULT" | jq -r '.description // .message // "Already subscribed"')
    echo "   ℹ️  $ERROR"
  fi
  
  echo ""
done <<< "$APIS"

echo "════════════════════════════════════════════════════════════════"
echo "✅ Complete!"
echo "════════════════════════════════════════════════════════════════"
echo "📊 Summary:"
echo "   APIs Published: $PUBLISHED"
echo "   Subscriptions Created: $SUBSCRIBED"
echo ""

# Verify subscriptions
echo "📋 Verifying subscriptions..."
SUB_COUNT=$(curl -sk -u "$ADMIN_USER:$ADMIN_PASS" \
  "$APIM_BASE/api/am/devportal/v3/subscriptions?applicationId=$APP_ID" | \
  jq '.count')

echo "✅ Total subscriptions for $APP_NAME: $SUB_COUNT"
echo ""
echo "Next step: Generate application keys"
echo "Run: ./generate-app-keys.sh"
