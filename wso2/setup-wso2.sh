#!/bin/bash
set -e

echo "========================================================================"
echo "WSO2 API Manager - Complete Setup Automation"
echo "========================================================================"

# Wait for WSO2 to be fully ready
echo ""
echo "🔄 Waiting for WSO2 API Manager to be ready..."
MAX_RETRIES=40
RETRY_COUNT=0

while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    if curl -k -fsS https://wso2am:9443/services/Version > /dev/null 2>&1; then
        echo "✅ WSO2 API Manager is ready!"
        break
    fi
    RETRY_COUNT=$((RETRY_COUNT + 1))
    echo "⏳ Waiting for WSO2... (attempt $RETRY_COUNT/$MAX_RETRIES)"
    sleep 6
done

if [ $RETRY_COUNT -eq $MAX_RETRIES ]; then
    echo "❌ WSO2 API Manager did not become ready in time"
    exit 1
fi

# Wait for Keycloak to be ready
echo ""
echo "🔄 Waiting for Keycloak to be ready..."
RETRY_COUNT=0

while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    if curl -fsS http://keycloak:8080/realms/innover/.well-known/openid-configuration > /dev/null 2>&1; then
        echo "✅ Keycloak is ready!"
        break
    fi
    RETRY_COUNT=$((RETRY_COUNT + 1))
    echo "⏳ Waiting for Keycloak... (attempt $RETRY_COUNT/$MAX_RETRIES)"
    sleep 6
done

if [ $RETRY_COUNT -eq $MAX_RETRIES ]; then
    echo "❌ Keycloak did not become ready in time"
    exit 1
fi

# Additional wait to ensure services are fully initialized
echo ""
echo "⏳ Waiting 10 seconds for services to fully initialize..."
sleep 10

# Step 1: Configure Keycloak as Key Manager
echo ""
echo "========================================================================"
echo "Step 1: Configuring Keycloak as Key Manager"
echo "========================================================================"
python3 /wso2/configure-keycloak.py
if [ $? -ne 0 ]; then
    echo "❌ Failed to configure Keycloak Key Manager"
    exit 1
fi

# Step 2: Publish APIs
echo ""
echo "========================================================================"
echo "Step 2: Publishing APIs to WSO2"
echo "========================================================================"
python3 /wso2/wso2-publisher-from-config.py
if [ $? -ne 0 ]; then
    echo "❌ Failed to publish APIs"
    exit 1
fi

# Step 2.5: Deploy APIs to Gateway
echo ""
echo "========================================================================"
echo "Step 2.5: Deploying APIs to Gateway"
echo "========================================================================"
python3 /wso2/deploy-existing-apis.py
if [ $? -ne 0 ]; then
    echo "❌ Failed to deploy APIs"
    exit 1
fi

# Step 3: Create Application and Subscribe to APIs
echo ""
echo "========================================================================"
echo "Step 3: Creating Application and Subscribing to APIs"
echo "========================================================================"
python3 /wso2/create-application.py
if [ $? -ne 0 ]; then
    echo "❌ Failed to create application"
    exit 1
fi

# Final summary
echo ""
echo "========================================================================"
echo "✅ WSO2 API Manager Setup Complete!"
echo "========================================================================"
echo ""
echo "📊 Summary:"
echo "   ✅ Keycloak Key Manager configured"
echo "   ✅ APIs published and deployed to gateway"
echo "   ✅ Application created and subscribed"
echo ""
echo "🌐 Access Points:"
echo "   - WSO2 Publisher: https://localhost:9443/publisher"
echo "   - WSO2 DevPortal: https://localhost:9443/devportal"
echo "   - Keycloak Admin: http://localhost:8080"
echo ""
echo "🔑 Credentials:"
echo "   - WSO2: admin/admin"
echo "   - Keycloak: admin/admin"
echo ""
echo "🧪 Test Commands:"
echo "   python3 sandbox/test_keycloak_token.py"
echo "   python3 sandbox/test_services_direct.py"
echo ""

# Keep container running (if this is the main process)
if [ "${KEEP_ALIVE}" = "true" ]; then
    echo "Container will stay alive for monitoring..."
    tail -f /dev/null
fi
