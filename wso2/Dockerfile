FROM wso2/wso2am:4.5.0-alpine

USER root

# Install dependencies for API setup script
RUN apk add --no-cache bash curl jq yq

# ============================================================================
# IS7 Key Manager Registration
# ============================================================================
# Copy IS7 Key Manager configuration to home directory (not /config which gets mounted)
COPY is7-key-manager.json /home/wso2carbon/is7-key-manager.json
COPY register-is7-key-manager.sh /home/wso2carbon/register-is7-key-manager.sh
RUN chmod +x /home/wso2carbon/register-is7-key-manager.sh && \
    chown wso2carbon:wso2 /home/wso2carbon/register-is7-key-manager.sh /home/wso2carbon/is7-key-manager.json

# ============================================================================
# API Publishing Scripts
# ============================================================================
# Copy API setup scripts
COPY apim-publish-from-yaml.sh /home/wso2carbon/apim-publish-from-yaml.sh
COPY publish-apis-manual.sh /home/wso2carbon/publish-apis-manual.sh
RUN chmod +x /home/wso2carbon/apim-publish-from-yaml.sh /home/wso2carbon/publish-apis-manual.sh && \
    chown wso2carbon:wso2 /home/wso2carbon/apim-publish-from-yaml.sh /home/wso2carbon/publish-apis-manual.sh

# Create wrapper script to run API-M then setup APIs
COPY am-entrypoint-wrapper.sh /home/wso2carbon/am-entrypoint-wrapper.sh
RUN chmod +x /home/wso2carbon/am-entrypoint-wrapper.sh && \
    chown wso2carbon:wso2 /home/wso2carbon/am-entrypoint-wrapper.sh

# ============================================================================
# Disable hostname verification for WSO2-IS integration
# ============================================================================
# This allows APIM to trust certificates with CN=localhost when calling wso2is:9443
ENV JAVA_OPTS="${JAVA_OPTS} -Dhttpclient.hostnameVerifier=AllowAll"

USER wso2carbon

ENTRYPOINT ["/home/wso2carbon/am-entrypoint-wrapper.sh"]
