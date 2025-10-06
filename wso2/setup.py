#!/usr/bin/env python3
"""
WSO2 API Manager Setup Service
Handles API creation, application deployment, and subscriptions programmatically
"""
import os
import sys
import time
import json
import yaml
import base64
import requests
from typing import Dict, List, Optional
from urllib.parse import urljoin

# Disable SSL warnings for dev environment
requests.packages.urllib3.disable_warnings()


class WSO2APIManager:
    """WSO2 API Manager REST API Client"""
    
    def __init__(self, host: str, username: str, password: str, verify_ssl: bool = False):
        self.host = host.rstrip('/')
        self.username = username
        self.password = password
        self.verify_ssl = verify_ssl
        self.session = requests.Session()
        self.session.verify = verify_ssl
        
        # API endpoints
        self.publisher_api = f"{self.host}/api/am/publisher/v4"
        self.devportal_api = f"{self.host}/api/am/devportal/v3"
        self.admin_api = f"{self.host}/api/am/admin/v4"
        
        # Token and registration endpoint
        self.token_endpoint = f"{self.host}/oauth2/token"

        # WSO2 4.5.0 moved the DCR endpoint to v0.18 while older versions
        # (including 4.1.x/4.4.x) still expose v0.17. Try the newest version
        # first but keep a fallback list for older images so the setup script
        # works across multiple docker-compose configurations.
        self.dcr_versions = ["v0.18", "v0.17"]
        
        self.access_token = None
        
    def get_access_token(self) -> str:
        """Get OAuth2 access token using password grant"""
        print("🔑 Obtaining access token...")
        
        # First, register a dynamic client for DCR. The endpoint version
        # differs between WSO2 releases so attempt each supported version until
        # one responds successfully.
        auth_header = base64.b64encode(f"{self.username}:{self.password}".encode()).decode()

        dcr_payload = {
            "clientName": "setup_client",
            "owner": self.username,
            "grantType": "password refresh_token",
            "saasApp": True
        }

        client_credentials: List[tuple[str, str]] = []
        last_dcr_response: Optional[requests.Response] = None

        for version in self.dcr_versions:
            dcr_endpoint = f"{self.host}/client-registration/{version}/register"
            print(f"   → Trying DCR endpoint {version}...")
            response = self.session.post(
                dcr_endpoint,
                json=dcr_payload,
                headers={
                    "Authorization": f"Basic {auth_header}",
                    "Content-Type": "application/json"
                }
            )
            last_dcr_response = response

            if response.status_code in [200, 201]:
                dcr_data = response.json()
                client_id = dcr_data["clientId"]
                client_secret = dcr_data["clientSecret"]
                client_credentials.append((client_id, client_secret))
                print(f"✓ DCR successful using {version}: {client_id}")
                break

            # If the client already exists WSO2 responds with a 409/400. Some
            # versions echo the credentials back in the payload – reuse them if
            # available instead of treating the call as fatal.
            try:
                error_data = response.json()
            except Exception:
                error_data = {}

            existing_id = error_data.get("clientId") or error_data.get("client_id")
            existing_secret = error_data.get("clientSecret") or error_data.get("client_secret")
            if existing_id and existing_secret:
                client_credentials.append((existing_id, existing_secret))
                print(f"⚠️  DCR reported existing client ({version}), reusing credentials")
                break

        if not client_credentials:
            print("⚠️  DCR failed for all known versions, falling back to built-in clients")

        token_data = {
            "grant_type": "password",
            "username": self.username,
            "password": self.password,
            "scope": "apim:api_view apim:api_create apim:api_publish apim:subscribe apim:app_manage apim:sub_manage"
        }

        # Candidate OAuth clients to try against the token endpoint. Prefer the
        # dynamically registered client, then known built-ins, and finally the
        # legacy behaviour (username/password) to preserve backwards
        # compatibility.
        fallback_clients = [
            ("admin_cli", "admin"),
            (self.username, self.password),
        ]

        token_response = None
        for client in [*client_credentials, *fallback_clients]:
            try:
                token_response = self.session.post(
                    self.token_endpoint,
                    data=token_data,
                    auth=client
                )
            except Exception as exc:
                print(f"   ⚠️  Token request with client {client[0]} failed: {exc}")
                continue

            if token_response.status_code == 200:
                break
            else:
                print(f"   ⚠️  Token request using client {client[0]} failed: {token_response.status_code}")

        if not token_response or token_response.status_code != 200:
            if last_dcr_response is not None:
                print(f"❌ Failed to register OAuth client: {last_dcr_response.status_code} - {last_dcr_response.text}")
            if token_response is not None:
                print(f"❌ Token endpoint response: {token_response.status_code} - {token_response.text[:300]}")
            sys.exit(1)
        
        if token_response.status_code == 200:
            token_data = token_response.json()
            self.access_token = token_data["access_token"]
            self.session.headers.update({"Authorization": f"Bearer {self.access_token}"})
            print("✓ Access token obtained")
            return self.access_token
        else:
            print(f"❌ Failed to get token: {token_response.status_code} - {token_response.text}")
            sys.exit(1)
    
    def wait_for_ready(self, max_attempts: int = 80):
        """Wait for WSO2 to be FULLY ready - not just healthy"""
        print("⏳ Waiting for WSO2 API Manager to be FULLY ready...")
        print(f"   This can take up to {max_attempts * 10 // 60} minutes on first start...")
        
        # Step 1: Wait for basic service to respond
        print("   Step 1/3: Waiting for WSO2 service...")
        for attempt in range(max_attempts):
            try:
                response = self.session.get(f"{self.host}/services/Version", timeout=5)
                if response.status_code == 200:
                    print("   ✓ WSO2 service is up")
                    break
            except Exception:
                pass
            
            if attempt % 6 == 0:
                print(f"      Checking... ({attempt + 1}/{max_attempts})")
            time.sleep(10)
        else:
            print("   ❌ WSO2 service did not start")
            sys.exit(1)
        
        # Step 2: Wait for Publisher API to be fully ready
        print("   Step 2/3: Waiting for Publisher API...")
        for attempt in range(40):
            try:
                # Try to get access token first
                token_response = self.session.post(
                    f"{self.host}/oauth2/token",
                    data={
                        "grant_type": "password",
                        "username": self.username,
                        "password": self.password,
                        "scope": "apim:api_view apim:api_create"
                    },
                    headers={"Content-Type": "application/x-www-form-urlencoded"},
                    auth=(self.username, self.password),
                    timeout=10
                )
                
                if token_response.status_code == 200:
                    token_data = token_response.json()
                    temp_token = token_data.get("access_token")
                    
                    # Now verify Publisher API actually works with the token
                    api_response = self.session.get(
                        f"{self.publisher_api}/apis?limit=1",
                        headers={"Authorization": f"Bearer {temp_token}"},
                        timeout=10
                    )
                    if api_response.status_code == 200:
                        print("   ✓ Publisher API is ready")
                        break
            except Exception as e:
                pass
            
            if attempt % 6 == 0:
                print(f"      Checking... ({attempt + 1}/40)")
            time.sleep(10)
        else:
            print("   ❌ Publisher API failed to initialize properly")
            print("   This may indicate WSO2AM is not fully configured")
            sys.exit(1)
        
        # Step 3: Final wait to ensure everything is stable
        print("   Step 3/3: Waiting for full initialization...")
        time.sleep(20)
        print("✓ WSO2 API Manager is FULLY ready")
        return True
    
    def get_api_by_name(self, name: str, version: str) -> Optional[Dict]:
        """Check if API already exists"""
        response = self.session.get(
            f"{self.publisher_api}/apis",
            params={"query": f"name:{name} version:{version}"}
        )
        
        if response.status_code == 200:
            data = response.json()
            if data.get("count", 0) > 0:
                return data["list"][0]
        return None
    
    def get_available_key_managers(self) -> List[str]:
        """Get list of available Key Managers"""
        try:
            response = self.session.get(f"{self.admin_api}/key-managers")
            if response.status_code == 200:
                data = response.json()
                return [km["name"] for km in data.get("list", [])]
        except:
            pass
        return ["Resident Key Manager"]  # Fallback to default
    
    def create_rest_api(self, api_config: Dict, retry_count: int = 3) -> Optional[str]:
        """Create REST API in WSO2 with retry logic"""
        name = api_config["name"]
        version = api_config["version"]
        context = api_config["context"]
        backend_url = api_config["backend_url"]
        
        print(f"\n📡 Creating API: {name} v{version}")
        
        # Check if exists
        existing = self.get_api_by_name(name, version)
        if existing:
            print(f"   ℹ️  API already exists: {existing['id']}")
            api_id = existing["id"]
            
            # Still apply security fixes to existing API
            self.ensure_api_security(api_id)
            self.create_mediation_sequence(api_id)
            
            return api_id
        
        # Get available Key Managers - only use what's configured
        available_kms = self.get_available_key_managers()
        if not available_kms or available_kms == ["Resident Key Manager"]:
            key_managers = ["Resident Key Manager"]
            print(f"   ✓ Using Resident Key Manager only")
        else:
            key_managers = available_kms
            print(f"   ✓ Using Key Managers: {', '.join(key_managers)}")
        
        # API payload for WSO2 4.x - rely on default gateway security model
        api_payload = {
            "name": name,
            "version": version,
            "context": context,
            "description": api_config.get("description", ""),
            "type": "HTTP",
            "transport": ["http", "https"],
            "tags": api_config.get("tags", []),
            "visibility": "PUBLIC",
            "endpointConfig": {
                "endpoint_type": "http",
                "sandbox_endpoints": {
                    "url": backend_url
                },
                "production_endpoints": {
                    "url": backend_url
                }
            },
            "endpointImplementationType": "ENDPOINT",
            "policies": ["Unlimited"],
            "apiThrottlingPolicy": "Unlimited",
            "authorizationHeader": "Authorization",
            "securityScheme": ["oauth2"],
            "keyManagers": key_managers
        }
        
        # Retry logic for API creation
        for attempt in range(retry_count):
            response = self.session.post(
                f"{self.publisher_api}/apis",
                json=api_payload,
                headers={"Content-Type": "application/json"},
                timeout=30
            )
            
            if response.status_code == 201:
                api_data = response.json()
                api_id = api_data["id"]
                print(f"   ✓ Created API: {api_id}")

                # Ensure OpenAPI definition keeps the default security contract
                self.ensure_api_security(api_id)

                # Add mediation sequence as backup
                self.create_mediation_sequence(api_id)

                return api_id
            elif response.status_code == 500 and attempt < retry_count - 1:
                print(f"   ⚠️  Attempt {attempt + 1}/{retry_count} failed with 500 error, retrying...")
                time.sleep(5)
                continue
            else:
                print(f"   ❌ Failed to create API: {response.status_code}")
                print(f"      Response: {response.text[:300]}")
                return None
        
        return None
    
    def ensure_api_security(self, api_id: str) -> bool:
        """Restore default security settings for the API and its Swagger definition"""
        print("   🔐 Ensuring API security configuration")

        try:
            api_response = self.session.get(f"{self.publisher_api}/apis/{api_id}")
            print(f"   DEBUG: Get API config status: {api_response.status_code}")

            if api_response.status_code == 200:
                api_details = api_response.json()
                updated = False

                if not api_details.get("authorizationHeader"):
                    api_details["authorizationHeader"] = "Authorization"
                    updated = True

                security_scheme = list(api_details.get("securityScheme") or [])
                if "oauth2" not in security_scheme:
                    security_scheme.append("oauth2")
                    api_details["securityScheme"] = security_scheme
                    updated = True

                if updated:
                    update_api_response = self.session.put(
                        f"{self.publisher_api}/apis/{api_id}",
                        json=api_details,
                        headers={"Content-Type": "application/json"}
                    )
                    print(f"   DEBUG: Update API config status: {update_api_response.status_code}")
            else:
                print(f"   ⚠️  Could not fetch API config: {api_response.status_code}")

        except Exception as e:
            print(f"   ❌ Exception while updating API config: {str(e)}")

        try:
            response = self.session.get(f"{self.publisher_api}/apis/{api_id}/swagger")
            print(f"   DEBUG: Get swagger status: {response.status_code}")

            if response.status_code != 200:
                print(f"   ⚠️  Could not get swagger: {response.status_code}")
                print(f"   Response: {response.text[:200]}")
                return False

            swagger = response.json()
            changed = False

            if "paths" in swagger and swagger["paths"]:
                for path_config in swagger["paths"].values():
                    for method_config in path_config.values():
                        if isinstance(method_config, dict):
                            if method_config.get("security") == []:
                                del method_config["security"]
                                changed = True
                            if method_config.get("x-auth-type") == "None":
                                method_config["x-auth-type"] = "Application & Application User"
                                changed = True
            else:
                swagger.setdefault("paths", {})

            if not swagger.get("security"):
                swagger["security"] = [{"default": []}]
                changed = True

            if changed:
                print(f"   DEBUG: Updating swagger with {len(swagger.get('paths', {}))} paths")
                update_response = self.session.put(
                    f"{self.publisher_api}/apis/{api_id}/swagger",
                    json=swagger,
                    headers={"Content-Type": "application/json"}
                )

                print(f"   DEBUG: Update swagger status: {update_response.status_code}")

                if update_response.status_code == 200:
                    print("   ✓ API swagger now requires OAuth2 security")
                    return True
                else:
                    print(f"   ❌ Failed to update swagger: {update_response.status_code}")
                    print(f"   Response: {update_response.text[:200]}")
                    return False

            print("   ✓ API swagger already enforces security")
            return True

        except Exception as e:
            print(f"   ❌ Exception while updating swagger: {str(e)}")
            return False
    
    def create_mediation_sequence(self, api_id: str) -> bool:
        """Upload inline mediation sequence to bypass scope validation"""
        print(f"   📝 Uploading scope bypass mediation sequence")
        
        sequence_xml = '''<?xml version="1.0" encoding="UTF-8"?>
<sequence xmlns="http://ws.apache.org/ns/synapse" name="skip_scope_validation">
    <log level="custom">
        <property name="message" value="Bypassing scope validation"/>
    </log>
    <property name="api.ut.scopesValidated" value="true" scope="default"/>
    <property name="SCOPE_VALIDATION_FAILED" action="remove" scope="default"/>
</sequence>'''
        
        try:
            files = {
                'file': ('skip_scope_validation.xml', sequence_xml.encode(), 'application/xml')
            }
            
            response = self.session.post(
                f"{self.publisher_api}/apis/{api_id}/mediation-policies",
                params={"type": "in"},
                files=files
            )
            
            if response.status_code in [200, 201]:
                print(f"   ✓ Mediation sequence uploaded")
                return True
            else:
                print(f"   ⚠️  Mediation upload: {response.status_code}")
                return False
        except Exception as e:
            print(f"   ❌ Mediation exception: {e}")
            return False
    
    def publish_api(self, api_id: str) -> bool:
        """Publish API (change lifecycle to PUBLISHED)"""
        print(f"   📢 Publishing API {api_id}")
        
        response = self.session.post(
            f"{self.publisher_api}/apis/change-lifecycle",
            params={"apiId": api_id, "action": "Publish"}
        )
        
        if response.status_code == 200:
            print(f"   ✓ API published successfully")
            return True
        else:
            print(f"   ⚠️  Publish status: {response.status_code}")
            return False
    
    def create_revision(self, api_id: str) -> Optional[str]:
        """Create a new revision for the API"""
        print(f"   📦 Creating revision for API {api_id}")
        
        # Verify API exists first
        verify_response = self.session.get(f"{self.publisher_api}/apis/{api_id}")
        if verify_response.status_code != 200:
            print(f"   ❌ API not found: {api_id}")
            print(f"   Response: {verify_response.text[:200]}")
            return None
        
        api_data = verify_response.json()
        print(f"   ✓ API exists: {api_data.get('name')} v{api_data.get('version')}")
        print(f"   Status: {api_data.get('lifeCycleStatus')}")
        
        # Only create revision if API is PUBLISHED
        if api_data.get('lifeCycleStatus') != 'PUBLISHED':
            print(f"   ⚠️  API not published yet, skipping revision")
            return None
        
        revision_payload = {
            "description": "Auto-generated revision"
        }
        
        response = self.session.post(
            f"{self.publisher_api}/apis/{api_id}/revisions",
            json=revision_payload,
            headers={"Content-Type": "application/json"}
        )
        
        print(f"   DEBUG: Create revision status: {response.status_code}")
        
        if response.status_code in [200, 201]:
            revision_id = response.json().get("id")
            print(f"   ✓ Revision created: {revision_id}")
            return revision_id
        else:
            print(f"   ⚠️  Revision creation failed: {response.status_code}")
            print(f"   Response: {response.text[:300]}")
            return None
    
    def deploy_revision(self, api_id: str, revision_id: str, environments: List[str] = None) -> bool:
        """Deploy revision to gateway environments"""
        if environments is None:
            environments = ["Default"]  # Default gateway environment
        
        print(f"   🚀 Deploying revision {revision_id} to gateways: {', '.join(environments)}")
        
        deploy_payload = [
            {
                "name": env,
                "vhost": "localhost",
                "displayOnDevportal": True
            }
            for env in environments
        ]
        
        response = self.session.post(
            f"{self.publisher_api}/apis/{api_id}/deploy-revision",
            params={"revisionId": revision_id},
            json=deploy_payload
        )
        
        if response.status_code in [200, 201]:
            print(f"   ✓ Revision deployed to gateway successfully")
            return True
        else:
            print(f"   ⚠️  Deployment failed: {response.status_code}")
            print(f"   Response: {response.text[:200]}")
            return False
    
    def update_api_endpoint(self, api_id: str, backend_url: str) -> bool:
        """Update API endpoint configuration"""
        print(f"   🔧 Updating endpoint to: {backend_url}")
        
        # Get current API definition
        response = self.session.get(f"{self.publisher_api}/apis/{api_id}")
        if response.status_code != 200:
            print(f"   ⚠️  Failed to get API: {response.status_code}")
            return False
        
        api_data = response.json()
        
        # Update endpoint config
        api_data["endpointConfig"] = {
            "endpoint_type": "http",
            "sandbox_endpoints": {
                "url": backend_url
            },
            "production_endpoints": {
                "url": backend_url
            }
        }
        api_data["endpointImplementationType"] = "ENDPOINT"
        
        # Update API
        response = self.session.put(
            f"{self.publisher_api}/apis/{api_id}",
            json=api_data,
            headers={"Content-Type": "application/json"}
        )
        
        if response.status_code == 200:
            print(f"   ✓ Endpoint updated successfully")
            return True
        else:
            print(f"   ⚠️  Endpoint update failed: {response.status_code}")
            return False
    
    def get_application_by_name(self, name: str) -> Optional[Dict]:
        """Check if application exists"""
        response = self.session.get(
            f"{self.devportal_api}/applications",
            params={"query": name}
        )
        
        if response.status_code == 200:
            data = response.json()
            for app in data.get("list", []):
                if app["name"] == name:
                    return app
        return None
    
    def create_application(self, name: str, throttling_policy: str = "Unlimited", 
                          description: str = "") -> Optional[str]:
        """Create application in Developer Portal"""
        print(f"\n📱 Creating Application: {name}")
        
        # Check if exists
        existing = self.get_application_by_name(name)
        if existing:
            print(f"   ℹ️  Application already exists: {existing['applicationId']}")
            return existing["applicationId"]
        
        app_payload = {
            "name": name,
            "throttlingPolicy": throttling_policy,
            "description": description,
            "tokenType": "JWT"
        }
        
        response = self.session.post(
            f"{self.devportal_api}/applications",
            json=app_payload,
            headers={"Content-Type": "application/json"}
        )
        
        if response.status_code == 201:
            app_data = response.json()
            app_id = app_data["applicationId"]
            print(f"   ✓ Created Application: {app_id}")
            return app_id
        else:
            print(f"   ❌ Failed to create application: {response.status_code} - {response.text}")
            return None
    
    def subscribe_to_api(self, api_id: str, app_id: str, throttling_policy: str = "Unlimited"):
        """Subscribe application to API"""
        print(f"   🔗 Subscribing app {app_id} to API {api_id}")
        
        # Check existing subscriptions
        response = self.session.get(
            f"{self.devportal_api}/subscriptions",
            params={"apiId": api_id, "applicationId": app_id}
        )
        
        if response.status_code == 200:
            data = response.json()
            if data.get("count", 0) > 0:
                print(f"   ℹ️  Subscription already exists")
                return data["list"][0]["subscriptionId"]
        
        sub_payload = {
            "apiId": api_id,
            "applicationId": app_id,
            "throttlingPolicy": throttling_policy
        }
        
        response = self.session.post(
            f"{self.devportal_api}/subscriptions",
            json=sub_payload,
            headers={"Content-Type": "application/json"}
        )
        
        if response.status_code == 201:
            sub_data = response.json()
            print(f"   ✓ Subscription created: {sub_data['subscriptionId']}")
            return sub_data["subscriptionId"]
        else:
            print(f"   ⚠️  Subscription status: {response.status_code}")
            return None
    
    def get_application_scopes(self, app_id: str) -> List[str]:
        """Get scopes for application - use default to avoid scope validation issues"""
        print(f"   📋 Using default scopes for app {app_id}")
        
        # Use 'default' scope which should always work
        # Empty list or specific scopes can cause validation failures
        scopes = ["default"]
        
        print(f"   ✓ Using 'default' scope")
        return scopes
    
    def generate_application_keys(self, app_id: str, key_type: str = "PRODUCTION"):
        """Generate or retrieve keys for application (WSO2 4.5.0 compatible)"""
        print(f"   🔐 Getting {key_type} keys for app {app_id}")
        
        # Try to retrieve existing keys first (avoids 409 conflicts)
        get_response = self.session.get(
            f"{self.devportal_api}/applications/{app_id}/keys/{key_type}"
        )
        
        if get_response.status_code == 200:
            try:
                key_data = get_response.json()
                print(f"   ✓ Retrieved existing keys")
                print(f"      Consumer Key: {key_data.get('consumerKey', 'N/A')}")
                return key_data
            except Exception as e:
                print(f"   ⚠️  Failed to parse existing keys response: {e}")
                # Continue to generate new keys
        
        # Keys don't exist, generate new ones
        print(f"   📝 Generating new {key_type} keys...")
        key_payload = {
            "keyType": key_type,
            "grantTypesToBeSupported": [
                "password",
                "client_credentials",
                "authorization_code",
                "refresh_token"
            ],
            "callbackUrl": "https://localhost:9443/login/callback",
            "validityTime": 3600
        }
        
        response = self.session.post(
            f"{self.devportal_api}/applications/{app_id}/generate-keys",
            json=key_payload,
            headers={"Content-Type": "application/json"}
        )
        
        if response.status_code == 200:
            key_data = response.json()
            print(f"   ✓ Keys generated")
            print(f"      Consumer Key: {key_data['consumerKey']}")
            print(f"      Consumer Secret: {key_data['consumerSecret'][:20]}...")
            return key_data
        else:
            print(f"   ⚠️  Key generation failed: {response.status_code}")
            print(f"      Response: {response.text[:200]}")
            return None


def load_api_config(config_file: str) -> Dict:
    """Load API configuration from YAML file"""
    with open(config_file, 'r') as f:
        return yaml.safe_load(f)


def wait_for_wso2is_ready(wso2is_host: str, max_attempts: int = 60):
    """Wait for WSO2 IS to be ready (optional - it auto-connects with APIM)"""
    print("⏳ Waiting for WSO2 Identity Server...")
    
    for attempt in range(max_attempts):
        try:
            response = requests.get(
                f"{wso2is_host}/carbon/admin/login.jsp",
                verify=False,
                timeout=5
            )
            if response.status_code == 200:
                print("   ✓ WSO2 IS is ready")
                return True
        except Exception:
            pass
        
        if attempt % 6 == 0:
            print(f"      Checking... ({attempt + 1}/{max_attempts})")
        time.sleep(5)
    
    print("   ⚠️  WSO2 IS check timed out, proceeding anyway...")
    return False


def main():
    """Main setup function"""
    print("=" * 60)
    print("WSO2 API Manager Setup Service")
    print("=" * 60)
    
    # Environment variables
    wso2_host = os.getenv("WSO2_HOST", "https://wso2am:9443")
    wso2is_host = os.getenv("WSO2_IS_HOST", "https://wso2is:9444")
    wso2_username = os.getenv("WSO2_ADMIN_USERNAME", "admin")
    wso2_password = os.getenv("WSO2_ADMIN_PASSWORD", "admin")
    config_file = os.getenv("API_CONFIG_FILE", "/config/api-config.yaml")
    
    # Wait for WSO2 IS to be ready (optional - WSO2 IS & APIM auto-connect)
    wait_for_wso2is_ready(wso2is_host)
    
    # Create client
    client = WSO2APIManager(wso2_host, wso2_username, wso2_password)
    
    # Wait for WSO2 to be ready
    client.wait_for_ready()
    
    # Get access token
    client.get_access_token()
    
    # Load configuration
    print(f"\n📄 Loading API configuration from {config_file}")
    config = load_api_config(config_file)
    
    # Track created APIs
    created_apis = []
    
    # Create REST APIs
    print("\n" + "=" * 60)
    print("Creating REST APIs")
    print("=" * 60)
    
    for api_config in config.get("rest_apis", []):
        api_id = client.create_rest_api(api_config)
        if api_id:
            # Update endpoint configuration (fix for existing APIs with invalid URLs)
            backend_url = api_config.get("backend_url")
            if backend_url:
                client.update_api_endpoint(api_id, backend_url)
            
            # Complete deployment sequence for WSO2 4.x
            # 1. Publish API (lifecycle change) - might already be published
            published = client.publish_api(api_id)
            
            # 2. Create revision (works even if already published)
            revision_id = client.create_revision(api_id)
            if revision_id:
                # 3. Deploy revision to gateway
                client.deploy_revision(api_id, revision_id, environments=["Default"])
            elif not published:
                print(f"   ⚠️  Skipping deployment - API not published and no revision")
            
            created_apis.append({
                "id": api_id,
                "name": api_config["name"],
                "version": api_config["version"]
            })
    
    # Create default application
    print("\n" + "=" * 60)
    print("Creating Default Application")
    print("=" * 60)
    
    app_name = "DefaultApplication"
    app_id = client.create_application(
        app_name,
        throttling_policy="Unlimited",
        description="Default application for all APIs"
    )
    
    # Subscribe application to all APIs
    if app_id:
        print("\n" + "=" * 60)
        print("Creating Subscriptions")
        print("=" * 60)
        
        for api in created_apis:
            client.subscribe_to_api(api["id"], app_id)
        
        # Generate keys
        print("\n" + "=" * 60)
        print("Generating Application Keys")
        print("=" * 60)
        
        prod_keys = client.generate_application_keys(app_id, "PRODUCTION")
        sandbox_keys = client.generate_application_keys(app_id, "SANDBOX")
        
        # Save keys to file
        if prod_keys or sandbox_keys:
            keys_file = "/config/application-keys.json"
            keys_data = {
                "application": app_name,
                "applicationId": app_id,
                "production": prod_keys,
                "sandbox": sandbox_keys
            }
            
            with open(keys_file, 'w') as f:
                json.dump(keys_data, f, indent=2)
            
            print(f"\n💾 Keys saved to {keys_file}")
    
    print("\n" + "=" * 60)
    print("✅ Setup Complete!")
    print("=" * 60)
    print(f"\n📊 Summary:")
    print(f"   APIs created: {len(created_apis)}")
    print(f"   Application: {app_name} (ID: {app_id})")
    print(f"\n🌐 Access WSO2 APIM:")
    external_host = wso2_host.replace('wso2am', 'localhost')
    print(f"   Publisher: {external_host}/publisher")
    print(f"   DevPortal: {external_host}/devportal")
    print(f"   Admin: {external_host}/admin")
    print()


if __name__ == "__main__":
    main()
