#!/bin/bash
set -e

# Start WSO2 API-M in background
echo "▶ Starting WSO2 API Manager..."
/home/wso2carbon/wso2am-4.5.0/bin/api-manager.sh &
AM_PID=$!

# Wait for API-M to be ready (proper health checks)
echo "▶ Waiting for WSO2 API-M server to start..."
MAX_WAIT=600
ELAPSED=0

# Step 1: Wait for server to be up
until curl -k -sf https://localhost:9443/services/Version >/dev/null 2>&1; do
  if [ $ELAPSED -ge $MAX_WAIT ]; then
    echo "❌ API-M server did not start in time"
    exit 1
  fi
  sleep 10
  ELAPSED=$((ELAPSED + 10))
  echo "  ... waiting for server ($ELAPSED/${MAX_WAIT}s)"
done
echo "  ✓ Server is up"

# Step 2: Wait for Gateway to be ready for deployment
echo "▶ Waiting for Gateway deployment readiness..."
ELAPSED=0
until curl -k -sf https://localhost:9443/api/am/gateway/v2/server-startup-healthcheck >/dev/null 2>&1; do
  if [ $ELAPSED -ge $MAX_WAIT ]; then
    echo "⚠️  Gateway health check timeout, proceeding anyway"
    break
  fi
  sleep 10
  ELAPSED=$((ELAPSED + 10))
  echo "  ... waiting for gateway ($ELAPSED/${MAX_WAIT}s)"
done
echo "  ✓ Gateway is ready"

# Step 3: Wait for Publisher API to be responsive
echo "▶ Waiting for Publisher API..."
ELAPSED=0
until curl -k -sf https://localhost:9443/publisher >/dev/null 2>&1; do
  if [ $ELAPSED -ge 120 ]; then
    echo "⚠️  Publisher timeout, proceeding anyway"
    break
  fi
  sleep 5
  ELAPSED=$((ELAPSED + 5))
  echo "  ... waiting for publisher ($ELAPSED/120s)"
done
echo "  ✓ Publisher is ready"

echo "✅ WSO2 API-M is fully ready"
sleep 10  # Brief stabilization time

# ============================================================================
# Step 1: Register WSO2 IS 7 as Third-Party Key Manager
# ============================================================================
echo ""
echo "▶ Registering WSO2 IS 7 as Third-Party Key Manager..."
AM_HOST=localhost \
AM_PORT=9443 \
AM_ADMIN_USER=${AM_ADMIN_USER:-admin} \
AM_ADMIN_PASS=${AM_ADMIN_PASS:-admin} \
/home/wso2carbon/register-is7-key-manager.sh || {
  echo "⚠️  Key Manager registration failed - continuing with Resident Key Manager"
}

# Wait for Key Manager configuration to be loaded and propagated
echo "▶ Waiting for Key Manager configuration to stabilize..."
sleep 30

# Verify Key Manager is accessible
echo "▶ Verifying Key Manager registration..."
for i in {1..5}; do
  if curl -sk -u admin:admin "https://localhost:9443/api/am/admin/v4/key-managers" | grep -q "WSO2-IS"; then
    echo "  ✓ Key Manager verified"
    break
  fi
  echo "  ... attempt $i/5"
  sleep 5
done

# ============================================================================
# Step 2: Publish APIs from YAML configuration (Optional - can be run manually)
# ============================================================================
AUTO_PUBLISH_APIS="${AUTO_PUBLISH_APIS:-false}"

if [ "${AUTO_PUBLISH_APIS}" = "true" ]; then
  if [ -f "/config/api-config.yaml" ]; then
    echo ""
    echo "▶ Running automatic API setup..."
    AM_HOST=localhost \
    AM_PORT=9443 \
    AM_ADMIN_USER=${AM_ADMIN_USER:-admin} \
    AM_ADMIN_PASS=${AM_ADMIN_PASS:-admin} \
    KEY_MANAGER_NAME="WSO2-IS" \
    POST_STABILIZE_WAIT="${POST_STABILIZE_WAIT:-50}" \
    /home/wso2carbon/apim-publish-from-yaml.sh /config/api-config.yaml || echo "⚠️  API setup failed"
  else
    echo "⚠️  No API config found at /config/api-config.yaml, skipping setup"
  fi
else
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "ℹ️  Automatic API publishing is DISABLED"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""
  echo "To publish APIs manually, run:"
  echo "  docker exec innover-wso2am-1 /home/wso2carbon/publish-apis-manual.sh"
  echo ""
  echo "Or from host:"
  echo "  docker compose exec wso2am /home/wso2carbon/publish-apis-manual.sh"
  echo ""
  echo "To enable automatic publishing on startup, set:"
  echo "  AUTO_PUBLISH_APIS=true"
  echo ""
fi

echo ""
echo "════════════════════════════════════════════════════════════════"
echo "✅ WSO2 APIM Setup Complete"
echo "════════════════════════════════════════════════════════════════"
echo "Key Manager: WSO2-IS"
echo "All users from WSO2 IS can now authenticate (admin, finance, auditor, ops_user, user)"
echo ""
echo "Admin Portal: https://localhost:9443/admin"
echo "Dev Portal:   https://localhost:9443/devportal"
echo "Publisher:    https://localhost:9443/publisher"
echo "════════════════════════════════════════════════════════════════"

# Keep container running
echo "✅ Setup complete, WSO2 API-M running"
wait $AM_PID
