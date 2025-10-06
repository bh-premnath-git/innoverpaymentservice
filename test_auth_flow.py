#!/usr/bin/env python3
"""
Complete End-to-End System Test
Tests: WSO2 AM OAuth2 → WSO2 Gateway → All Backend Services
Financial-grade OAuth2 | PCI-DSS Compliant
"""

import requests
import json
import sys

requests.packages.urllib3.disable_warnings()

# Users created in WSO2 IS
TEST_USERS = [
    {"username": "admin", "password": "admin", "role": "Administrator"},
    {"username": "ops_user", "password": "OpsUser123", "role": "Operations"},
    {"username": "finance", "password": "Finance123", "role": "Finance"},
    {"username": "auditor", "password": "Auditor123", "role": "Auditor"},
    {"username": "user", "password": "User1234", "role": "User"}
]

# APIs to test
TEST_APIS = [
    {"name": "Profile", "path": "/api/profile/1.0.0/health"},
    {"name": "Payment", "path": "/api/payment/1.0.0/health"},
    {"name": "Forex", "path": "/api/forex/1.0.0/health"},
    {"name": "Ledger", "path": "/api/ledger/1.0.0/health"},
    {"name": "Wallet", "path": "/api/wallet/1.0.0/health"},
    {"name": "Rules", "path": "/api/rules/1.0.0/health"}
]


def load_app_keys():
    """Load WSO2 AM application keys"""
    try:
        with open('/home/premnath/innover/wso2/output/application-keys.json', 'r') as f:
            return json.load(f)
    except Exception as e:
        print(f"❌ Failed to load application keys: {e}")
        print("   Run: make setup")
        sys.exit(1)


def get_token(consumer_key: str, consumer_secret: str, username: str, password: str):
    """Get OAuth2 token from WSO2 AM"""
    try:
        response = requests.post(
            "https://localhost:9443/oauth2/token",
            data={"grant_type": "password", "username": username, "password": password},
            auth=(consumer_key, consumer_secret),
            verify=False,
            timeout=10
        )
        
        if response.status_code == 200:
            token_data = response.json()
            return {
                "token": token_data["access_token"],
                "expires_in": token_data.get("expires_in", 3600)
            }
        else:
            return {"error": response.status_code, "details": response.text[:200]}
    except Exception as e:
        return {"error": "Exception", "details": str(e)}


def main():
    print("=" * 70)
    print("Complete System Test: WSO2 AM → Gateway → All Services")
    print("Testing with Multiple Users")
    print("=" * 70)
    
    # Load app keys
    app_keys = load_app_keys()
    consumer_key = app_keys['production']['consumerKey']
    consumer_secret = app_keys['production']['consumerSecret']
    key_manager = app_keys['production'].get('keyManager', 'Resident Key Manager')
    
    print(f"\n📱 Application: {app_keys['application']}")
    print(f"   Consumer Key: {consumer_key}")
    print(f"   Key Manager: {key_manager}")
    
    if key_manager == "Resident Key Manager":
        print("\n⚠️  NOTE: Using Resident Key Manager (WSO2 AM built-in user store)")
        print("   Only 'admin' user will work. Other users exist in WSO2 IS only.")
        print("   To enable all users: See wso2/enable-is-key-manager.md")
    
    overall_results = {"users_tested": 0, "users_passed": 0, "total_api_calls": 0, "api_success": 0}
    
    # Test each user
    for user in TEST_USERS:
        username = user["username"]
        password = user["password"]
        role = user["role"]
        
        print(f"\n{'=' * 70}")
        print(f"👤 User: {username} ({role})")
        print(f"{'=' * 70}")
        
        # Get OAuth2 token
        print(f"\n🔑 Getting OAuth2 token...")
        token_result = get_token(consumer_key, consumer_secret, username, password)
        
        if "error" in token_result:
            print(f"   ❌ Token failed: HTTP {token_result['error']}")
            print(f"      {token_result['details']}")
            continue
        
        access_token = token_result["token"]
        print(f"   ✅ Token obtained: {access_token[:30]}...")
        print(f"   Expires in: {token_result['expires_in']}s")
        
        overall_results["users_tested"] += 1
        
        # Test all APIs
        print(f"\n📡 Testing All APIs via WSO2 AM Gateway...")
        print("-" * 70)
        
        user_api_success = 0
        
        for api in TEST_APIS:
            overall_results["total_api_calls"] += 1
            try:
                response = requests.get(
                    f"http://localhost:8280{api['path']}",
                    headers={"Authorization": f"Bearer {access_token}"},
                    timeout=10
                )
                
                if response.status_code == 200:
                    data = response.json()
                    print(f"   ✅ {api['name']:12} → {data}")
                    user_api_success += 1
                    overall_results["api_success"] += 1
                else:
                    print(f"   ❌ {api['name']:12} → HTTP {response.status_code}")
            except Exception as e:
                print(f"   ❌ {api['name']:12} → Error: {e}")
        
        print("-" * 70)
        print(f"User Result: {user_api_success}/{len(TEST_APIS)} APIs successful")
        
        if user_api_success == len(TEST_APIS):
            overall_results["users_passed"] += 1
    
    # Overall Summary
    print(f"\n{'=' * 70}")
    print("📊 Overall Test Results")
    print(f"{'=' * 70}")
    print(f"   👥 Users Tested: {overall_results['users_tested']}/{len(TEST_USERS)}")
    print(f"   ✅ Users Passed: {overall_results['users_passed']}/{overall_results['users_tested']}")
    print(f"   📡 API Calls: {overall_results['api_success']}/{overall_results['total_api_calls']} successful")
    
    if overall_results['users_passed'] == len(TEST_USERS):
        print("\n🎉 ALL USERS & ALL TESTS PASSED!")
        print("✅ All Users → OAuth2 → WSO2 AM Gateway → All Services Working")
        print("=" * 70)
        return 0
    else:
        print(f"\n⚠️  {len(TEST_USERS) - overall_results['users_passed']} user(s) failed")
        return 1


if __name__ == "__main__":
    sys.exit(main())
