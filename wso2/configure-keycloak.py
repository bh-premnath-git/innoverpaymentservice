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

    def discover_connector_type(self, preferred: str = "Keycloak") -> Dict[str, object]:
        """Return discovery details for available Key Manager connector types."""

        endpoints = [
            f"{self.admin_api}/settings",
        ]

        for endpoint in endpoints:
            try:
                response = self.session.get(endpoint)
                if response.status_code != 200:
                    continue
                settings = response.json()
                connectors = settings.get("keyManagerConfiguration", [])
                if not connectors:
                    continue

                def _match(candidate: Dict[str, object]) -> bool:
                    type_value = str(candidate.get("type", ""))
                    display = str(candidate.get("displayName", ""))
                    if preferred and type_value.lower() == preferred.lower():
                        return True
                    if preferred and display.lower() == preferred.lower():
                        return True
                    if preferred and preferred.lower() in display.lower():
                        return True
                    return False

                for connector in connectors:
                    if _match(connector):
                        return {
                            "type": str(connector.get("type")),
                            "matched": True,
                            "available": connectors,
                        }

                if connectors:
                    return {
                        "type": str(connectors[0].get("type")),
                        "matched": False,
                        "available": connectors,
                    }
            except Exception as exc:  # pragma: no cover - runtime aid
                print(f"⚠️  Unable to discover connector types from {endpoint}: {exc}")

        return {"type": None, "matched": False, "available": []}

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

    def delete_key_manager(self, km_id: str) -> bool:
        try:
            response = self.session.delete(f"{self.admin_api}/key-managers/{km_id}")
            if response.status_code in (200, 204):
                print(f"✅ Deleted Key Manager (ID: {km_id})")
                return True
            print(f"⚠️  Failed to delete Key Manager: {response.status_code}")
        except Exception as exc:
            print(f"⚠️  Error deleting Key Manager: {exc}")
        return False

    def _payload(self, config: Dict[str, str], connector_type: str) -> Dict[str, object]:
        return {
            "name": "Keycloak",
            "type": connector_type,
            "displayName": "Keycloak",
            "description": "Keycloak OpenID Connect Key Manager for the innover realm",
            "enabled": True,
            "wellKnownEndpoint": config.get("well_known"),
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
            # Accept raw JWTs issued by Keycloak without an additional exchange flow.
            "tokenType": "JWT",
            "additionalProperties": {
                "client_id": config["client_id"],
                "client_secret": config["client_secret"],
                "Username": config["client_id"],
                "Password": config["client_secret"],
            },
        }

    def configure(self, config: Dict[str, str]) -> Optional[Dict[str, object]]:
        connector_type = config.get("connector_type", "Keycloak")
        payload = self._payload(config, connector_type)
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
        connector_type = config.get("connector_type", "Keycloak")
        payload = self._payload(config, connector_type)
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
    public_realm = os.getenv(
        "KEYCLOAK_PUBLIC_REALM_URL",
        env_from_file.get("KEYCLOAK_PUBLIC_REALM_URL", internal_realm),
    ).rstrip("/")
    issuer = os.getenv(
        "KEYCLOAK_ISSUER",
        env_from_file.get("KEYCLOAK_ISSUER", public_realm),
    ).rstrip("/")
    connector_type_hint = os.getenv(
        "KEYCLOAK_CONNECTOR_TYPE",
        env_from_file.get("KEYCLOAK_CONNECTOR_TYPE", "Keycloak"),
    )

    well_known_url = f"{internal_realm}/.well-known/openid-configuration"

    # Try to fetch from .well-known endpoint
    print(f"📡 Fetching configuration from: {well_known_url}")
    well_known = fetch_well_known_config(well_known_url)
    
    if well_known:
        print("✅ Using endpoints from .well-known configuration")
    else:
        print("⚠️  Using fallback endpoint construction")

    def internal_endpoint(suffix: str) -> str:
        return f"{internal_realm}/protocol/openid-connect/{suffix}"

    def public_endpoint(suffix: str) -> str:
        return f"{public_realm}/protocol/openid-connect/{suffix}"

    return {
        "client_id": client_id,
        "client_secret": client_secret,
        "issuer": issuer,
        # Internal endpoints are reachable from containers without host networking
        "introspection_endpoint": internal_endpoint("token/introspect"),
        "token_endpoint": internal_endpoint("token"),
        "revoke_endpoint": internal_endpoint("revoke"),
        "userinfo_endpoint": internal_endpoint("userinfo"),
        "jwks_endpoint": internal_endpoint("certs"),
        # Browser redirects must resolve from the host machine, so we prefer the public realm URL
        "authorize_endpoint": public_endpoint("auth"),
        "well_known": well_known_url,
        "connector_type_hint": connector_type_hint,
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
    print(f"   Auth Endpoint (public): {keycloak_config['authorize_endpoint']}")
    print(f"   Token Endpoint (internal): {keycloak_config['token_endpoint']}")
    print(f"   Client ID: {keycloak_config['client_id']}")
    print(f"   Client Secret: {'*' * len(keycloak_config['client_secret'])}")

    configurator = WSO2KeyManagerConfigurator(wso2_host=wso2_host, username=admin_user, password=admin_pass)

    discovery = configurator.discover_connector_type(
        keycloak_config.get("connector_type_hint", "Keycloak")
    )
    connector_type = discovery.get("type")
    if not connector_type:
        print("\n❌ Unable to determine a valid Key Manager connector type from WSO2 settings")
        print("   Please ensure the Keycloak connector is installed and try again.")
        sys.exit(1)

    keycloak_config["connector_type"] = connector_type
    print(f"   Connector Type: {connector_type}")
    if not discovery.get("matched", False):
        print("   ⚠️  Preferred connector type not found; using first available option")
        available = ", ".join(
            str(conn.get("displayName") or conn.get("type"))
            for conn in discovery.get("available", [])
        )
        if available:
            print(f"   Available connector types reported by WSO2: {available}")

    print("\n🔄 Checking existing Key Managers...")
    existing_km = configurator.check_keycloak_exists()

    if existing_km:
        print(f"✅ Keycloak Key Manager already exists (ID: {existing_km['id']})")
        print("   Deleting existing Key Manager to recreate with correct issuer...")
        if configurator.delete_key_manager(existing_km['id']):
            import time
            time.sleep(2)
            print("📝 Creating new Keycloak Key Manager...")
            result = configurator.configure(keycloak_config)
            if not result:
                print("\n❌ Failed to configure Keycloak integration")
                sys.exit(1)
        else:
            print("\n⚠️  Failed to delete existing Key Manager, skipping reconfiguration")
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
