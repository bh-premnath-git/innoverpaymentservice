#!/usr/bin/env python3
"""
Test Keycloak Token Generation and Role Verification
Run from local machine to get tokens from Keycloak and verify role claims
"""

import requests
import json
import sys
import base64
from urllib3.exceptions import InsecureRequestWarning

requests.packages.urllib3.disable_warnings(category=InsecureRequestWarning)


def decode_jwt(token):
    """Decode JWT payload (without signature verification)"""
    try:
        # JWT format: header.payload.signature
        parts = token.split('.')
        if len(parts) != 3:
            return None
        
        # Decode payload (add padding if needed)
        payload = parts[1]
        padding = 4 - len(payload) % 4
        if padding != 4:
            payload += '=' * padding
        
        decoded = base64.urlsafe_b64decode(payload)
        return json.loads(decoded)
    except Exception as e:
        print(f"⚠️  Failed to decode JWT: {e}")
        return None

def get_token(username="ops_user", password="ops_user"):
    """Get access token from Keycloak"""
    
    print("=" * 70)
    print("Keycloak Token Generation Test")
    print("=" * 70)
    print()
    
    keycloak_url = "https://auth.127.0.0.1.sslip.io"
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
        print("Requesting token with roles...")
        response = requests.post(
            token_url,
            data={
                'client_id': client_id,
                'client_secret': client_secret,
                'grant_type': 'password',
                'username': username,
                'password': password,
                'scope': 'openid profile email'  # Request ID token with user info
            },
            timeout=10,
            verify=False  # Accept self-signed certificates
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
        
        # Decode and show claims
        payload = decode_jwt(access_token)
        if payload:
            print("🔍 JWT Claims:")
            print(f"  Issuer: {payload.get('iss')}")
            print(f"  Subject: {payload.get('sub')}")
            print(f"  Username: {payload.get('preferred_username')}")
            print(f"  Email: {payload.get('email')}")
            print(f"  Client ID (azp): {payload.get('azp')}")
            print()
            
            # Show roles (the key feature!)
            realm_roles = payload.get('realm_access', {}).get('roles', [])
            if realm_roles:
                print("✨ Realm Roles:")
                for role in realm_roles:
                    print(f"    - {role}")
                print()
            
            # Show client roles
            resource_access = payload.get('resource_access', {})
            if resource_access:
                print("✨ Client Roles:")
                for client, data in resource_access.items():
                    client_roles = data.get('roles', [])
                    if client_roles:
                        print(f"    {client}:")
                        for role in client_roles:
                            print(f"      - {role}")
                print()
            
            # Show audience
            aud = payload.get('aud')
            if aud:
                print(f"📢 Audience: {', '.join(aud) if isinstance(aud, list) else aud}")
                print()
        
        # Also decode ID token if present
        id_token = token_data.get('id_token')
        if id_token:
            print("🆔 ID Token Claims:")
            id_payload = decode_jwt(id_token)
            if id_payload:
                print(f"  Name: {id_payload.get('name')}")
                print(f"  Given Name: {id_payload.get('given_name')}")
                print(f"  Family Name: {id_payload.get('family_name')}")
                print(f"  Email Verified: {id_payload.get('email_verified')}")
                
                # Show roles in ID token too
                id_realm_roles = id_payload.get('realm_access', {}).get('roles', [])
                if id_realm_roles:
                    print(f"  Realm Roles: {', '.join(id_realm_roles)}")
                print()
        
        # Save tokens to files
        with open('/tmp/keycloak-access-token.txt', 'w') as f:
            f.write(access_token)
        print("✅ Access Token saved to: /tmp/keycloak-access-token.txt")
        
        if id_token:
            with open('/tmp/keycloak-id-token.txt', 'w') as f:
                f.write(id_token)
            print("✅ ID Token saved to: /tmp/keycloak-id-token.txt")
        
        # Save decoded payload
        if payload:
            with open('/tmp/keycloak-token-decoded.json', 'w') as f:
                json.dump(payload, f, indent=2)
            print("✅ Decoded JWT saved to: /tmp/keycloak-token-decoded.json")
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
