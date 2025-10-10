#!/bin/bash
set -e

# Replace hostname in deployment.toml with environment variable
echo "▶ Configuring hostname: ${WSO2_HOSTNAME:-localhost}"
sed -i "s/^hostname = .*/hostname = \"${WSO2_HOSTNAME:-localhost}\"/" \
  /home/wso2carbon/wso2am-4.5.0/repository/conf/deployment.toml


# Start WSO2 IS in background
echo "▶ Starting WSO2 Identity Server..."
/home/wso2carbon/wso2is-7.1.0/bin/wso2server.sh &
IS_PID=$!

# Wait for IS to be ready using the official health check API (not deprecated Carbon UI)
echo "▶ Waiting for WSO2 IS to be ready..."
MAX_WAIT=300
ELAPSED=0
until curl -k -sf https://localhost:9443/api/health-check/v1.0/health >/dev/null 2>&1; do
  if [ $ELAPSED -ge $MAX_WAIT ]; then
    echo "❌ WSO2 IS did not start in time"
    exit 1
  fi
  sleep 5
  ELAPSED=$((ELAPSED + 5))
  echo "  ... waiting ($ELAPSED/${MAX_WAIT}s)"
done

echo "✅ WSO2 IS is ready"
sleep 20  # Extra stabilization time for SCIM2 and other services

# Test SCIM2 endpoint before running setup
echo "▶ Testing SCIM2 endpoint..."
for i in {1..10}; do
  if curl -k -sf -u admin:admin https://localhost:9443/scim2/Users >/dev/null 2>&1; then
    echo "✅ SCIM2 endpoint ready"
    break
  fi
  echo "  ... SCIM2 not ready, waiting (${i}/10)"
  sleep 3
done

# Run user/role setup
echo "▶ Running user/role setup..."
export IS_HOST=localhost
export IS_ADMIN_USER="${IS_ADMIN_USER:-admin}"
export IS_ADMIN_PASS="${IS_ADMIN_PASS:-admin}"
/home/wso2carbon/setup-users-and-roles.sh || {
  echo "⚠️  User setup failed - this is OK if users already exist"
  echo "   Check logs above for details"
}

# Keep container running
echo "✅ Setup complete, WSO2 IS running"
wait $IS_PID
