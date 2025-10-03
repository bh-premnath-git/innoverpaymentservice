#!/usr/bin/env python3
"""
Test Services Directly (Localhost Ports)
Tests all 6 services exposed on localhost:8001-8006
"""

import requests
import json
import sys

def load_token():
    """Load token from file"""
    try:
        with open('/tmp/keycloak-token.txt', 'r') as f:
            return f.read().strip()
    except FileNotFoundError:
        print("❌ Token file not found. Run test_keycloak_token.py first.")
        return None


def test_service(name, port, token):
    """Test a single service"""
    url = f"http://localhost:{port}/health"
    
    print(f"📞 Testing {name}...")
    print(f"   URL: {url}")
    
    try:
        # Test without token
        response_no_auth = requests.get(url, timeout=5)
        
        # Test with token
        headers = {'Authorization': f'Bearer {token}'} if token else {}
        response = requests.get(url, headers=headers, timeout=5)
        
        if response.status_code == 200:
            data = response.json()
            print(f"   ✅ Status: {response.status_code}")
            print(f"   Response: {data}")
            return True
        else:
            print(f"   ⚠️  Status: {response.status_code}")
            print(f"   Response: {response.text[:100]}")
            return False
            
    except requests.exceptions.ConnectionError:
        print(f"   ❌ Connection refused - service not accessible on localhost:{port}")
        return False
    except Exception as e:
        print(f"   ❌ Error: {e}")
        return False


def test_all_services():
    """Test all 6 services"""
    print("=" * 70)
    print("Direct Service Testing (Localhost Ports)")
    print("=" * 70)
    print()
    
    # Load token
    token = load_token()
    if token:
        print(f"✅ Token loaded (first 50 chars): {token[:50]}...")
    else:
        print("⚠️  No token - testing without authentication")
    print()
    
    services = [
        ("Profile Service", 8001),
        ("Payment Service", 8002),
        ("Ledger Service", 8003),
        ("Wallet Service", 8004),
        ("Rule Engine", 8005),
        ("Forex Service", 8006),
    ]
    
    results = []
    for name, port in services:
        success = test_service(name, port, token)
        results.append((name, success))
        print()
    
    # Summary
    print("=" * 70)
    print("Summary")
    print("=" * 70)
    successful = sum(1 for _, success in results if success)
    print(f"✅ Services accessible: {successful}/{len(services)}")
    print()
    
    for name, success in results:
        status = "✅" if success else "❌"
        print(f"{status} {name}")
    
    return successful == len(services)


if __name__ == "__main__":
    success = test_all_services()
    sys.exit(0 if success else 1)
