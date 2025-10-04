#!/bin/bash
set -e

# Start Keycloak in the background
echo "Starting Keycloak..."
/opt/keycloak/bin/kc.sh "$@" &
KC_PID=$!

# Wait for Keycloak to be ready
echo "Waiting for Keycloak to be ready..."
until curl -sf http://localhost:9000/health/ready > /dev/null 2>&1; do
    if ! kill -0 $KC_PID 2>/dev/null; then
        echo "Keycloak process died"
        exit 1
    fi
    sleep 2
done

echo "Keycloak is ready. Waiting 2 more seconds for full initialization..."
sleep 2

# Run user creation script in the background
echo "Starting user creation..."
/opt/keycloak/create-users.sh &

# Wait for Keycloak process
wait $KC_PID
