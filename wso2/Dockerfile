FROM python:3.11-slim

WORKDIR /app

# Install dependencies
RUN pip install --no-cache-dir \
    requests \
    pyyaml

# Copy setup scripts
COPY setup.py /app/setup.py
COPY configure-keycloak-km.py /app/configure-keycloak-km.py
RUN chmod +x /app/setup.py /app/configure-keycloak-km.py

# Run setup (default entrypoint, can be overridden)
ENTRYPOINT ["python3", "/app/setup.py"]
