FROM wso2/wso2is:7.1.0-alpine

USER root

# Install dependencies for setup script
RUN apk add --no-cache curl bash jq

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
