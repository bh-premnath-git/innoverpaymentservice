#!/usr/bin/env python3
"""
Test Services Through WSO2 API Gateway
Tests APIs published in WSO2 API Manager
"""

import requests
import json
import sys
from urllib3.exceptions import InsecureRequestWarning

requests.packages.urllib3.disable_warnings(category=InsecureRequestWarning)


def load_token():
    """Load token from file"""
    try:
        with open('/tmp/keycloak-token.txt', 'r') as f:
            return f.read().strip()
    except FileNotFoundError:
        print("❌ Token file not found. Run test_keycloak_token.py first.")
        return None


def test_wso2_api(name, context, token):
    """Test an API through WSO2 gateway"""
    
    # Try both HTTPS and HTTP
    urls = [
        f"https://localhost:9443{context}/1.0.0/health",
        f"http://localhost:8280{context}/1.0.0/health"
    ]
    
    print(f"📞 Testing {name}...")
    
    for url in urls:
        print(f"   Trying: {url}")
        
        try:
            headers = {'Authorization': f'Bearer {token}'}
            response = requests.get(url, headers=headers, verify=False, timeout=5)
            
            print(f"   Status: {response.status_code}")
            
            if response.status_code == 200:
                try:
                    data = response.json()
                    print(f"   ✅ Response: {data}")
                    return True
                except:
                    print(f"   ✅ Response: {response.text[:100]}")
                    return True
            elif response.status_code == 302:
                print(f"   ⚠️  Redirect (authentication issue)")
                print(f"   Location: {response.headers.get('Location', 'N/A')}")
            else:
                print(f"   ⚠️  Response: {response.text[:200]}")
                
        except requests.exceptions.ConnectionError:
            print(f"   ❌ Connection refused")
        except Exception as e:
            print(f"   ❌ Error: {e}")
    
    return False


def check_wso2_apis():
    """Check which APIs are published in WSO2"""
    print("Checking WSO2 API Manager...")
    print()
    
    try:
        response = requests.get(
            'https://localhost:9443/api/am/devportal/v3/apis',
            auth=('admin', 'admin'),
            verify=False,
            timeout=10
        )
        
        if response.status_code == 200:
            apis = response.json().get('list', [])
            print(f"✅ Found {len(apis)} published APIs:")
            for api in apis:
                print(f"   - {api['name']} ({api['context']})")
            print()
            return apis
        else:
            print(f"⚠️  Could not fetch APIs: {response.status_code}")
            return []
            
    except Exception as e:
        print(f"❌ Error connecting to WSO2: {e}")
        return []


def test_all_wso2_apis():
    """Test all APIs through WSO2 gateway"""
    print("=" * 70)
    print("WSO2 API Gateway Testing")
    print("=" * 70)
    print()
    
    # Load token
    token = load_token()
    if not token:
        print("❌ Cannot test without token")
        return False
    
    print(f"✅ Token loaded (first 50 chars): {token[:50]}...")
    print()
    
    # Check published APIs
    published_apis = check_wso2_apis()
    
    # Test APIs
    apis = [
        ("Profile Service API", "/api/profile"),
        ("Payment Service API", "/api/payment"),
        ("Ledger Service API", "/api/ledger"),
        ("Wallet Service API", "/api/wallet"),
        ("Rule Engine Service API", "/api/rules"),
        ("Forex Service API", "/api/forex"),
    ]
    
    results = []
    for name, context in apis:
        success = test_wso2_api(name, context, token)
        results.append((name, success))
        print()
    
    # Summary
    print("=" * 70)
    print("Summary")
    print("=" * 70)
    successful = sum(1 for _, success in results if success)
    print(f"✅ APIs accessible through WSO2: {successful}/{len(apis)}")
    print()
    
    for name, success in results:
        status = "✅" if success else "❌"
        print(f"{status} {name}")
    
    if successful == 0:
        print()
        print("💡 Troubleshooting:")
        print("   1. Check if APIs are published: https://localhost:9443/publisher")
        print("   2. Check if Keycloak Key Manager is configured")
        print("   3. Check WSO2 logs: docker compose logs wso2am")
    
    return successful > 0


if __name__ == "__main__":
    success = test_all_wso2_apis()
    sys.exit(0 if success else 1)
