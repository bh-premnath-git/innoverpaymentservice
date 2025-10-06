#!/usr/bin/env python3
"""
Script to enable WSO2 IS as Key Manager after initial setup
Run this after both WSO2 IS and WSO2 AM are stable
"""
import os
import sys
import requests
import base64
import json
from typing import Dict, Any

# Disable SSL warnings for dev environment
requests.packages.urllib3.disable_warnings()


def build_key_manager_payload(wso2_is_host: str, username: str, password: str) -> Dict[str, Any]:
    """Construct payload used for the Admin REST API."""

    wso2_is_host = wso2_is_host.rstrip("/")

    configuration: Dict[str, Any] = {
        "ServerURL": f"{wso2_is_host}/services/",
        "Username": username,
        "Password": password,
        "TokenURL": f"{wso2_is_host}/oauth2/token",
        "RevokeURL": f"{wso2_is_host}/oauth2/revoke",
        "IntrospectURL": f"{wso2_is_host}/oauth2/introspect",
        "UserInfoURL": f"{wso2_is_host}/oauth2/userinfo",
        "AuthorizeURL": f"{wso2_is_host}/oauth2/authorize",
        "JWKSEndpoint": f"{wso2_is_host}/oauth2/jwks",
        "WellKnownEndpoint": f"{wso2_is_host}/oauth2/.well-known/openid-configuration",
        "Issuer": f"{wso2_is_host}/oauth2/token",
        "TokenValidation": "INTROSPECT",
        "ClaimConfiguration": "use_user_store_as_claim_dialect",
        "ConsumerKeyClaim": "azp",
        "ScopesClaim": "scope",
        "Audience": "wso2am",
        "KeyManagerClientConfiguration": {
            "GrantTypes": [
                "password",
                "client_credentials",
                "refresh_token",
                "urn:ietf:params:oauth:grant-type:jwt-bearer",
            ]
        },
    }

    return {
        "name": "WSO2IS",
        "displayName": "WSO2 Identity Server",
        "type": "WSO2-IS",
        "description": "WSO2 Identity Server as external Key Manager",
        "enabled": True,
        "isDefault": True,
        "tokenType": "JWT",
        "alias": "WSO2IS",
        "configuration": configuration,
        "additionalProperties": {},
        "claimMapping": [
            {
                "remoteClaim": "sub",
                "localClaim": "http://wso2.org/claims/username",
            },
            {
                "remoteClaim": "email",
                "localClaim": "http://wso2.org/claims/emailaddress",
            },
        ],
        "scopeMappings": [],
        "certificate": {
            "type": "JWKS",
            "value": "",
            "alias": "",
        },
    }


def enable_key_manager(wso2_host: str, username: str, password: str, wso2_is_host: str | None = None) -> bool:
    """Enable WSO2 IS Key Manager via REST API"""
    print("=" * 60)
    print("WSO2 IS Key Manager Enablement")
    print("=" * 60)
    
    session = requests.Session()
    session.verify = False
    
    admin_api = f"{wso2_host}/api/am/admin/v4"
    token_endpoint = f"{wso2_host}/oauth2/token"
    dcr_endpoint = f"{wso2_host}/client-registration/v0.17/register"
    wso2_is_host = (wso2_is_host or os.getenv("WSO2_IS_HOST", "https://wso2is:9443")).rstrip("/")
    
    # Step 1: Get access token
    print("\n🔑 Obtaining access token...")
    
    auth_header = base64.b64encode(f"{username}:{password}".encode()).decode()
    
    dcr_payload = {
        "clientName": "km_enabler_client",
        "owner": username,
        "grantType": "password refresh_token",
        "saasApp": True
    }
    
    dcr_response = session.post(
        dcr_endpoint,
        json=dcr_payload,
        headers={
            "Authorization": f"Basic {auth_header}",
            "Content-Type": "application/json"
        }
    )
    
    if dcr_response.status_code in [200, 201]:
        dcr_data = dcr_response.json()
        client_id = dcr_data["clientId"]
        client_secret = dcr_data["clientSecret"]
        
        token_data = {
            "grant_type": "password",
            "username": username,
            "password": password,
            "scope": "apim:admin"
        }
        
        token_response = session.post(
            token_endpoint,
            data=token_data,
            auth=(client_id, client_secret)
        )
    else:
        print("⚠️  DCR failed, trying direct token endpoint...")
        token_data = {
            "grant_type": "password",
            "username": username,
            "password": password,
            "scope": "apim:admin"
        }
        
        token_response = session.post(
            token_endpoint,
            data=token_data,
            auth=(username, password)
        )
    
    if token_response.status_code != 200:
        print(f"❌ Failed to get token: {token_response.status_code}")
        print(f"   Response: {token_response.text}")
        return False
    
    token_data = token_response.json()
    access_token = token_data["access_token"]
    session.headers.update({"Authorization": f"Bearer {access_token}"})
    print("✓ Access token obtained")
    
    # Step 2: Get existing Key Managers
    print("\n📋 Fetching Key Managers...")
    
    km_response = session.get(f"{admin_api}/key-managers")
    if km_response.status_code != 200:
        print(f"❌ Failed to fetch Key Managers: {km_response.status_code}")
        return False
    
    km_data = km_response.json()
    key_managers = km_data.get("list", [])
    
    print(f"   Found {len(key_managers)} Key Manager(s):")
    for km in key_managers:
        print(f"   - {km['name']}: enabled={km.get('enabled', False)}")
    
    # Step 3: Check if WSO2IS Key Manager exists
    wso2is_km = None
    for km in key_managers:
        if km["name"] in ["WSO2IS", "WSO2 Identity Server"]:
            wso2is_km = km
            break
    
    payload = build_key_manager_payload(wso2_is_host, username, password)

    if not wso2is_km:
        print("\nℹ️  WSO2 IS Key Manager not found. Creating new configuration via Admin REST API...")

        create_response = session.post(
            f"{admin_api}/key-managers",
            json=payload,
            headers={"Content-Type": "application/json"}
        )

        if create_response.status_code not in (200, 201):
            print(f"❌ Failed to create Key Manager: {create_response.status_code}")
            print(f"   Response: {create_response.text[:300]}")
            return False

        print("✓ WSO2 IS Key Manager created and enabled")
        return True

    km_id = wso2is_km["id"]

    if wso2is_km.get("enabled", False):
        print(f"\n✓ WSO2 IS Key Manager is already enabled")
        return True

    print(f"\n🔧 Updating WSO2 IS Key Manager configuration (ID: {km_id})...")

    updated_payload: Dict[str, Any] = {**wso2is_km, **payload}
    updated_payload["id"] = km_id

    update_response = session.put(
        f"{admin_api}/key-managers/{km_id}",
        json=updated_payload,
        headers={"Content-Type": "application/json"}
    )

    if update_response.status_code not in (200, 202):
        print(f"❌ Failed to enable Key Manager: {update_response.status_code}")
        print(f"   Response: {update_response.text[:300]}")
        return False

    print("✓ WSO2 IS Key Manager enabled successfully")
    return True


def main():
    # Environment variables
    wso2_host = os.getenv("WSO2_HOST", "https://localhost:9443")
    wso2_username = os.getenv("WSO2_ADMIN_USERNAME", "admin")
    wso2_password = os.getenv("WSO2_ADMIN_PASSWORD", "admin")
    wso2_is_host = os.getenv("WSO2_IS_HOST", "https://localhost:9444")

    success = enable_key_manager(wso2_host, wso2_username, wso2_password, wso2_is_host)
    
    if success:
        print("\n" + "=" * 60)
        print("✅ WSO2 IS Key Manager Enabled")
        print("=" * 60)
        print("\nNext steps:")
        print("1. Restart WSO2 API Manager for changes to take effect")
        print("2. Re-run the setup script if additional APIs need provisioning")
        sys.exit(0)
    else:
        print("\n" + "=" * 60)
        print("❌ Failed to enable WSO2 IS Key Manager")
        print("=" * 60)
        sys.exit(1)


if __name__ == "__main__":
    main()
