#!/usr/bin/env python3
"""Delete all APIs from WSO2"""

import os
import sys
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
    devportal_api = f"{wso2_host}/api/am/devportal/v3"
    
    print("=" * 70)
    print("Deleting All APIs from WSO2")
    print("=" * 70)
    
    # Get all APIs
    response = session.get(f"{publisher_api}/apis")
    if response.status_code != 200:
        print(f"❌ Failed to list APIs: {response.status_code}")
        sys.exit(1)
    
    apis = response.json().get('list', [])
    print(f"\n📋 Found {len(apis)} API(s) to delete\n")
    
    # Get all subscriptions
    subs_response = session.get(f"{devportal_api}/subscriptions")
    if subs_response.status_code == 200:
        subscriptions = subs_response.json().get('list', [])
        print(f"\n🔗 Found {len(subscriptions)} subscription(s) to remove\n")
        for sub in subscriptions:
            sub_id = sub['subscriptionId']
            api_name = sub.get('apiInfo', {}).get('name', 'Unknown')
            session.delete(f"{devportal_api}/subscriptions/{sub_id}")
            print(f"🗑️  Removed subscription for {api_name}")
    
    deleted_count = 0
    for api in apis:
        api_id = api['id']
        api_name = api['name']
        
        # Change lifecycle to CREATED (unpublish)
        if api.get('lifeCycleStatus') == 'PUBLISHED':
            lifecycle_response = session.post(
                f"{publisher_api}/apis/change-lifecycle?apiId={api_id}&action=Demote"
            )
            if lifecycle_response.status_code == 200:
                print(f"📉 Unpublished {api_name}")
        
        # Delete API
        response = session.delete(f"{publisher_api}/apis/{api_id}")
        
        if response.status_code in (200, 204):
            print(f"✅ Deleted {api_name}")
            deleted_count += 1
        else:
            print(f"⚠️  Failed to delete {api_name}: {response.status_code}")
    
    print(f"\n✅ Successfully deleted {deleted_count}/{len(apis)} API(s)")
    print("=" * 70)

if __name__ == "__main__":
    main()
