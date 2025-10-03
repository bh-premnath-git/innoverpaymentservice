#!/usr/bin/env python3
"""
Configure Keycloak as an external Key Manager in WSO2 API Manager
"""

import requests
import json
import sys
from urllib3.exceptions import InsecureRequestWarning

# Suppress SSL warnings
requests.packages.urllib3.disable_warnings(category=InsecureRequestWarning)

class WSO2KeyManagerConfigurator:
    def __init__(self, wso2_host="https://localhost:9443", username="admin", password="admin"):
        self.wso2_host = wso2_host
        self.admin_api = f"{wso2_host}/api/am/admin/v4"
        self.session = requests.Session()
        self.session.verify = False
        self.session.auth = (username, password)
        self.session.headers.update({"Content-Type": "application/json"})

    def get_key_managers(self):
        """List existing key managers"""
        try:
            response = self.session.get(f"{self.admin_api}/key-managers")
            if response.status_code == 200:
                return response.json().get('list', [])
            return []
        except Exception as e:
            print(f"❌ Error listing key managers: {str(e)}")
            return []

    def check_keycloak_exists(self):
        """Check if Keycloak key manager already exists"""
        key_managers = self.get_key_managers()
        for km in key_managers:
            if 'keycloak' in km.get('name', '').lower():
                return km
        return None

    def configure_keycloak_key_manager(self, keycloak_config):
        """Configure Keycloak as an external Key Manager"""
        
        payload = {
            "name": "Keycloak",
            "type": "Keycloak",
            "displayName": "Keycloak",
            "description": "Keycloak OpenID Connect Key Manager for innover realm",
            "enabled": True,
            "introspectionEndpoint": keycloak_config["introspection_endpoint"],
            "tokenEndpoint": keycloak_config["token_endpoint"],
            "revokeEndpoint": keycloak_config["revoke_endpoint"],
            "userInfoEndpoint": keycloak_config["userinfo_endpoint"],
            "authorizeEndpoint": keycloak_config["authorize_endpoint"],
            "certificates": {
                "type": "JWKS",
                "value": keycloak_config["jwks_endpoint"]
            },
            "issuer": keycloak_config["server_url"],
            "availableGrantTypes": [
                "authorization_code",
                "password",
                "client_credentials",
                "refresh_token"
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
                    "localClaim": "http://wso2.org/claims/enduser"
                },
                {
                    "remoteClaim": "email",
                    "localClaim": "http://wso2.org/claims/emailaddress"
                },
                {
                    "remoteClaim": "given_name",
                    "localClaim": "http://wso2.org/claims/givenname"
                },
                {
                    "remoteClaim": "family_name",
                    "localClaim": "http://wso2.org/claims/lastname"
                },
                {
                    "remoteClaim": "preferred_username",
                    "localClaim": "http://wso2.org/claims/username"
                }
            ],
            "consumerKeyClaim": "azp",
            "scopesClaim": "scope",
            "tokenType": "JWT",
            "additionalProperties": {
                "client_id": keycloak_config["client_id"],
                "client_secret": keycloak_config["client_secret"],
                "Username": keycloak_config["client_id"],
                "Password": keycloak_config["client_secret"]
            }
        }

        try:
            response = self.session.post(f"{self.admin_api}/key-managers", json=payload)
            if response.status_code in [200, 201]:
                print(f"✅ Keycloak Key Manager configured successfully!")
                return response.json()
            else:
                print(f"❌ Failed to configure Keycloak: {response.status_code}")
                print(f"   Response: {response.text}")
                return None
        except Exception as e:
            print(f"❌ Error configuring Keycloak: {str(e)}")
            return None

    def update_keycloak_key_manager(self, km_id, keycloak_config):
        """Update existing Keycloak key manager"""
        payload = {
            "name": "Keycloak",
            "type": "Keycloak",
            "displayName": "Keycloak",
            "description": "Keycloak OpenID Connect Key Manager for innover realm",
            "enabled": True,
            "introspectionEndpoint": keycloak_config["introspection_endpoint"],
            "tokenEndpoint": keycloak_config["token_endpoint"],
            "revokeEndpoint": keycloak_config["revoke_endpoint"],
            "userInfoEndpoint": keycloak_config["userinfo_endpoint"],
            "authorizeEndpoint": keycloak_config["authorize_endpoint"],
            "certificates": {
                "type": "JWKS",
                "value": keycloak_config["jwks_endpoint"]
            },
            "issuer": keycloak_config["server_url"],
            "availableGrantTypes": [
                "authorization_code",
                "password",
                "client_credentials",
                "refresh_token"
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
                    "localClaim": "http://wso2.org/claims/enduser"
                },
                {
                    "remoteClaim": "email",
                    "localClaim": "http://wso2.org/claims/emailaddress"
                },
                {
                    "remoteClaim": "given_name",
                    "localClaim": "http://wso2.org/claims/givenname"
                },
                {
                    "remoteClaim": "family_name",
                    "localClaim": "http://wso2.org/claims/lastname"
                },
                {
                    "remoteClaim": "preferred_username",
                    "localClaim": "http://wso2.org/claims/username"
                }
            ],
            "consumerKeyClaim": "azp",
            "scopesClaim": "scope",
            "tokenType": "EXCHANGED",
            "additionalProperties": {
                "client_id": keycloak_config["client_id"],
                "client_secret": keycloak_config["client_secret"],
                "Username": keycloak_config["client_id"],
                "Password": keycloak_config["client_secret"]
            }
        }

        try:
            response = self.session.put(f"{self.admin_api}/key-managers/{km_id}", json=payload)
            if response.status_code == 200:
                print(f"✅ Keycloak Key Manager updated successfully!")
                return response.json()
            else:
                print(f"❌ Failed to update Keycloak: {response.status_code}")
                print(f"   Response: {response.text}")
                return None
        except Exception as e:
            print(f"❌ Error updating Keycloak: {str(e)}")
            return None


def get_keycloak_config():
    """Get Keycloak configuration from environment or defaults"""
    import os
    
    # Read from .env file if available
    env_file = os.path.join(os.path.dirname(os.path.dirname(__file__)), '.env')
    client_secret = "wso2am-secret"  # default
    
    if os.path.exists(env_file):
        with open(env_file, 'r') as f:
            for line in f:
                if line.startswith('WSO2_AM_CLIENT_SECRET='):
                    client_secret = line.split('=', 1)[1].strip()
                    break
    
    # Use internal Docker network hostname
    keycloak_base = "http://keycloak:8080/realms/innover"
    
    return {
        "server_url": keycloak_base,
        "client_id": "wso2am",
        "client_secret": client_secret,
        "introspection_endpoint": f"{keycloak_base}/protocol/openid-connect/token/introspect",
        "token_endpoint": f"{keycloak_base}/protocol/openid-connect/token",
        "revoke_endpoint": f"{keycloak_base}/protocol/openid-connect/revoke",
        "userinfo_endpoint": f"{keycloak_base}/protocol/openid-connect/userinfo",
        "authorize_endpoint": f"{keycloak_base}/protocol/openid-connect/auth",
        "jwks_endpoint": f"{keycloak_base}/protocol/openid-connect/certs",
        "well_known": f"{keycloak_base}/.well-known/openid-configuration"
    }


def main():
    print("=" * 70)
    print("WSO2 API Manager - Keycloak Integration")
    print("=" * 70)
    
    # Check Keycloak availability
    print("\n🔄 Checking Keycloak availability...")
    try:
        response = requests.get("http://localhost:8080/realms/innover/.well-known/openid-configuration", timeout=5)
        if response.status_code == 200:
            print("✅ Keycloak is accessible")
        else:
            print("❌ Keycloak is not responding properly")
            sys.exit(1)
    except Exception as e:
        print(f"❌ Cannot reach Keycloak: {str(e)}")
        sys.exit(1)
    
    # Check WSO2 availability
    print("🔄 Checking WSO2 API Manager availability...")
    try:
        response = requests.get("https://localhost:9443/services/Version", verify=False, timeout=5)
        if response.status_code == 200:
            print("✅ WSO2 API Manager is accessible")
        else:
            print("❌ WSO2 is not responding properly")
            sys.exit(1)
    except Exception as e:
        print(f"❌ Cannot reach WSO2: {str(e)}")
        sys.exit(1)
    
    # Get Keycloak configuration
    keycloak_config = get_keycloak_config()
    print(f"\n📋 Keycloak Configuration:")
    print(f"   Server: {keycloak_config['server_url']}")
    print(f"   Client ID: {keycloak_config['client_id']}")
    print(f"   Client Secret: {'*' * len(keycloak_config['client_secret'])}")
    
    # Configure WSO2
    configurator = WSO2KeyManagerConfigurator()
    
    print("\n🔄 Checking existing Key Managers...")
    existing_km = configurator.check_keycloak_exists()
    
    if existing_km:
        print(f"⚠️  Keycloak Key Manager already exists (ID: {existing_km['id']})")
        print("   Updating configuration...")
        result = configurator.update_keycloak_key_manager(existing_km['id'], keycloak_config)
    else:
        print("📝 Creating new Keycloak Key Manager...")
        result = configurator.configure_keycloak_key_manager(keycloak_config)
    
    if result:
        print("\n" + "=" * 70)
        print("✅ Keycloak Integration Complete!")
        print("=" * 70)
        print("\n📊 Current Key Managers:")
        key_managers = configurator.get_key_managers()
        for km in key_managers:
            status = "✅" if km.get('enabled') else "❌"
            print(f"{status} {km.get('name')} ({km.get('type')})")
        
        print("\n💡 Next Steps:")
        print("1. Go to WSO2 Publisher: https://localhost:9443/publisher")
        print("2. Edit an API and update its Key Manager to 'Keycloak'")
        print("3. Test token generation with Keycloak credentials")
    else:
        print("\n❌ Failed to configure Keycloak integration")
        sys.exit(1)


if __name__ == "__main__":
    main()
