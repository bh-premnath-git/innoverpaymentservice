FROM python:3.11-slim

WORKDIR /app

# Install dependencies
COPY requirements.txt /app/
RUN pip install --no-cache-dir -r requirements.txt

# Copy setup scripts
COPY setup.py /app/setup.py
COPY configure-keycloak-km.py /app/configure-keycloak-km.py

RUN chmod +x /app/*.py

# Default entrypoint (use setup.py for WSO2 4.5.0)
ENTRYPOINT ["python3", "/app/setup.py"]
