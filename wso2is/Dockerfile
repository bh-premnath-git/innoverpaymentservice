FROM wso2/wso2is:7.1.0-alpine

USER root

# Install curl and bash for healthcheck and initialization
RUN apk add --no-cache curl bash

# Copy user initialization script
COPY create-users.sh /home/wso2carbon/create-users.sh
RUN chmod +x /home/wso2carbon/create-users.sh && \
    chown wso2carbon:wso2 /home/wso2carbon/create-users.sh

USER wso2carbon

# Keep default entrypoint - users will be created via separate service
