#!/usr/bin/env python3
"""Deploy existing published APIs to the gateway"""

import os
import sys
import time
import requests
from urllib3.exceptions import InsecureRequestWarning

requests.packages.urllib3.disable_warnings(category=InsecureRequestWarning)

def main():
    wso2_host = os.getenv("WSO2_HOST", "https://localhost:9443")
    admin_user = os.getenv("WSO2_ADMIN_USERNAME", "admin")
    admin_pass = os.getenv("WSO2_ADMIN_PASSWORD", "admin")
    
    session = requests.Session()
    session.verify = False
    session.auth = (admin_user, admin_pass)
    session.headers.update({"Content-Type": "application/json"})
    
    publisher_api = f"{wso2_host}/api/am/publisher/v4"
    
    print("=" * 70)
    print("Deploying Existing APIs to Gateway")
    print("=" * 70)
    
    # Get all APIs
    response = session.get(f"{publisher_api}/apis")
    if response.status_code != 200:
        print(f"❌ Failed to list APIs: {response.status_code}")
        sys.exit(1)
    
    apis = response.json().get('list', [])
    print(f"\n📋 Found {len(apis)} API(s)\n")
    
    deployed_count = 0
    for api in apis:
        api_id = api['id']
        api_name = api['name']
        
        # Create revision
        payload = {"description": "Deployment revision"}
        response = session.post(f"{publisher_api}/apis/{api_id}/revisions", json=payload)
        
        if response.status_code in (200, 201):
            revision_id = response.json().get('id')
            print(f"✅ Created revision {revision_id} for {api_name}")
            
            # Deploy revision
            deploy_payload = [
                {
                    "name": "Default",
                    "vhost": "localhost",
                    "displayOnDevportal": True
                }
            ]
            response = session.post(
                f"{publisher_api}/apis/{api_id}/deploy-revision?revisionId={revision_id}",
                json=deploy_payload
            )
            
            if response.status_code in (200, 201):
                print(f"🚀 Deployed {api_name} to gateway")
                deployed_count += 1
            else:
                print(f"⚠️  Failed to deploy {api_name}: {response.status_code}")
        else:
            print(f"⚠️  Failed to create revision for {api_name}: {response.status_code}")
        
        time.sleep(0.5)
    
    print(f"\n✅ Successfully deployed {deployed_count}/{len(apis)} API(s)")
    print("=" * 70)

if __name__ == "__main__":
    main()
