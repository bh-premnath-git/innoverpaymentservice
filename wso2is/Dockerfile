FROM wso2/wso2is:7.1.0-alpine

USER root

# Install dependencies for setup script
RUN apk add --no-cache curl bash jq

# =============================================================================
# WSO2 IS <-> APIM Integration Configuration
# =============================================================================

# First, let's backup the original deployment.toml and then create our APIM-integrated version
RUN cp /home/wso2carbon/wso2is-7.1.0/repository/conf/deployment.toml /home/wso2carbon/wso2is-7.1.0/repository/conf/deployment.toml.backup 2>/dev/null || true

# Copy our APIM integration deployment.toml (this will be the main config)
COPY deployment.toml /home/wso2carbon/wso2is-7.1.0/repository/conf/deployment.toml
RUN chown wso2carbon:wso2 /home/wso2carbon/wso2is-7.1.0/repository/conf/deployment.toml

# Remove X509Certificate valve configuration from catalina-server.xml to avoid ClassNotFoundException
RUN sed -i '/<Valve className="org.wso2.carbon.extension.identity.x509Certificate.valve.X509CertificateAuthenticationValve"/d' \
    /home/wso2carbon/wso2is-7.1.0/repository/conf/tomcat/catalina-server.xml || true

# =============================================================================
# Key Manager Extensions (for APIM Integration)
# =============================================================================
# Note: For IS 7.1.0, the notification handlers are built-in (no dropins needed)
# The deployment.toml event_listener configuration is sufficient
# If you need additional Key Manager operations, add them here as needed

# =============================================================================
# User/Role Setup Scripts
# =============================================================================

# Copy user/role setup script
COPY setup-users-and-roles.sh /home/wso2carbon/setup-users-and-roles.sh
RUN chmod +x /home/wso2carbon/setup-users-and-roles.sh && \
    chown wso2carbon:wso2 /home/wso2carbon/setup-users-and-roles.sh

# Create wrapper script to run IS then setup users
COPY entrypoint-wrapper.sh /home/wso2carbon/entrypoint-wrapper.sh
RUN chmod +x /home/wso2carbon/entrypoint-wrapper.sh && \
    chown wso2carbon:wso2 /home/wso2carbon/entrypoint-wrapper.sh

USER wso2carbon

ENTRYPOINT ["/home/wso2carbon/entrypoint-wrapper.sh"]
