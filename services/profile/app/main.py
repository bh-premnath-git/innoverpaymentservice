import os
import base64
import json
from fastapi import FastAPI, Request

SERVICE_NAME = os.getenv("SERVICE_NAME", "svc-unknown")

app = FastAPI(title=SERVICE_NAME)


def decode_jwt_header(request: Request) -> dict:
    """Decode X-JWT-Assertion header from WSO2 Gateway"""
    jwt_assertion = request.headers.get("X-JWT-Assertion", "")
    if not jwt_assertion:
        return {}
    
    try:
        # Decode base64 JWT assertion
        decoded_bytes = base64.b64decode(jwt_assertion)
        decoded_str = decoded_bytes.decode('utf-8')
        
        # Parse JWT payload (middle part)
        parts = decoded_str.split('.')
        if len(parts) >= 2:
            payload = parts[1]
            # Add padding if needed
            payload += '=' * (4 - len(payload) % 4)
            payload_decoded = base64.urlsafe_b64decode(payload)
            return json.loads(payload_decoded)
    except Exception as e:
        return {"error": str(e)}
    
    return {}


@app.get("/health")
def health(request: Request) -> dict:
    """Liveness probe with user info."""
    response = {
        "status": "ok",
        "service": SERVICE_NAME
    }
    
    # Extract user info from custom headers (passed by backend/gateway)
    user_email = request.headers.get("X-User-Email", "")
    user_roles = request.headers.get("X-User-Roles", "")
    user_name = request.headers.get("X-User-Name", "")
    
    if user_email or user_name:
        response["user"] = {
            "username": user_name or "unknown",
            "email": user_email or "N/A",
            "roles": user_roles.split(",") if user_roles else []
        }
    
    return response


@app.get("/readiness")
def readiness() -> dict[str, str]:
    """Readiness probe for upstream load balancers."""
    return {"status": "ready", "service": SERVICE_NAME}
