---
name: agent-identity
description: Authenticate AI agents with auth servers using the Agent Identity (AID) protocol. Supports Ed25519 identity documents, proof of possession, OAuth 2.0 token exchange, and scoped JWT tokens. Self-contained — works independently without other protocols.
license: MIT
compatibility: Requires curl, jq, openssl (3.x for Ed25519), and base64 CLI tools. macOS and Linux supported.
metadata:
  version: "0.3.0"
  homepage: "https://agentids.org"
  repository: "https://github.com/agentmessaging/agent-identity"
---

# Agent Identity (AID) Protocol

Authenticate AI agents with auth servers using cryptographic identity documents and proof of possession. AID is self-contained — no other protocols required.

## When to use this skill

Use this skill when the user or task requires:
- Initializing an agent's Ed25519 identity
- Requesting registration with an auth server (agent-initiated)
- Registering an agent's identity with an auth server (admin-initiated)
- Checking the status of a pending registration request
- Obtaining JWT tokens for API access via token exchange
- Checking an agent's AID registration status
- Setting up agent-to-server authentication
- Configuring scoped permissions for agent API access

## Quick Start

```bash
# 1. Initialize agent identity (one-time)
aid-init.sh --auto

# 2a. Request registration (agent-initiated, no admin token needed)
aid-request.sh --auth https://auth.23blocks.com/acme
# ... wait for admin approval ...
aid-request.sh --auth https://auth.23blocks.com/acme --poll

# 2b. Or: admin-initiated registration (requires admin token)
aid-register.sh --auth https://auth.23blocks.com/acme \
  --token <ADMIN_JWT> --role-id 2

# 3. Get a JWT token
TOKEN=$(aid-token.sh --auth https://auth.23blocks.com/acme --quiet)

# 4. Use it for API calls
curl -H "Authorization: Bearer $TOKEN" https://api.example.com/resource
```

## Installation

### For Claude Code (skill)

```bash
npx skills add agentmessaging/agent-identity
```

### Quick Install

```bash
curl -fsSL https://raw.githubusercontent.com/agentmessaging/agent-identity/main/install.sh | bash
```

### Manual

```bash
git clone https://github.com/agentmessaging/agent-identity.git ~/agent-identity
export PATH="$HOME/agent-identity/scripts:$PATH"
```

## Commands Reference

### aid-init.sh — Initialize Agent Identity

Create an Ed25519 keypair and identity for this agent.

```bash
aid-init.sh --auto              # Auto-detect name from environment
aid-init.sh --name my-agent     # Specify agent name
aid-init.sh --name my-agent --force  # Overwrite existing
```

**Parameters:**
- `--auto` — Auto-detect agent name from environment
- `--name, -n` — Specify agent name
- `--force, -f` — Overwrite existing identity

### aid-discover.sh — Discover Auth Server from Resource URL

Walks the RFC 9728 / RFC 8414 discovery chain. Given a protected resource URL, finds the AID-enabled auth server, validates that it advertises `urn:aid:agent-identity`, and emits the registration/token endpoints.

```bash
aid-discover.sh --resource https://api.acme.com               # Human-readable
aid-discover.sh -r https://api.acme.com --json                # Full blob
AUTH=$(aid-discover.sh -r https://api.acme.com --quiet)       # Just the auth URL
```

**Parameters:**
- `--resource, -r` — Protected resource URL (required)
- `--json, -j` — Output the full discovery blob as JSON
- `--quiet, -q` — Output only the discovered auth server URL

`aid-request.sh` and `aid-token.sh` also accept `--resource` directly:

```bash
aid-request.sh --resource https://api.acme.com
TOKEN=$(aid-token.sh --resource https://api.acme.com --quiet)
```

### aid-request.sh — Request Registration (Agent-Initiated)

Request registration without an admin token. Creates a `pending` registration that an admin must approve.

```bash
aid-request.sh --auth https://auth.23blocks.com/acme
aid-request.sh --auth https://auth.23blocks.com/acme --poll
```

**Parameters:**
- `--auth, -a` — Auth server URL (required)
- `--api-key, -k` — API key (X-Api-Key header)
- `--name, -n` — Display name (default: agent name)
- `--description, -d` — Why this agent needs access
- `--poll, -p` — Check status of a pending request

**What it does:**
1. Reads the agent's Ed25519 public key and identity
2. POSTs to `/agent_registrations/request` (no auth token required)
3. Server creates a `pending` registration
4. Stores the registration ID locally for polling
5. With `--poll`, checks whether the admin has approved the request

### aid-register.sh — Register with Auth Server (Admin-Initiated)

One-time registration linking the agent's Ed25519 identity to a tenant with a specific role. Requires an admin JWT.

```bash
aid-register.sh --auth https://auth.23blocks.com/acme \
  --token <ADMIN_JWT> --role-id 2
```

**Parameters:**
- `--auth, -a` — Auth server URL (required)
- `--token, -t` — Admin JWT for authorization (required)
- `--role-id, -r` — Role ID to assign (required)
- `--api-key, -k` — API key (X-Api-Key header)
- `--name, -n` — Display name (default: agent name)
- `--description, -d` — Agent description
- `--lifetime, -l` — Token lifetime in seconds (default: 3600)

**What it does:**
1. Reads the agent's Ed25519 public key and identity
2. POSTs the registration to the server's agent registration endpoint
3. Stores the registration locally for future token exchanges

### aid-token.sh — Exchange Identity for JWT Token

Performs the OAuth 2.0 token exchange using `grant_type=urn:aid:agent-identity`.

```bash
# Get a token (uses cache if valid)
aid-token.sh --auth https://auth.23blocks.com/acme

# Get just the token string (for scripting)
TOKEN=$(aid-token.sh --auth https://auth.23blocks.com/acme --quiet)

# Get a token with specific scopes
aid-token.sh --auth https://auth.23blocks.com/acme --scope "files:read files:write"
```

**Parameters:**
- `--auth, -a` — Auth server URL (required, unless `--resource` given)
- `--resource, -r` — Protected resource URL — auth server is discovered via RFC 9728
- `--api-key, -k` — API key (X-Api-Key header)
- `--scope, -s` — Space-separated scopes (optional)
- `--credential-type, -c` — `access_token` (JWT, default) or `api_key` (opaque)
- `--json, -j` — Output as JSON
- `--quiet, -q` — Output only the token string
- `--no-cache` — Skip token cache

**What it does:**
1. Builds a fresh Agent Identity Document with current timestamp (canonical JSON: sorted keys, compact)
2. Creates a Proof of Possession (`aid-token-exchange\n{timestamp}\n{oidc_issuer}`)
3. Signs the proof with the agent's Ed25519 private key
4. POSTs to the token endpoint resolved from the registration file (falls back to `{auth_url}/oauth/token`)
5. Returns the JWT access token (cached for reuse)

### aid-status.sh — Check Identity & Registration Status

```bash
aid-status.sh          # Human-readable output
aid-status.sh --json   # JSON output
```

## How AID Authentication Works

### Step 1: Agent Identity Document

A signed JSON document proving the agent's identity:

```json
{
  "aid_version": "1.0",
  "address": "support-agent@default.local",
  "alias": "support-agent",
  "public_key": "-----BEGIN PUBLIC KEY-----\n...",
  "key_algorithm": "Ed25519",
  "fingerprint": "SHA256:abc123...",
  "issued_at": "2026-03-23T00:00:00Z",
  "expires_at": "2026-09-23T00:00:00Z",
  "signature": "base64-ed25519-signature"
}
```

### Step 2: Proof of Possession

The agent signs a challenge proving it holds the private key:

```
aid-token-exchange\n{timestamp}\n{oidc_issuer}
```

The `oidc_issuer` is the auth server's OIDC issuer URL for the tenant (e.g., `https://auth.example.com/apps/tenant-id`). This is returned in the registration response and stored locally. Falls back to the `--auth` URL if not available.

### Step 3: Token Exchange

```
POST {token_endpoint}
Content-Type: application/x-www-form-urlencoded

grant_type=urn%3Aaid%3Aagent-identity
&agent_identity={base64url-identity-document}
&proof={base64url-signed-proof}
```

The `token_endpoint` is resolved from the registration file (returned by the auth server during registration/approval). Falls back to `{auth_url}/oauth/token` if not stored.

### Step 4: Use the JWT

The server returns a standard OAuth 2.0 response with an RS256 JWT access token. Use it with any API that validates JWTs via the auth server's JWKS endpoint.

## Natural Language Examples

Agents should map these user intents to the appropriate commands:

- "Initialize my identity" -> `aid-init.sh --auto`
- "Request access to the API" -> `aid-request.sh --auth <url>`
- "Register with the API" -> `aid-register.sh --auth <url> --token <jwt> --role-id <id>`
- "Check if I'm approved" -> `aid-request.sh --auth <url> --poll`
- "Get me an API token" -> `aid-token.sh --auth <url>`
- "Check my registrations" -> `aid-status.sh`
- "Authenticate with the auth server" -> `aid-token.sh --auth <url>`

## Security

- **Self-contained** — no external protocol dependencies
- **Ed25519 signatures** — identity documents are cryptographically signed
- **Proof of possession** — agents prove key ownership at every token exchange
- **Human-controlled access** — admin creates roles and registers agents
- **Short-lived tokens** — JWTs expire quickly, limiting blast radius
- **No shared secrets** — private keys never leave the agent
- **Scoped access** — tokens carry only the permissions the agent's role allows

## Interoperability

AID shares the `~/.agent-messaging/agents/` directory with [AMP](https://agentmessaging.org) if both are installed. One identity serves both protocols. Neither requires the other.

## Agent Lifecycle

Agents have 4 lifecycle states controlled by the admin:

| Status | Can get tokens? | Introspection |
|--------|----------------|---------------|
| `pending` | No | `active: false` |
| `active` | Yes | `active: true` |
| `suspended` | No (403) | `active: false, reason: agent_suspended` |
| `deleted` | No | `active: false, reason: agent_not_found` |

Admin commands:
- Suspend: `POST /agent_registrations/:id/suspend`
- Reactivate: `POST /agent_registrations/:id/reactivate`

## Token Introspection

Target APIs can verify agent tokens in real-time:

```
POST /:tenant/oauth/introspect
token=eyJhbGciOiJSUz...
```

Returns `active: true/false` with agent details. Useful for detecting suspended agents before their token expires.

## Troubleshooting

| Problem | Solution |
|---------|----------|
| "Agent identity not initialized" | Run `aid-init.sh --auto` |
| "Not registered" | Run `aid-request.sh` or `aid-register.sh` with auth server details |
| "Registration pending" | Run `aid-request.sh --poll` to check approval status |
| "Proof expired" | Clock skew >5 minutes; sync system clock |
| "Invalid signature" | Agent identity may be corrupted; re-init and re-register |
| "Fingerprint mismatch" | Agent key changed since registration; re-register |
| "Scope not allowed" | Request only scopes granted during registration |
| "Agent suspended" | Admin has suspended this agent; contact admin for reactivation |
| "403 on token exchange" | Agent may be suspended; run `aid-status` to check |

## Protocol Reference

Full specification: https://agentids.org
GitHub: https://github.com/agentmessaging/agent-identity
