import os
import base64
import json
from fastapi import FastAPI, HTTPException, Request

from services.common.auth import decode_token
from services.common.userinfo import extract_user_info

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

    jwt_payload = decode_jwt_header(request)
    user_info = extract_user_info(jwt_payload)

    if not user_info:
        auth_header = request.headers.get("Authorization", "")
        if auth_header.lower().startswith("bearer "):
            token = auth_header.split(" ", 1)[1]
            try:
                claims = decode_token(token)
            except HTTPException:
                claims = {}
            except Exception:
                claims = {}
            else:
                user_info = extract_user_info(claims)

    if user_info:
        response["user"] = user_info

    return response


@app.get("/readiness")
def readiness() -> dict[str, str]:
    """Readiness probe for upstream load balancers."""
    return {"status": "ready", "service": SERVICE_NAME}
