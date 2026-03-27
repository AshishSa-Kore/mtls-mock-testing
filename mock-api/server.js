// mock-api/server.js
const express = require("express");
const crypto = require("crypto");
const jwt = require("jsonwebtoken");
const jwksClient = require("jwks-rsa");

const app = express();
app.use(express.json());
const PORT = 3000;

const JWKS_URI = process.env.OAUTH2_JWKS_URI || "http://oauth2:8080/default/jwks";
const ISSUER = process.env.OAUTH2_ISSUER || "http://oauth2:8080/default";

// JWKS client to fetch signing keys from the OAuth2 server
const client = jwksClient({ jwksUri: JWKS_URI });

function getKey(header, callback) {
  client.getSigningKey(header.kid, (err, key) => {
    if (err) return callback(err);
    callback(null, key.getPublicKey());
  });
}

// Token validation middleware
function validateToken(req, res, next) {
  console.log('headers received are ', req.headers)
  const authHeader = req.headers.authorization;

  if (!authHeader || !authHeader.startsWith("Bearer ")) {
    return res.status(401).json({
      error: "missing_token",
      message: "Authorization header with Bearer token is required",
    });
  }

  const token = authHeader.split(" ")[1];

  jwt.verify(token, getKey, { issuer: ISSUER }, (err, decoded) => {
    if (err) {
      return res.status(403).json({
        error: "invalid_token",
        message: err.message,
      });
    }
    req.tokenPayload = decoded;
    next();
  });
}

// --- Routes ---

// Public health check (no auth)
app.get("/api/health", (req, res) => {
  res.json({ status: "ok", service: "mock-api" });
});

// Protected endpoints
app.get("/api/resources", validateToken, (req, res) => {
  res.json({
    data: [
      { id: 1, name: "Resource A", status: "active" },
      { id: 2, name: "Resource B", status: "active" },
      { id: 3, name: "Resource C", status: "inactive" },
    ],
    meta: {
      client_id: req.tokenPayload.client_id,
      scope: req.tokenPayload.scope,
      issued_at: new Date(req.tokenPayload.iat * 1000).toISOString(),
      expires_at: new Date(req.tokenPayload.exp * 1000).toISOString(),
    },
  });
});

app.get("/api/resources/:id", validateToken, (req, res) => {
  const id = parseInt(req.params.id);
  const resources = {
    1: { id: 1, name: "Resource A", status: "active", detail: "Full details for A" },
    2: { id: 2, name: "Resource B", status: "active", detail: "Full details for B" },
    3: { id: 3, name: "Resource C", status: "inactive", detail: "Full details for C" },
  };

  if (!resources[id]) {
    return res.status(404).json({ error: "not_found", message: `Resource ${id} not found` });
  }

  res.json({
    data: resources[id],
    meta: {
      client_id: req.tokenPayload.client_id,
    },
  });
});

// OpenAI-compatible chat completion endpoint (echoes user message)
app.post("/api/mock-model", validateToken, (req, res) => {
  console.log("[mock-model] headers:", JSON.stringify(req.headers));
  console.log("[mock-model] body:", JSON.stringify(req.body));
  const { model, messages } = req.body;

  if (!messages || !Array.isArray(messages) || messages.length === 0) {
    return res.status(400).json({
      error: {
        message: "messages is required and must be a non-empty array",
        type: "invalid_request_error",
        param: "messages",
        code: null,
      },
    });
  }

  const lastUserMessage = [...messages].reverse().find((m) => m.role === "user");
  const echoContent = lastUserMessage
    ? lastUserMessage.content
    : "";

  const completionId = `chatcmpl-${crypto.randomUUID()}`;
  const created = Math.floor(Date.now() / 1000);

  res.json({
    id: completionId,
    object: "chat.completion",
    created,
    model: model || "mock-echo-1",
    choices: [
      {
        index: 0,
        message: {
          role: "assistant",
          content: echoContent,
        },
        finish_reason: "stop",
      },
    ],
    usage: {
      prompt_tokens: 0,
      completion_tokens: 0,
      total_tokens: 0,
    },
  });
});

// --- MCP Server (plain JSON-RPC over HTTP) ---

const MCP_SERVER_INFO = {
  name: "mock-mcp-server",
  version: "1.0.0",
};

const MCP_TOOLS = [
  {
    name: "process_data",
    description: "Processes input data and returns a success status",
    inputSchema: {
      type: "object",
      properties: {
        name: { type: "string", description: "Name of the data item" },
        value: { type: "string", description: "Value to process" },
        category: { type: "string", description: "Category of the data (e.g. metrics, logs, events)" },
        priority: { type: "number", description: "Priority level (1-5)" },
      },
      required: ["name", "value", "category", "priority"],
    },
  },
];

function handleToolCall(name, args) {
  if (name === "process_data") {
    return {
      content: [
        {
          type: "text",
          text: JSON.stringify({
            status: "success",
            processed: args,
            timestamp: new Date().toISOString(),
            message: `Successfully processed '${args.name}' in category '${args.category}'`,
          }, null, 2),
        },
      ],
    };
  }
  return null;
}

function jsonrpc(id, result) {
  return { jsonrpc: "2.0", id, result };
}

function jsonrpcError(id, code, message) {
  return { jsonrpc: "2.0", id, error: { code, message } };
}

app.post("/mcp", (req, res) => {
  console.log("[mcp] request:", JSON.stringify({ method: req.body?.method, id: req.body?.id, headers: req.headers }));
  const { jsonrpc: version, id, method, params } = req.body;

  if (version !== "2.0") {
    return res.json(jsonrpcError(id || null, -32600, "Invalid Request: expected jsonrpc 2.0"));
  }

  // Notifications (no id) — acknowledge silently
  if (id === undefined || id === null) {
    return res.status(202).end();
  }

  switch (method) {
    case "initialize":
      return res.json(jsonrpc(id, {
        protocolVersion: "2025-03-26",
        capabilities: { tools: {} },
        serverInfo: MCP_SERVER_INFO,
      }));

    case "tools/list":
      return res.json(jsonrpc(id, { tools: MCP_TOOLS }));

    case "tools/call": {
      const toolName = params?.name;
      const args = params?.arguments || {};
      const result = handleToolCall(toolName, args);
      if (!result) {
        return res.json(jsonrpcError(id, -32602, `Unknown tool: ${toolName}`));
      }
      return res.json(jsonrpc(id, result));
    }

    default:
      return res.json(jsonrpcError(id, -32601, `Method not found: ${method}`));
  }
});

app.listen(PORT, () => {
  console.log(`Mock API + MCP server running on port ${PORT}`);
  console.log(`JWKS URI: ${JWKS_URI}`);
  console.log(`Expected issuer: ${ISSUER}`);
  console.log(`MCP endpoint: /mcp`);
});
