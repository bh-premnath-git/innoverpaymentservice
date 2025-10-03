#!/usr/bin/env python3
"""
WSO2 API Manager - Config-based API Publisher
Reads API definitions from api-config.yaml and publishes to WSO2
"""

import requests
import json
import time
import sys
import os
import yaml
from typing import Dict, List, Optional
from urllib3.exceptions import InsecureRequestWarning

# Suppress SSL warnings for local development
requests.packages.urllib3.disable_warnings(category=InsecureRequestWarning)

class WSO2APIPublisher:
    def __init__(self, host: str = "https://localhost:9443", username: str = "admin", password: str = "admin"):
        self.host = host
        self.username = username
        self.password = password
        self.publisher_api = f"{host}/api/am/publisher/v4"
        self.session = requests.Session()
        self.session.verify = False
        self.session.auth = (username, password)
        self.session.headers.update({"Content-Type": "application/json"})

    def create_api(self, api_config: Dict, api_type: str, global_settings: Dict) -> Optional[str]:
        """Generic API creation method"""
        # Merge global settings with API-specific config
        cors_config = global_settings.get('cors', {})
        
        base_payload = {
            "name": api_config["name"],
            "context": api_config["context"],
            "version": api_config.get("version", "1.0.0"),
            "provider": api_config.get("provider", "admin"),
            "description": api_config.get("description", ""),
            "lifeCycleStatus": "CREATED",
            "policies": api_config.get("policies", global_settings.get("throttling_policies", ["Unlimited"])),
            "visibility": api_config.get("visibility", global_settings.get("visibility", "PUBLIC")),
            "securityScheme": ["oauth2"],  # Enable OAuth2 for Keycloak tokens
            "transport": api_config.get("transport", global_settings.get("transport", ["http", "https"])),
            "tags": api_config.get("tags", []),
        }

        # Add CORS configuration
        if cors_config.get('enabled', True):
            base_payload["corsConfiguration"] = {
                "corsConfigurationEnabled": True,
                "accessControlAllowOrigins": cors_config.get("allow_origins", ["*"]),
                "accessControlAllowCredentials": cors_config.get("allow_credentials", False),
                "accessControlAllowHeaders": cors_config.get("allow_headers", ["authorization", "Content-Type"]),
                "accessControlAllowMethods": cors_config.get("allow_methods", ["GET", "POST", "PUT", "DELETE", "PATCH", "OPTIONS"])
            }

        # Type-specific configurations
        if api_type == "rest":
            base_payload["type"] = "HTTP"
            base_payload["endpointConfig"] = {
                "endpoint_type": "http",
                "production_endpoints": {
                    "url": api_config["backend_url"]
                },
                "sandbox_endpoints": {
                    "url": api_config.get("sandbox_url", api_config["backend_url"])
                }
            }
            base_payload["operations"] = api_config.get("operations", [
                {"target": "/*", "verb": "GET", "authType": "Application & Application User", "throttlingPolicy": "Unlimited"},
                {"target": "/*", "verb": "POST", "authType": "Application & Application User", "throttlingPolicy": "Unlimited"},
                {"target": "/*", "verb": "PUT", "authType": "Application & Application User", "throttlingPolicy": "Unlimited"},
                {"target": "/*", "verb": "DELETE", "authType": "Application & Application User", "throttlingPolicy": "Unlimited"},
                {"target": "/*", "verb": "PATCH", "authType": "Application & Application User", "throttlingPolicy": "Unlimited"}
            ])

        elif api_type == "graphql":
            base_payload["type"] = "GRAPHQL"
            base_payload["endpointConfig"] = {
                "endpoint_type": "graphql",
                "production_endpoints": {
                    "url": api_config["backend_url"]
                }
            }
            base_payload["graphQLSchema"] = api_config.get("schema", "type Query { health: String }")

        elif api_type == "websocket":
            base_payload["type"] = "WS"
            base_payload["endpointConfig"] = {
                "endpoint_type": "ws",
                "production_endpoints": {
                    "url": api_config["backend_url"]
                }
            }
            base_payload["transport"] = ["ws", "wss"]

        elif api_type == "llm":
            base_payload["type"] = "HTTP"
            timeout = api_config.get("timeout", global_settings.get("endpoint_config", {}).get("timeout", 300000))
            base_payload["endpointConfig"] = {
                "endpoint_type": "http",
                "production_endpoints": {
                    "url": api_config["backend_url"],
                    "config": {
                        "actionDuration": timeout
                    }
                }
            }
            base_payload["operations"] = api_config.get("operations", [
                {"target": "/chat", "verb": "POST", "authType": "Application & Application User", "throttlingPolicy": "Unlimited"},
                {"target": "/completions", "verb": "POST", "authType": "Application & Application User", "throttlingPolicy": "Unlimited"},
                {"target": "/embeddings", "verb": "POST", "authType": "Application & Application User", "throttlingPolicy": "Unlimited"},
                {"target": "/*", "verb": "GET", "authType": "Application & Application User", "throttlingPolicy": "Unlimited"}
            ])

        try:
            response = self.session.post(f"{self.publisher_api}/apis", json=base_payload)
            if response.status_code in [200, 201]:
                api_data = response.json()
                print(f"✅ Created {api_type.upper()} API: {api_config['name']} (ID: {api_data['id']})")
                return api_data['id']
            else:
                print(f"❌ Failed to create {api_config['name']}: {response.status_code} - {response.text}")
                return None
        except Exception as e:
            print(f"❌ Error creating {api_config['name']}: {str(e)}")
            return None

    def publish_api(self, api_id: str) -> bool:
        """Publish an API"""
        try:
            response = self.session.post(
                f"{self.publisher_api}/apis/change-lifecycle",
                params={"apiId": api_id, "action": "Publish"}
            )
            if response.status_code == 200:
                print(f"✅ Published API: {api_id}")
                return True
            else:
                print(f"❌ Failed to publish {api_id}: {response.status_code}")
                return False
        except Exception as e:
            print(f"❌ Error publishing {api_id}: {str(e)}")
            return False

    def list_apis(self) -> List[Dict]:
        """List all APIs"""
        try:
            response = self.session.get(f"{self.publisher_api}/apis")
            if response.status_code == 200:
                return response.json().get('list', [])
            return []
        except Exception as e:
            print(f"❌ Error listing APIs: {str(e)}")
            return []
    
    def create_revision(self, api_id: str) -> Optional[str]:
        """Create a new revision for the API"""
        try:
            payload = {"description": "Initial revision for deployment"}
            response = self.session.post(f"{self.publisher_api}/apis/{api_id}/revisions", json=payload)
            if response.status_code in (200, 201):
                revision_id = response.json().get('id')
                return revision_id
            else:
                print(f"⚠️  Failed to create revision for {api_id}: {response.status_code}")
                return None
        except Exception as e:
            print(f"⚠️  Error creating revision for {api_id}: {str(e)}")
            return None
    
    def deploy_revision(self, api_id: str, revision_id: str) -> bool:
        """Deploy a revision to the gateway"""
        try:
            payload = [
                {
                    "name": "Default",
                    "vhost": "localhost",
                    "displayOnDevportal": True
                }
            ]
            response = self.session.post(
                f"{self.publisher_api}/apis/{api_id}/deploy-revision?revisionId={revision_id}",
                json=payload
            )
            if response.status_code in (200, 201):
                return True
            else:
                print(f"⚠️  Failed to deploy revision {revision_id} for {api_id}: {response.status_code}")
                return False
        except Exception as e:
            print(f"⚠️  Error deploying revision for {api_id}: {str(e)}")
            return False


def load_config(config_file: str = "api-config.yaml") -> Dict:
    """Load API configuration from YAML file"""
    import os
    
    # If config_file is relative, look in script directory first
    if not os.path.isabs(config_file):
        script_dir = os.path.dirname(os.path.abspath(__file__))
        config_path = os.path.join(script_dir, config_file)
        if not os.path.exists(config_path):
            config_path = config_file  # Fall back to relative path
    else:
        config_path = config_file
    
    try:
        with open(config_path, 'r') as f:
            return yaml.safe_load(f)
    except FileNotFoundError:
        print(f"❌ Configuration file '{config_file}' not found!")
        print(f"   Looked in: {os.path.abspath(config_path)}")
        sys.exit(1)
    except yaml.YAMLError as e:
        print(f"❌ Error parsing YAML configuration: {e}")
        sys.exit(1)


def main():
    print("=" * 70)
    print("WSO2 API Manager - Config-based API Publisher")
    print("=" * 70)
    
    # Load configuration
    print("\n📄 Loading API configuration from api-config.yaml...")
    config = load_config()
    global_settings = config.get('global_settings', {})
    
    # Get WSO2 connection details from environment
    wso2_host = os.getenv("WSO2_HOST", "https://localhost:9443").rstrip("/")
    admin_user = os.getenv("WSO2_ADMIN_USERNAME", "admin")
    admin_pass = os.getenv("WSO2_ADMIN_PASSWORD", "admin")
    
    # Initialize publisher
    publisher = WSO2APIPublisher(host=wso2_host, username=admin_user, password=admin_pass)
    
    # Wait for WSO2 to be ready
    print("\n🔄 Checking WSO2 API Manager availability...")
    max_retries = 30
    for i in range(max_retries):
        try:
            response = requests.get(f"{publisher.host}/services/Version", verify=False, timeout=5)
            if response.status_code == 200:
                print("✅ WSO2 API Manager is ready!")
                break
        except:
            pass
        
        if i < max_retries - 1:
            print(f"⏳ Waiting for WSO2... ({i+1}/{max_retries})")
            time.sleep(2)
        else:
            print("❌ WSO2 API Manager is not responding. Please check if it's running.")
            sys.exit(1)
    
    # Collect all APIs to create
    all_apis = []
    
    # REST APIs
    rest_apis = config.get('rest_apis', [])
    for api in rest_apis:
        all_apis.append(('rest', api))
    
    # GraphQL APIs
    graphql_apis = config.get('graphql_apis', []) or []
    for api in graphql_apis:
        if api:  # Skip None/empty entries
            all_apis.append(('graphql', api))
    
    # WebSocket APIs
    websocket_apis = config.get('websocket_apis', []) or []
    for api in websocket_apis:
        if api:
            all_apis.append(('websocket', api))
    
    # LLM APIs
    llm_apis = config.get('llm_apis', []) or []
    for api in llm_apis:
        if api:
            all_apis.append(('llm', api))
    
    print(f"\n📋 Found {len(all_apis)} API(s) to publish")
    print(f"   - REST APIs: {len(rest_apis)}")
    print(f"   - GraphQL APIs: {len([a for a in graphql_apis if a])}")
    print(f"   - WebSocket APIs: {len([a for a in websocket_apis if a])}")
    print(f"   - LLM APIs: {len([a for a in llm_apis if a])}\n")
    
    # Create APIs
    created_apis = []
    for api_type, api_config in all_apis:
        api_id = publisher.create_api(api_config, api_type, global_settings)
        if api_id:
            created_apis.append(api_id)
            time.sleep(1)
    
    # Publish all created APIs
    print(f"\n📤 Publishing {len(created_apis)} API(s)...\n")
    for api_id in created_apis:
        publisher.publish_api(api_id)
        time.sleep(1)
    
    # Create revisions and deploy to gateway
    print(f"\n🚀 Deploying {len(created_apis)} API(s) to gateway...\n")
    deployed_count = 0
    for api_id in created_apis:
        revision_id = publisher.create_revision(api_id)
        if revision_id:
            if publisher.deploy_revision(api_id, revision_id):
                deployed_count += 1
        time.sleep(0.5)
    
    print(f"\n✅ Successfully deployed {deployed_count}/{len(created_apis)} API(s)")
    
    # List all APIs
    print("\n📊 Current APIs in WSO2:\n")
    all_apis_list = publisher.list_apis()
    for api in all_apis_list:
        status_icon = "🟢" if api.get('lifeCycleStatus') == 'PUBLISHED' else "🟡"
        print(f"{status_icon} {api.get('name')} - {api.get('context')} ({api.get('lifeCycleStatus')})")
    
    print("\n" + "=" * 70)
    print("✅ API Publishing and Deployment Complete!")
    print("=" * 70)
    print(f"\n🌐 WSO2 Publisher: https://localhost:9443/publisher")
    print(f"🌐 Developer Portal: https://localhost:9443/devportal")
    print(f"🔑 Credentials: admin/admin")
    print(f"\n💡 To add GraphQL/WebSocket/LLM APIs, edit api-config.yaml\n")


if __name__ == "__main__":
    main()
