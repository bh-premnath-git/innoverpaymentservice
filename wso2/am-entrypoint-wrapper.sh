#!/bin/bash
set -e

# Start WSO2 API-M in background
echo "▶ Starting WSO2 API Manager..."
/home/wso2carbon/wso2am-4.5.0/bin/api-manager.sh &
AM_PID=$!

# Wait for API-M to be ready
echo "▶ Waiting for WSO2 API-M to be ready (this may take several minutes)..."
MAX_WAIT=600
ELAPSED=0
until curl -k -sf https://localhost:9443/publisher >/dev/null 2>&1; do
  if [ $ELAPSED -ge $MAX_WAIT ]; then
    echo "❌ API-M did not start in time"
    exit 1
  fi
  sleep 10
  ELAPSED=$((ELAPSED + 10))
  echo "  ... waiting ($ELAPSED/${MAX_WAIT}s)"
done

echo "✅ WSO2 API-M is ready"
sleep 20  # Extra stabilization time

# Run API setup if config file exists
if [ -f "/config/api-config.yaml" ]; then
  echo "▶ Running API setup..."
  AM_HOST=localhost \
  AM_PORT=9443 \
  AM_ADMIN_USER=${AM_ADMIN_USER:-admin} \
  AM_ADMIN_PASS=${AM_ADMIN_PASS:-admin} \
  GW_HOST=${GW_HOST:-localhost} \
  GW_PORT=${GW_PORT:-8243} \
  VHOST=${VHOST:-localhost} \
  /home/wso2carbon/apim-publish-from-yaml.sh /config/api-config.yaml || echo "⚠️  API setup failed"
else
  echo "⚠️  No API config found at /config/api-config.yaml, skipping setup"
fi

echo ""
echo "ℹ️  To integrate WSO2 IS as Key Manager:"
echo "   Configure manually via Admin Portal: https://localhost:9443/admin"
echo "   Settings > Key Managers > Add Key Manager"
echo "   Use WSO2 IS endpoints (port 9443 from Docker network: https://wso2is:9443)"

# Keep container running
echo "✅ Setup complete, WSO2 API-M running"
wait $AM_PID
