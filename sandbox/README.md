# Sandbox - Test Scripts

This folder contains test scripts to verify the entire Innover platform from your local machine.

## Test Scripts

### 1. `test_keycloak_token.py`
Tests Keycloak token generation for all users.

**Usage**:
```bash
# Test default user (ops_user)
python3 sandbox/test_keycloak_token.py

# Test specific user
python3 sandbox/test_keycloak_token.py admin admin

# Test all users
python3 sandbox/test_keycloak_token.py
```

**What it tests**:
- Connection to Keycloak (localhost:8080)
- Token generation for innover realm
- wso2am client authentication
- Saves token to `/tmp/keycloak-token.txt`

---

### 2. `test_services_direct.py`
Tests all 6 services directly via localhost ports.

**Usage**:
```bash
python3 sandbox/test_services_direct.py
```

**What it tests**:
- Profile Service (localhost:8001)
- Payment Service (localhost:8002)
- Ledger Service (localhost:8003)
- Wallet Service (localhost:8004)
- Rule Engine (localhost:8005)
- Forex Service (localhost:8006)

**Prerequisites**: Token must be generated first (runs test_keycloak_token.py)

---

### 3. `test_wso2_gateway.py`
Tests all APIs through WSO2 API Manager gateway.

**Usage**:
```bash
python3 sandbox/test_wso2_gateway.py
```

**What it tests**:
- WSO2 API Manager (localhost:9443)
- Published APIs
- Keycloak token validation through WSO2
- Both HTTPS (9443) and HTTP (8280) gateways

**Prerequisites**: 
- Token must be generated first
- APIs must be published in WSO2

---

### 4. `run_all_tests.py`
Runs all tests in sequence.

**Usage**:
```bash
python3 sandbox/run_all_tests.py
```

**What it does**:
1. Generates Keycloak token
2. Tests direct service access
3. Tests WSO2 gateway access
4. Provides comprehensive summary

---

## Quick Start

### Run All Tests
```bash
cd /home/premnath/innover
python3 sandbox/run_all_tests.py
```

### Run Individual Tests
```bash
# 1. Get token
python3 sandbox/test_keycloak_token.py

# 2. Test services directly
python3 sandbox/test_services_direct.py

# 3. Test through WSO2
python3 sandbox/test_wso2_gateway.py
```

---

## Expected Results

### ✅ All Tests Passing
```
✅ PASS - Keycloak Token Generation
✅ PASS - Direct Service Access
✅ PASS - WSO2 API Gateway

Total: 3/3 tests passed
```

### Troubleshooting

**If Keycloak token fails**:
```bash
# Check Keycloak is running
docker compose ps keycloak

# Check Keycloak logs
docker compose logs keycloak --tail=50
```

**If direct service access fails**:
```bash
# Check services are running
docker compose ps profile payment ledger wallet rule-engine forex

# Check if ports are exposed
docker compose ps --format "table {{.Service}}\t{{.Ports}}"
```

**If WSO2 gateway fails**:
```bash
# Check WSO2 is running
docker compose ps wso2am

# Check if APIs are published
curl -k -u admin:admin https://localhost:9443/api/am/devportal/v3/apis

# Check WSO2 logs
docker compose logs wso2am --tail=50
```

---

## Token File

All tests use a shared token file: `/tmp/keycloak-token.txt`

**Manual token usage**:
```bash
# Get token
TOKEN=$(cat /tmp/keycloak-token.txt)

# Use with curl
curl -H "Authorization: Bearer $TOKEN" http://localhost:8001/health
```

---

## Requirements

**Python packages** (install if needed):
```bash
pip install requests
```

**Services must be running**:
```bash
docker compose up -d
```

**Wait for services to be healthy**:
```bash
docker compose ps --format "table {{.Service}}\t{{.Health}}"
```

---

## Test Coverage

- ✅ Keycloak authentication
- ✅ Token generation (all 5 users)
- ✅ Direct service access (6 services)
- ✅ WSO2 gateway access (6 APIs)
- ✅ HTTPS and HTTP endpoints
- ✅ Error handling and reporting
