# How AID authentication works

The scripts do all of this for you. Read this when debugging a failed exchange or integrating a server.

## Contents

- Agent Identity Document
- Proof of possession
- Token exchange
- Agent lifecycle on the server
- Token introspection

## Agent Identity Document

A signed JSON document built fresh for each exchange (canonical JSON: sorted keys, compact):

```json
{
  "aid_version": "1.0",
  "address": "support-agent@default.local",
  "alias": "support-agent",
  "public_key": "-----BEGIN PUBLIC KEY-----\n...",
  "key_algorithm": "Ed25519",
  "fingerprint": "SHA256:abc123...",
  "issued_at": "2030-01-01T00:00:00Z",
  "expires_at": "2030-07-01T00:00:00Z",
  "signature": "base64-ed25519-signature"
}
```

## Proof of possession

The agent signs this string with its Ed25519 private key:

```
aid-token-exchange\n{timestamp}\n{oidc_issuer}
```

`oidc_issuer` is the auth server's OIDC issuer for the tenant (for example `https://auth.example.com/apps/tenant-id`). It comes back in the registration response and is stored locally; if it is missing, the `--auth` URL is used. The server rejects proofs whose timestamp is more than 5 minutes off.

## Token exchange

```
POST {token_endpoint}
Content-Type: application/x-www-form-urlencoded

grant_type=urn%3Aaid%3Aagent-identity
&agent_identity={base64url-identity-document}
&proof={base64url-signed-proof}
```

`token_endpoint` is read from the stored registration (the server returns it at registration or approval), falling back to `{auth_url}/oauth/token`. The response is a standard OAuth 2.0 token response with an RS256 JWT, verifiable against the auth server's JWKS. With `--credential-type api_key` the server issues an opaque API key instead.

## Agent lifecycle on the server

| Status | Can get tokens? | Introspection |
|--------|----------------|---------------|
| `pending` | No | `active: false` |
| `active` | Yes | `active: true` |
| `suspended` | No (403) | `active: false, reason: agent_suspended` |
| `deleted` | No | `active: false, reason: agent_not_found` |

Admins suspend and reactivate with `POST /agent_registrations/:id/suspend` and `POST /agent_registrations/:id/reactivate`.

## Token introspection

APIs can check an agent token in real time, which catches a suspended agent before its token expires:

```
POST /:tenant/oauth/introspect
token=eyJhbGciOiJSUz...
```

The response carries `active: true|false` and the agent's details.
