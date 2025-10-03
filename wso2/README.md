# WSO2 API Manager Configuration

This directory contains automation scripts and configuration for WSO2 API Manager.

## Files

- **`api-config.yaml`** - API definitions for all services (REST, GraphQL, WebSocket, AI/LLM)
- **`wso2-publisher-from-config.py`** - Main script that reads `api-config.yaml` and publishes APIs
- **`wso2-api-publisher.py`** - Standalone script with hardcoded API definitions (alternative approach)

## Quick Start

### Publish All APIs

From the repository root:
```bash
make publish-apis
```

Or directly:
```bash
cd wso2
python3 wso2-publisher-from-config.py
```

### Prerequisites

The scripts require Python 3 with the following packages:
```bash
pip install requests pyyaml
```

## Configuration

### Adding REST APIs

Edit `api-config.yaml` under the `rest_apis` section:

```yaml
rest_apis:
  - name: "My Service API"
    context: "/api/myservice"
    version: "1.0.0"
    backend_url: "http://myservice:8000"
    description: "My service description"
    tags: ["myservice", "custom"]
```

### Adding GraphQL APIs

Uncomment and edit the `graphql_apis` section:

```yaml
graphql_apis:
  - name: "Profile GraphQL API"
    context: "/graphql/profile"
    version: "1.0.0"
    backend_url: "http://profile:8000/graphql"
    description: "GraphQL interface for profile queries"
    tags: ["graphql", "profile"]
    schema: |
      type Query {
        user(id: ID!): User
        users: [User]
      }
      type User {
        id: ID!
        name: String!
        email: String!
      }
```

### Adding WebSocket/Streaming APIs

Uncomment and edit the `websocket_apis` section:

```yaml
websocket_apis:
  - name: "Payment Events Stream"
    context: "/stream/payments"
    version: "1.0.0"
    backend_url: "ws://payment:8000/ws"
    description: "Real-time payment event streaming"
    tags: ["websocket", "streaming", "events"]
```

### Adding AI/LLM APIs

Uncomment and edit the `llm_apis` section:

```yaml
llm_apis:
  - name: "AI Assistant API"
    context: "/api/ai/assistant"
    version: "1.0.0"
    backend_url: "http://ai-service:8000"
    description: "AI-powered assistant"
    timeout: 300000  # 5 minutes for LLM processing
    tags: ["ai", "llm", "assistant"]
    operations:
      - target: "/chat"
        verb: "POST"
        description: "Chat completion endpoint"
      - target: "/completions"
        verb: "POST"
        description: "Text completion endpoint"
```

## Global Settings

Modify the `global_settings` section in `api-config.yaml` to change:
- Security schemes (OAuth2, API Key, etc.)
- CORS configuration
- Throttling policies
- Default timeouts

## API Lifecycle

The script automatically:
1. Creates APIs in WSO2
2. Publishes them (changes lifecycle to PUBLISHED)
3. Makes them available in the Developer Portal

## WSO2 Access

- **Publisher Portal**: https://localhost:9443/publisher
- **Developer Portal**: https://localhost:9443/devportal
- **Admin Console**: https://localhost:9443/carbon
- **Default Credentials**: admin/admin

## Troubleshooting

### WSO2 Not Responding
```bash
# Check WSO2 status
docker ps | grep wso2
docker logs innover-wso2am-1

# Restart WSO2
docker compose restart wso2am
```

### API Creation Fails
- Ensure WSO2 is healthy: `make health`
- Check backend service URLs are correct
- Verify context paths don't conflict with existing APIs

### Dependencies Missing
```bash
pip install requests pyyaml
```

## Advanced Usage

### Programmatic API Creation

Use the `WSO2APIPublisher` class directly:

```python
from wso2_publisher_from_config import WSO2APIPublisher

publisher = WSO2APIPublisher()

api_config = {
    "name": "Custom API",
    "context": "/api/custom",
    "version": "1.0.0",
    "backend_url": "http://backend:8000"
}

api_id = publisher.create_api(api_config, "rest", {})
publisher.publish_api(api_id)
```

### List Existing APIs

```python
from wso2_publisher_from_config import WSO2APIPublisher

publisher = WSO2APIPublisher()
apis = publisher.list_apis()

for api in apis:
    print(f"{api['name']} - {api['context']} ({api['lifeCycleStatus']})")
```

## Integration with Keycloak

WSO2 is configured to use Keycloak for OAuth2/OIDC:
- **Issuer**: http://keycloak:8080/realms/innover
- **Client ID**: wso2am
- **Client Secret**: Set in `.env` as `WSO2_AM_CLIENT_SECRET`

Ensure these are configured in WSO2's identity provider settings.
