#!/bin/bash
# =============================================================================
# AID Request - Agent-Initiated Registration
# =============================================================================
#
# Request registration with an auth server WITHOUT an admin token.
# The agent submits its identity and waits for admin approval.
#
# Flow:
#   1. Agent runs: aid-request --auth <url>
#   2. Server creates a PENDING registration
#   3. Admin reviews and approves (via dashboard or API)
#   4. Agent polls: aid-request --auth <url> --poll
#   5. Once approved, agent can get tokens: aid-token --auth <url>
#
# Usage:
#   aid-request --auth https://auth.23blocks.com/acme
#   aid-request --auth https://auth.23blocks.com/acme --poll
#
# =============================================================================

set -e

# Source AID helper for identity, keys, and signing
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/aid-helper.sh"

# =============================================================================
# Arguments
# =============================================================================

AUTH_URL=""
RESOURCE_URL=""
API_KEY=""
DESCRIPTION=""
AGENT_DISPLAY_NAME=""
POLL_MODE=false

show_help() {
    echo "Usage: aid-request (--auth <url> | --resource <url>) [options]"
    echo ""
    echo "Request registration with an auth server (agent-initiated)."
    echo "No admin token required -- the agent submits its identity and"
    echo "waits for an admin to approve the registration."
    echo ""
    echo "One of --auth or --resource is required:"
    echo "  --auth, -a URL          Auth server URL (e.g., https://auth.23blocks.com/acme)"
    echo "  --resource, -r URL      Protected resource URL — auth server is discovered via RFC 9728"
    echo ""
    echo "Options:"
    echo "  --api-key, -k KEY       API key (X-Api-Key header)"
    echo "  --name, -n NAME         Display name (default: agent name)"
    echo "  --description, -d DESC  Why this agent needs access"
    echo "  --poll, -p              Check status of a pending request"
    echo "  --help, -h              Show this help"
    echo ""
    echo "Examples:"
    echo "  # Request registration"
    echo "  aid-request -a https://auth.23blocks.com/acme"
    echo ""
    echo "  # Request with description"
    echo "  aid-request -a https://auth.23blocks.com/acme \\"
    echo "    -d 'Handles customer support ticket triage'"
    echo ""
    echo "  # Check if request has been approved"
    echo "  aid-request -a https://auth.23blocks.com/acme --poll"
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
        --api-key|-k)
            API_KEY="$2"
            shift 2
            ;;
        --name|-n)
            AGENT_DISPLAY_NAME="$2"
            shift 2
            ;;
        --description|-d)
            DESCRIPTION="$2"
            shift 2
            ;;
        --poll|-p)
            POLL_MODE=true
            shift
            ;;
        --help|-h)
            show_help
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            echo "Run 'aid-request --help' for usage." >&2
            exit 1
            ;;
    esac
done

# Validate required args
if [ -z "$AUTH_URL" ] && [ -z "$RESOURCE_URL" ]; then
    echo "Error: one of --auth or --resource is required" >&2
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

PUBLIC_KEY="${AMP_KEYS_DIR}/public.pem"

if [ ! -f "$PUBLIC_KEY" ]; then
    echo "Error: Public key not found at ${PUBLIC_KEY}" >&2
    exit 1
fi

PUBLIC_KEY_PEM=$(cat "$PUBLIC_KEY")
DISPLAY_NAME="${AGENT_DISPLAY_NAME:-$AMP_AGENT_NAME}"

# =============================================================================
# Registration directory
# =============================================================================

AID_REG_DIR="${AMP_DIR}/api_registrations"
mkdir -p "$AID_REG_DIR"
AUTH_HOST=$(echo "$AUTH_URL" | sed -E 's|https?://||' | cut -d/ -f1)
REG_FILE="${AID_REG_DIR}/${AUTH_HOST}.json"

# =============================================================================
# Poll Mode - Check status of pending request
# =============================================================================

if [ "$POLL_MODE" = true ]; then
    if [ ! -f "$REG_FILE" ]; then
        echo "No pending request found for ${AUTH_URL}" >&2
        echo "Run 'aid-request --auth ${AUTH_URL}' to submit a request." >&2
        exit 1
    fi

    UNIQUE_ID=$(jq -r '.agent_unique_id // empty' "$REG_FILE" 2>/dev/null)
    CURRENT_STATUS=$(jq -r '.status // empty' "$REG_FILE" 2>/dev/null)

    if [ -z "$UNIQUE_ID" ]; then
        echo "Error: No registration ID found in ${REG_FILE}" >&2
        exit 1
    fi

    if [ "$CURRENT_STATUS" = "active" ]; then
        echo "Registration already approved."
        echo ""
        echo "  Get a token with:"
        echo "    aid-token --auth ${AUTH_URL}"
        exit 0
    fi

    # Build proof of possession to authenticate the status check
    require_openssl
    TIMESTAMP=$(date +%s)
    SIGN_INPUT="aid-registration-status\n${TIMESTAMP}\n${AUTH_URL}"
    PROOF_SIG=$(sign_message "$(echo -e "$SIGN_INPUT")")
    PROOF=$(echo -n "${PROOF_SIG}${TIMESTAMP}" | base64 | tr '+/' '-_' | tr -d '=')

    # Build curl headers
    CURL_HEADERS=(
        -H "Content-Type: application/json"
    )
    if [ -n "$API_KEY" ]; then
        CURL_HEADERS+=(-H "X-Api-Key: ${API_KEY}")
    fi

    STATUS_URL="${AUTH_URL}/agent_registrations/${UNIQUE_ID}/status"

    HTTP_RESPONSE=$(curl -s -w "\n%{http_code}" \
        -X POST "$STATUS_URL" \
        "${CURL_HEADERS[@]}" \
        -d "{\"fingerprint\":\"${AMP_FINGERPRINT}\",\"proof\":\"${PROOF}\"}" \
        --connect-timeout 10 \
        --max-time 30 \
        2>/dev/null) || {
        echo "Error: Failed to connect to auth server at ${STATUS_URL}" >&2
        exit 1
    }

    HTTP_BODY=$(echo "$HTTP_RESPONSE" | sed '$d')
    HTTP_STATUS=$(echo "$HTTP_RESPONSE" | tail -1)

    if [ "$HTTP_STATUS" = "200" ]; then
        REG_STATUS=$(echo "$HTTP_BODY" | jq -r '.data.attributes.status // .status // "unknown"' 2>/dev/null)
        POLL_TOKEN_ENDPOINT=$(echo "$HTTP_BODY" | jq -r '.data.attributes.token_endpoint // empty' 2>/dev/null)

        # Update local file with status and token_endpoint
        if [ -n "$POLL_TOKEN_ENDPOINT" ]; then
            jq --arg status "$REG_STATUS" --arg te "$POLL_TOKEN_ENDPOINT" \
                '.status = $status | .token_endpoint = $te' "$REG_FILE" > "${REG_FILE}.tmp" && \
                mv "${REG_FILE}.tmp" "$REG_FILE"
        else
            jq --arg status "$REG_STATUS" '.status = $status' "$REG_FILE" > "${REG_FILE}.tmp" && \
                mv "${REG_FILE}.tmp" "$REG_FILE"
        fi
        chmod 600 "$REG_FILE"

        case "$REG_STATUS" in
            active)
                ROLE_NAME=$(echo "$HTTP_BODY" | jq -r '.data.attributes.role_name // .role_name // "unknown"' 2>/dev/null)
                echo "Registration APPROVED"
                echo ""
                echo "  Status:  ${REG_STATUS}"
                echo "  Role:    ${ROLE_NAME}"
                if [ -n "$POLL_TOKEN_ENDPOINT" ]; then
                    echo "  Token:   ${POLL_TOKEN_ENDPOINT}"
                fi
                echo ""
                echo "  Get a token with:"
                echo "    aid-token --auth ${AUTH_URL}"
                ;;
            pending)
                POLL_INTERVAL=$(jq -r '.interval // "5"' "$REG_FILE" 2>/dev/null)
                echo "Registration still PENDING"
                echo ""
                echo "  Your request is waiting for admin approval."
                echo "  Poll again in ${POLL_INTERVAL} seconds"
                echo "  Check again later with:"
                echo "    aid-request --auth ${AUTH_URL} --poll"
                ;;
            rejected)
                REASON=$(echo "$HTTP_BODY" | jq -r '.data.attributes.rejection_reason // .reason // "No reason provided"' 2>/dev/null)
                echo "Registration REJECTED"
                echo ""
                echo "  Reason: ${REASON}"
                ;;
            *)
                echo "Registration status: ${REG_STATUS}"
                ;;
        esac
    else
        ERROR=$(echo "$HTTP_BODY" | jq -r '.errors[0].detail // .error // "Unknown error"' 2>/dev/null)
        echo "Error checking status (HTTP ${HTTP_STATUS}): ${ERROR}" >&2
        exit 1
    fi

    exit 0
fi

# =============================================================================
# Check for existing registration
# =============================================================================

if [ -f "$REG_FILE" ]; then
    EXISTING_STATUS=$(jq -r '.status // empty' "$REG_FILE" 2>/dev/null)
    if [ "$EXISTING_STATUS" = "active" ]; then
        echo "Already registered with ${AUTH_URL} (status: active)"
        echo ""
        echo "  Get a token with:"
        echo "    aid-token --auth ${AUTH_URL}"
        exit 0
    elif [ "$EXISTING_STATUS" = "pending" ]; then
        echo "A request is already pending for ${AUTH_URL}"
        echo ""
        echo "  Check status with:"
        echo "    aid-request --auth ${AUTH_URL} --poll"
        exit 0
    fi
fi

# =============================================================================
# Build Registration Request
# =============================================================================

REQUEST_URL="${AUTH_URL}/agent_registrations/request"

REQUEST_BODY=$(jq -n \
    --arg name "$DISPLAY_NAME" \
    --arg address "$AMP_ADDRESS" \
    --arg fingerprint "$AMP_FINGERPRINT" \
    --arg public_key "$PUBLIC_KEY_PEM" \
    --arg key_algorithm "Ed25519" \
    --arg description "$DESCRIPTION" \
    '{
        agent_registration: {
            name: $name,
            address: $address,
            fingerprint: $fingerprint,
            public_key: $public_key,
            key_algorithm: $key_algorithm,
            description: $description
        }
    }')

# =============================================================================
# Send Registration Request
# =============================================================================

echo "Requesting registration with auth server..."
echo "  Agent:  ${AMP_ADDRESS}"
echo "  Auth:   ${AUTH_URL}"
echo ""

# Build curl headers (no auth token required)
CURL_HEADERS=(
    -H "Content-Type: application/json"
)

if [ -n "$API_KEY" ]; then
    CURL_HEADERS+=(-H "X-Api-Key: ${API_KEY}")
fi

HTTP_RESPONSE=$(curl -s -w "\n%{http_code}" \
    -X POST "$REQUEST_URL" \
    "${CURL_HEADERS[@]}" \
    -d "$REQUEST_BODY" \
    --connect-timeout 10 \
    --max-time 30 \
    2>/dev/null) || {
    echo "Error: Failed to connect to auth server at ${REQUEST_URL}" >&2
    exit 1
}

# Split response
HTTP_BODY=$(echo "$HTTP_RESPONSE" | sed '$d')
HTTP_STATUS=$(echo "$HTTP_RESPONSE" | tail -1)

# =============================================================================
# Handle Response
# =============================================================================

if [ "$HTTP_STATUS" = "201" ] || [ "$HTTP_STATUS" = "202" ]; then
    UNIQUE_ID=$(echo "$HTTP_BODY" | jq -r '.data.id // .data.attributes.unique_id // "?"')
    REG_NAME=$(echo "$HTTP_BODY" | jq -r '.data.attributes.name // "?"')
    REG_STATUS=$(echo "$HTTP_BODY" | jq -r '.data.attributes.status // "pending"')
    AUTH_APPROVE_URL=$(echo "$HTTP_BODY" | jq -r '.data.attributes.authorization_url // empty' 2>/dev/null)
    USER_CODE=$(echo "$HTTP_BODY" | jq -r '.data.attributes.user_code // empty' 2>/dev/null)
    EXPIRES_IN=$(echo "$HTTP_BODY" | jq -r '.data.attributes.expires_in // empty' 2>/dev/null)
    INTERVAL=$(echo "$HTTP_BODY" | jq -r '.data.attributes.interval // "5"' 2>/dev/null)
    TOKEN_ENDPOINT=$(echo "$HTTP_BODY" | jq -r '.data.attributes.token_endpoint // empty' 2>/dev/null)

    # Save registration info locally
    jq -n \
        --arg auth_server "$AUTH_URL" \
        --arg unique_id "$UNIQUE_ID" \
        --arg name "$REG_NAME" \
        --arg status "$REG_STATUS" \
        --arg authorization_url "${AUTH_APPROVE_URL:-}" \
        --arg user_code "${USER_CODE:-}" \
        --arg expires_in "${EXPIRES_IN:-}" \
        --arg interval "${INTERVAL:-5}" \
        --arg token_endpoint "${TOKEN_ENDPOINT:-}" \
        --arg requested_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        '{
            auth_server: $auth_server,
            agent_unique_id: $unique_id,
            name: $name,
            status: $status,
            authorization_url: $authorization_url,
            user_code: $user_code,
            expires_in: ($expires_in | if . != "" then tonumber else null end),
            interval: ($interval | tonumber),
            token_endpoint: (if $token_endpoint != "" then $token_endpoint else null end),
            requested_at: $requested_at
        }' > "$REG_FILE"
    chmod 600 "$REG_FILE"

    echo "Registration request submitted"
    echo ""
    echo "  Unique ID:  ${UNIQUE_ID}"
    echo "  Name:       ${REG_NAME}"
    echo "  Status:     ${REG_STATUS}"
    echo "  Auth:       ${AUTH_URL}"
    if [ -n "$USER_CODE" ]; then
        echo ""
        echo "  Your authorization code: ${USER_CODE}"
    fi
    if [ -n "$AUTH_APPROVE_URL" ]; then
        echo ""
        echo "  Authorization URL (share with your admin):"
        echo "    ${AUTH_APPROVE_URL}"
    fi
    if [ -n "$EXPIRES_IN" ]; then
        EXPIRES_HOURS=$(( EXPIRES_IN / 3600 ))
        echo ""
        echo "  Expires in: ${EXPIRES_IN} seconds (~${EXPIRES_HOURS} hours)"
    fi
    echo ""
    echo "  Saved to: ${REG_FILE}"
    echo ""
    echo "  An admin must approve your request before you can get tokens."
    if [ -n "$USER_CODE" ]; then
        echo "  Admin can visit the authorization URL or enter code ${USER_CODE} at the server."
    elif [ -n "$AUTH_APPROVE_URL" ]; then
        echo "  Share the authorization URL above with your admin."
    fi
    echo "  Check status with:"
    echo "    aid-request --auth ${AUTH_URL} --poll"
    if [ -n "$INTERVAL" ]; then
        echo "  Poll again in ${INTERVAL} seconds"
    fi

elif [ "$HTTP_STATUS" = "422" ]; then
    ERROR_DETAIL=$(echo "$HTTP_BODY" | jq -r '.errors[0].detail // .error // "Validation failed"' 2>/dev/null)
    echo "Request failed -- validation error" >&2
    echo "" >&2
    echo "  Detail: ${ERROR_DETAIL}" >&2
    echo "" >&2

    if echo "$ERROR_DETAIL" | grep -qi "already"; then
        echo "  This agent may already have a pending or active registration." >&2
        echo "  Check status with:" >&2
        echo "    aid-request --auth ${AUTH_URL} --poll" >&2
    fi
    exit 1

elif [ "$HTTP_STATUS" = "404" ]; then
    echo "Request failed -- endpoint not found (HTTP 404)" >&2
    echo "" >&2
    echo "  The auth server may not support agent-initiated registration." >&2
    echo "  Ask an admin to register you instead:" >&2
    echo "    aid-register --auth ${AUTH_URL} --token <ADMIN_JWT> --role-id <id>" >&2
    exit 1

else
    ERROR=$(echo "$HTTP_BODY" | jq -r '.errors[0].detail // .error // "Unknown error"' 2>/dev/null)
    echo "Request failed (HTTP ${HTTP_STATUS})" >&2
    echo "" >&2
    echo "  Error: ${ERROR}" >&2
    exit 1
fi
