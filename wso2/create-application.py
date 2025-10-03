#!/usr/bin/env python3
"""
Automate Application (Service Provider) creation in WSO2 API Manager.

In WSO2 API Manager, Service Providers are called "Applications" and are
created through the DevPortal API.
"""

import os
import sys
import requests
from typing import Dict, List, Optional
from urllib3.exceptions import InsecureRequestWarning

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


class WSO2ApplicationManager:
    """Manages Applications (Service Providers) in WSO2 API Manager via DevPortal API"""

    def __init__(self, wso2_host: str, username: str, password: str):
        self.wso2_host = wso2_host.rstrip("/")
        self.devportal_api = f"{self.wso2_host}/api/am/devportal/v3"
        self.session = requests.Session()
        self.session.verify = False
        self.session.auth = (username, password)
        self.session.headers.update({"Content-Type": "application/json"})

    def get_applications(self) -> List[Dict[str, object]]:
        """List all applications"""
        try:
            response = self.session.get(f"{self.devportal_api}/applications")
            response.raise_for_status()
            return response.json().get("list", [])
        except Exception as exc:
            print(f"❌ Error listing applications: {exc}")
            return []

    def check_application_exists(self, app_name: str) -> Optional[Dict[str, object]]:
        """Check if an application with the given name exists"""
        for app in self.get_applications():
            if app.get("name") == app_name:
                return app
        return None

    def create_application(
        self,
        name: str,
        description: str = "",
        throttling_policy: str = "Unlimited",
        token_type: str = "JWT",
        groups: Optional[List[str]] = None,
        attributes: Optional[Dict[str, str]] = None,
    ) -> Optional[Dict[str, object]]:
        """
        Create a new application (Service Provider)
        
        Args:
            name: Application name
            description: Application description
            throttling_policy: Throttling tier (Unlimited, 10PerMin, etc.)
            token_type: JWT or OAUTH
            groups: User groups allowed to access
            attributes: Additional attributes
        """
        payload = {
            "name": name,
            "throttlingPolicy": throttling_policy,
            "description": description,
            "tokenType": token_type,
            "groups": groups or [],
            "attributes": attributes or {},
        }

        try:
            response = self.session.post(
                f"{self.devportal_api}/applications",
                json=payload
            )
            if response.status_code == 201:
                app = response.json()
                print(f"✅ Created application: {name} (ID: {app['applicationId']})")
                return app
            print(f"❌ Failed to create application: {response.status_code}\n   {response.text}")
        except Exception as exc:
            print(f"❌ Error creating application: {exc}")
        return None

    def generate_keys(
        self,
        app_id: str,
        key_type: str = "PRODUCTION",
        grant_types: Optional[List[str]] = None,
        callback_url: str = "",
        validity_time: int = 3600,
        additional_properties: Optional[Dict[str, str]] = None,
    ) -> Optional[Dict[str, object]]:
        """
        Generate OAuth keys for an application
        
        Args:
            app_id: Application ID
            key_type: PRODUCTION or SANDBOX
            grant_types: List of OAuth grant types
            callback_url: OAuth callback URL
            validity_time: Token validity in seconds (default: 3600 = 1 hour)
            additional_properties: Additional OAuth configuration
        """
        if grant_types is None:
            grant_types = [
                "authorization_code",
                "implicit",
                "password",
                "client_credentials",
                "refresh_token",
                "urn:ietf:params:oauth:grant-type:saml2-bearer",
                "urn:ietf:params:oauth:grant-type:jwt-bearer",
            ]

        if additional_properties is None:
            additional_properties = {
                "id_token_expiry_time": "3600",  # 1 hour
                "application_access_token_expiry_time": "3600",  # 1 hour
                "user_access_token_expiry_time": "3600",  # 1 hour
                "refresh_token_expiry_time": "86400",  # 24 hours
                "id_token_encryption_enabled": "true",
                "id_token_encryption_algorithm": "RSA-OAEP",
                "id_token_encryption_method": "A128GCM",
                "backchannel_logout_url": "",
                "backchannel_logout_session_required": "true",
                "token_type": "JWT",
                "bypass_client_credentials": "false",
                "renew_refresh_token": "true",
                "pkce_mandatory": "false",
                "pkce_support_plain": "true",
            }

        payload = {
            "keyType": key_type,
            "grantTypesToBeSupported": grant_types,
            "callbackUrl": callback_url,
            "scopes": ["default"],
            "validityTime": validity_time,
            "additionalProperties": additional_properties,
        }

        try:
            response = self.session.post(
                f"{self.devportal_api}/applications/{app_id}/generate-keys",
                json=payload
            )
            if response.status_code == 200:
                keys = response.json()
                print(f"✅ Generated {key_type} keys for application")
                print(f"   Consumer Key: {keys.get('consumerKey', 'N/A')}")
                print(f"   Consumer Secret: {keys.get('consumerSecret', 'N/A')[:20]}...")
                return keys
            print(f"❌ Failed to generate keys: {response.status_code}\n   {response.text}")
        except Exception as exc:
            print(f"❌ Error generating keys: {exc}")
        return None

    def subscribe_to_api(
        self,
        app_id: str,
        api_id: str,
        throttling_policy: str = "Unlimited"
    ) -> Optional[Dict[str, object]]:
        """Subscribe an application to an API"""
        payload = {
            "applicationId": app_id,
            "apiId": api_id,
            "throttlingPolicy": throttling_policy,
        }

        try:
            response = self.session.post(
                f"{self.devportal_api}/subscriptions",
                json=payload
            )
            if response.status_code == 201:
                sub = response.json()
                print(f"✅ Subscribed application to API")
                return sub
            print(f"❌ Failed to subscribe: {response.status_code}\n   {response.text}")
        except Exception as exc:
            print(f"❌ Error subscribing: {exc}")
        return None

    def get_apis(self) -> List[Dict[str, object]]:
        """Get all available APIs"""
        try:
            response = self.session.get(f"{self.devportal_api}/apis")
            response.raise_for_status()
            return response.json().get("list", [])
        except Exception as exc:
            print(f"❌ Error listing APIs: {exc}")
            return []


def main():
    print("=" * 70)
    print("WSO2 API Manager - Application (Service Provider) Setup")
    print("=" * 70)

    repo_root = os.path.dirname(os.path.dirname(__file__))
    env_from_file = load_env_file(os.path.join(repo_root, ".env"))

    wso2_host = os.getenv("WSO2_HOST", env_from_file.get("WSO2_HOST", "https://localhost:9443"))
    admin_user = os.getenv("WSO2_ADMIN_USERNAME", env_from_file.get("WSO2_ADMIN_USERNAME", "admin"))
    admin_pass = os.getenv("WSO2_ADMIN_PASSWORD", env_from_file.get("WSO2_ADMIN_PASSWORD", "admin"))

    manager = WSO2ApplicationManager(wso2_host, admin_user, admin_pass)

    # Application configuration
    app_name = "DefaultApplication"
    app_description = "Default application for API access with Keycloak authentication"
    callback_url = "https://localhost:9443/devportal/applications"

    print(f"\n📋 Application Configuration:")
    print(f"   Name: {app_name}")
    print(f"   Description: {app_description}")
    print(f"   Callback URL: {callback_url}")

    # Check if application exists
    print(f"\n🔄 Checking if application '{app_name}' exists...")
    existing_app = manager.check_application_exists(app_name)

    if existing_app:
        print(f"✅ Application already exists (ID: {existing_app['applicationId']})")
        app_id = existing_app["applicationId"]
    else:
        print(f"📝 Creating application '{app_name}'...")
        app = manager.create_application(
            name=app_name,
            description=app_description,
            throttling_policy="Unlimited",
            token_type="JWT",
        )
        if not app:
            print("\n❌ Failed to create application")
            sys.exit(1)
        app_id = app["applicationId"]

    # Generate OAuth keys
    print(f"\n🔑 Generating OAuth keys...")
    keys = manager.generate_keys(
        app_id=app_id,
        key_type="PRODUCTION",
        grant_types=[
            "authorization_code",
            "password",
            "client_credentials",
            "refresh_token",
        ],
        callback_url=callback_url,
        validity_time=3600,
    )

    if not keys:
        print("\n⚠️  Failed to generate keys (may already exist)")

    # Subscribe to all APIs
    print(f"\n📡 Subscribing to APIs...")
    apis = manager.get_apis()
    print(f"   Found {len(apis)} API(s)")

    for api in apis:
        api_id = api["id"]
        api_name = api["name"]
        
        # Check if already subscribed
        try:
            subs_response = manager.session.get(
                f"{manager.devportal_api}/subscriptions?apiId={api_id}"
            )
            existing_subs = subs_response.json().get("list", [])
            already_subscribed = any(
                sub["applicationInfo"]["applicationId"] == app_id
                for sub in existing_subs
            )
            
            if already_subscribed:
                print(f"   Already subscribed: {api_name}")
            else:
                manager.subscribe_to_api(app_id, api_id)
        except Exception as exc:
            print(f"   ⚠️  Error checking subscription for {api_name}: {exc}")

    print("\n" + "=" * 70)
    print("✅ Application Setup Complete!")
    print("=" * 70)

    print("\n📊 Summary:")
    print(f"   Application: {app_name}")
    print(f"   Application ID: {app_id}")
    print(f"   Callback URL: {callback_url}")
    print(f"   APIs Subscribed: {len(apis)}")

    print("\n💡 Next Steps:")
    print("1. Use Keycloak tokens to access APIs")
    print("2. Test with: python3 sandbox/test_keycloak_token.py")
    print("3. Access DevPortal: https://localhost:9443/devportal")


if __name__ == "__main__":
    main()
