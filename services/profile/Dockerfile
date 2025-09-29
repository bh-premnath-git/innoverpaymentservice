# services/profile/Dockerfile
FROM python:3.14.0rc3-slim-trixie

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1

WORKDIR /app

# Optional: requirements (skip if you don't have any)
COPY app/requirements.txt /app/requirements.txt
RUN if [ -s /app/requirements.txt ]; then pip install -r /app/requirements.txt; fi

# Copy code
COPY app/ /app/

# Minimal healthcheck (optional)
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
  CMD python -c "import os; print('ok')" || exit 1

# Run your script continuously
CMD ["python", "-u", "main.py"]
