"""Helpers for extracting user information from WSO2-provided JWT claims."""
from __future__ import annotations

import re
from typing import Any, Dict, List, Optional


def _as_list(value: Any) -> List[str]:
    """Normalise claim values that may be either a list or comma-separated string."""
    if isinstance(value, list):
        return [str(item).strip() for item in value if str(item).strip()]
    if isinstance(value, str):
        parts = re.split(r"[\s,]+", value)
        return [part.strip() for part in parts if part.strip()]
    return []


def _first_claim(claims: Dict[str, Any], keys: List[str]) -> Optional[Any]:
    for key in keys:
        if key in claims and claims[key]:
            return claims[key]
    return None


def extract_user_info(claims: Dict[str, Any]) -> Optional[Dict[str, Any]]:
    """Return a normalised view of user details from a JWT payload."""
    if not claims:
        return None

    email = _first_claim(
        claims,
        [
            "email",
            "emails",
            "preferred_email",
            "http://wso2.org/claims/emailaddress",
        ],
    )

    if isinstance(email, list):
        email = email[0] if email else None

    username = _first_claim(
        claims,
        [
            "preferred_username",
            "username",
            "http://wso2.org/claims/username",
            "name",
            "sub",
        ],
    )

    roles = None
    for key in [
        "groups",
        "roles",
        "scope",
        "scp",
        "http://wso2.org/claims/role",
    ]:
        if key in claims and claims[key]:
            roles = _as_list(claims[key])
            if roles:
                break

    if not email and isinstance(username, dict):
        email = username.get("email")

    if not username and email:
        username = email.split("@")[0]

    if not (email or username or roles):
        return None

    return {
        "username": str(username) if username else "unknown",
        "email": str(email) if email else "N/A",
        "roles": roles or [],
    }
