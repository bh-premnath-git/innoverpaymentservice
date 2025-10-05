#!/bin/sh
set -e

echo "=== Initializing mkcert Setup ==="

# Install required packages
apk add --no-cache bash openssl curl libc6-compat

# Download and install mkcert
echo "Downloading mkcert..."
MKCERT_VERSION="v1.4.4"
curl -L "https://github.com/FiloSottile/mkcert/releases/download/${MKCERT_VERSION}/mkcert-${MKCERT_VERSION}-linux-amd64" -o /usr/local/bin/mkcert
chmod +x /usr/local/bin/mkcert

# Create certificates directory
mkdir -p /certs

# Install CA to system
echo "Installing local CA..."
export CAROOT=/certs/CA
mkdir -p $CAROOT
mkcert -install

# Parse domains from environment variable
DOMAINS=${DOMAINS:-"localhost,127.0.0.1"}
echo "Generating certificate for domains: ${DOMAINS}"

# Convert comma-separated domains to space-separated for mkcert
DOMAIN_LIST=$(echo "$DOMAINS" | tr ',' ' ')

# Generate certificate
cd /certs
mkcert -key-file key.pem -cert-file cert.pem $DOMAIN_LIST

# Also create with standard names for compatibility
cp cert.pem local.crt
cp key.pem local.key

# Set proper permissions
chmod 644 /certs/*.pem /certs/*.crt /certs/*.key

# Create certificate info file
CERT_INFO="/certs/certificate.info"
{
    echo "GENERATED_DATE=$(date -Iseconds)"
    echo "DOMAINS=${DOMAINS}"
    openssl x509 -in /certs/cert.pem -noout -dates
    openssl x509 -in /certs/cert.pem -noout -subject
} > "$CERT_INFO"

echo "=== mkcert Setup Complete ==="
echo "Certificate: /certs/cert.pem (also as local.crt)"
echo "Private Key: /certs/key.pem (also as local.key)"
echo "Domains: ${DOMAINS}"
cat "$CERT_INFO"
