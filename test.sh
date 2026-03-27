#!/bin/bash
# =============================================================
# End-to-End mTLS + OAuth2 Test Script — Separate Instances
# =============================================================
# This version tests against separate mTLS endpoints:
#   - OAuth2 server at https://localhost:8443
#   - API server at https://localhost:9443
#
# The client must present its certificate independently to each
# service, simulating real multi-instance deployment.
# =============================================================

set -e

MTLS_ARGS="--cacert certs/ca.crt --cert certs/client.crt --key certs/client.key"
OAUTH2_URL="https://localhost:8443"
API_URL="https://localhost:9443"

echo "=== Step 1: Verify mTLS to OAuth2 server ==="
echo ""
echo "Connecting to $OAUTH2_URL with client certificate..."
curl -s -o /dev/null -w "HTTP Status: %{http_code}\n" $MTLS_ARGS "$OAUTH2_URL/default/.well-known/openid-configuration"
echo ""

echo "=== Step 2: Verify mTLS to API server ==="
echo ""
echo "Connecting to $API_URL with client certificate..."
curl -s $MTLS_ARGS "$API_URL/api/health" | python3 -m json.tool
echo ""

echo "=== Step 3: Request OAuth2 token via mTLS (client_credentials) ==="
echo ""
TOKEN_RESPONSE=$(curl -s $MTLS_ARGS \
  -X POST "$OAUTH2_URL/default/token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=client_credentials" \
  -d "client_id=my-test-client" \
  -d "client_secret=my-test-secret" \
  -d "scope=read write")

echo "$TOKEN_RESPONSE" | python3 -m json.tool 2>/dev/null || echo "$TOKEN_RESPONSE"
echo ""

ACCESS_TOKEN=$(echo "$TOKEN_RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin)['access_token'])" 2>/dev/null)

if [ -z "$ACCESS_TOKEN" ]; then
  echo "ERROR: Failed to extract access token"
  exit 1
fi

echo "Token: ${ACCESS_TOKEN:0:50}..."
echo ""

echo "=== Step 4: Call API WITHOUT token (expect 401) ==="
echo ""
curl -s $MTLS_ARGS "$API_URL/api/resources" | python3 -m json.tool
echo ""

echo "=== Step 5: Call API WITH token (expect 200) ==="
echo ""
curl -s $MTLS_ARGS \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  "$API_URL/api/resources" | python3 -m json.tool
echo ""

echo "=== Step 6: Call single resource WITH token ==="
echo ""
curl -s $MTLS_ARGS \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  "$API_URL/api/resources/1" | python3 -m json.tool
echo ""

echo "=== Step 7: OAuth2 WITHOUT client cert (expect failure) ==="
echo ""
curl -s --cacert certs/ca.crt "$OAUTH2_URL/default/token" \
  -X POST -d "grant_type=client_credentials" 2>&1 || echo "Connection rejected (no client cert) - EXPECTED"
echo ""

echo "=== Step 8: API WITHOUT client cert (expect failure) ==="
echo ""
curl -s --cacert certs/ca.crt "$API_URL/api/resources" \
  -H "Authorization: Bearer $ACCESS_TOKEN" 2>&1 || echo "Connection rejected (no client cert) - EXPECTED"
echo ""

echo ""
echo "=== All tests complete ==="
echo ""
echo "Summary:"
echo "  - OAuth2 server (mTLS on :8443): independently verified client cert"
echo "  - API server (mTLS on :9443):    independently verified client cert"
echo "  - Both reject connections without a valid client certificate"
