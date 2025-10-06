"""
Common utilities shared across all microservices.
WSO2 Identity Server integration - Financial-grade OAuth2 | PCI-DSS Compliant
"""
from .auth import (
    decode_token,
    get_current_user,
    get_current_user_optional,
    require_roles,
    require_all_roles,
    require_client_role,
    require_admin,
    require_user,
    require_ops,
    require_finance,
    require_auditor,
)
from .userinfo import extract_user_info

__all__ = [
    # Token decoding
    "decode_token",
    "extract_user_info",
    # User authentication dependencies
    "get_current_user",
    "get_current_user_optional",
    # Role-based access control
    "require_roles",
    "require_all_roles",
    "require_client_role",
    # Convenience role dependencies
    "require_admin",
    "require_user",
    "require_ops",
    "require_finance",
    "require_auditor",
]
