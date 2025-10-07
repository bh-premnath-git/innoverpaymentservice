#!/usr/bin/env bash
# Exchanges TLS certificates between WSO2 API-M and WSO2 IS containers
# so they can trust each other for HTTPS communication
#
# Usage: ./exchange-certs.sh
#
# This script:
# 1. Exports IS's public cert and imports it into API-M truststore
# 2. Exports API-M's public cert and imports it into IS truststore
#
# Prerequisites:
# - Both containers must be running
# - Docker must be accessible

set -euo pipefail

# ---------- Configuration ----------
IS_CONTAINER="${IS_CONTAINER:-innover-wso2is-1}"
AM_CONTAINER="${AM_CONTAINER:-innover-wso2am-1}"

KEYSTORE_PASS="${KEYSTORE_PASS:-wso2carbon}"
TRUSTSTORE_PASS="${TRUSTSTORE_PASS:-wso2carbon}"

IS_HOME="/home/wso2carbon/wso2is-7.1.0"
AM_HOME="/home/wso2carbon/wso2am-4.5.0"

echo "▶ Exchanging TLS certificates between WSO2 API-M and WSO2 IS"
echo "  IS Container: ${IS_CONTAINER}"
echo "  API-M Container: ${AM_CONTAINER}"
echo ""

# ---------- Export IS certificate ----------
echo "▶ [1/4] Exporting WSO2 IS public certificate"
docker exec "${IS_CONTAINER}" bash -c "
  keytool -export -alias wso2carbon \
    -keystore ${IS_HOME}/repository/resources/security/wso2carbon.jks \
    -storepass '${KEYSTORE_PASS}' \
    -file /tmp/wso2is-cert.crt
" || { echo "!! Failed to export IS certificate"; exit 1; }
echo "  ✅ Exported to /tmp/wso2is-cert.crt (inside IS container)"

# ---------- Import IS cert into API-M truststore ----------
echo "▶ [2/4] Importing WSO2 IS certificate into API-M truststore"
docker exec "${IS_CONTAINER}" cat /tmp/wso2is-cert.crt | \
docker exec -i "${AM_CONTAINER}" bash -c "
  cat > /tmp/wso2is-cert.crt && \
  keytool -import -noprompt -trustcacerts \
    -alias wso2is \
    -file /tmp/wso2is-cert.crt \
    -keystore ${AM_HOME}/repository/resources/security/client-truststore.jks \
    -storepass '${TRUSTSTORE_PASS}' 2>/dev/null || echo '  (already imported or error)'
"
echo "  ✅ Imported into API-M client-truststore.jks"

# ---------- Export API-M certificate ----------
echo "▶ [3/4] Exporting WSO2 API-M public certificate"
docker exec "${AM_CONTAINER}" bash -c "
  keytool -export -alias wso2carbon \
    -keystore ${AM_HOME}/repository/resources/security/wso2carbon.jks \
    -storepass '${KEYSTORE_PASS}' \
    -file /tmp/wso2am-cert.crt
" || { echo "!! Failed to export API-M certificate"; exit 1; }
echo "  ✅ Exported to /tmp/wso2am-cert.crt (inside API-M container)"

# ---------- Import API-M cert into IS truststore ----------
echo "▶ [4/4] Importing WSO2 API-M certificate into IS truststore"
docker exec "${AM_CONTAINER}" cat /tmp/wso2am-cert.crt | \
docker exec -i "${IS_CONTAINER}" bash -c "
  cat > /tmp/wso2am-cert.crt && \
  keytool -import -noprompt -trustcacerts \
    -alias wso2am \
    -file /tmp/wso2am-cert.crt \
    -keystore ${IS_HOME}/repository/resources/security/client-truststore.jks \
    -storepass '${TRUSTSTORE_PASS}' 2>/dev/null || echo '  (already imported or error)'
"
echo "  ✅ Imported into IS client-truststore.jks"

# ---------- Cleanup ----------
echo ""
echo "▶ Cleaning up temporary files"
docker exec "${IS_CONTAINER}" rm -f /tmp/wso2is-cert.crt /tmp/wso2am-cert.crt 2>/dev/null || true
docker exec "${AM_CONTAINER}" rm -f /tmp/wso2is-cert.crt /tmp/wso2am-cert.crt 2>/dev/null || true

echo ""
echo "✅ Certificate exchange complete!"
echo ""
echo "⚠️  IMPORTANT: You must restart both containers for changes to take effect:"
echo "  docker restart ${IS_CONTAINER}"
echo "  docker restart ${AM_CONTAINER}"
echo ""
