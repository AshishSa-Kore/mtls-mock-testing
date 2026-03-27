# CLAUDE.md

## Project Purpose

End-to-end test environment for **mTLS + OAuth2 client credentials** flow with **separate service instances**. Unlike the shared-proxy version, each service has its own independent mTLS termination, simulating a real deployment where the OAuth2 server and API live on different machines.

## Architecture

```
Client --[mTLS :8443]--> oauth2-proxy (Caddy) --[HTTP]--> mock-oauth2-server (:8080)
Client --[mTLS :9443]--> api-proxy (Caddy)    --[HTTP]--> mock-api (:3000)
```

- **oauth2-proxy** — Caddy instance on port 8443. Terminates mTLS and proxies to the OAuth2 server. Simulates the OAuth2 server's own TLS endpoint.
- **api-proxy** — Caddy instance on port 9443. Terminates mTLS and proxies to the mock API. Simulates the API server's own TLS endpoint.
- **mock-oauth2-server** — `ghcr.io/navikt/mock-oauth2-server:2.1.10`. Issues JWTs via `client_credentials` grant.
- **mock-api** — Express.js (Node 20). Validates Bearer tokens via JWKS from the OAuth2 server.

### Network Isolation

- `oauth2-net`: oauth2-proxy <-> oauth2 (isolated pair)
- `api-net`: api-proxy <-> api (isolated pair)
- `shared-net`: oauth2 <-> api (so the API can fetch JWKS from OAuth2)

## Setup & Run

```bash
chmod +x generate-certs.sh && ./generate-certs.sh
docker-compose up -d
chmod +x test.sh && ./test.sh
```

## Test Script

`test.sh` runs an 8-step e2e flow:
1. mTLS connectivity to OAuth2 server (:8443)
2. mTLS connectivity to API server (:9443)
3. OAuth2 token request via mTLS
4. API call without token (expects 401)
5. API call with token (expects 200)
6. Single resource fetch with token
7. OAuth2 without client cert (expects failure)
8. API without client cert (expects failure)
