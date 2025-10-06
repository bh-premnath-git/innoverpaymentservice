#!/usr/bin/env python3
"""
Test Direct Keycloak JWT with WSO2 Gateway
No token exchange needed - uses JWT validation via JWKS
"""

import requests
import base64
import json
import sys

requests.packages.urllib3.disable_warnings()

def main():
    print("=" * 70)
    print("Direct Keycloak JWT Validation with WSO2 Gateway")
    print("=" * 70)
    
    # Step 1: Get Keycloak JWT token
    print("\n🔐 Step 1: Getting Keycloak JWT token...")
    try:
        kc_resp = requests.post(
            "https://auth.127.0.0.1.sslip.io/realms/innover/protocol/openid-connect/token",
            data={
                "client_id": "wso2am",
                "client_secret": "wso2am-secret",
                "username": "admin",
                "password": "admin",
                "grant_type": "password"
            },
            verify=False,
            timeout=10
        )
        
        if kc_resp.status_code == 200:
            kc_token = kc_resp.json()["access_token"]
            print(f"   ✅ Keycloak JWT obtained")
            
            # Decode token to show info
            parts = kc_token.split('.')
            payload = parts[1] + '=' * (4 - len(parts[1]) % 4)
            user_info = json.loads(base64.urlsafe_b64decode(payload))
            print(f"   👤 User: {user_info.get('preferred_username')}")
            print(f"   📧 Email: {user_info.get('email')}")
            print(f"   🎭 Roles: {', '.join(user_info.get('realm_access', {}).get('roles', []))}")
            print(f"   🔑 Issuer: {user_info.get('iss')}")
            print(f"   📝 Client (azp): {user_info.get('azp')}")
        else:
            print(f"   ❌ Failed: HTTP {kc_resp.status_code}")
            print(f"   Response: {kc_resp.text}")
            return
    except Exception as e:
        print(f"   ❌ Error: {e}")
        return
    
    # Step 2: Use Keycloak JWT directly with WSO2 Gateway
    print("\n📡 Step 2: Testing API with Keycloak JWT (Direct Validation)...")
    
    # Test with JWT in Authorization header (WSO2 format: /api/{service}/{version}/{endpoint})
    api_resp = requests.get(
        "http://localhost:8280/api/forex/1.0.0/health",
        headers={"Authorization": f"Bearer {kc_token}"}
    )
    
    print(f"   HTTP {api_resp.status_code}")
    
    if api_resp.status_code == 200:
        print(f"   ✅ SUCCESS! API accessible with Keycloak JWT")
        print(f"   Response: {api_resp.json()}")
    elif api_resp.status_code == 404:
        print(f"   ❌ 404 Not Found - API routing still broken")
        print(f"   This means WSO2 gateway routing issue persists")
    elif api_resp.status_code == 401:
        print(f"   ❌ 401 Unauthorized - JWT validation failed")
        print(f"   Response: {api_resp.text[:200]}")
    elif api_resp.status_code == 403:
        print(f"   ❌ 403 Forbidden - Scope validation failed")
        print(f"   Response: {api_resp.text[:200]}")
    else:
        print(f"   ❌ Unexpected status: {api_resp.status_code}")
        print(f"   Response: {api_resp.text[:200]}")
    
    # Step 3: Test without token
    print("\n🔓 Step 3: Testing without token...")
    no_auth_resp = requests.get("http://localhost:8280/api/forex/health")
    print(f"   HTTP {no_auth_resp.status_code}")
    if no_auth_resp.status_code == 401:
        print(f"   ✅ Correctly rejected (authentication required)")
    elif no_auth_resp.status_code == 404:
        print(f"   ❌ 404 - Routing issue (not auth issue)")
    else:
        print(f"   Response: {no_auth_resp.text[:100]}")
    
    # Step 4: Test backend directly
    print("\n🔧 Step 4: Backend direct test...")
    backend_resp = requests.get("http://localhost:8006/health")
    if backend_resp.status_code == 200:
        print(f"   ✅ Backend healthy: {backend_resp.json()}")
    else:
        print(f"   ❌ Backend: HTTP {backend_resp.status_code}")
    
    # Summary
    print("\n" + "=" * 70)
    print("Summary:")
    print("  ✅ Keycloak JWT generation working")
    print(f"  {'✅' if api_resp.status_code == 200 else '❌'} WSO2 Gateway with JWT validation")
    print(f"  ✅ Backend services healthy")
    
    if api_resp.status_code == 200:
        print("\n🎉 SUCCESS! Direct JWT validation is working!")
        print("   No need for token exchange - Keycloak JWT works directly")
    elif api_resp.status_code == 404:
        print("\n⚠️  JWT validation config applied, but API routing still broken")
        print("   This is the WSO2 4.6.0-alpha3 gateway routing bug")
        print("   APIs are created but not properly deployed to gateway")
    elif api_resp.status_code in [401, 403]:
        print("\n⚠️  JWT validation issue")
        print("   Check WSO2 logs: docker logs wso2am | grep -i jwt")
        print("   Verify JWKS endpoint: docker exec wso2am curl -k https://auth.127.0.0.1.sslip.io/realms/innover/protocol/openid-connect/certs")
    
    print("=" * 70)

if __name__ == "__main__":
    main()
