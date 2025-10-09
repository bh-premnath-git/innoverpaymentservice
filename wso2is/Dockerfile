FROM wso2/wso2is:7.1.0-alpine

USER root

# Install dependencies for setup script
RUN apk add --no-cache curl bash jq

<<<<<<< HEAD
# =============================================================================
# WSO2 IS <-> APIM Integration Configuration
# =============================================================================

# First, let's backup the original deployment.toml and then create our APIM-integrated version
RUN cp /home/wso2carbon/wso2is-7.1.0/repository/conf/deployment.toml /home/wso2carbon/wso2is-7.1.0/repository/conf/deployment.toml.backup 2>/dev/null || true

# Copy our APIM integration deployment.toml (this will be the main config)
COPY deployment.toml /home/wso2carbon/wso2is-7.1.0/repository/conf/deployment.toml
RUN chown wso2carbon:wso2 /home/wso2carbon/wso2is-7.1.0/repository/conf/deployment.toml

# Download token revocation event handler JAR (required for APIM integration)
RUN curl -L -o /home/wso2carbon/wso2is-7.1.0/repository/components/dropins/notification.event.handlers-2.0.5.jar \
    https://maven.wso2.org/nexus/service/local/repositories/releases/content/org/wso2/is/notification.event.handlers/2.0.5/notification.event.handlers-2.0.5.jar && \
    chown wso2carbon:wso2 /home/wso2carbon/wso2is-7.1.0/repository/components/dropins/notification.event.handlers-2.0.5.jar

# =============================================================================
# User/Role Setup Scripts
# =============================================================================

=======
# ============================================================================
# IMPORTANT: Using DEFAULT deployment.toml from WSO2 IS
# ============================================================================
# We do NOT override deployment.toml to avoid configuration errors
# WSO2 IS 7.1.0 default config is sufficient for basic APIM integration
# Advanced config (token revocation, etc.) can be added later if needed

# ============================================================================
# User/Role Setup Scripts
# ============================================================================
>>>>>>> 5cb1c70 (changes)
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
