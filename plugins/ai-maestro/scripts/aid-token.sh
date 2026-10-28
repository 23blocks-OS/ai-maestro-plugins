#!/bin/bash
# =============================================================================
# AID Token - Agent Identity
# =============================================================================
#
# Request an API token from a 23blocks Auth server using Agent Identity.
# The agent presents its Agent Identity + proof of possession and receives
# an RS256 JWT that works with any 23blocks API (or any JWT-validating API).
#
# Usage:
#   aid-token --auth https://auth.23blocks.com/acme
#   aid-token --auth https://auth.23blocks.com/acme --scope "files:read files:write"
#   aid-token --auth https://auth.23blocks.com/acme --json
#
# Prerequisites:
#   - Agent identity initialized (aid-init --auto)
#   - Agent registered with the auth server (aid-register)
#
# =============================================================================

set -e

# Source AID helper for identity, keys, and signing
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/aid-helper.sh"

# =============================================================================
# Arguments
# =============================================================================

ORIG_ARGS=("$@")
WAIT_SECONDS=0
AUTH_URL=""
RESOURCE_URL=""
AUDIENCE_URL=""
API_KEY=""
SCOPE=""
CREDENTIAL_TYPE=""
OUTPUT_FORMAT="text"
NO_CACHE=false
QUIET=false

show_help() {
    echo "Usage: aid-token (--auth <url> | --resource <url>) [options]"
    echo ""
    echo "Request an API token from a 23blocks Auth server using Agent Identity."
    echo ""
    echo "One of --auth or --resource is required:"
    echo "  --auth, -a URL          Auth server URL (e.g., https://auth.23blocks.com/acme)"
    echo "  --resource, -r URL      Protected resource URL — auth server is discovered via RFC 9728"
    echo ""
    echo "Options:"
    echo "  --api-key, -k KEY       API key (X-Api-Key header)"
    echo "  --scope, -s SCOPES      Space-separated scopes (default: all registered scopes)"
    echo "  --credential-type, -c TYPE  Credential format: access_token (JWT, default) or api_key (opaque)"
    echo "  --json, -j              Output as JSON"
    echo "  --no-cache              Skip token cache, always request new token"
    echo "  --quiet, -q             Output only the access token (for piping)"
    echo "  --audience URL          The service the token is for (RFC 8707 resource). The token's aud is then"
    echo "                          exactly this service. It must be registered at the auth server."
    echo "  --wait SECONDS          While the registration is waiting for approval, ask again until it is"
    echo "                          approved or SECONDS pass (default: do not wait). Exit 75 if still pending."
    echo "  --help, -h              Show this help"
    echo ""
    echo "Examples:"
    echo "  # Get token with all registered scopes"
    echo "  aid-token --auth https://auth.23blocks.com/acme"
    echo ""
    echo "  # Get token with specific scopes"
    echo "  aid-token -a https://auth.23blocks.com/acme -s 'files:read files:write'"
    echo ""
    echo "  # Get just the token string (for scripts)"
    echo "  TOKEN=\$(aid-token -a https://auth.23blocks.com/acme -q)"
    echo "  curl -H \"Authorization: Bearer \$TOKEN\" https://files.23blocks.com/..."
}

while [[ $# -gt 0 ]]; do
    case $1 in
        --auth|-a)
            AUTH_URL="$2"
            shift 2
            ;;
        --resource|-r)
            RESOURCE_URL="$2"
            shift 2
            ;;
        --audience)
            AUDIENCE_URL="$2"
            shift 2
            ;;
        --wait)
            WAIT_SECONDS="$2"
            shift 2
            ;;
        --api-key|-k)
            API_KEY="$2"
            shift 2
            ;;
        --scope|-s)
            SCOPE="$2"
            shift 2
            ;;
        --credential-type|-c)
            CREDENTIAL_TYPE="$2"
            shift 2
            ;;
        --json|-j)
            OUTPUT_FORMAT="json"
            shift
            ;;
        --no-cache)
            NO_CACHE=true
            shift
            ;;
        --quiet|-q)
            OUTPUT_FORMAT="quiet"
            shift
            ;;
        --help|-h)
            show_help
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            echo "Run 'aid-token --help' for usage." >&2
            exit 1
            ;;
    esac
done

if [ -z "$AUTH_URL" ] && [ -z "$RESOURCE_URL" ]; then
    echo "Error: one of --auth or --resource is required" >&2
    echo "Run 'aid-token --help' for usage." >&2
    exit 1
fi

# Validate --credential-type value if provided
if [ -n "$CREDENTIAL_TYPE" ] && [ "$CREDENTIAL_TYPE" != "access_token" ] && [ "$CREDENTIAL_TYPE" != "api_key" ]; then
    echo "Error: --credential-type must be 'access_token' or 'api_key', got '${CREDENTIAL_TYPE}'" >&2
    exit 1
fi

# Resolve --resource into AUTH_URL via RFC 9728 / RFC 8414 discovery
if [ -z "$AUTH_URL" ]; then
    AUTH_URL=$(discover_from_resource "$RESOURCE_URL" 2>/dev/null | jq -r '.auth_server // empty')
    if [ -z "$AUTH_URL" ]; then
        echo "Error: failed to discover an AID-enabled auth server from ${RESOURCE_URL}" >&2
        echo "  Try 'aid-discover --resource ${RESOURCE_URL}' for details." >&2
        exit 1
    fi
fi

# =============================================================================
# Load Agent Identity
# =============================================================================

if ! is_initialized; then
    echo "Error: Agent identity not initialized." >&2
    echo "Run: aid-init --auto" >&2
    exit 1
fi

load_config
require_openssl

PRIVATE_KEY="${AMP_KEYS_DIR}/private.pem"
PUBLIC_KEY="${AMP_KEYS_DIR}/public.pem"

if [ ! -f "$PRIVATE_KEY" ] || [ ! -f "$PUBLIC_KEY" ]; then
    echo "Error: Agent keys not found at ${AMP_KEYS_DIR}/" >&2
    exit 1
fi

# =============================================================================
# Token Cache
# =============================================================================

AID_CACHE_DIR="${AMP_DIR}/tokens"
mkdir -p "$AID_CACHE_DIR"
chmod 700 "$AID_CACHE_DIR" 2>/dev/null || true

# Derive cache key from auth URL + credential_type + audience (so api_key and access_token
# requests, or tokens meant for different services, never collide on disk).
cache_key_for_auth() {
    local ct="${CREDENTIAL_TYPE:-access_token}"
    echo "${AUTH_URL}|${ct}|${AUDIENCE_URL}" | shasum -a 256 | cut -c1-16
}

check_cache() {
    local cache_file="${AID_CACHE_DIR}/$(cache_key_for_auth).json"

    if [ ! -f "$cache_file" ]; then
        return 1
    fi

    local expires_at
    expires_at=$(jq -r '.expires_at // 0' "$cache_file" 2>/dev/null)
    local now
    now=$(date +%s)

    # Check if token is still valid (with 60-second buffer)
    if [ "$expires_at" -gt $((now + 60)) ] 2>/dev/null; then
        # Check if scope matches (if specific scope requested)
        if [ -n "$SCOPE" ]; then
            local cached_scope
            cached_scope=$(jq -r '.scope // ""' "$cache_file" 2>/dev/null)
            if [ "$cached_scope" != "$SCOPE" ]; then
                return 1
            fi
        fi
        # Check if credential_type matches (api_key tokens are never valid as access_token, vice versa)
        if [ -n "$CREDENTIAL_TYPE" ]; then
            local cached_ct
            cached_ct=$(jq -r '.credential_type // "access_token"' "$cache_file" 2>/dev/null)
            if [ "$cached_ct" != "$CREDENTIAL_TYPE" ]; then
                return 1
            fi
        fi
        cat "$cache_file"
        return 0
    fi

    # Expired — clean up
    rm -f "$cache_file"
    return 1
}

save_cache() {
    local response="$1"
    local cache_file="${AID_CACHE_DIR}/$(cache_key_for_auth).json"

    local expires_in
    expires_in=$(echo "$response" | jq -r '.expires_in // 3600')
    local expires_at
    expires_at=$(( $(date +%s) + expires_in ))

    # The auth URL goes in as a jq argument, never spliced into the program text.
    # The file is created 0600 before the token is written to it.
    ( umask 077; : > "$cache_file" )
    echo "$response" | jq --arg ea "$expires_at" --arg au "$AUTH_URL" \
        '. + {expires_at: ($ea | tonumber), auth_server: $au}' \
        > "$cache_file"
    chmod 600 "$cache_file"
}

# =============================================================================
# Check cache first
# =============================================================================

if [ "$NO_CACHE" = false ]; then
    cached_response=$(check_cache 2>/dev/null) || true
    if [ -n "$cached_response" ]; then
        case "$OUTPUT_FORMAT" in
            json)
                echo "$cached_response"
                ;;
            quiet)
                echo "$cached_response" | jq -r '.access_token'
                ;;
            *)
                echo "✅ Token (cached)"
                echo ""
                echo "  Auth:       ${AUTH_URL}"
                echo "  Type:       $(echo "$cached_response" | jq -r '.credential_type // "access_token"')"
                echo "  Scope:      $(echo "$cached_response" | jq -r '.scope // "all"')"
                echo "  Expires in: $(echo "$cached_response" | jq -r '.expires_in // "?"')s"
                echo "  Agent:      $(echo "$cached_response" | jq -r '.agent_address // "?"')"
                echo ""
                echo "  Credential:"
                echo "  $(echo "$cached_response" | jq -r '.access_token')"
                ;;
        esac
        exit 0
    fi
fi

# =============================================================================
# Build Agent Identity
# =============================================================================

PUBLIC_KEY_PEM=$(cat "$PUBLIC_KEY")

AGENT_IDENTITY=$(jq -n \
    --arg version "1.0" \
    --arg address "$AMP_ADDRESS" \
    --arg alias "$AMP_AGENT_NAME" \
    --arg public_key "$PUBLIC_KEY_PEM" \
    --arg key_algorithm "Ed25519" \
    --arg fingerprint "$AMP_FINGERPRINT" \
    --arg issued_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg expires_at "$(date -u -v+6m +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d '+6 months' +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '{
        aid_version: $version,
        address: $address,
        alias: $alias,
        public_key: $public_key,
        key_algorithm: $key_algorithm,
        fingerprint: $fingerprint,
        issued_at: $issued_at,
        expires_at: $expires_at
    }' | jq -cS .)

# Sign the canonical JSON (sorted keys, compact, no whitespace)
IDENTITY_SIGNATURE=$(sign_message "$AGENT_IDENTITY")
if [ -z "$IDENTITY_SIGNATURE" ]; then
    echo "Error: Failed to sign Agent Identity" >&2
    exit 1
fi

# Add signature to identity (use urlsafe base64)
SIGNED_IDENTITY=$(echo "$AGENT_IDENTITY" | jq --arg sig "$IDENTITY_SIGNATURE" '. + {signature: $sig}')

# Base64url encode the signed identity
AGENT_IDENTITY_B64=$(echo -n "$SIGNED_IDENTITY" | base64 | tr '+/' '-_' | tr -d '=\n')

# =============================================================================
# Resolve registration file (needed for token_endpoint and oidc_issuer)
# =============================================================================

AID_REG_DIR="${AMP_DIR}/api_registrations"
AUTH_HOST=$(echo "$AUTH_URL" | sed -E 's|https?://||' | cut -d/ -f1)
REG_FILE="${AID_REG_DIR}/${AUTH_HOST}.json"

# =============================================================================
# Build Proof of Possession
# =============================================================================

TIMESTAMP=$(date +%s)

# The issuer for the proof: check registration file for oidc_issuer, fall back to AUTH_URL
AUTH_ISSUER=""
if [ -f "$REG_FILE" ]; then
    AUTH_ISSUER=$(jq -r '.oidc_issuer // empty' "$REG_FILE" 2>/dev/null)
fi
if [ -z "$AUTH_ISSUER" ]; then
    AUTH_ISSUER="$AUTH_URL"
fi

SIGN_INPUT="aid-token-exchange
${TIMESTAMP}
${AUTH_ISSUER}"

# Sign the proof
PROOF_SIGNATURE_B64=$(sign_message "$SIGN_INPUT")
if [ -z "$PROOF_SIGNATURE_B64" ]; then
    echo "Error: Failed to sign proof of possession" >&2
    exit 1
fi

# Proof = signature bytes + timestamp string, then base64url encode
# Decode signature from base64, append timestamp, re-encode as base64url
PROOF_B64=$(
    {
        echo -n "$PROOF_SIGNATURE_B64" | base64 -d
        echo -n "$TIMESTAMP"
    } | base64 | tr '+/' '-_' | tr -d '=\n'
)

# =============================================================================
# Token Request
# =============================================================================

# Resolve the token endpoint URL from registration file, fall back to AUTH_URL
TOKEN_URL=""
if [ -f "$REG_FILE" ]; then
    TOKEN_URL=$(jq -r '.token_endpoint // empty' "$REG_FILE" 2>/dev/null)
fi
if [ -z "$TOKEN_URL" ]; then
    TOKEN_URL="${AUTH_URL}/oauth/token"
fi

# Build form body
FORM_DATA="grant_type=urn%3Aaid%3Aagent-identity&agent_identity=${AGENT_IDENTITY_B64}&proof=${PROOF_B64}"
if [ -n "$SCOPE" ]; then
    ENCODED_SCOPE=$(echo -n "$SCOPE" | jq -sRr @uri)
    FORM_DATA="${FORM_DATA}&scope=${ENCODED_SCOPE}"
fi
if [ -n "$CREDENTIAL_TYPE" ]; then
    FORM_DATA="${FORM_DATA}&requested_credential_type=${CREDENTIAL_TYPE}"
fi
if [ -n "$AUDIENCE_URL" ]; then
    ENCODED_AUDIENCE=$(echo -n "$AUDIENCE_URL" | jq -sRr @uri)
    FORM_DATA="${FORM_DATA}&resource=${ENCODED_AUDIENCE}"
fi

# Make the request
HTTP_RESPONSE=$(curl -s -w "\n%{http_code}" \
    -X POST "$TOKEN_URL" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    ${API_KEY:+-H "X-Api-Key: ${API_KEY}"} \
    -d "$FORM_DATA" \
    --connect-timeout 10 \
    --max-time 30 \
    2>/dev/null) || {
    echo "Error: Failed to connect to auth server at ${TOKEN_URL}" >&2
    exit 1
}

# Split response body and HTTP status
HTTP_BODY=$(echo "$HTTP_RESPONSE" | sed '$d')
HTTP_STATUS=$(echo "$HTTP_RESPONSE" | tail -1)

# =============================================================================
# Handle Response
# =============================================================================

if [ "$HTTP_STATUS" = "200" ]; then
    # Cache the successful response
    save_cache "$HTTP_BODY"

    case "$OUTPUT_FORMAT" in
        json)
            echo "$HTTP_BODY" | jq --arg auth "$AUTH_URL" '. + {auth_server: $auth}'
            ;;
        quiet)
            echo "$HTTP_BODY" | jq -r '.access_token'
            ;;
        *)
            echo "✅ Token obtained"
            echo ""
            echo "  Auth:       ${AUTH_URL}"
            echo "  Scope:      $(echo "$HTTP_BODY" | jq -r '.scope // "all"')"
            echo "  Expires in: $(echo "$HTTP_BODY" | jq -r '.expires_in // "?"')s"
            echo "  Agent:      $(echo "$HTTP_BODY" | jq -r '.agent_address // "?"')"
            echo ""
            echo "  Access Token:"
            echo "  $(echo "$HTTP_BODY" | jq -r '.access_token')"
            ;;
    esac
    exit 0
else
    # Error response
    ERROR=$(echo "$HTTP_BODY" | jq -r '.error // "unknown_error"' 2>/dev/null)
    ERROR_DESC=$(echo "$HTTP_BODY" | jq -r '.error_description // "Unknown error"' 2>/dev/null)

    if [ "$OUTPUT_FORMAT" = "json" ]; then
        echo "$HTTP_BODY" | jq --arg status "$HTTP_STATUS" '. + {http_status: ($status | tonumber)}'
    elif [ "$OUTPUT_FORMAT" = "quiet" ]; then
        echo "Error: ${ERROR}" >&2
    else
        echo "❌ Token request failed (HTTP ${HTTP_STATUS})" >&2
        echo "" >&2
        echo "  Error:       ${ERROR}" >&2
        echo "  Description: ${ERROR_DESC}" >&2
        echo "" >&2

        case "$ERROR" in
            authorization_pending)
                echo "  → Not approved yet. This is not a failure: ask again after a few seconds," >&2
                echo "    or run with --wait SECONDS. Exit status 75 means 'try again later'." >&2
                ;;
            access_denied)
                echo "  → The registration was rejected or the agent is disabled. Do not retry;" >&2
                echo "    ask the tenant administrator." >&2
                ;;
            invalid_grant)
                echo "  → Either the Agent Identity signature is invalid or expired (check that your keys" >&2
                echo "    match the registration), or the agent has no role, or its role has no permissions." >&2
                echo "    In the second case retrying does not help: ask the tenant administrator." >&2
                ;;
            invalid_target)
                echo "  → The --audience service is not registered at the auth server, is disabled," >&2
                echo "    or this agent's role may not use it. Ask the administrator to register it." >&2
                ;;
            invalid_proof)
                echo "  → Proof of possession failed. Check system clock sync." >&2
                ;;
            agent_not_registered)
                echo "  → This agent is not registered with the auth server." >&2
                echo "    Run: aid-register --auth ${AUTH_URL}" >&2
                ;;
            invalid_scope)
                echo "  → Requested scopes exceed your permissions." >&2
                echo "    Try without --scope to get all available scopes." >&2
                ;;
            agent_suspended)
                echo "  → This agent has been suspended. Contact the admin." >&2
                ;;
        esac
    fi

    # Waiting for approval is not a failure: poll, or exit 75 (EX_TEMPFAIL) so a caller can tell it from an error.
    if [ "$ERROR" = "authorization_pending" ] || [ "$ERROR" = "slow_down" ]; then
        if [ "$WAIT_SECONDS" -gt 0 ] 2>/dev/null; then
            INTERVAL=$(echo "$HTTP_BODY" | jq -r '.interval // 5' 2>/dev/null)
            [ "$ERROR" = "slow_down" ] && INTERVAL=$((INTERVAL + 5))
            [ "$INTERVAL" -ge 1 ] 2>/dev/null || INTERVAL=5
            if [ "$WAIT_SECONDS" -gt "$INTERVAL" ]; then
                sleep "$INTERVAL"
                # Ask again with a fresh proof (it carries a timestamp): re-run with the time left.
                ARGS=(); skip=0
                for a in "${ORIG_ARGS[@]}"; do
                    if [ "$skip" = 1 ]; then skip=0; continue; fi
                    if [ "$a" = "--wait" ]; then skip=1; continue; fi
                    ARGS+=("$a")
                done
                exec "$0" "${ARGS[@]}" --wait $((WAIT_SECONDS - INTERVAL))
            fi
        fi
        exit 75
    fi
    exit 1
fi
