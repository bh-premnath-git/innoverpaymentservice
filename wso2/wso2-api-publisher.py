#!/usr/bin/env python3
"""
WSO2 API Manager - Automated API Publisher
Supports: REST, GraphQL, WebSocket/Streaming, and AI/LLM endpoints
"""

import requests
import json
import time
import sys
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
        self.admin_api = f"{host}/api/am/admin/v4"
        self.session = requests.Session()
        self.session.verify = False
        self.session.auth = (username, password)
        self.session.headers.update({"Content-Type": "application/json"})

    def create_rest_api(self, api_config: Dict) -> Optional[str]:
        """Create a REST API in WSO2"""
        payload = {
            "name": api_config["name"],
            "context": api_config["context"],
            "version": api_config.get("version", "1.0.0"),
            "provider": api_config.get("provider", "admin"),
            "lifeCycleStatus": "CREATED",
            "type": "HTTP",
            "endpointConfig": {
                "endpoint_type": "http",
                "production_endpoints": {
                    "url": api_config["backend_url"]
                },
                "sandbox_endpoints": {
                    "url": api_config.get("sandbox_url", api_config["backend_url"])
                }
            },
            "operations": api_config.get("operations", [
                {"target": "/*", "verb": "GET", "authType": "Application & Application User", "throttlingPolicy": "Unlimited"},
                {"target": "/*", "verb": "POST", "authType": "Application & Application User", "throttlingPolicy": "Unlimited"},
                {"target": "/*", "verb": "PUT", "authType": "Application & Application User", "throttlingPolicy": "Unlimited"},
                {"target": "/*", "verb": "DELETE", "authType": "Application & Application User", "throttlingPolicy": "Unlimited"},
                {"target": "/*", "verb": "PATCH", "authType": "Application & Application User", "throttlingPolicy": "Unlimited"}
            ]),
            "policies": api_config.get("policies", ["Unlimited"]),
            "visibility": api_config.get("visibility", "PUBLIC"),
            "securityScheme": api_config.get("securityScheme", ["oauth2", "oauth_basic_auth_api_key_mandatory"]),
            "gatewayEnvironments": api_config.get("gatewayEnvironments", ["Production and Sandbox"]),
            "transport": api_config.get("transport", ["http", "https"]),
            "tags": api_config.get("tags", []),
            "corsConfiguration": {
                "corsConfigurationEnabled": True,
                "accessControlAllowOrigins": ["*"],
                "accessControlAllowCredentials": False,
                "accessControlAllowHeaders": ["authorization", "Access-Control-Allow-Origin", "Content-Type", "SOAPAction"],
                "accessControlAllowMethods": ["GET", "PUT", "POST", "DELETE", "PATCH", "OPTIONS"]
            }
        }

        try:
            response = self.session.post(f"{self.publisher_api}/apis", json=payload)
            if response.status_code in [200, 201]:
                api_data = response.json()
                print(f"✅ Created REST API: {api_config['name']} (ID: {api_data['id']})")
                return api_data['id']
            else:
                print(f"❌ Failed to create {api_config['name']}: {response.status_code} - {response.text}")
                return None
        except Exception as e:
            print(f"❌ Error creating {api_config['name']}: {str(e)}")
            return None

    def create_graphql_api(self, api_config: Dict) -> Optional[str]:
        """Create a GraphQL API in WSO2"""
        # GraphQL schema - can be customized per service
        graphql_schema = api_config.get("schema", """
type Query {
  health: String
  status: String
}

type Mutation {
  placeholder: String
}
        """)

        payload = {
            "name": api_config["name"],
            "context": api_config["context"],
            "version": api_config.get("version", "1.0.0"),
            "provider": api_config.get("provider", "admin"),
            "lifeCycleStatus": "CREATED",
            "type": "GRAPHQL",
            "endpointConfig": {
                "endpoint_type": "graphql",
                "production_endpoints": {
                    "url": api_config["backend_url"]
                }
            },
            "graphQLSchema": graphql_schema,
            "policies": api_config.get("policies", ["Unlimited"]),
            "visibility": api_config.get("visibility", "PUBLIC"),
            "securityScheme": api_config.get("securityScheme", ["oauth2"]),
            "gatewayEnvironments": ["Production and Sandbox"],
            "transport": ["http", "https"],
            "tags": api_config.get("tags", ["graphql"]),
            "corsConfiguration": {
                "corsConfigurationEnabled": True,
                "accessControlAllowOrigins": ["*"],
                "accessControlAllowCredentials": False,
                "accessControlAllowHeaders": ["authorization", "Content-Type"],
                "accessControlAllowMethods": ["POST", "OPTIONS"]
            }
        }

        try:
            response = self.session.post(f"{self.publisher_api}/apis", json=payload)
            if response.status_code in [200, 201]:
                api_data = response.json()
                print(f"✅ Created GraphQL API: {api_config['name']} (ID: {api_data['id']})")
                return api_data['id']
            else:
                print(f"❌ Failed to create GraphQL {api_config['name']}: {response.status_code} - {response.text}")
                return None
        except Exception as e:
            print(f"❌ Error creating GraphQL {api_config['name']}: {str(e)}")
            return None

    def create_websocket_api(self, api_config: Dict) -> Optional[str]:
        """Create a WebSocket/Streaming API in WSO2"""
        payload = {
            "name": api_config["name"],
            "context": api_config["context"],
            "version": api_config.get("version", "1.0.0"),
            "provider": api_config.get("provider", "admin"),
            "lifeCycleStatus": "CREATED",
            "type": "WS",
            "endpointConfig": {
                "endpoint_type": "ws",
                "production_endpoints": {
                    "url": api_config["backend_url"]
                }
            },
            "policies": api_config.get("policies", ["Unlimited"]),
            "visibility": api_config.get("visibility", "PUBLIC"),
            "securityScheme": api_config.get("securityScheme", ["oauth2"]),
            "gatewayEnvironments": ["Production and Sandbox"],
            "transport": ["ws", "wss"],
            "tags": api_config.get("tags", ["websocket", "streaming"]),
        }

        try:
            response = self.session.post(f"{self.publisher_api}/apis", json=payload)
            if response.status_code in [200, 201]:
                api_data = response.json()
                print(f"✅ Created WebSocket API: {api_config['name']} (ID: {api_data['id']})")
                return api_data['id']
            else:
                print(f"❌ Failed to create WebSocket {api_config['name']}: {response.status_code} - {response.text}")
                return None
        except Exception as e:
            print(f"❌ Error creating WebSocket {api_config['name']}: {str(e)}")
            return None

    def create_llm_api(self, api_config: Dict) -> Optional[str]:
        """Create an AI/LLM API with appropriate configurations"""
        # LLM APIs typically need higher timeouts and streaming support
        payload = {
            "name": api_config["name"],
            "context": api_config["context"],
            "version": api_config.get("version", "1.0.0"),
            "provider": api_config.get("provider", "admin"),
            "lifeCycleStatus": "CREATED",
            "type": "HTTP",
            "endpointConfig": {
                "endpoint_type": "http",
                "production_endpoints": {
                    "url": api_config["backend_url"],
                    "config": {
                        "actionDuration": api_config.get("timeout", 300000)  # 5 min default for LLM
                    }
                }
            },
            "operations": api_config.get("operations", [
                {"target": "/chat", "verb": "POST", "authType": "Application & Application User", "throttlingPolicy": "Unlimited"},
                {"target": "/completions", "verb": "POST", "authType": "Application & Application User", "throttlingPolicy": "Unlimited"},
                {"target": "/embeddings", "verb": "POST", "authType": "Application & Application User", "throttlingPolicy": "Unlimited"},
                {"target": "/stream", "verb": "POST", "authType": "Application & Application User", "throttlingPolicy": "Unlimited"},
                {"target": "/*", "verb": "GET", "authType": "Application & Application User", "throttlingPolicy": "Unlimited"}
            ]),
            "policies": api_config.get("policies", ["Unlimited"]),
            "visibility": api_config.get("visibility", "PUBLIC"),
            "securityScheme": api_config.get("securityScheme", ["oauth2", "api_key"]),
            "gatewayEnvironments": ["Production and Sandbox"],
            "transport": ["http", "https"],
            "tags": api_config.get("tags", ["ai", "llm", "ml"]),
            "corsConfiguration": {
                "corsConfigurationEnabled": True,
                "accessControlAllowOrigins": ["*"],
                "accessControlAllowCredentials": False,
                "accessControlAllowHeaders": ["authorization", "Content-Type", "X-API-Key"],
                "accessControlAllowMethods": ["POST", "GET", "OPTIONS"]
            }
        }

        try:
            response = self.session.post(f"{self.publisher_api}/apis", json=payload)
            if response.status_code in [200, 201]:
                api_data = response.json()
                print(f"✅ Created LLM API: {api_config['name']} (ID: {api_data['id']})")
                return api_data['id']
            else:
                print(f"❌ Failed to create LLM {api_config['name']}: {response.status_code} - {response.text}")
                return None
        except Exception as e:
            print(f"❌ Error creating LLM {api_config['name']}: {str(e)}")
            return None

    def publish_api(self, api_id: str) -> bool:
        """Publish an API (change lifecycle to PUBLISHED)"""
        try:
            response = self.session.post(
                f"{self.publisher_api}/apis/change-lifecycle",
                params={"apiId": api_id, "action": "Publish"}
            )
            if response.status_code == 200:
                print(f"✅ Published API: {api_id}")
                return True
            else:
                print(f"❌ Failed to publish {api_id}: {response.status_code} - {response.text}")
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

    def delete_api(self, api_id: str) -> bool:
        """Delete an API"""
        try:
            response = self.session.delete(f"{self.publisher_api}/apis/{api_id}")
            if response.status_code == 200:
                print(f"✅ Deleted API: {api_id}")
                return True
            else:
                print(f"❌ Failed to delete {api_id}: {response.status_code}")
                return False
        except Exception as e:
            print(f"❌ Error deleting {api_id}: {str(e)}")
            return False


def get_service_apis() -> List[Dict]:
    """Define all service APIs - customize this for your services"""
    return [
        # Microservices - REST APIs
        {
            "type": "rest",
            "name": "Profile Service API",
            "context": "/api/profile",
            "version": "1.0.0",
            "backend_url": "http://profile:8000",
            "tags": ["profile", "user", "microservice"]
        },
        {
            "type": "rest",
            "name": "Payment Service API",
            "context": "/api/payment",
            "version": "1.0.0",
            "backend_url": "http://payment:8000",
            "tags": ["payment", "transaction", "microservice"]
        },
        {
            "type": "rest",
            "name": "Ledger Service API",
            "context": "/api/ledger",
            "version": "1.0.0",
            "backend_url": "http://ledger:8000",
            "tags": ["ledger", "accounting", "microservice"]
        },
        {
            "type": "rest",
            "name": "Wallet Service API",
            "context": "/api/wallet",
            "version": "1.0.0",
            "backend_url": "http://wallet:8000",
            "tags": ["wallet", "balance", "microservice"]
        },
        {
            "type": "rest",
            "name": "Rule Engine Service API",
            "context": "/api/rules",
            "version": "1.0.0",
            "backend_url": "http://rule-engine:8000",
            "tags": ["rules", "decision", "microservice"]
        },
        {
            "type": "rest",
            "name": "Forex Service API",
            "context": "/api/forex",
            "version": "1.0.0",
            "backend_url": "http://forex:8000",
            "tags": ["forex", "currency", "microservice"]
        },
        
        # Example GraphQL API (uncomment when ready)
        # {
        #     "type": "graphql",
        #     "name": "Profile GraphQL API",
        #     "context": "/graphql/profile",
        #     "version": "1.0.0",
        #     "backend_url": "http://profile:8000/graphql",
        #     "tags": ["graphql", "profile"]
        # },
        
        # Example WebSocket/Streaming API (uncomment when ready)
        # {
        #     "type": "websocket",
        #     "name": "Payment Events Stream",
        #     "context": "/stream/payments",
        #     "version": "1.0.0",
        #     "backend_url": "ws://payment:8000/ws",
        #     "tags": ["websocket", "streaming", "events"]
        # },
        
        # Example AI/LLM API (uncomment when ready)
        # {
        #     "type": "llm",
        #     "name": "AI Assistant API",
        #     "context": "/api/ai",
        #     "version": "1.0.0",
        #     "backend_url": "http://ai-service:8000",
        #     "timeout": 300000,  # 5 minutes
        #     "tags": ["ai", "llm", "assistant"]
        # },
    ]


def main():
    print("=" * 60)
    print("WSO2 API Manager - Automated API Publisher")
    print("=" * 60)
    
    # Initialize publisher
    publisher = WSO2APIPublisher()
    
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
    
    # Get service configurations
    services = get_service_apis()
    
    print(f"\n📋 Found {len(services)} API(s) to publish\n")
    
    # Create and publish APIs
    created_apis = []
    for service in services:
        api_type = service.get("type", "rest").lower()
        
        if api_type == "rest":
            api_id = publisher.create_rest_api(service)
        elif api_type == "graphql":
            api_id = publisher.create_graphql_api(service)
        elif api_type == "websocket" or api_type == "ws":
            api_id = publisher.create_websocket_api(service)
        elif api_type == "llm" or api_type == "ai":
            api_id = publisher.create_llm_api(service)
        else:
            print(f"⚠️  Unknown API type '{api_type}' for {service['name']}")
            continue
        
        if api_id:
            created_apis.append(api_id)
            time.sleep(1)  # Brief pause between creations
    
    # Publish all created APIs
    print(f"\n📤 Publishing {len(created_apis)} API(s)...\n")
    for api_id in created_apis:
        publisher.publish_api(api_id)
        time.sleep(1)
    
    # List all APIs
    print("\n📊 Current APIs in WSO2:\n")
    all_apis = publisher.list_apis()
    for api in all_apis:
        status_icon = "🟢" if api.get('lifeCycleStatus') == 'PUBLISHED' else "🟡"
        print(f"{status_icon} {api.get('name')} - {api.get('context')} ({api.get('lifeCycleStatus')})")
    
    print("\n" + "=" * 60)
    print("✅ API Publishing Complete!")
    print("=" * 60)
    print(f"\n🌐 Access WSO2 Publisher: https://localhost:9443/publisher")
    print(f"🌐 Access Developer Portal: https://localhost:9443/devportal")
    print(f"🔑 Default credentials: admin/admin\n")


if __name__ == "__main__":
    main()
