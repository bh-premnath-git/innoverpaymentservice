FROM python:3.11-slim

WORKDIR /app

# Install dependencies
COPY requirements.txt /app/
RUN pip install --no-cache-dir -r requirements.txt

# Copy setup script
COPY setup.py /app/setup.py

RUN chmod +x /app/*.py

# WSO2 IS & APIM auto-connect - just setup APIs
ENTRYPOINT ["python3", "/app/setup.py"]
