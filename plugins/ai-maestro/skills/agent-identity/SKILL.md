---
name: agent-identity
description: Authenticate AI agents with auth servers using the Agent Identity (AID) protocol. Supports Ed25519 identity documents, proof of possession, OAuth 2.0 token exchange, and scoped JWT tokens. Works with any AI agent that can execute shell commands.
license: MIT
compatibility: Requires curl, jq, openssl, and base64 CLI tools. macOS and Linux supported. Scripts are POSIX-compatible bash.
metadata:
  version: "0.1.0"
  homepage: "https://agentids.org"
  repository: "https://github.com/agentmessaging/agent-identity"
---

# Agent Identity (AID) Protocol

Authenticate AI agents with auth servers using cryptographic identity documents and proof of possession.

## When to use this skill

Use this skill when the user or task requires:
- Registering an agent's identity with an auth server
- Obtaining JWT tokens for API access via token exchange
- Checking an agent's AID registration status
- Setting up agent-to-server authentication
- Configuring scoped permissions for agent API access

## Prerequisites

AID builds on AMP (Agent Messaging Protocol). The agent must be initialized with AMP first:

```bash
# Ensure AMP identity exists
amp-identity.sh
# If not initialized:
amp-init.sh --auto
```

The agent's AMP Ed25519 keypair is reused for AID authentication.

## Quick Start

```bash
# 1. Register with an auth server (one-time)
aid-register.sh --server https://api.example.com --tenant acme --api-key pk_live_xxx

# 2. Get a JWT token
TOKEN=$(aid-token.sh --server https://api.example.com)

# 3. Use it for API calls
curl -H "Authorization: Bearer $TOKEN" \
     -H "X-Api-Key: pk_live_xxx" \
     https://api.example.com/users
```

## Installation

### For Claude Code (skill)

```bash
npx skills add agentmessaging/agent-identity
```

### Manual

Clone the repo and add `scripts/` to your PATH:

```bash
git clone https://github.com/agentmessaging/agent-identity.git ~/agent-identity
export PATH="$HOME/agent-identity/scripts:$PATH"
```

## Commands Reference

### aid-register.sh — Register Agent Identity

Registers the agent's public key and identity with an auth server's OIDC endpoint.

```bash
aid-register.sh --server https://api.example.com --tenant acme --api-key pk_live_xxx
aid-register.sh -s https://api.example.com -t acme -k pk_live_xxx
aid-register.sh --server https://api.example.com --tenant acme --api-key pk_live_xxx --scopes "read:users write:users"
```

**Parameters:**
- `--server, -s` — Auth server base URL (required)
- `--tenant, -t` — Tenant/company identifier (required)
- `--api-key, -k` — API key for the tenant (required)
- `--scopes` — Space-separated list of requested scopes (optional)

**What it does:**
1. Reads the agent's AMP public key and identity
2. Creates an Agent Identity Document (signed JSON)
3. POSTs the registration to the server's agent registration endpoint
4. Stores the registration locally for future token exchanges

### aid-token.sh — Exchange Identity for JWT Token

Performs the OAuth 2.0 token exchange using `grant_type=urn:aid:agent-identity`.

```bash
# Get a token (uses stored registration)
aid-token.sh --server https://api.example.com

# Get a token with specific scopes
aid-token.sh --server https://api.example.com --scopes "read:users"

# Output just the token (for scripting)
TOKEN=$(aid-token.sh --server https://api.example.com --quiet)
```

**Parameters:**
- `--server, -s` — Auth server base URL (required)
- `--scopes` — Request specific scopes (optional, defaults to registered scopes)
- `--quiet, -q` — Output only the token string (for variable assignment)

**What it does:**
1. Builds a fresh Agent Identity Document with current timestamp
2. Creates a Proof of Possession (`aid-token-exchange\n{timestamp}\n{auth_issuer}`)
3. Signs the proof with the agent's Ed25519 private key
4. POSTs to the OIDC token endpoint with `grant_type=urn:aid:agent-identity`
5. Returns the JWT access token

**Token details:**
- RS256 JWT signed by the auth server's company RSA key
- Contains `token_type: "agent"`, `sub: "agent:{uuid}"`
- Short-lived (typically 15-60 minutes)
- Scoped permissions based on agent registration

### aid-status.sh — Check Registration Status

```bash
aid-status.sh                              # Show all registrations
aid-status.sh --server https://api.example.com  # Check specific server
aid-status.sh --json                       # JSON output
```

## How AID Authentication Works

### Step 1: Agent Identity Document

A signed JSON document proving the agent's identity:

```json
{
  "aid_version": "0.1",
  "address": "my-agent@org.aimaestro.local",
  "public_key": "MCowBQYDK2VwAyEA...",
  "fingerprint": "SHA256:abc123...",
  "issued_at": "2026-03-23T00:00:00Z",
  "expires_at": "2026-03-23T01:00:00Z",
  "signature": "base64-ed25519-signature"
}
```

### Step 2: Proof of Possession

The agent signs a challenge proving it holds the private key:

```
aid-token-exchange\n{timestamp}\n{auth_issuer}
```

### Step 3: Token Exchange

```
POST /oauth/token
grant_type=urn:aid:agent-identity
agent_identity={base64-identity-document}
proof={base64-signed-proof}
```

### Step 4: Use the JWT

The server returns a standard OAuth 2.0 response with a JWT access token.

## Natural Language Examples

Agents should map these user intents to the appropriate commands:

- "Register with the API" → `aid-register.sh --server <url> --tenant <t> --api-key <k>`
- "Get me an API token" → `aid-token.sh --server <url>`
- "Check my registrations" → `aid-status.sh`
- "Authenticate with the auth server" → `aid-token.sh --server <url>`
- "What servers am I registered with?" → `aid-status.sh`

## Security

- **Ed25519 signatures** — identity documents are cryptographically signed
- **Proof of possession** — agents prove key ownership at every token exchange
- **Short-lived tokens** — JWTs expire quickly, limiting blast radius
- **No shared secrets** — private keys never leave the agent
- **Scoped access** — tokens carry only the permissions the agent needs
- **Fingerprint binding** — server verifies the agent's key fingerprint matches registration

## Troubleshooting

| Problem | Solution |
|---------|----------|
| "AMP not initialized" | Run `amp-init.sh --auto` first |
| "Not registered" | Run `aid-register.sh` with server details |
| "Proof expired" | Clock skew >5 minutes; sync system clock |
| "Invalid signature" | Agent identity may be corrupted; re-register |
| "Fingerprint mismatch" | Agent key changed since registration; re-register |
| "Scope not allowed" | Request only scopes granted during registration |

## Protocol Reference

Full specification: https://agentids.org
GitHub: https://github.com/agentmessaging/agent-identity
