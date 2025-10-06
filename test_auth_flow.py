#!/usr/bin/env python3
"""
Comprehensive WSO2 Authentication & API Access Test
Tests: WSO2 IS authentication → WSO2 Gateway → Backend services
Financial-grade OAuth2 | PCI-DSS Compliant
"""

import requests
import base64
import json
import sys
from typing import Dict, Optional

requests.packages.urllib3.disable_warnings()

# Configuration
WSO2_IS = "https://localhost:9444"
WSO2_GATEWAY = "http://localhost:8280"

TEST_USERS = [
    {"username": "admin", "password": "admin", "role": "Administrator"},
    {"username": "ops_user", "password": "OpsUser123", "role": "Operations"},
    {"username": "finance", "password": "Finance123", "role": "Finance"},
    {"username": "auditor", "password": "Auditor123", "role": "Auditor (PCI-DSS)"},
    {"username": "user", "password": "User1234", "role": "Standard User"}
]

TEST_APIS = [
    {"name": "Profile", "path": "/profile/1.0.0/health", "port": 8001},
    {"name": "Payment", "path": "/payment/1.0.0/health", "port": 8002},
    {"name": "Forex", "path": "/forex/1.0.0/health", "port": 8006},
    {"name": "Ledger", "path": "/ledger/1.0.0/health", "port": 8003},
    {"name": "Wallet", "path": "/wallet/1.0.0/health", "port": 8004},
    {"name": "Rules", "path": "/rules/1.0.0/health", "port": 8005}
]


def get_token(username: str, password: str) -> Optional[Dict]:
    """Get JWT token from WSO2 IS using DCR + Password Grant"""
    try:
        # DCR
        auth_header = base64.b64encode(f"{username}:{password}".encode()).decode()
        dcr_response = requests.post(
            f"{WSO2_IS}/client-registration/v0.17/register",
            json={
                "clientName": f"test_{username}",
                "owner": username,
                "grantType": "password refresh_token",
                "saasApp": True
            },
            headers={"Authorization": f"Basic {auth_header}", "Content-Type": "application/json"},
            verify=False,
            timeout=10
        )
        
        if dcr_response.status_code not in [200, 201]:
            return {"error": f"DCR failed: {dcr_response.status_code}", "details": dcr_response.text[:150]}
        
        dcr_data = dcr_response.json()
        client_id = dcr_data["clientId"]
        client_secret = dcr_data["clientSecret"]
        
        # Get token
        token_response = requests.post(
            f"{WSO2_IS}/oauth2/token",
            data={"grant_type": "password", "username": username, "password": password, "scope": "openid"},
            auth=(client_id, client_secret),
            verify=False,
            timeout=10
        )
        
        if token_response.status_code == 200:
            token_data = token_response.json()
            access_token = token_data["access_token"]
            
            # Decode JWT
            parts = access_token.split('.')
            if len(parts) >= 2:
                payload = parts[1] + '=' * (4 - len(parts[1]) % 4)
                user_info = json.loads(base64.urlsafe_b64decode(payload))
                
            return {
                "token": access_token,
                "user": user_info.get("sub"),
                "client_id": client_id,
                "expires_in": token_data.get("expires_in")
            }
        else:
            return {"error": f"Token failed: {token_response.status_code}", "details": token_response.text[:150]}
    except Exception as e:
        return {"error": f"Exception: {str(e)}"}


def test_api(api: Dict, token: str) -> Dict:
    """Test API via Gateway"""
    try:
        response = requests.get(
            f"{WSO2_GATEWAY}{api['path']}",
            headers={"Authorization": f"Bearer {token}"},
            timeout=10
        )
        return {
            "status": response.status_code,
            "success": response.status_code == 200,
            "data": response.json() if response.status_code == 200 else response.text[:100]
        }
    except Exception as e:
        return {"status": 0, "success": False, "error": str(e)}


def test_backend(api: Dict) -> bool:
    """Test backend service directly"""
    try:
        response = requests.get(f"http://localhost:{api['port']}/health", timeout=5)
        return response.status_code == 200
    except:
        return False


def main():
    print("=" * 80)
    print("🔐 WSO2 Authentication & API Access Test")
    print("Financial-grade OAuth2 | PCI-DSS Compliant")
    print("=" * 80)
    
    results = {"auth": 0, "gateway": 0, "backend": 0, "total": len(TEST_APIS)}
    
    # Test each user
    for user in TEST_USERS:
        username = user["username"]
        password = user["password"]
        role = user["role"]
        
        print(f"\n👤 User: {username} ({role})")
        print("-" * 80)
        
        # Step 1: Authentication
        print(f"\n🔑 Step 1: WSO2 IS Authentication...")
        token_result = get_token(username, password)
        
        if "error" in token_result:
            print(f"   ❌ {token_result['error']}")
            print(f"      {token_result.get('details', '')}")
            continue
        
        print(f"   ✅ Token obtained")
        print(f"      User: {token_result['user']}")
        print(f"      Client: {token_result['client_id']}")
        print(f"      Expires: {token_result['expires_in']}s")
        results["auth"] += 1
        
        token = token_result["token"]
        
        # Step 2: Test APIs via Gateway
        print(f"\n📡 Step 2: Testing APIs via WSO2 Gateway...")
        for api in TEST_APIS:
            result = test_api(api, token)
            
            if result["success"]:
                print(f"   ✅ {api['name']}: {result['data']}")
                results["gateway"] += 1
            elif result["status"] == 404:
                print(f"   ⚠️  {api['name']}: HTTP 404 - Not deployed")
            elif result["status"] == 401:
                print(f"   ❌ {api['name']}: HTTP 401 - Auth failed")
            else:
                print(f"   ❌ {api['name']}: HTTP {result['status']}")
        
        # Step 3: Test backends directly
        print(f"\n🔧 Step 3: Testing Backend Services...")
        for api in TEST_APIS:
            if test_backend(api):
                print(f"   ✅ {api['name']}: Healthy")
                results["backend"] += 1
            else:
                print(f"   ❌ {api['name']}: Unhealthy")
        
        # Step 4: Test without auth
        print(f"\n🔓 Step 4: Testing without authentication...")
        no_auth = requests.get(f"{WSO2_GATEWAY}{TEST_APIS[0]['path']}")
        if no_auth.status_code in [401, 403]:
            print(f"   ✅ Correctly rejected (HTTP {no_auth.status_code})")
        elif no_auth.status_code == 404:
            print(f"   ⚠️  HTTP 404 - APIs not deployed")
        else:
            print(f"   ❌ HTTP {no_auth.status_code} - Should require auth")
    
    # Summary
    print(f"\n{'=' * 80}")
    print("📊 Test Results")
    print(f"{'=' * 80}")
    print(f"   ✅ Authentication: {results['auth']}/{len(TEST_USERS)} users")
    print(f"   📡 Gateway Access: {results['gateway']}/{results['total']} APIs")
    print(f"   🔧 Backend Health: {results['backend']}/{results['total']} services")
    
    if results['gateway'] == 0:
        print(f"\n💡 APIs not accessible via gateway")
        print(f"   Run: make setup")
    elif results['gateway'] == results['total']:
        print(f"\n🎉 All tests passed! System fully operational")
    else:
        print(f"\n⚠️  Partial success - some APIs not accessible")
    
    print("=" * 80)
    
    return 0 if results['gateway'] == results['total'] else 1


if __name__ == "__main__":
    sys.exit(main())
