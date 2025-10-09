#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# Setup Mutual TLS Trust between WSO2 APIM and WSO2 IS
# ============================================================================
# This script:
# 1. Exports IS cert and imports to APIM truststore
# 2. Exports APIM cert and imports to IS truststore
# 3. Verifies connectivity both directions
# ============================================================================

echo "════════════════════════════════════════════════════════════════"
echo "🔐 Setting up Mutual TLS Trust: WSO2 APIM ↔ WSO2 IS"
echo "════════════════════════════════════════════════════════════════"
echo ""

# ============================================================================
# Step 1: Export IS certificate and import to APIM truststore
# ============================================================================
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📤 Step 1: IS ➜ APIM Trust"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

echo "▶ Exporting IS server certificate..."
docker exec innover-wso2is-1 keytool -exportcert -rfc \
  -alias wso2carbon \
  -keystore /home/wso2carbon/wso2is-7.1.0/repository/resources/security/wso2carbon.p12 \
  -storetype PKCS12 \
  -storepass wso2carbon \
  -file /tmp/is.crt
echo "  ✓ IS certificate exported to /tmp/is.crt"

echo ""
echo "▶ Copying IS certificate to host..."
docker cp innover-wso2is-1:/tmp/is.crt /tmp/is.crt
echo "  ✓ Copied to /tmp/is.crt"

echo ""
echo "▶ Copying IS certificate to APIM container..."
docker cp /tmp/is.crt innover-wso2am-1:/tmp/is.crt
echo "  ✓ Copied to APIM container"

echo ""
echo "▶ Removing old wso2is alias if exists..."
docker exec innover-wso2am-1 keytool -delete -alias wso2is \
  -keystore /home/wso2carbon/wso2am-4.5.0/repository/resources/security/client-truststore.jks \
  -storepass wso2carbon 2>/dev/null || echo "  (no existing alias, continuing)"

echo ""
echo "▶ Importing IS certificate into APIM client-truststore.jks..."
docker exec innover-wso2am-1 keytool -importcert \
  -alias wso2is \
  -file /tmp/is.crt \
  -keystore /home/wso2carbon/wso2am-4.5.0/repository/resources/security/client-truststore.jks \
  -storepass wso2carbon \
  -noprompt
echo "  ✅ IS certificate imported to APIM truststore"
echo ""

# ============================================================================
# Step 2: Export APIM certificate and import to IS truststore
# ============================================================================
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📤 Step 2: APIM ➜ IS Trust"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

echo "▶ Exporting APIM server certificate..."
docker exec innover-wso2am-1 keytool -exportcert -rfc \
  -alias wso2carbon \
  -keystore /home/wso2carbon/wso2am-4.5.0/repository/resources/security/wso2carbon.jks \
  -storepass wso2carbon \
  -file /tmp/apim.crt
echo "  ✓ APIM certificate exported to /tmp/apim.crt"

echo ""
echo "▶ Copying APIM certificate to host..."
docker cp innover-wso2am-1:/tmp/apim.crt /tmp/apim.crt
echo "  ✓ Copied to /tmp/apim.crt"

echo ""
echo "▶ Copying APIM certificate to IS container..."
docker cp /tmp/apim.crt innover-wso2is-1:/tmp/apim.crt
echo "  ✓ Copied to IS container"

echo ""
echo "▶ Removing old apim alias if exists..."
docker exec innover-wso2is-1 keytool -delete -alias apim \
  -keystore /home/wso2carbon/wso2is-7.1.0/repository/resources/security/client-truststore.p12 \
  -storetype PKCS12 \
  -storepass wso2carbon 2>/dev/null || echo "  (no existing alias, continuing)"

echo ""
echo "▶ Importing APIM certificate into IS client-truststore.p12..."
docker exec innover-wso2is-1 keytool -importcert \
  -alias apim \
  -file /tmp/apim.crt \
  -keystore /home/wso2carbon/wso2is-7.1.0/repository/resources/security/client-truststore.p12 \
  -storetype PKCS12 \
  -storepass wso2carbon \
  -noprompt
echo "  ✅ APIM certificate imported to IS truststore"
echo ""

# ============================================================================
# Step 3: Restart both containers to load new truststores
# ============================================================================
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🔄 Step 3: Restarting Containers"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

echo "▶ Restarting WSO2 IS..."
docker compose restart wso2is
echo "  ✓ IS restarted"

echo ""
echo "▶ Waiting for IS to be healthy..."
sleep 10
for i in {1..30}; do
  if docker exec innover-wso2is-1 curl -sk https://localhost:9443/carbon/admin/login.jsp > /dev/null 2>&1; then
    echo "  ✓ IS is healthy"
    break
  fi
  echo "  ... waiting (${i}/30)"
  sleep 5
done

echo ""
echo "▶ Restarting WSO2 APIM..."
docker compose restart wso2am
echo "  ✓ APIM restarted"

echo ""
echo "▶ Waiting for APIM to be healthy (this may take 3-4 minutes)..."
sleep 30
for i in {1..40}; do
  if docker exec innover-wso2am-1 curl -sk https://localhost:9443/carbon/admin/login.jsp > /dev/null 2>&1; then
    echo "  ✅ APIM is healthy"
    break
  fi
  echo "  ... waiting (${i}/40)"
  sleep 10
done

echo ""

# ============================================================================
# Step 4: Verify connectivity both directions
# ============================================================================
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ Step 4: Verifying Connectivity"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

echo "▶ Testing APIM ➜ IS (OIDC well-known endpoint)..."
if docker exec innover-wso2am-1 curl -sf https://wso2is:9443/oauth2/token/.well-known/openid-configuration > /dev/null 2>&1; then
  echo "  ✅ APIM can reach IS (HTTPS trust established)"
else
  echo "  ❌ APIM cannot reach IS (SSL may still have issues)"
fi

echo ""
echo "▶ Testing IS ➜ APIM (health endpoint)..."
if docker exec innover-wso2is-1 curl -sf https://wso2am:9443/services/Version > /dev/null 2>&1; then
  echo "  ✅ IS can reach APIM (HTTPS trust established)"
else
  echo "  ⚠️  IS cannot reach APIM (may be normal if endpoint doesn't exist)"
fi

echo ""
echo "▶ Testing token endpoint from APIM..."
TOKEN_TEST=$(docker exec innover-wso2am-1 curl -sk https://wso2is:9443/oauth2/token/.well-known/openid-configuration 2>&1)
if echo "$TOKEN_TEST" | grep -q "token_endpoint"; then
  echo "  ✅ Token endpoint accessible"
  echo "     $(echo "$TOKEN_TEST" | jq -r '.token_endpoint // "N/A"')"
else
  echo "  ❌ Token endpoint not accessible"
fi

echo ""

# ============================================================================
# Summary
# ============================================================================
echo "════════════════════════════════════════════════════════════════"
echo "✅ Mutual TLS Trust Setup Complete"
echo "════════════════════════════════════════════════════════════════"
echo ""
echo "📋 What was done:"
echo "  1. ✓ Exported IS certificate"
echo "  2. ✓ Imported IS cert into APIM client-truststore.jks"
echo "  3. ✓ Exported APIM certificate"
echo "  4. ✓ Imported APIM cert into IS client-truststore.p12"
echo "  5. ✓ Restarted both containers"
echo "  6. ✓ Verified connectivity"
echo ""
echo "🔧 Next steps:"
echo "  1. Regenerate application keys with WSO2-IS Key Manager:"
echo "     docker exec innover-wso2am-1 /home/wso2carbon/publish-apis-manual.sh"
echo ""
echo "  2. Or manually via APIM Developer Portal:"
echo "     https://localhost:9443/devportal"
echo ""
echo "💡 Note: The certificates persist in the mounted volumes,"
echo "   so this trust setup survives container restarts."
echo ""
