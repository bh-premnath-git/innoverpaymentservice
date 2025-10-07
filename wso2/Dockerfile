FROM wso2/wso2am:4.5.0-alpine

USER root

# Install dependencies for API setup script
RUN apk add --no-cache bash curl jq yq

# Copy API setup script
COPY apim-publish-from-yaml.sh /home/wso2carbon/apim-publish-from-yaml.sh
RUN chmod +x /home/wso2carbon/apim-publish-from-yaml.sh && \
    chown wso2carbon:wso2 /home/wso2carbon/apim-publish-from-yaml.sh

# Create wrapper script to run API-M then setup APIs
COPY am-entrypoint-wrapper.sh /home/wso2carbon/am-entrypoint-wrapper.sh
RUN chmod +x /home/wso2carbon/am-entrypoint-wrapper.sh && \
    chown wso2carbon:wso2 /home/wso2carbon/am-entrypoint-wrapper.sh

USER wso2carbon

ENTRYPOINT ["/home/wso2carbon/am-entrypoint-wrapper.sh"]
