#!/usr/bin/env python3
"""Automate wiring Keycloak as an external Key Manager in WSO2 API Manager."""

import os
import sys
import time
from typing import Dict, List, Optional

import requests
from urllib3.exceptions import InsecureRequestWarning

# WSO2 ships with a self-signed management certificate. We deliberately ignore
# verification when calling the Admin REST APIs to avoid local trust-store work.
requests.packages.urllib3.disable_warnings(category=InsecureRequestWarning)


def load_env_file(path: str) -> Dict[str, str]:
    """Best-effort parser for a .env file."""

    values: Dict[str, str] = {}
    if not os.path.exists(path):
        return values

    with open(path, "r", encoding="utf-8") as handle:
        for raw_line in handle:
            line = raw_line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            key, value = line.split("=", 1)
            values[key.strip()] = value.strip()
    return values


class WSO2KeyManagerConfigurator:
    """Thin wrapper around the WSO2 Admin REST API for Key Manager tasks."""

    def __init__(self, wso2_host: str, username: str, password: str) -> None:
        self.wso2_host = wso2_host.rstrip("/")
        self.admin_api = f"{self.wso2_host}/api/am/admin/v4"
        self.session = requests.Session()
        self.session.verify = False
        self.session.auth = (username, password)
        self.session.headers.update({"Content-Type": "application/json"})

    def get_key_managers(self) -> List[Dict[str, object]]:
        try:
            response = self.session.get(f"{self.admin_api}/key-managers")
            response.raise_for_status()
            return response.json().get("list", [])
        except Exception as exc:  # pragma: no cover - runtime aid
            print(f"❌ Error listing key managers: {exc}")
            return []

    def check_keycloak_exists(self) -> Optional[Dict[str, object]]:
        for km in self.get_key_managers():
            name = km.get("name", "").lower()
            if "keycloak" in name:
                return km
        return None

    def _payload(self, config: Dict[str, str]) -> Dict[str, object]:
        return {
            "name": "Keycloak",
            "type": "Keycloak",
            "displayName": "Keycloak",
            "description": "Keycloak OpenID Connect Key Manager for the innover realm",
            "enabled": True,
            "introspectionEndpoint": config["introspection_endpoint"],
            "tokenEndpoint": config["token_endpoint"],
            "revokeEndpoint": config["revoke_endpoint"],
            "userInfoEndpoint": config["userinfo_endpoint"],
            "authorizeEndpoint": config["authorize_endpoint"],
            "certificates": {
                "type": "JWKS",
                "value": config["jwks_endpoint"],
            },
            "issuer": config["issuer"],
            "availableGrantTypes": [
                "authorization_code",
                "password",
                "client_credentials",
                "refresh_token",
            ],
            "enableTokenGeneration": True,
            "enableTokenEncryption": False,
            "enableTokenHashing": False,
            "enableMapOAuthConsumerApps": False,
            "enableOAuthAppCreation": False,
            "enableSelfValidationJWT": True,
            "claimMapping": [
                {
                    "remoteClaim": "sub",
                    "localClaim": "http://wso2.org/claims/enduser",
                },
                {
                    "remoteClaim": "email",
                    "localClaim": "http://wso2.org/claims/emailaddress",
                },
                {
                    "remoteClaim": "given_name",
                    "localClaim": "http://wso2.org/claims/givenname",
                },
                {
                    "remoteClaim": "family_name",
                    "localClaim": "http://wso2.org/claims/lastname",
                },
                {
                    "remoteClaim": "preferred_username",
                    "localClaim": "http://wso2.org/claims/username",
                },
            ],
            "consumerKeyClaim": "azp",
            "scopesClaim": "scope",
            # Tokens issued by Keycloak are exchanged at the Gateway.
            "tokenType": "EXCHANGED",
            "additionalProperties": {
                "client_id": config["client_id"],
                "client_secret": config["client_secret"],
                "Username": config["client_id"],
                "Password": config["client_secret"],
            },
        }

    def configure(self, config: Dict[str, str]) -> Optional[Dict[str, object]]:
        payload = self._payload(config)
        try:
            response = self.session.post(f"{self.admin_api}/key-managers", json=payload)
            if response.status_code in (200, 201):
                print("✅ Keycloak Key Manager configured successfully!")
                return response.json()
            print(f"❌ Failed to configure Keycloak: {response.status_code}\n   {response.text}")
        except Exception as exc:  # pragma: no cover - runtime aid
            print(f"❌ Error configuring Keycloak: {exc}")
        return None

    def update(self, km_id: str, config: Dict[str, str]) -> Optional[Dict[str, object]]:
        payload = self._payload(config)
        try:
            response = self.session.put(f"{self.admin_api}/key-managers/{km_id}", json=payload)
            if response.status_code == 200:
                print("✅ Keycloak Key Manager updated successfully!")
                return response.json()
            print(f"❌ Failed to update Keycloak: {response.status_code}\n   {response.text}")
        except Exception as exc:  # pragma: no cover - runtime aid
            print(f"❌ Error updating Keycloak: {exc}")
        return None


def fetch_well_known_config(well_known_url: str) -> Optional[Dict[str, str]]:
    """Fetch OpenID Connect configuration from .well-known endpoint"""
    try:
        response = requests.get(well_known_url, timeout=10)
        if response.status_code == 200:
            return response.json()
        print(f"⚠️  Failed to fetch .well-known config: {response.status_code}")
    except Exception as exc:
        print(f"⚠️  Error fetching .well-known config: {exc}")
    return None


def get_keycloak_config() -> Dict[str, str]:
    repo_root = os.path.dirname(os.path.dirname(__file__))
    env_from_file = load_env_file(os.path.join(repo_root, ".env"))

    client_id = os.getenv("WSO2_AM_CLIENT_ID", env_from_file.get("WSO2_AM_CLIENT_ID", "wso2am"))
    client_secret = os.getenv(
        "WSO2_AM_CLIENT_SECRET",
        env_from_file.get("WSO2_AM_CLIENT_SECRET", "wso2am-secret"),
    )

    internal_realm = os.getenv(
        "KEYCLOAK_INTERNAL_REALM_URL",
        env_from_file.get("KEYCLOAK_INTERNAL_REALM_URL", "http://keycloak:8080/realms/innover"),
    ).rstrip("/")
    issuer = os.getenv(
        "KEYCLOAK_ISSUER",
        env_from_file.get("KEYCLOAK_ISSUER", internal_realm),
    ).rstrip("/")

    well_known_url = f"{internal_realm}/.well-known/openid-configuration"
    
    # Try to fetch from .well-known endpoint
    print(f"📡 Fetching configuration from: {well_known_url}")
    well_known = fetch_well_known_config(well_known_url)
    
    if well_known:
        print("✅ Using endpoints from .well-known configuration")
        return {
            "client_id": client_id,
            "client_secret": client_secret,
            "issuer": well_known.get("issuer", issuer),
            "introspection_endpoint": well_known.get("introspection_endpoint", f"{internal_realm}/protocol/openid-connect/token/introspect"),
            "token_endpoint": well_known.get("token_endpoint", f"{internal_realm}/protocol/openid-connect/token"),
            "revoke_endpoint": well_known.get("revocation_endpoint", f"{internal_realm}/protocol/openid-connect/revoke"),
            "userinfo_endpoint": well_known.get("userinfo_endpoint", f"{internal_realm}/protocol/openid-connect/userinfo"),
            "authorize_endpoint": well_known.get("authorization_endpoint", f"{internal_realm}/protocol/openid-connect/auth"),
            "jwks_endpoint": well_known.get("jwks_uri", f"{internal_realm}/protocol/openid-connect/certs"),
            "well_known": well_known_url,
        }
    else:
        # Fallback to manual construction
        print("⚠️  Using fallback endpoint construction")
        return {
            "client_id": client_id,
            "client_secret": client_secret,
            "issuer": issuer,
            "introspection_endpoint": f"{internal_realm}/protocol/openid-connect/token/introspect",
            "token_endpoint": f"{internal_realm}/protocol/openid-connect/token",
            "revoke_endpoint": f"{internal_realm}/protocol/openid-connect/revoke",
            "userinfo_endpoint": f"{internal_realm}/protocol/openid-connect/userinfo",
            "authorize_endpoint": f"{internal_realm}/protocol/openid-connect/auth",
            "jwks_endpoint": f"{internal_realm}/protocol/openid-connect/certs",
            "well_known": well_known_url,
        }


def wait_for_service(name: str, url: str, verify: bool = False, retries: int = 40, delay: int = 6) -> bool:
    for attempt in range(1, retries + 1):
        try:
            response = requests.get(url, verify=verify, timeout=10)
            if response.status_code < 500:
                print(f"✅ {name} is accessible (attempt {attempt}/{retries})")
                return True
            print(f"⚠️  {name} responded with {response.status_code} (attempt {attempt}/{retries}); retrying...")
        except Exception as exc:  # pragma: no cover - runtime aid
            print(f"⚠️  {name} not ready ({exc}) (attempt {attempt}/{retries}); retrying...")
        time.sleep(delay)
    print(f"❌ {name} did not become ready after {retries} attempts")
    return False


def main() -> None:
    print("=" * 70)
    print("WSO2 API Manager - Keycloak Integration")
    print("=" * 70)

    repo_root = os.path.dirname(os.path.dirname(__file__))
    env_from_file = load_env_file(os.path.join(repo_root, ".env"))

    wso2_host = os.getenv("WSO2_HOST", env_from_file.get("WSO2_HOST", "https://localhost:9443")).rstrip("/")
    admin_user = os.getenv("WSO2_ADMIN_USERNAME", env_from_file.get("WSO2_ADMIN_USERNAME", "admin"))
    admin_pass = os.getenv("WSO2_ADMIN_PASSWORD", env_from_file.get("WSO2_ADMIN_PASSWORD", "admin"))

    keycloak_internal = os.getenv(
        "KEYCLOAK_INTERNAL_REALM_URL",
        env_from_file.get("KEYCLOAK_INTERNAL_REALM_URL", "http://keycloak:8080/realms/innover"),
    ).rstrip("/")

    print("\n🔄 Checking Keycloak availability...")
    if not wait_for_service("Keycloak", f"{keycloak_internal}/.well-known/openid-configuration"):
        sys.exit(1)

    print("🔄 Checking WSO2 API Manager availability...")
    if not wait_for_service("WSO2 API Manager", f"{wso2_host}/services/Version"):
        sys.exit(1)

    keycloak_config = get_keycloak_config()
    print("\n📋 Keycloak Configuration:")
    print(f"   Issuer: {keycloak_config['issuer']}")
    print(f"   Client ID: {keycloak_config['client_id']}")
    print(f"   Client Secret: {'*' * len(keycloak_config['client_secret'])}")

    configurator = WSO2KeyManagerConfigurator(wso2_host=wso2_host, username=admin_user, password=admin_pass)

    print("\n🔄 Checking existing Key Managers...")
    existing_km = configurator.check_keycloak_exists()

    if existing_km:
        print(f"✅ Keycloak Key Manager already exists (ID: {existing_km['id']})")
        print("   Skipping configuration (already set up)")
        result = existing_km
    else:
        print("📝 Creating new Keycloak Key Manager...")
        result = configurator.configure(keycloak_config)
        if not result:
            print("\n❌ Failed to configure Keycloak integration")
            sys.exit(1)

    print("\n" + "=" * 70)
    print("✅ Keycloak Integration Complete!")
    print("=" * 70)

    key_managers = configurator.get_key_managers()
    if key_managers:
        print("\n📊 Current Key Managers:")
        for km in key_managers:
            status = "✅" if km.get("enabled") else "❌"
            print(f"{status} {km.get('name')} ({km.get('type')})")

    print("\n💡 Next Steps:")
    print("1. Visit the WSO2 Publisher: https://localhost:9443/publisher")
    print("2. Select an API and enable the 'Keycloak' key manager")
    print("3. Generate tokens using Keycloak credentials")


if __name__ == "__main__":
    main()
