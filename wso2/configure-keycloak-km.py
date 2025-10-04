#!/usr/bin/env python3
"""
Configure Keycloak as External Key Manager in WSO2 APIM
This allows WSO2 Gateway to validate tokens issued by Keycloak
"""
import os
import sys
import time
import json
import requests

requests.packages.urllib3.disable_warnings()


class KeyManagerConfigurator:
    """Configure External Key Manager in WSO2 APIM"""
    
    def __init__(self, wso2_host: str, username: str, password: str, verify_ssl: bool = False):
        self.wso2_host = wso2_host.rstrip('/')
        self.username = username
        self.password = password
        self.verify_ssl = verify_ssl
        self.session = requests.Session()
        self.session.verify = verify_ssl
        
        # Admin API endpoint
        self.admin_api = f"{self.wso2_host}/api/am/admin/v4"
        self.token_endpoint = f"{self.wso2_host}/oauth2/token"
        self.dcrEndpoint = f"{self.wso2_host}/client-registration/v0.17/register"
        
        self.access_token = None
    
    def get_access_token(self):
        """Get OAuth2 access token"""
        print("🔑 Obtaining admin access token...")
        
        import base64
        auth_header = base64.b64encode(f"{self.username}:{self.password}".encode()).decode()
        
        # Register DCR client
        dcr_payload = {
            "clientName": "keycloak_km_configurator",
            "owner": self.username,
            "grantType": "password refresh_token",
            "saasApp": True
        }
        
        dcr_response = self.session.post(
            self.dcrEndpoint,
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
            print(f"✓ DCR successful: {client_id}")
        else:
            # Fallback to basic auth
            client_id = self.username
            client_secret = self.password
        
        # Get token
        token_data = {
            "grant_type": "password",
            "username": self.username,
            "password": self.password,
            "scope": "apim:admin apim:api_key"
        }
        
        token_response = self.session.post(
            self.token_endpoint,
            data=token_data,
            auth=(client_id, client_secret)
        )
        
        if token_response.status_code == 200:
            token_data = token_response.json()
            self.access_token = token_data["access_token"]
            self.session.headers.update({"Authorization": f"Bearer {self.access_token}"})
            print("✓ Access token obtained")
            return self.access_token
        else:
            print(f"❌ Failed to get token: {token_response.status_code}")
            print(token_response.text)
            sys.exit(1)
    
    def get_key_manager_by_name(self, name: str):
        """Check if Key Manager exists"""
        response = self.session.get(f"{self.admin_api}/key-managers")
        
        if response.status_code == 200:
            data = response.json()
            for km in data.get("list", []):
                if km["name"] == name:
                    return km
        return None
    
    def configure_keycloak_key_manager(self, keycloak_issuer: str):
        """Configure Keycloak as external Key Manager (JWT validation)"""
        print(f"\n🔧 Configuring Keycloak Key Manager...")
        
        # 1) Discover OIDC endpoints
        well_known = f"{keycloak_issuer.rstrip('/')}/.well-known/openid-configuration"
        print(f"   Discovering OIDC from: {well_known}")
        r = self.session.get(well_known)
        if r.status_code != 200:
            print(f"   ❌ OIDC discovery failed: {r.status_code}\n{r.text}")
            return None
        oidc = r.json()
        print(f"   ✓ OIDC discovery successful")
        
        # 2) Required endpoints/fields
        token_ep = oidc["token_endpoint"]
        introspect_ep = oidc.get("introspection_endpoint", f"{token_ep}/introspect")
        revoke_ep = oidc.get("revocation_endpoint", f"{token_ep}/revoke")
        authorize_ep = oidc["authorization_endpoint"]
        jwks_ep = oidc["jwks_uri"]
        userinfo_ep = oidc.get("userinfo_endpoint")
        reg_ep = oidc.get("registration_endpoint") or (
            # Keycloak DCR endpoint pattern
            keycloak_issuer.rstrip("/").replace("/realms/", "/realms/")
            + "/clients-registrations/openid-connect"
        )
        
        print(f"   JWKS: {jwks_ep}")
        print(f"   Token: {token_ep}")
        
        # 3) Client credentials (create a CONFIDENTIAL client in Keycloak)
        km_client_id = os.getenv("KEYCLOAK_KM_CLIENT_ID", "wso2am")
        km_client_secret = os.getenv("KEYCLOAK_KM_CLIENT_SECRET", "wso2am-secret")
        
        print(f"   Client ID: {km_client_id}")
        
        # 4) Build payload (Admin v4)
        # Use "default" type for WSO2 APIM 4.6.0-alpha3 (Keycloak connector may not be installed)
        km_config = {
            "name": "Keycloak",
            "displayName": "Keycloak",
            "type": "default",  # Use default type, not Keycloak-specific
            "description": "Keycloak Key Manager for JWT validation",
            "enabled": True,
            
            # For JWT validation at the Gateway:
            "issuer": keycloak_issuer,
            "scopesClaim": "scope",
            "consumerKeyClaim": "azp",
            
            # Endpoints as individual top-level fields
            "introspectionEndpoint": introspect_ep,
            "tokenEndpoint": token_ep,
            "revokeEndpoint": revoke_ep,
            "authorizeEndpoint": authorize_ep,
            "clientRegistrationEndpoint": reg_ep,
            "userInfoEndpoint": userinfo_ep,
            
            # Certificates for JWT validation
            "certificates": {
                "type": "JWKS",
                "value": jwks_ep
            },
            
            # Tell APIM we validate JWTs
            "tokenValidation": [
                {
                    "type": "jwt",
                    "value": {}
                }
            ],
            
            # Additional properties as key-value object
            "additionalProperties": {
                "client_id": km_client_id,
                "client_secret": km_client_secret,
            },
        }
        
        # Create or update
        existing = self.get_key_manager_by_name("Keycloak")
        if existing:
            url = f"{self.admin_api}/key-managers/{existing['id']}"
            print(f"   ℹ️  Updating existing Key Manager: {existing['id']}")
            resp = self.session.put(url, json=km_config, headers={"Content-Type": "application/json"})
        else:
            url = f"{self.admin_api}/key-managers"
            print("   ➕ Creating Key Manager")
            resp = self.session.post(url, json=km_config, headers={"Content-Type": "application/json"})
        
        if resp.status_code in (200, 201):
            print("   ✓ Keycloak Key Manager configured")
            return resp.json()
        print(f"   ❌ Failed: {resp.status_code}\n{resp.text}")
        return None
    
    def update_apis_to_use_keycloak(self):
        """Update existing APIs to use Keycloak Key Manager"""
        print(f"\n🔄 Updating APIs to use Keycloak Key Manager...")
        
        # This would require updating each API's keyManagers array
        # For now, we'll note that new APIs should specify Keycloak
        print("   ℹ️  Note: Existing APIs need to be updated manually or re-created")
        print("   ℹ️  New APIs will be able to select Keycloak as Key Manager")


def main():
    print("=" * 70)
    print("Configure Keycloak as WSO2 APIM Key Manager")
    print("=" * 70)
    
    # Environment variables
    wso2_host = os.getenv("WSO2_HOST", "https://wso2am:9443")
    wso2_username = os.getenv("WSO2_ADMIN_USERNAME", "admin")
    wso2_password = os.getenv("WSO2_ADMIN_PASSWORD", "admin")
    
    # Keycloak configuration
    keycloak_issuer = os.getenv("KEYCLOAK_ISSUER", "https://auth.127.0.0.1.sslip.io/realms/innover")
    
    print(f"\n📋 Configuration:")
    print(f"   WSO2 Host: {wso2_host}")
    print(f"   Keycloak Issuer: {keycloak_issuer}")
    
    # Create configurator
    configurator = KeyManagerConfigurator(wso2_host, wso2_username, wso2_password)
    
    # Get access token
    configurator.get_access_token()
    
    # Configure Keycloak Key Manager
    result = configurator.configure_keycloak_key_manager(keycloak_issuer)
    
    if result:
        print("\n" + "=" * 70)
        print("✅ Keycloak Key Manager Configuration Complete!")
        print("=" * 70)
        print("\n📝 Next Steps:")
        print("1. Go to WSO2 Admin Portal: https://apim.127.0.0.1.sslip.io/admin")
        print("2. Navigate to: Key Managers")
        print("3. Verify 'Keycloak' Key Manager is listed and enabled")
        print("4. When creating APIs, select 'Keycloak' as the Key Manager")
        print("\n🔐 Token Validation:")
        print("WSO2 Gateway will now validate JWT tokens issued by Keycloak")
        print(f"Issuer: {keycloak_issuer}")
        print("\n🧪 Test with Keycloak token:")
        print("1. Get token from Keycloak:")
        print(f"   curl -k -X POST {keycloak_issuer}/protocol/openid-connect/token \\")
        print(f"     -d 'client_id=wso2am' \\")
        print(f"     -d 'client_secret=wso2am-secret' \\")
        print(f"     -d 'username=admin' \\")
        print(f"     -d 'password=admin' \\")
        print(f"     -d 'grant_type=password'")
        print("\n2. Use token with WSO2 APIs:")
        print("   curl -k -H 'Authorization: Bearer <keycloak_token>' \\")
        print("     https://apim.127.0.0.1.sslip.io/api/profile/1.0.0/health")
    else:
        print("\n❌ Configuration failed. Check logs above.")
        sys.exit(1)


if __name__ == "__main__":
    main()
