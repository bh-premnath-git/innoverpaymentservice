import os
from fastapi import FastAPI

SERVICE_NAME = os.getenv("SERVICE_NAME", "svc-unknown")

app = FastAPI(title=SERVICE_NAME)


@app.get("/health")
def health() -> dict[str, str]:
    """Liveness probe for the service."""
    return {"status": "ok", "service": SERVICE_NAME}


@app.get("/readiness")
def readiness() -> dict[str, str]:
    """Readiness probe for upstream load balancers."""
    return {"status": "ready", "service": SERVICE_NAME}
