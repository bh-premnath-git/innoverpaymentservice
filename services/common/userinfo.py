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
    for key in keys:
        if key in claims and claims[key]:
            return claims[key]
    return None


def _is_uuid(value: str) -> bool:
    """Check if string is a UUID format."""
    uuid_pattern = re.compile(
        r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
        re.IGNORECASE
    )
    return bool(uuid_pattern.match(value))


@lru_cache(maxsize=1000)
def _fetch_user_from_wso2is(user_id: str) -> Optional[Dict[str, Any]]:
    """Fetch user details from WSO2-IS SCIM API using user ID (UUID)."""
    wso2is_host = os.getenv("WSO2_IS_HOST", "wso2is")
    wso2is_port = os.getenv("WSO2_IS_PORT", "9443")
    wso2is_admin_user = os.getenv("WSO2_IS_ADMIN_USER", "admin")
    wso2is_admin_pass = os.getenv("WSO2_IS_ADMIN_PASS", "admin")
    
    try:
        # Call SCIM API to get user details
        url = f"https://{wso2is_host}:{wso2is_port}/scim2/Users/{user_id}"
        
        with httpx.Client(verify=False, timeout=5.0) as client:
            response = client.get(
                url,
                auth=(wso2is_admin_user, wso2is_admin_pass)
            )
            
            if response.status_code == 200:
                user_data = response.json()
                
                # Extract username
                username = user_data.get("userName", "unknown")
                
                # Extract email
                emails = user_data.get("emails", [])
                email = emails[0] if isinstance(emails, list) and emails else "N/A"
                
                # Extract roles (filter out 'everyone' role)
                roles_data = user_data.get("roles", [])
                roles = [role.get("display") for role in roles_data if role.get("display") and role.get("display") != "everyone"]
                
                # Extract name
                name_data = user_data.get("name", {})
                given_name = name_data.get("givenName", "")
                family_name = name_data.get("familyName", "")
                
                return {
                    "username": username,
                    "email": email,
                    "roles": roles,
                    "given_name": given_name,
                    "family_name": family_name
                }
    except Exception:
        # Silently fail and return None if unable to fetch
        pass
    
    return None


def extract_user_info(claims: Dict[str, Any]) -> Optional[Dict[str, Any]]:
    """Return a normalised view of user details from a JWT payload.
    
    If the JWT only contains a UUID in the sub field without username/email/roles,
    this function will fetch the user details from WSO2-IS SCIM API.
    """
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

    # If username is a UUID and we don't have email/roles, fetch from WSO2-IS
    if username and isinstance(username, str) and _is_uuid(username) and not (email and roles):
        user_details = _fetch_user_from_wso2is(username)
        if user_details:
            username = user_details.get("username", username)
            email = user_details.get("email", email)
            roles = user_details.get("roles", roles) or []

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
