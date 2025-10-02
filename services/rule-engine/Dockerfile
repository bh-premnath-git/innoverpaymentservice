# services/rule-engine/Dockerfile
FROM python:3.12-slim

RUN apt-get update \
    && apt-get install -y --no-install-recommends build-essential \
    && rm -rf /var/lib/apt/lists/*

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1

WORKDIR /app

# Optional: requirements (skip if you don't have any)
COPY app/requirements.txt /app/requirements.txt
RUN pip install --upgrade pip setuptools wheel
RUN if [ -s /app/requirements.txt ]; then pip install -r /app/requirements.txt; fi

# Copy code
COPY app/ /app/

# Create non-root user
RUN groupadd -r appuser && useradd -r -g appuser appuser \
    && chown -R appuser:appuser /app

USER appuser

# No healthcheck for workers - they don't expose HTTP
# For FastAPI mode, healthcheck can be added in docker-compose override

EXPOSE 8000

# Run the FastAPI application
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
