#!/bin/sh
set -e

echo "🔐 Creating Java Truststore from mkcert CA..."

# mkcert stores CA in CAROOT directory
CA_CERT="/certs/CA/rootCA.pem"
TRUSTSTORE="/certs/truststore.jks"
TRUSTSTORE_PASSWORD="changeit"

if [ ! -f "$CA_CERT" ]; then
    echo "❌ CA certificate not found: $CA_CERT"
    echo "📁 Checking /certs directory..."
    ls -la /certs/
    if [ -d "/certs/CA" ]; then
        echo "📁 Checking /certs/CA directory..."
        ls -la /certs/CA/
    fi
    exit 1
fi

echo "   ✓ Found CA certificate"

# Remove existing truststore if it exists
if [ -f "$TRUSTSTORE" ]; then
    rm -f "$TRUSTSTORE"
    echo "   ✓ Removed old truststore"
fi

# Import CA certificate into Java truststore
keytool -import -trustcacerts -noprompt \
    -alias mkcert-root-ca \
    -file "$CA_CERT" \
    -keystore "$TRUSTSTORE" \
    -storepass "$TRUSTSTORE_PASSWORD"

if [ $? -eq 0 ]; then
    echo "   ✓ Truststore created: $TRUSTSTORE"
    echo "   ✓ CA certificate imported"
    
    # Verify import
    echo ""
    echo "📋 Truststore contents:"
    keytool -list -keystore "$TRUSTSTORE" -storepass "$TRUSTSTORE_PASSWORD" | grep mkcert
    
    # Set permissions
    chmod 644 "$TRUSTSTORE"
    echo "   ✓ Permissions set"
else
    echo "   ❌ Failed to create truststore"
    exit 1
fi

echo ""
echo "✅ Truststore setup complete!"
