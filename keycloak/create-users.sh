#!/bin/bash
set -e

# Wait for Keycloak to be ready
echo "Waiting for Keycloak to be ready..."
until curl -sf http://localhost:9000/health/ready > /dev/null 2>&1; do
    echo "Waiting for Keycloak..."
    sleep 2
done

echo "Keycloak is ready. Waiting 5 more seconds for full initialization..."
sleep 5

# Get admin token
echo "Getting admin access token..."
ADMIN_TOKEN=$(curl -s -X POST "http://localhost:8080/realms/master/protocol/openid-connect/token" \
    -d "client_id=admin-cli" \
    -d "username=${KC_BOOTSTRAP_ADMIN_USERNAME}" \
    -d "password=${KC_BOOTSTRAP_ADMIN_PASSWORD}" \
    -d "grant_type=password" | grep -o '"access_token":"[^"]*' | cut -d'"' -f4)

if [ -z "$ADMIN_TOKEN" ]; then
    echo "Failed to get admin token"
    exit 1
fi

echo "Admin token obtained successfully"

# Function to create user
create_user() {
    local username=$1
    local password=$2
    local role=$3
    
    echo "Checking if user '$username' exists..."
    
    # Check if user exists
    USER_ID=$(curl -s -X GET "http://localhost:8080/admin/realms/innover/users?username=${username}&exact=true" \
        -H "Authorization: Bearer ${ADMIN_TOKEN}" | grep -o '"id":"[^"]*' | head -1 | cut -d'"' -f4)
    
    if [ -n "$USER_ID" ]; then
        echo "User '$username' already exists with ID: $USER_ID"
        
        # Update password
        echo "Updating password for user '$username'..."
        curl -s -X PUT "http://localhost:8080/admin/realms/innover/users/${USER_ID}/reset-password" \
            -H "Authorization: Bearer ${ADMIN_TOKEN}" \
            -H "Content-Type: application/json" \
            -d "{\"type\":\"password\",\"value\":\"${password}\",\"temporary\":false}"
        
        echo "Password updated for user '$username'"
    else
        echo "Creating user '$username'..."
        
        # Create user
        CREATE_RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "http://localhost:8080/admin/realms/innover/users" \
            -H "Authorization: Bearer ${ADMIN_TOKEN}" \
            -H "Content-Type: application/json" \
            -d "{
                \"username\": \"${username}\",
                \"enabled\": true,
                \"emailVerified\": true,
                \"credentials\": [{
                    \"type\": \"password\",
                    \"value\": \"${password}\",
                    \"temporary\": false
                }]
            }")
        
        HTTP_CODE=$(echo "$CREATE_RESPONSE" | tail -n1)
        
        if [ "$HTTP_CODE" = "201" ]; then
            echo "User '$username' created successfully"
            
            # Get the new user ID
            USER_ID=$(curl -s -X GET "http://localhost:8080/admin/realms/innover/users?username=${username}&exact=true" \
                -H "Authorization: Bearer ${ADMIN_TOKEN}" | grep -o '"id":"[^"]*' | head -1 | cut -d'"' -f4)
        else
            echo "Failed to create user '$username'. HTTP code: $HTTP_CODE"
            return 1
        fi
    fi
    
    # Remove any required actions
    if [ -n "$USER_ID" ]; then
        echo "Removing required actions for user '$username'..."
        curl -s -X PUT "http://localhost:8080/admin/realms/innover/users/${USER_ID}" \
            -H "Authorization: Bearer ${ADMIN_TOKEN}" \
            -H "Content-Type: application/json" \
            -d "{\"requiredActions\":[]}"
        echo "Required actions removed for user '$username'"
    fi
    
    # Assign role
    if [ -n "$USER_ID" ] && [ -n "$role" ]; then
        echo "Assigning role '$role' to user '$username'..."
        
        # Get role representation
        ROLE_REP=$(curl -s -X GET "http://localhost:8080/admin/realms/innover/roles/${role}" \
            -H "Authorization: Bearer ${ADMIN_TOKEN}")
        
        # Assign role to user
        curl -s -X POST "http://localhost:8080/admin/realms/innover/users/${USER_ID}/role-mappings/realm" \
            -H "Authorization: Bearer ${ADMIN_TOKEN}" \
            -H "Content-Type: application/json" \
            -d "[${ROLE_REP}]"
        
        echo "Role '$role' assigned to user '$username'"
    fi
    
    echo "---"
}

# Create users
echo "Creating/updating users in innover realm..."
echo "=========================================="

create_user "admin" "admin" "admin"
create_user "ops_user" "ops_user" "ops_user"
create_user "finance" "finance" "finance"
create_user "auditor" "auditor" "auditor"
create_user "user" "user" "user"

echo "=========================================="
echo "All users created/updated successfully!"

# Configure Kong client for introspection
echo ""
echo "Configuring Kong client for introspection..."
KONG_ID=$(curl -s -X GET "http://localhost:8080/admin/realms/innover/clients?clientId=kong" \
    -H "Authorization: Bearer ${ADMIN_TOKEN}" | grep -o '"id":"[^"]*' | head -1 | cut -d'"' -f4)

if [ -n "$KONG_ID" ]; then
    curl -s -X PUT "http://localhost:8080/admin/realms/innover/clients/${KONG_ID}" \
        -H "Authorization: Bearer ${ADMIN_TOKEN}" \
        -H "Content-Type: application/json" \
        -d '{"serviceAccountsEnabled":true}'
    echo "✓ Kong client configured"
fi

# Create apitest user
echo "Creating apitest user..."
create_user "apitest" "test123" ""

echo ""
echo "=========================================="
echo "Setup complete! You can log in with:"
echo "  - admin/admin"
echo "  - apitest/test123 (for API testing)"
echo "=========================================="
