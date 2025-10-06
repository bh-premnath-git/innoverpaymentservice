# Optimal Architecture - Final Design

## 🎯 The Perfect Solution

```
┌──────────────────────────────────────────────────────────────────┐
│                        External Clients                           │
│                                                                   │
│    Web Apps    Mobile Apps    Partner APIs    IoT Devices       │
│       │             │              │               │              │
│    REST/        GraphQL        REST/           gRPC              │
│   GraphQL                     WebSocket                          │
└───────┴─────────────┴──────────────┴───────────────┴────────────┘
        │             │              │               │
        └─────────────┴──────────────┴───────────────┘
                      ↓
┌──────────────────────────────────────────────────────────────────┐
│                    WSO2 API Manager                               │
│                   (Single Gateway for ALL External Traffic)       │
│                                                                   │
│  ┌────────────┐  ┌────────────┐  ┌────────────┐  ┌──────────┐  │
│  │    REST    │  │  GraphQL   │  │ WebSocket  │  │   gRPC   │  │
│  │   Handler  │  │  Handler   │  │  Handler   │  │ Handler  │  │
│  └────────────┘  └────────────┘  └────────────┘  └──────────┘  │
│                                                                   │
│  Features:                                                        │
│  ✅ JWT Validation        ✅ Rate Limiting                       │
│  ✅ Protocol Translation  ✅ Response Caching                    │
│  ✅ Analytics             ✅ Monetization                        │
│  ✅ Developer Portal      ✅ API Versioning                      │
└──────────────────────────────────────────────────────────────────┘
        │
        ↓ (REST/HTTP to backend services)
        │
┌──────────────────────────────────────────────────────────────────┐
│                    Microservices Layer                            │
│                   (Your FastAPI Services)                         │
│                                                                   │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐        │
│  │ Profile  │  │ Payment  │  │  Forex   │  │  Ledger  │        │
│  │          │  │          │  │          │  │          │        │
│  │ REST API │  │ REST API │  │ REST API │  │ REST API │        │
│  │  :8000   │  │  :8000   │  │  :8000   │  │  :8000   │        │
│  │          │  │          │  │          │  │          │        │
│  │gRPC:50051│  │gRPC:50052│  │gRPC:50056│  │gRPC:50053│        │
│  └────┬─────┘  └────┬─────┘  └────┬─────┘  └────┬─────┘        │
│       │             │             │             │                │
│       └─────────────┴─────────────┴─────────────┘                │
│                          │                                        │
│              Internal gRPC Communication                          │
│              (Direct, Fast, Type-Safe)                           │
│              ✅ 10-20ms latency                                   │
│              ✅ Binary protocol (Protobuf)                        │
│              ✅ Bidirectional streaming                           │
│              ✅ No gateway overhead                               │
└──────────────────────────────────────────────────────────────────┘
```

---

## 📊 Protocol Decision Table

| Traffic Type | Protocol | Gateway | Latency | Use For |
|--------------|----------|---------|---------|---------|
| **External → Service** | REST | WSO2 APIM | ~50ms | Public APIs, third-party |
| **External → Service** | GraphQL | WSO2 APIM | ~60ms | Web/mobile dashboards |
| **External → Service** | WebSocket | WSO2 APIM | ~40ms | Real-time updates |
| **External → Service** | gRPC | WSO2 APIM | ~45ms | High-perf clients (optional) |
| **Service → Service** | **gRPC** | **Direct** | **~10ms** | **Internal calls** ✅ |

---

## 🔥 Why This Architecture is Optimal

### 1. External Traffic → WSO2 APIM (REST/GraphQL)

**✅ Benefits:**
- Single gateway for all protocols
- Built-in security (JWT, OAuth2, API Key)
- Rate limiting per user/app
- Response caching
- Protocol translation (e.g., gRPC → REST)
- API analytics and monetization
- Developer portal with documentation

**Example:**
```bash
# Client calls WSO2 APIM
curl -H "Authorization: Bearer $TOKEN" \
  http://localhost:8280/api/payment/1.0.0/process

# WSO2 APIM:
# 1. Validates JWT ✅
# 2. Checks rate limits ✅
# 3. Routes to backend (http://payment:8000)
# 4. Caches response ✅
# 5. Logs analytics ✅
```

---

### 2. Internal Traffic → Direct gRPC

**✅ Benefits:**
- 10x faster than HTTP/REST
- Type-safe (compile-time checking)
- Smaller payloads (Protobuf vs JSON)
- Built-in streaming
- No single point of failure
- Load balancing at client side

**Example:**
```python
# Payment service calls Profile service directly
async def process_payment(payment: PaymentRequest):
    # Direct gRPC call (bypasses WSO2)
    user = await profile_client.get_user(payment.user_id)  # ~10ms
    
    # Validate
    if user.balance < payment.amount:
        raise InsufficientFundsError()
    
    # Another direct gRPC call
    rate = await forex_client.get_rate(payment.currency)  # ~8ms
    
    return await execute_payment(payment)
```

**Performance:**
```
❌ Through WSO2:
Payment → WSO2 → Profile
  (20ms)   (30ms)   (total: 50ms)

✅ Direct gRPC:
Payment ────→ Profile
       (10ms)
```

---

## 🏗️ Implementation Guide

### Step 1: Backend Services (Both REST + gRPC)

Each service exposes **both** protocols:
- **REST** on port 8000 (for WSO2 APIM)
- **gRPC** on port 50051+ (for internal calls)

```python
# services/profile/app/main.py
from fastapi import FastAPI
import asyncio
import grpc_server

app = FastAPI()

# REST endpoints (for WSO2 APIM)
@app.get("/users/{user_id}")
async def get_user_rest(user_id: str):
    """REST endpoint - called by WSO2 APIM"""
    return await fetch_user(user_id)

# Start both servers
async def start_servers():
    # Start REST server (FastAPI)
    rest_task = asyncio.create_task(
        uvicorn.run(app, host="0.0.0.0", port=8000)
    )
    
    # Start gRPC server (internal)
    grpc_task = asyncio.create_task(
        grpc_server.serve()
    )
    
    await asyncio.gather(rest_task, grpc_task)

if __name__ == "__main__":
    asyncio.run(start_servers())
```

```python
# services/profile/app/grpc_server.py
import grpc
from generated.profile.v1 import profile_pb2_grpc

class ProfileServicer(profile_pb2_grpc.ProfileServiceServicer):
    """gRPC service - called by other services"""
    
    async def GetUser(self, request, context):
        user = await fetch_user(request.user_id)
        return profile_pb2.GetUserResponse(
            user_id=user.id,
            username=user.username,
            email=user.email
        )

async def serve():
    server = grpc.aio.server()
    profile_pb2_grpc.add_ProfileServiceServicer_to_server(
        ProfileServicer(), server
    )
    server.add_insecure_port('[::]:50051')
    await server.start()
    await server.wait_for_termination()
```

---

### Step 2: WSO2 APIM Configuration

```yaml
# wso2/api-config.yaml

# REST APIs (for external clients)
rest_apis:
  - name: "Profile API"
    context: "/api/profile"
    version: "1.0.0"
    backend_url: "http://profile:8000"
    throttling_policy: "Gold"
    
  - name: "Payment API"
    context: "/api/payment"
    version: "1.0.0"
    backend_url: "http://payment:8000"
    throttling_policy: "Gold"

# GraphQL API (unified query interface)
graphql_apis:
  - name: "Financial Platform GraphQL"
    context: "/graphql"
    version: "1.0.0"
    backend_url: "http://graphql-gateway:8000/graphql"
    schema_file: "schemas/platform.graphql"

# WebSocket APIs (real-time)
websocket_apis:
  - name: "Forex Streaming"
    context: "/stream/forex"
    version: "1.0.0"
    backend_url: "ws://forex:8000/ws/rates"

# gRPC APIs (optional - for high-performance external clients)
grpc_apis:
  - name: "Profile gRPC API"
    context: "/grpc/profile"
    version: "1.0.0"
    backend_url: "grpc://profile:50051"
    proto_file: "protos/profile/v1/profile.proto"
```

---

### Step 3: Internal gRPC Client

```python
# services/common/grpc_clients.py
import grpc
from generated.profile.v1 import profile_pb2_grpc, profile_pb2

class ProfileClient:
    """Internal gRPC client for Profile service"""
    
    def __init__(self):
        # Direct connection (bypasses WSO2)
        self.channel = grpc.aio.insecure_channel(
            'profile:50051',  # Direct to service
            options=[
                ('grpc.lb_policy_name', 'round_robin'),
                ('grpc.keepalive_time_ms', 30000),
            ]
        )
        self.stub = profile_pb2_grpc.ProfileServiceStub(self.channel)
    
    async def get_user(self, user_id: str):
        """Direct gRPC call (10ms latency)"""
        request = profile_pb2.GetUserRequest(user_id=user_id)
        response = await self.stub.GetUser(request, timeout=3.0)
        return {
            "user_id": response.user_id,
            "username": response.username,
            "email": response.email
        }

# Usage in other services
profile_client = ProfileClient()

@app.post("/payment/process")
async def process_payment(payment: PaymentRequest):
    # Internal gRPC call (fast!)
    user = await profile_client.get_user(payment.user_id)
    
    # Business logic
    if user["balance"] < payment.amount:
        raise HTTPException(400, "Insufficient funds")
    
    return await execute_payment(payment)
```

---

### Step 4: GraphQL Gateway (Optional)

For complex queries that aggregate multiple services:

```python
# services/graphql-gateway/app/main.py
from ariadne import QueryType, make_executable_schema
from services.common.grpc_clients import ProfileClient, PaymentClient

type_defs = """
    type Query {
        userDashboard(userId: ID!): Dashboard
    }
    
    type Dashboard {
        user: User!
        recentPayments: [Payment!]!
        balance: Float!
    }
    
    type User {
        id: ID!
        username: String!
        email: String!
    }
    
    type Payment {
        id: ID!
        amount: Float!
        status: String!
    }
"""

query = QueryType()

@query.field("userDashboard")
async def resolve_user_dashboard(_, info, userId):
    """
    Single GraphQL query → Multiple internal gRPC calls
    Client gets all data in one request
    """
    profile_client = ProfileClient()
    payment_client = PaymentClient()
    
    # Parallel gRPC calls
    user, payments = await asyncio.gather(
        profile_client.get_user(userId),
        payment_client.get_recent_payments(userId)
    )
    
    return {
        "user": user,
        "recentPayments": payments,
        "balance": user["balance"]
    }
```

---

## 📋 docker-compose.yml

```yaml
services:
  # Backend Services (REST + gRPC)
  profile:
    build: ./services/profile
    ports:
      - "8001:8000"   # REST (for WSO2)
      - "50051:50051" # gRPC (for internal)
    networks: [edge]
  
  payment:
    build: ./services/payment
    ports:
      - "8002:8000"   # REST (for WSO2)
      - "50052:50052" # gRPC (for internal)
    networks: [edge]
  
  forex:
    build: ./services/forex
    ports:
      - "8006:8000"   # REST (for WSO2)
      - "50056:50056" # gRPC (for internal)
    networks: [edge]
  
  # GraphQL Gateway (optional)
  graphql-gateway:
    build: ./services/graphql-gateway
    ports:
      - "4000:8000"
    depends_on:
      - profile
      - payment
      - forex
    networks: [edge]
  
  # WSO2 API Manager (external gateway)
  wso2am:
    image: wso2/wso2am:4.5.0-alpine
    ports:
      - "8280:8280"  # HTTP Gateway
      - "8243:8243"  # HTTPS Gateway
      - "9443:9443"  # Management Console
      - "9099:9099"  # WebSocket
    volumes:
      - ./wso2/deployment.toml:/home/wso2carbon/wso2am-4.5.0/repository/conf/deployment.toml:ro
    networks: [edge]
```

---

## 🎯 Client Access Patterns

### 1. External REST API

```bash
# Client → WSO2 APIM → Backend
curl -H "Authorization: Bearer $TOKEN" \
  http://localhost:8280/api/payment/1.0.0/process \
  -d '{"amount": 100, "currency": "USD"}'
```

### 2. External GraphQL

```graphql
# Client → WSO2 APIM → GraphQL Gateway → Multiple gRPC calls
query {
  userDashboard(userId: "123") {
    user { username email }
    recentPayments { amount status }
    balance
  }
}
```

### 3. External WebSocket

```javascript
// Client → WSO2 APIM → Backend WebSocket
const ws = new WebSocket('ws://localhost:9099/stream/forex/1.0.0');
ws.send(JSON.stringify({ subscribe: ['USD/EUR'] }));
ws.onmessage = (event) => console.log('Rate:', event.data);
```

### 4. Internal gRPC

```python
# Service → Service (direct, no WSO2)
async def process_payment(payment):
    # Direct gRPC call (10ms)
    user = await profile_client.get_user(payment.user_id)
    rate = await forex_client.get_rate(payment.currency)
    return await execute_payment(payment)
```

---

## ✅ Architecture Benefits

| Aspect | Benefit |
|--------|---------|
| **External APIs** | ✅ WSO2 handles security, rate limiting, caching |
| **Internal Communication** | ✅ Fast gRPC (10ms vs 50ms through gateway) |
| **Type Safety** | ✅ gRPC Protobuf (compile-time validation) |
| **Flexibility** | ✅ Multiple external protocols (REST, GraphQL, WebSocket) |
| **Performance** | ✅ Optimal for each use case |
| **Scalability** | ✅ No single point of failure for internal calls |
| **Observability** | ✅ WSO2 analytics + gRPC tracing |
| **Security** | ✅ WSO2 for external, mTLS for internal (optional) |

---

## 🚀 Summary

### Perfect Architecture:

```
✅ External Clients
   ↓
✅ WSO2 APIM (REST, GraphQL, WebSocket, gRPC)
   - Security, rate limiting, caching, analytics
   ↓
✅ Backend Services (FastAPI + gRPC servers)
   - Business logic, validation, workflows
   ↓
✅ Internal gRPC Communication (Direct)
   - Fast, type-safe, efficient
   ↓
✅ Infrastructure (CockroachDB, Redis, Redpanda)
   - Data persistence, caching, events
```

### Key Principles:

1. **External → WSO2 APIM** for security, rate limiting, caching
2. **Internal → Direct gRPC** for performance, type safety
3. **REST APIs** for backward compatibility and third-party
4. **GraphQL** for flexible queries (web/mobile apps)
5. **WebSocket** for real-time updates
6. **FastAPI** for business logic
7. **CockroachDB** for data storage

**This is the optimal architecture.** You get:
- Best performance (fast internal gRPC)
- Best security (WSO2 gateway for external)
- Best flexibility (multiple external protocols)
- Best developer experience (FastAPI + type-safe gRPC)

---

**Last Updated:** 2025-10-06  
**Version:** 1.0 - Final Optimal Architecture