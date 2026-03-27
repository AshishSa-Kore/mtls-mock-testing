# mTLS + OAuth2 API Guide

## Prerequisites

All requests require mutual TLS (mTLS). You need these three files:

| File | Purpose |
|---|---|
| `ca-cert.pem` | CA certificate — to trust the server |
| `client-cert.pem` | Client certificate — your identity |
| `client-key.pem` | Client private key |

Without these, the TLS handshake will be rejected before any data is exchanged.

---

## Endpoints

| Service | URL |
|---|---|
| OAuth2 Server | `https://0.tcp.in.ngrok.io:14346` |
| API Server | `https://0.tcp.in.ngrok.io:19667` |

---

## Step 1: Obtain an Access Token

**POST** `https://0.tcp.in.ngrok.io:14346/default/token`

| Parameter | Value |
|---|---|
| `grant_type` | `client_credentials` |
| `client_id` | `my-test-client` |
| `client_secret` | `my-test-secret` |
| `scope` | `read write` |

### curl

```bash
curl --cacert ca-cert.pem --cert client-cert.pem --key client-key.pem \
  -X POST "https://0.tcp.in.ngrok.io:14346/default/token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=client_credentials" \
  -d "client_id=my-test-client" \
  -d "client_secret=my-test-secret" \
  -d "scope=read write"
```

### Response

```json
{
  "token_type": "Bearer",
  "access_token": "eyJraWQiOiJkZWZhdWx0Iiw...",
  "expires_in": 3599,
  "scope": "read write"
}
```

---

## Step 2: Call the API

All API requests require:
- mTLS (client certificate)
- `Authorization: Bearer <access_token>` header

### List Resources

**GET** `https://0.tcp.in.ngrok.io:19667/api/resources`

```bash
curl --cacert ca-cert.pem --cert client-cert.pem --key client-key.pem \
  -H "Authorization: Bearer <access_token>" \
  "https://0.tcp.in.ngrok.io:19667/api/resources"
```

#### Response (200 OK)

```json
{
  "data": [
    { "id": 1, "name": "Resource A", "status": "active" },
    { "id": 2, "name": "Resource B", "status": "active" },
    { "id": 3, "name": "Resource C", "status": "inactive" }
  ],
  "meta": {
    "client_id": "my-test-client",
    "scope": "read write",
    "issued_at": "2026-03-27T08:39:40.000Z",
    "expires_at": "2026-03-27T09:39:40.000Z"
  }
}
```

### Get Single Resource

**GET** `https://0.tcp.in.ngrok.io:19667/api/resources/:id`

```bash
curl --cacert ca-cert.pem --cert client-cert.pem --key client-key.pem \
  -H "Authorization: Bearer <access_token>" \
  "https://0.tcp.in.ngrok.io:19667/api/resources/1"
```

#### Response (200 OK)

```json
{
  "data": {
    "id": 1,
    "name": "Resource A",
    "status": "active",
    "detail": "Full details for A"
  },
  "meta": {
    "client_id": "my-test-client"
  }
}
```

### Chat Completion (OpenAI-compatible)

**POST** `https://0.tcp.in.ngrok.io:19667/api/mock-model`

Echoes back the last user message in the OpenAI chat completion response format.

#### Request Body

| Field | Type | Required | Description |
|---|---|---|---|
| `model` | string | No | Model name (defaults to `mock-echo-1`) |
| `messages` | array | Yes | Array of message objects with `role` and `content` |

```bash
curl --cacert ca-cert.pem --cert client-cert.pem --key client-key.pem \
  -X POST "https://0.tcp.in.ngrok.io:19667/api/mock-model" \
  -H "Authorization: Bearer <access_token>" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "mock-echo-1",
    "messages": [
      {"role": "system", "content": "You are a helpful assistant."},
      {"role": "user", "content": "Hello, this is a test message!"}
    ]
  }'
```

#### Response (200 OK)

```json
{
  "id": "chatcmpl-464c9f00-1f3c-4ccb-9a97-495196e41175",
  "object": "chat.completion",
  "created": 1774607158,
  "model": "mock-echo-1",
  "choices": [
    {
      "index": 0,
      "message": {
        "role": "assistant",
        "content": "Hello, this is a test message!"
      },
      "finish_reason": "stop"
    }
  ],
  "usage": {
    "prompt_tokens": 0,
    "completion_tokens": 0,
    "total_tokens": 0
  }
}
```

---

## Step 3: MCP Server (JSON-RPC)

The API server also hosts an MCP (Model Context Protocol) endpoint. It uses plain JSON-RPC 2.0 over HTTP — no SSE, no sessions required. Only mTLS is needed (no Bearer token).

**POST** `https://0.tcp.in.ngrok.io:19667/mcp`

### Initialize

```bash
curl --cacert ca-cert.pem --cert client-cert.pem --key client-key.pem \
  -X POST "https://0.tcp.in.ngrok.io:19667/mcp" \
  -H "Content-Type: application/json" \
  -d '{
    "jsonrpc": "2.0",
    "id": 1,
    "method": "initialize",
    "params": {
      "protocolVersion": "2025-03-26",
      "capabilities": {},
      "clientInfo": { "name": "my-client", "version": "1.0.0" }
    }
  }'
```

#### Response

```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "result": {
    "protocolVersion": "2025-03-26",
    "capabilities": { "tools": {} },
    "serverInfo": { "name": "mock-mcp-server", "version": "1.0.0" }
  }
}
```

### List Tools

```bash
curl --cacert ca-cert.pem --cert client-cert.pem --key client-key.pem \
  -X POST "https://0.tcp.in.ngrok.io:19667/mcp" \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc": "2.0", "id": 2, "method": "tools/list"}'
```

#### Response

```json
{
  "jsonrpc": "2.0",
  "id": 2,
  "result": {
    "tools": [
      {
        "name": "process_data",
        "description": "Processes input data and returns a success status",
        "inputSchema": {
          "type": "object",
          "properties": {
            "name": { "type": "string", "description": "Name of the data item" },
            "value": { "type": "string", "description": "Value to process" },
            "category": { "type": "string", "description": "Category of the data (e.g. metrics, logs, events)" },
            "priority": { "type": "number", "description": "Priority level (1-5)" }
          },
          "required": ["name", "value", "category", "priority"]
        }
      }
    ]
  }
}
```

### Call Tool

```bash
curl --cacert ca-cert.pem --cert client-cert.pem --key client-key.pem \
  -X POST "https://0.tcp.in.ngrok.io:19667/mcp" \
  -H "Content-Type: application/json" \
  -d '{
    "jsonrpc": "2.0",
    "id": 3,
    "method": "tools/call",
    "params": {
      "name": "process_data",
      "arguments": {
        "name": "test-item",
        "value": "hello-world",
        "category": "metrics",
        "priority": 3
      }
    }
  }'
```

#### Response

```json
{
  "jsonrpc": "2.0",
  "id": 3,
  "result": {
    "content": [
      {
        "type": "text",
        "text": "{\n  \"status\": \"success\",\n  \"processed\": {\n    \"name\": \"test-item\",\n    \"value\": \"hello-world\",\n    \"category\": \"metrics\",\n    \"priority\": 3\n  },\n  \"timestamp\": \"2026-03-27T11:04:46.999Z\",\n  \"message\": \"Successfully processed 'test-item' in category 'metrics'\"\n}"
      }
    ]
  }
}
```

### Notifications

Notifications (requests without an `id`) are accepted with HTTP 202 and no response body.

---

## Other Endpoints

### Health Check (no auth required)

**GET** `https://0.tcp.in.ngrok.io:19667/api/health`

```bash
curl --cacert ca-cert.pem --cert client-cert.pem --key client-key.pem \
  "https://0.tcp.in.ngrok.io:19667/api/health"
```

---

## Error Responses

| Scenario | HTTP Status | Response |
|---|---|---|
| No client certificate | N/A | TLS handshake failure — connection refused |
| Missing Bearer token | 401 | `{"error": "missing_token", "message": "Authorization header with Bearer token is required"}` |
| Invalid/expired token | 403 | `{"error": "invalid_token", "message": "..."}` |
| Resource not found | 404 | `{"error": "not_found", "message": "Resource {id} not found"}` |
| Invalid/missing messages | 400 | `{"error": {"message": "messages is required and must be a non-empty array", "type": "invalid_request_error"}}` |
| MCP unknown tool | 200 | `{"jsonrpc": "2.0", "id": ..., "error": {"code": -32602, "message": "Unknown tool: ..."}}` |
| MCP unknown method | 200 | `{"jsonrpc": "2.0", "id": ..., "error": {"code": -32601, "message": "Method not found: ..."}}` |

---

## Notes

- The ngrok URLs are **ephemeral** — they change each time ngrok restarts.
- Tokens expire after **3599 seconds** (~1 hour). Request a new one when expired.
- Both endpoints independently verify the client certificate. A valid cert for one does not bypass the other.
