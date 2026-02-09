#!/bin/bash
# =============================================================================
# AMP Fetch - Fetch Messages from External Providers
# =============================================================================
#
# Pull new messages from registered external providers.
#
# Usage:
#   amp-fetch                    # Fetch from all providers
#   amp-fetch --provider crabmail.ai   # Fetch from specific provider
#
# =============================================================================

set -e

# Source helper functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/amp-helper.sh"

# Parse arguments
PROVIDER=""
VERBOSE=false
MARK_AS_FETCHED=true

show_help() {
    echo "Usage: amp-fetch [options]"
    echo ""
    echo "Fetch new messages from external providers."
    echo ""
    echo "Options:"
    echo "  --provider, -p PROVIDER   Fetch from specific provider only"
    echo "  --verbose, -v             Show detailed output"
    echo "  --no-mark                 Don't mark messages as fetched on provider"
    echo "  --help, -h                Show this help"
    echo ""
    echo "Examples:"
    echo "  amp-fetch                     # Fetch from all registered providers"
    echo "  amp-fetch -p crabmail.ai      # Fetch from Crabmail only"
    echo "  amp-fetch --verbose           # Show details"
}

while [[ $# -gt 0 ]]; do
    case $1 in
        --provider|-p)
            PROVIDER="$2"
            shift 2
            ;;
        --verbose|-v)
            VERBOSE=true
            shift
            ;;
        --no-mark)
            MARK_AS_FETCHED=false
            shift
            ;;
        --help|-h)
            show_help
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Run 'amp-fetch --help' for usage."
            exit 1
            ;;
    esac
done

# Require initialization
require_init

# Get list of providers to fetch from
if [ -n "$PROVIDER" ]; then
    PROVIDER_LOWER=$(echo "$PROVIDER" | tr '[:upper:]' '[:lower:]')
    REG_FILE="${AMP_REGISTRATIONS_DIR}/${PROVIDER_LOWER}.json"
    if [ ! -f "$REG_FILE" ]; then
        echo "Error: Not registered with ${PROVIDER}"
        echo ""
        echo "Register first: amp-register --provider ${PROVIDER}"
        exit 1
    fi
    PROVIDERS=("$PROVIDER_LOWER")
else
    # Find all registered providers
    PROVIDERS=()
    if [ -d "$AMP_REGISTRATIONS_DIR" ]; then
        for reg_file in "${AMP_REGISTRATIONS_DIR}"/*.json; do
            if [ -f "$reg_file" ]; then
                provider_name=$(basename "$reg_file" .json)
                PROVIDERS+=("$provider_name")
            fi
        done
    fi
fi

if [ ${#PROVIDERS[@]} -eq 0 ]; then
    echo "No external providers registered."
    echo ""
    echo "Register with a provider first:"
    echo "  amp-register --provider crabmail.ai --tenant <your-tenant>"
    exit 0
fi

# Fetch from each provider
TOTAL_NEW=0

for provider in "${PROVIDERS[@]}"; do
    REG_FILE="${AMP_REGISTRATIONS_DIR}/${provider}.json"
    REGISTRATION=$(cat "$REG_FILE")

    API_URL=$(echo "$REGISTRATION" | jq -r '.apiUrl')
    API_KEY=$(echo "$REGISTRATION" | jq -r '.apiKey')
    EXTERNAL_ADDRESS=$(echo "$REGISTRATION" | jq -r '.address')

    if [ "$VERBOSE" = true ]; then
        echo "Fetching from ${provider}..."
        echo "  API: ${API_URL}"
        echo "  Address: ${EXTERNAL_ADDRESS}"
    fi

    # Determine fetch endpoint based on provider type
    # AI Maestro local providers use /messages/pending (API_URL already includes /api/v1)
    # External providers (e.g., Crabmail) use /v1/inbox
    FETCH_ENDPOINT="${API_URL}/v1/inbox"
    if [ "$provider" = "aimaestro.local" ] || [ "$provider" = "${AMP_PROVIDER_DOMAIN}" ]; then
        FETCH_ENDPOINT="${API_URL}/messages/pending"
    fi

    # Fetch messages from provider
    RESPONSE=$(curl -s -w "\n%{http_code}" --connect-timeout 5 --max-time 15 \
        -X GET "${FETCH_ENDPOINT}" \
        -H "Authorization: Bearer ${API_KEY}" \
        -H "Accept: application/json" 2>&1)

    HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
    BODY=$(echo "$RESPONSE" | sed '$d')

    if [ "$HTTP_CODE" = "200" ]; then
        # Parse messages
        MESSAGE_COUNT=$(echo "$BODY" | jq '.messages | length' 2>/dev/null || echo "0")

        if [ "$MESSAGE_COUNT" = "0" ] || [ "$MESSAGE_COUNT" = "null" ]; then
            if [ "$VERBOSE" = true ]; then
                echo "  No new messages"
            fi
            continue
        fi

        if [ "$VERBOSE" = true ]; then
            echo "  Found ${MESSAGE_COUNT} new message(s)"
        fi

        # Process each message (use process substitution to avoid subshell variable scope issue)
        while read -r msg; do
            # Get message ID
            msg_id=$(echo "$msg" | jq -r '.envelope.id // .id')

            # Validate message ID format (security) - use strict format or server-assigned UUIDs
            if ! validate_message_id "$msg_id" 2>/dev/null && [[ ! "$msg_id" =~ ^[a-zA-Z0-9][a-zA-Z0-9_-]{3,63}$ ]]; then
                if [ "$VERBOSE" = true ]; then
                    echo "    Skipping invalid message ID: ${msg_id}"
                fi
                continue
            fi

            # Check if already exists locally (search flat and sender subdirectories)
            if find_message_file "${msg_id}" "${AMP_INBOX_DIR}" >/dev/null 2>&1; then
                if [ "$VERBOSE" = true ]; then
                    echo "    Skipping ${msg_id} (already exists)"
                fi
                continue
            fi

            # Signature verification for fetched messages
            # - AI Maestro providers: server already verified on ingest, trust it
            # - External providers: verify if we have the sender's public key
            signature=$(echo "$msg" | jq -r '.envelope.signature // empty')
            sig_valid="false"

            if [ "$provider" = "aimaestro.local" ] || [ "$provider" = "${AMP_PROVIDER_DOMAIN}" ]; then
                # AI Maestro verified signatures at route time — trust the relay
                sig_valid="true"
            elif [ -n "$signature" ]; then
                # External provider: attempt local verification if sender's public
                # key is cached (e.g. from a previous registration exchange).
                # Without the sender's key, we mark it as unverified but still accept.
                sender_addr=$(echo "$msg" | jq -r '.envelope.from // empty')
                sender_name="${sender_addr%%@*}"
                # Look up sender UUID from .index.json for key resolution
                _sender_uuid=""
                _amp_index="${AMP_AGENTS_BASE}/.index.json"
                if [ -f "$_amp_index" ]; then
                    _sender_uuid=$(jq -r --arg name "$sender_name" '.[$name] // empty' "$_amp_index" 2>/dev/null)
                fi
                if [ -n "$_sender_uuid" ]; then
                    sender_pubkey="${AMP_AGENTS_BASE}/${_sender_uuid}/keys/public.pem"
                else
                    sender_pubkey="${AMP_AGENTS_BASE}/${sender_name}/keys/public.pem"
                fi

                if [ -f "$sender_pubkey" ]; then
                    # Reconstruct canonical signing data and verify
                    v_to=$(echo "$msg" | jq -r '.envelope.to // empty')
                    v_subj=$(echo "$msg" | jq -r '.envelope.subject // empty')
                    v_pri=$(echo "$msg" | jq -r '.envelope.priority // "normal"')
                    v_reply=$(echo "$msg" | jq -r '.envelope.in_reply_to // ""')
                    v_phash=$(echo "$msg" | jq -c '.payload' | tr -d '\n' | $OPENSSL_BIN dgst -sha256 -binary 2>/dev/null | base64 | tr -d '\n')
                    v_sdata="${sender_addr}|${v_to}|${v_subj}|${v_pri}|${v_reply}|${v_phash}"

                    if verify_signature "$v_sdata" "$signature" "$sender_pubkey"; then
                        sig_valid="true"
                    else
                        if [ "$VERBOSE" = true ]; then
                            echo "    ⚠️  Signature verification failed for ${msg_id}"
                        fi
                    fi
                fi
                # No public key available — accept but mark unverified
            fi

            # Apply security module if available
            if type apply_content_security &>/dev/null; then
                load_config 2>/dev/null || true
                msg=$(apply_content_security "$msg" "${AMP_TENANT:-default}" "$sig_valid")
            fi

            # Add additional metadata (including signature verification status)
            msg=$(echo "$msg" | jq \
                --arg receivedAt "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
                --arg provider "$provider" \
                --arg method "fetch" \
                --arg sigVerified "$sig_valid" \
                '.local = (.local // {}) + {
                    received_at: $receivedAt,
                    fetched_from: $provider,
                    delivery_method: $method,
                    signature_verified: ($sigVerified == "true"),
                    status: "unread"
                }')

            # Save to inbox (use sender subdirectory)
            from_addr=$(echo "$msg" | jq -r '.envelope.from')
            sender_dir=$(sanitize_address_for_path "$from_addr")
            mkdir -p "${AMP_INBOX_DIR}/${sender_dir}"
            echo "$msg" > "${AMP_INBOX_DIR}/${sender_dir}/${msg_id}.json"

            if [ "$VERBOSE" = true ]; then
                subject=$(echo "$msg" | jq -r '.envelope.subject')
                from=$(echo "$msg" | jq -r '.envelope.from')
                echo "    Saved: ${msg_id}"
                echo "      From: ${from}"
                echo "      Subject: ${subject}"
            fi

            # Check for suspicious attachments
            fetch_att_count=$(echo "$msg" | jq '.payload.attachments // [] | length' 2>/dev/null || echo "0")
            if [ "$fetch_att_count" -gt 0 ]; then
                echo "$msg" | jq -r '.payload.attachments[]? | @base64' 2>/dev/null | while read -r fetch_att_b64; do
                    fetch_att=$(echo "$fetch_att_b64" | base64 -d)
                    fetch_scan=$(echo "$fetch_att" | jq -r '.scan_status // "unknown"')
                    fetch_att_name=$(echo "$fetch_att" | jq -r '.filename // "unknown"')
                    if [ "$fetch_scan" = "rejected" ]; then
                        echo "    ⚠️  WARNING: Attachment '${fetch_att_name}' rejected by security scan!"
                    elif [ "$fetch_scan" = "suspicious" ]; then
                        echo "    ⚠️  WARNING: Attachment '${fetch_att_name}' flagged as suspicious — requires human approval!"
                    elif [ "$fetch_scan" = "pending" ] || [ "$fetch_scan" = "unknown" ]; then
                        echo "    ⚠️  Attachment '${fetch_att_name}' scan status: ${fetch_scan}"
                    fi
                done
            fi

            TOTAL_NEW=$((TOTAL_NEW + 1))

            # Mark as fetched on provider (if enabled)
            if [ "$MARK_AS_FETCHED" = true ]; then
                # AI Maestro uses DELETE /messages/pending?id=X
                # External providers use POST /v1/inbox/<id>/ack
                if [ "$provider" = "aimaestro.local" ] || [ "$provider" = "${AMP_PROVIDER_DOMAIN}" ]; then
                    curl -s --connect-timeout 3 -X DELETE "${API_URL}/messages/pending?id=${msg_id}" \
                        -H "Authorization: Bearer ${API_KEY}" \
                        >/dev/null 2>&1 || true
                else
                    curl -s --connect-timeout 3 -X POST "${API_URL}/v1/inbox/${msg_id}/ack" \
                        -H "Authorization: Bearer ${API_KEY}" \
                        >/dev/null 2>&1 || true
                fi
            fi
        done < <(echo "$BODY" | jq -c '.messages[]' 2>/dev/null)

    elif [ "$HTTP_CODE" = "401" ]; then
        echo "Error: Authentication failed for ${provider}"
        echo "  Your API key may have expired. Re-register with:"
        echo "  amp-register --provider ${provider} --force"

    elif [ "$HTTP_CODE" = "000" ]; then
        echo "Error: Could not connect to ${provider}"
        echo "  Check your internet connection."

    else
        echo "Error: Failed to fetch from ${provider} (HTTP ${HTTP_CODE})"
        ERROR_MSG=$(echo "$BODY" | jq -r '.error // .message // empty' 2>/dev/null)
        if [ -n "$ERROR_MSG" ]; then
            echo "  ${ERROR_MSG}"
        fi
    fi
done

# Summary
if [ "$TOTAL_NEW" -gt 0 ]; then
    echo ""
    echo "✅ Fetched ${TOTAL_NEW} new message(s)"
    echo ""
    echo "View messages: amp-inbox"
else
    echo "No new messages from external providers."
fi
