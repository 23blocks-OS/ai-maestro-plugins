#!/bin/bash
# =============================================================================
# AID Discover — Resolve a resource URL to AID auth-server metadata
# =============================================================================
#
# Walks the RFC 9728 / RFC 8414 discovery chain to find an AID-enabled
# authorization server starting from just a resource URL.
#
# Flow:
#   1. GET <resource>/.well-known/oauth-protected-resource
#   2. Read authorization_servers[0]
#   3. GET <auth_server>/.well-known/oauth-authorization-server
#   4. Validate urn:aid:agent-identity in grant_types_supported
#   5. Emit the aid_grant block + token_endpoint + scopes
#
# Usage:
#   aid-discover --resource https://api.acme.com
#   aid-discover -r https://api.acme.com --json
#   aid-discover -r https://api.acme.com --quiet   # just the auth_server URL
#
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/aid-helper.sh"

RESOURCE_URL=""
FORMAT="text"

show_help() {
    echo "Usage: aid-discover --resource <url> [options]"
    echo ""
    echo "Discover an AID-enabled auth server from a protected resource URL."
    echo "Walks RFC 9728 Protected Resource Metadata to RFC 8414 Authorization"
    echo "Server Metadata and validates that the server advertises the AID grant."
    echo ""
    echo "Required:"
    echo "  --resource, -r URL    Protected resource URL (e.g., https://api.acme.com)"
    echo ""
    echo "Options:"
    echo "  --json, -j            Output the full discovery blob as JSON"
    echo "  --quiet, -q           Output only the auth server URL (for piping)"
    echo "  --help, -h            Show this help"
    echo ""
    echo "Examples:"
    echo "  aid-discover -r https://api.acme.com"
    echo "  AUTH=\$(aid-discover -r https://api.acme.com -q)"
    echo "  aid-token --auth \"\$AUTH\""
}

while [[ $# -gt 0 ]]; do
    case $1 in
        --resource|-r)
            RESOURCE_URL="$2"
            shift 2
            ;;
        --json|-j)
            FORMAT="json"
            shift
            ;;
        --quiet|-q)
            FORMAT="quiet"
            shift
            ;;
        --help|-h)
            show_help
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            echo "Run 'aid-discover --help' for usage." >&2
            exit 1
            ;;
    esac
done

if [ -z "$RESOURCE_URL" ]; then
    echo "Error: --resource is required" >&2
    exit 1
fi

DISCOVERY=$(discover_from_resource "$RESOURCE_URL") || exit 1

case "$FORMAT" in
    json)
        echo "$DISCOVERY"
        ;;
    quiet)
        echo "$DISCOVERY" | jq -r '.auth_server'
        ;;
    *)
        AUTH=$(echo "$DISCOVERY" | jq -r '.auth_server')
        ISSUER=$(echo "$DISCOVERY" | jq -r '.issuer // "?"')
        TOKEN_EP=$(echo "$DISCOVERY" | jq -r '.token_endpoint // "?"')
        INTRO_EP=$(echo "$DISCOVERY" | jq -r '.introspection_endpoint // "?"')
        REG_EP=$(echo "$DISCOVERY" | jq -r '.registration_endpoint // "?"')
        REQ_EP=$(echo "$DISCOVERY" | jq -r '.registration_request_endpoint // "?"')
        AUTH_URI=$(echo "$DISCOVERY" | jq -r '.agent_authorization_uri // "?"')
        AID_VER=$(echo "$DISCOVERY" | jq -r '.aid_version // "?"')
        SCOPES=$(echo "$DISCOVERY" | jq -r '.scopes_supported | join(", ")')
        KEY_ALGS=$(echo "$DISCOVERY" | jq -r '.key_algorithms_supported | join(", ")')

        echo ""
        echo "AID discovery for ${RESOURCE_URL}"
        echo ""
        echo "  Resource:                  ${RESOURCE_URL}"
        echo "  Auth server:               ${AUTH}"
        echo "  Issuer:                    ${ISSUER}"
        echo "  AID version:               ${AID_VER}"
        echo ""
        echo "  Token endpoint:            ${TOKEN_EP}"
        echo "  Introspection endpoint:    ${INTRO_EP}"
        echo "  Registration (admin):      ${REG_EP}"
        echo "  Registration (request):    ${REQ_EP}"
        echo "  Agent authorization page:  ${AUTH_URI}"
        echo ""
        echo "  Key algorithms:            ${KEY_ALGS}"
        echo "  Scopes:                    ${SCOPES}"
        echo ""
        echo "  Use the auth server with other AID commands:"
        echo "    aid-token --auth ${AUTH}"
        echo "    aid-request --auth ${AUTH}"
        ;;
esac
