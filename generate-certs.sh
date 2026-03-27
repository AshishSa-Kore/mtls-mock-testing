#!/bin/bash
# =============================================================
# mTLS Test Certificate Generation Script
# =============================================================
# Generates certificates for testing mutual TLS (mTLS).
#
# Generated files:
#   ca.key / ca.crt           - Certificate Authority
#   server.key / server.crt   - Server certificate (signed by CA)
#   client.key / client.crt   - Client certificate (signed by CA)
# =============================================================

set -e

DAYS_VALID=365
RSA_BITS=2048
CERT_DIR="./certs"
EXTRA_SANS="${EXTRA_SANS:-}"

mkdir -p "$CERT_DIR"

# --- 1. Certificate Authority (CA) ---
echo "==> Generating CA key and certificate..."
openssl genrsa -out "$CERT_DIR/ca.key" $RSA_BITS

openssl req -new -x509 -days $DAYS_VALID -key "$CERT_DIR/ca.key" -out "$CERT_DIR/ca.crt" \
  -subj "/C=US/ST=Test/L=Test/O=Test CA/CN=Test Root CA"

# --- 2. Server Certificate ---
echo "==> Generating server key and certificate..."
openssl genrsa -out "$CERT_DIR/server.key" $RSA_BITS

openssl req -new -key "$CERT_DIR/server.key" -out "$CERT_DIR/server.csr" \
  -subj "/C=US/ST=Test/L=Test/O=Test Server/CN=localhost"

DNS_COUNT=2
cat > server_ext.cnf <<EOF
authorityKeyIdentifier=keyid,issuer
basicConstraints=CA:FALSE
keyUsage = digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth
subjectAltName = @alt_names

[alt_names]
DNS.1 = localhost
DNS.2 = *.localhost
IP.1 = 127.0.0.1
IP.2 = ::1
EOF

# Append any extra SANs (comma-separated hostnames via EXTRA_SANS env var)
if [ -n "$EXTRA_SANS" ]; then
  IFS=',' read -ra SANS <<< "$EXTRA_SANS"
  for san in "${SANS[@]}"; do
    san=$(echo "$san" | xargs)  # trim whitespace
    DNS_COUNT=$((DNS_COUNT + 1))
    echo "DNS.${DNS_COUNT} = ${san}" >> server_ext.cnf
    echo "    Adding SAN: ${san}"
  done
fi

openssl x509 -req -in "$CERT_DIR/server.csr" -CA "$CERT_DIR/ca.crt" -CAkey "$CERT_DIR/ca.key" \
  -CAcreateserial -out "$CERT_DIR/server.crt" -days $DAYS_VALID \
  -extfile server_ext.cnf

# --- 3. Client Certificate ---
echo "==> Generating client key and certificate..."
openssl genrsa -out "$CERT_DIR/client.key" $RSA_BITS

openssl req -new -key "$CERT_DIR/client.key" -out "$CERT_DIR/client.csr" \
  -subj "/C=US/ST=Test/L=Test/O=Test Client/CN=test-client"

cat > client_ext.cnf <<EOF
authorityKeyIdentifier=keyid,issuer
basicConstraints=CA:FALSE
keyUsage = digitalSignature, keyEncipherment
extendedKeyUsage = clientAuth
EOF

openssl x509 -req -in "$CERT_DIR/client.csr" -CA "$CERT_DIR/ca.crt" -CAkey "$CERT_DIR/ca.key" \
  -CAcreateserial -out "$CERT_DIR/client.crt" -days $DAYS_VALID \
  -extfile client_ext.cnf

# --- Cleanup CSRs and temp files ---
rm -f "$CERT_DIR/server.csr" "$CERT_DIR/client.csr" server_ext.cnf client_ext.cnf "$CERT_DIR/ca.srl"

# --- 4. Generate PEM files ---
echo "==> Generating PEM files..."

# CA: cert PEM and key PEM (already PEM-encoded, just copy with .pem extension)
cp "$CERT_DIR/ca.crt" "$CERT_DIR/ca-cert.pem"
cp "$CERT_DIR/ca.key" "$CERT_DIR/ca-key.pem"

# Server: cert PEM, key PEM, and combined bundle (cert + key)
cp "$CERT_DIR/server.crt" "$CERT_DIR/server-cert.pem"
cp "$CERT_DIR/server.key" "$CERT_DIR/server-key.pem"
cat "$CERT_DIR/server.crt" "$CERT_DIR/server.key" > "$CERT_DIR/server-bundle.pem"

# Client: cert PEM, key PEM, and combined bundle (cert + key)
cp "$CERT_DIR/client.crt" "$CERT_DIR/client-cert.pem"
cp "$CERT_DIR/client.key" "$CERT_DIR/client-key.pem"
cat "$CERT_DIR/client.crt" "$CERT_DIR/client.key" > "$CERT_DIR/client-bundle.pem"

# Full chain: client cert + CA cert (useful for some TLS libraries)
cat "$CERT_DIR/client.crt" "$CERT_DIR/ca.crt" > "$CERT_DIR/client-fullchain.pem"
cat "$CERT_DIR/server.crt" "$CERT_DIR/ca.crt" > "$CERT_DIR/server-fullchain.pem"

echo ""
echo "==> Done! Generated files in $CERT_DIR/:"
echo "    CA:     ca.key, ca.crt, ca-cert.pem, ca-key.pem"
echo "    Server: server.key, server.crt, server-cert.pem, server-key.pem, server-bundle.pem, server-fullchain.pem"
echo "    Client: client.key, client.crt, client-cert.pem, client-key.pem, client-bundle.pem, client-fullchain.pem"
echo ""

# --- 4. Quick Verification ---
echo "==> Verifying server cert against CA..."
openssl verify -CAfile "$CERT_DIR/ca.crt" "$CERT_DIR/server.crt"

echo "==> Verifying client cert against CA..."
openssl verify -CAfile "$CERT_DIR/ca.crt" "$CERT_DIR/client.crt"
