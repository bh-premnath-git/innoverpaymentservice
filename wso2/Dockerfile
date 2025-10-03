# WSO2 Setup Automation Container
FROM python:3.11-slim

# Install dependencies
RUN apt-get update && \
    apt-get install -y curl && \
    rm -rf /var/lib/apt/lists/*

# Install Python dependencies
RUN pip install --no-cache-dir requests pyyaml

# Create working directory
WORKDIR /wso2

# Copy all WSO2 configuration scripts
COPY configure-keycloak.py /wso2/
COPY wso2-publisher-from-config.py /wso2/
COPY deploy-existing-apis.py /wso2/
COPY create-application.py /wso2/
COPY api-config.yaml /wso2/
COPY setup-wso2.sh /wso2/

# Make scripts executable
RUN chmod +x /wso2/setup-wso2.sh && \
    chmod +x /wso2/configure-keycloak.py && \
    chmod +x /wso2/wso2-publisher-from-config.py && \
    chmod +x /wso2/deploy-existing-apis.py && \
    chmod +x /wso2/create-application.py

# Set environment variables
ENV PYTHONUNBUFFERED=1

# Run setup script
CMD ["/wso2/setup-wso2.sh"]
