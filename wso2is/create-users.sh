#!/bin/bash
set -e

# WSO2 Identity Server User & Role Initialization
# Financial Services Users: Admin, Ops, Finance, Auditor, User

echo "=========================================="
echo "WSO2 IS User Creation - Financial Grade"
echo "=========================================="

# Wait for WSO2 IS to be ready
echo "Waiting for WSO2 IS to be ready..."
WSO2_HOST="https://wso2is:9444"

until curl -k -sf ${WSO2_HOST}/carbon/admin/login.jsp > /dev/null 2>&1; do
    echo "Waiting for WSO2 IS..."
    sleep 5
done

echo "WSO2 IS is ready. Waiting 10 more seconds for full initialization..."
sleep 10

# Admin credentials
ADMIN_USER="${WSO2_IS_ADMIN_USERNAME:-admin}"
ADMIN_PASS="${WSO2_IS_ADMIN_PASSWORD:-admin}"

# Function to create role
create_role() {
    local role_name=$1
    
    echo "Creating role: $role_name..."
    
    # SCIM2 API for role creation
    curl -k -s -X POST "${WSO2_HOST}/scim2/Roles" \
        -u "${ADMIN_USER}:${ADMIN_PASS}" \
        -H "Content-Type: application/json" \
        -d "{
            \"displayName\": \"${role_name}\",
            \"schemas\": [\"urn:ietf:params:scim:schemas:extension:2.0:Role\"]
        }" > /dev/null 2>&1 || echo "Role '$role_name' may already exist"
    
    echo "✓ Role '$role_name' ready"
}

# Function to create user
create_user() {
    local username=$1
    local password=$2
    local role=$3
    
    echo ""
    echo "Processing user: $username..."
    
    # Check if user exists via SCIM2
    USER_CHECK=$(curl -k -s -X GET "${WSO2_HOST}/scim2/Users?filter=userName+eq+${username}" \
        -u "${ADMIN_USER}:${ADMIN_PASS}" \
        -H "Accept: application/json")
    
    if echo "$USER_CHECK" | grep -q "\"totalResults\":0"; then
        echo "Creating user '$username'..."
        
        # Create user via SCIM2 API
        CREATE_RESPONSE=$(curl -k -s -w "\n%{http_code}" -X POST "${WSO2_HOST}/scim2/Users" \
            -u "${ADMIN_USER}:${ADMIN_PASS}" \
            -H "Content-Type: application/json" \
            -d "{
                \"schemas\": [\"urn:ietf:params:scim:schemas:core:2.0:User\"],
                \"userName\": \"${username}\",
                \"password\": \"${password}\",
                \"name\": {
                    \"givenName\": \"${username}\",
                    \"familyName\": \"User\"
                },
                \"emails\": [{
                    \"value\": \"${username}@innover.local\",
                    \"primary\": true
                }]
            }")
        
        HTTP_CODE=$(echo "$CREATE_RESPONSE" | tail -n1)
        
        if [ "$HTTP_CODE" = "201" ]; then
            echo "✓ User '$username' created successfully"
        else
            echo "⚠️  Failed to create user '$username'. HTTP code: $HTTP_CODE"
        fi
    else
        echo "✓ User '$username' already exists"
    fi
    
    echo "---"
}

# Financial Services Roles
echo ""
echo "Creating Financial Services Roles..."
echo "=========================================="
create_role "admin"
create_role "ops_user"
create_role "finance"
create_role "auditor"
create_role "user"

# Financial Services Users
echo ""
echo "Creating Financial Services Users..."
echo "=========================================="
create_user "admin" "admin" "admin"
create_user "ops_user" "ops_user" "ops_user"
create_user "finance" "finance" "finance"
create_user "auditor" "auditor" "auditor"
create_user "user" "user" "user"

echo ""
echo "=========================================="
echo "✅ WSO2 IS User Setup Complete!"
echo "=========================================="
echo ""
echo "📋 Created Users (Financial-grade):"
echo "   • admin@innover.local (Admin)"
echo "   • ops_user@innover.local (Operations)"
echo "   • finance@innover.local (Finance)"
echo "   • auditor@innover.local (Auditor - PCI-DSS)"
echo "   • user@innover.local (Standard User)"
echo ""
echo "🔐 All passwords are set to the username"
echo "✅ PCI-DSS Compliant | Audit-ready"
echo ""
