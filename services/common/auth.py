"""
Shared authentication module for all FastAPI services.
Handles JWT token validation from Keycloak with support for:
- Authorization Code Flow (browser-based)
- Client Credentials Flow (service-to-service)
- Password Grant Flow (direct authentication)
"""
import os
from typing import Optional, Dict, Any, List
from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from jose import jwt, JWTError
import httpx
from functools import lru_cache
import logging

logger = logging.getLogger(__name__)

# Security scheme for Bearer token
security = HTTPBearer()

# Environment variables with fallbacks
KEYCLOAK_URL = os.getenv("KEYCLOAK_URL", "http://keycloak:8080")
KEYCLOAK_REALM = os.getenv("KEYCLOAK_REALM", "innover")
OIDC_ISSUER = os.getenv("OIDC_ISSUER", f"{KEYCLOAK_URL}/realms/{KEYCLOAK_REALM}")


@lru_cache(maxsize=1)
def get_keycloak_public_key() -> str:
    """
    Fetch and cache Keycloak's public key for JWT verification.
    Uses JWKS endpoint to get the public key.
    
    Returns:
        PEM-formatted public key string
        
    Raises:
        HTTPException: If unable to fetch public key
    """
    jwks_url = f"{OIDC_ISSUER}/protocol/openid-connect/certs"
    
    try:
        logger.info(f"Fetching JWKS from: {jwks_url}")
        response = httpx.get(jwks_url, timeout=10.0)
        response.raise_for_status()
        jwks = response.json()
        
        if not jwks.get("keys"):
            raise ValueError("No keys found in JWKS response")
        
        # Get the first key (in production, match by kid from token header)
        key_data = jwks["keys"][0]
        
        # Convert JWK to PEM format
        from jose.jwk import construct
        public_key = construct(key_data).to_pem().decode('utf-8')
        
        logger.info("Successfully fetched and cached Keycloak public key")
        return public_key
        
    except Exception as e:
        logger.error(f"Failed to fetch Keycloak public key: {str(e)}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Unable to fetch authentication configuration: {str(e)}"
        )


def decode_token(token: str) -> Dict[str, Any]:
    """
    Decode and validate JWT token from Keycloak.
    
    Args:
        token: JWT token string
        
    Returns:
        Decoded token payload containing user/client information
        
    Raises:
        HTTPException: If token is invalid, expired, or malformed
    """
    try:
        public_key = get_keycloak_public_key()
        
        # Decode and validate token
        payload = jwt.decode(
            token,
            public_key,
            algorithms=["RS256"],
            issuer=OIDC_ISSUER,
            options={
                "verify_signature": True,
                "verify_aud": False,  # Keycloak uses multiple audiences
                "verify_exp": True,
                "verify_iat": True,
                "verify_iss": True,
            }
        )
        
        logger.debug(f"Token decoded successfully for subject: {payload.get('sub')}")
        return payload
        
    except jwt.ExpiredSignatureError:
        logger.warning("Token has expired")
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Token has expired",
            headers={"WWW-Authenticate": "Bearer"},
        )
    except jwt.JWTClaimsError as e:
        logger.warning(f"Invalid token claims: {str(e)}")
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail=f"Invalid token claims: {str(e)}",
            headers={"WWW-Authenticate": "Bearer"},
        )
    except JWTError as e:
        logger.error(f"JWT validation error: {str(e)}")
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid authentication credentials",
            headers={"WWW-Authenticate": "Bearer"},
        )


async def get_current_user(
    credentials: HTTPAuthorizationCredentials = Depends(security)
) -> Dict[str, Any]:
    """
    FastAPI dependency to extract and validate current user from JWT token.
    Works with all OAuth2 flows:
    - Authorization Code (user tokens)
    - Client Credentials (service tokens)
    - Password Grant (direct user authentication)
    
    Returns:
        Dictionary containing user/client information:
        - sub: Subject (user ID or client ID)
        - username: Username (for user tokens)
        - email: Email address (for user tokens)
        - realm_roles: List of realm-level roles
        - client_roles: Dict of client-specific roles
        - client_id: Client that issued the token
        - scope: Granted scopes
        
    Raises:
        HTTPException: If token is invalid or missing
    """
    token = credentials.credentials
    payload = decode_token(token)
    
    # Extract realm roles
    realm_roles = payload.get("realm_access", {}).get("roles", [])
    
    # Extract client roles
    resource_access = payload.get("resource_access", {})
    client_roles = {
        client: data.get("roles", [])
        for client, data in resource_access.items()
    }
    
    # Build user info
    user_info = {
        "sub": payload.get("sub"),
        "username": payload.get("preferred_username"),
        "email": payload.get("email"),
        "email_verified": payload.get("email_verified", False),
        "name": payload.get("name"),
        "given_name": payload.get("given_name"),
        "family_name": payload.get("family_name"),
        "realm_roles": realm_roles,
        "client_roles": client_roles,
        "scope": payload.get("scope", ""),
        "client_id": payload.get("azp"),  # authorized party
        "token_type": payload.get("typ", "Bearer"),
        "session_state": payload.get("session_state"),
        "raw_payload": payload,  # For debugging
    }
    
    logger.debug(f"Authenticated user: {user_info.get('username') or user_info.get('client_id')}")
    return user_info


def require_roles(required_roles: List[str]):
    """
    Dependency factory to require specific realm roles.
    
    Args:
        required_roles: List of role names that user must have (OR logic)
        
    Returns:
        FastAPI dependency function
        
    Example:
        @app.get("/admin")
        async def admin_endpoint(user = Depends(require_roles(["admin"]))):
            return {"message": "Admin access"}
    """
    async def check_roles(user: Dict[str, Any] = Depends(get_current_user)) -> Dict[str, Any]:
        user_roles = user.get("realm_roles", [])
        
        if not any(role in user_roles for role in required_roles):
            logger.warning(
                f"Access denied for {user.get('username')}: "
                f"requires {required_roles}, has {user_roles}"
            )
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail=f"Required role(s): {', '.join(required_roles)}"
            )
        
        return user
    
    return check_roles


def require_all_roles(required_roles: List[str]):
    """
    Dependency factory to require ALL specified realm roles (AND logic).
    
    Args:
        required_roles: List of role names that user must have all of
        
    Returns:
        FastAPI dependency function
    """
    async def check_all_roles(user: Dict[str, Any] = Depends(get_current_user)) -> Dict[str, Any]:
        user_roles = user.get("realm_roles", [])
        
        if not all(role in user_roles for role in required_roles):
            missing_roles = [r for r in required_roles if r not in user_roles]
            logger.warning(
                f"Access denied for {user.get('username')}: "
                f"missing roles {missing_roles}"
            )
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail=f"Missing required role(s): {', '.join(missing_roles)}"
            )
        
        return user
    
    return check_all_roles


def require_client_role(client_id: str, role: str):
    """
    Dependency factory to require a specific client role.
    
    Args:
        client_id: Client ID to check role for
        role: Role name required for that client
        
    Returns:
        FastAPI dependency function
    """
    async def check_client_role(user: Dict[str, Any] = Depends(get_current_user)) -> Dict[str, Any]:
        client_roles = user.get("client_roles", {}).get(client_id, [])
        
        if role not in client_roles:
            logger.warning(
                f"Access denied for {user.get('username')}: "
                f"requires {client_id}.{role}"
            )
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail=f"Required client role: {client_id}.{role}"
            )
        
        return user
    
    return check_client_role


# Convenience dependencies for common roles
require_admin = require_roles(["admin"])
require_user = require_roles(["user"])
require_ops = require_roles(["ops_user"])
require_finance = require_roles(["finance"])
require_auditor = require_roles(["auditor"])


# Optional: Make authentication optional
async def get_current_user_optional(
    credentials: Optional[HTTPAuthorizationCredentials] = Depends(HTTPBearer(auto_error=False))
) -> Optional[Dict[str, Any]]:
    """
    Optional authentication - returns None if no token provided.
    Useful for endpoints that work differently for authenticated vs anonymous users.
    """
    if credentials is None:
        return None
    
    try:
        token = credentials.credentials
        payload = decode_token(token)
        return await get_current_user(HTTPAuthorizationCredentials(
            scheme="Bearer",
            credentials=token
        ))
    except HTTPException:
        return None
