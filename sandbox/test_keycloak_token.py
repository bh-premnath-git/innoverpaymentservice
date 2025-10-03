#!/usr/bin/env python3
"""
Test Keycloak Token Generation
Run from local machine to get tokens from Keycloak
"""

import requests
import json
import sys
from urllib3.exceptions import InsecureRequestWarning

requests.packages.urllib3.disable_warnings(category=InsecureRequestWarning)

def get_token(username="ops_user", password="ops_user"):
    """Get access token from Keycloak"""
    
    print("=" * 70)
    print("Keycloak Token Generation Test")
    print("=" * 70)
    print()
    
    keycloak_url = "http://localhost:8080"
    realm = "innover"
    client_id = "wso2am"
    client_secret = "wso2am-secret"
    
    token_url = f"{keycloak_url}/realms/{realm}/protocol/openid-connect/token"
    
    print(f"Keycloak URL: {keycloak_url}")
    print(f"Realm: {realm}")
    print(f"Client: {client_id}")
    print(f"User: {username}")
    print()
    
    try:
        print("Requesting token...")
        response = requests.post(
            token_url,
            data={
                'client_id': client_id,
                'client_secret': client_secret,
                'grant_type': 'password',
                'username': username,
                'password': password
            },
            timeout=10
        )
        
        if response.status_code != 200:
            print(f"❌ Failed to get token. Status: {response.status_code}")
            print(f"Response: {response.text}")
            return None
        
        token_data = response.json()
        access_token = token_data.get('access_token')
        
        if not access_token:
            print("❌ No access token in response")
            print(json.dumps(token_data, indent=2))
            return None
        
        print("✅ Token obtained successfully!")
        print()
        print(f"Access Token (first 100 chars): {access_token[:100]}...")
        print()
        print("Token Details:")
        print(f"  Token Type: {token_data.get('token_type')}")
        print(f"  Expires In: {token_data.get('expires_in')} seconds")
        print(f"  Scope: {token_data.get('scope')}")
        print()
        
        # Save token to file
        with open('/tmp/keycloak-token.txt', 'w') as f:
            f.write(access_token)
        print("✅ Token saved to: /tmp/keycloak-token.txt")
        print()
        
        return access_token
        
    except requests.exceptions.ConnectionError:
        print("❌ Connection error: Cannot connect to Keycloak")
        print(f"   Make sure Keycloak is running at {keycloak_url}")
        print("   Check with: docker compose ps keycloak")
        return None
    except Exception as e:
        print(f"❌ Error: {e}")
        return None


def test_all_users():
    """Test token generation for all users"""
    print("\n" + "=" * 70)
    print("Testing All Users")
    print("=" * 70)
    print()
    
    users = [
        ("admin", "admin"),
        ("ops_user", "ops_user"),
        ("finance", "finance"),
        ("auditor", "auditor"),
        ("user", "user")
    ]
    
    results = []
    for username, password in users:
        print(f"Testing {username}...")
        token = get_token(username, password)
        results.append((username, token is not None))
        print()
    
    print("=" * 70)
    print("Summary")
    print("=" * 70)
    for username, success in results:
        status = "✅" if success else "❌"
        print(f"{status} {username}")


if __name__ == "__main__":
    if len(sys.argv) > 1:
        username = sys.argv[1]
        password = sys.argv[2] if len(sys.argv) > 2 else username
        get_token(username, password)
    else:
        # Default: test ops_user
        get_token()
