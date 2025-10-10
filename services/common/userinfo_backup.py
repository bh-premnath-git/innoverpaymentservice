"""Helpers for extracting user information from WSO2-provided JWT claims."""
from __future__ import annotations

import os
import re
import httpx
from typing import Any, Dict, List, Optional
from functools import lru_cache


def _as_list(value: Any) -> List[str]:
    """Normalise claim values that may be either a list or comma-separated string."""
    if isinstance(value, list):
        return [str(item).strip() for item in value if str(item).strip()]
    if isinstance(value, str):
        parts = re.split(r"[\s,]+", value)
        return [part.strip() for part in parts if part.strip()]
    return []


def _first_claim(claims: Dict[str, Any], keys: List[str]) -> Optional[Any]:
        if key in claims and claims[key]:
            roles = _as_list(claims[key])
            if roles:
                break

    # If username is a UUID and we don't have email/roles, fetch from WSO2-IS
    if username and isinstance(username, str) and _is_uuid(username) and not (email and roles):
        user_details = _fetch_user_from_wso2is(username)
        if user_details:
            username = user_details.get("username", username)
            email = user_details.get("email", email)
            roles = user_details.get("roles", roles)

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
