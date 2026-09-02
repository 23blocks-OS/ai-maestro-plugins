#!/bin/bash
# =============================================================================
# AMP Identity - Check and Display Agent Identity
# =============================================================================
#
# Quick identity check for agents recovering context.
# This is the FIRST command an agent should run when using AMP.
#
# Usage:
#   amp-identity              # Human-readable output
#   amp-identity --json       # JSON output for parsing
#   amp-identity --brief      # One-line summary
#
# =============================================================================

set -e

# Pre-source: extract --id to set agent identity before helper resolves it.
#
# An explicit --id is the caller naming a specific agent, so it must beat an
# inherited AMP_DIR. AI Maestro exports AMP_DIR into every agent session, and
# the helper skips its whole resolution block when AMP_DIR is already set — so
# `--id <other-agent>` run from inside an agent session was silently ignored
# and you read your OWN mailbox believing it was theirs. Unsetting AMP_DIR here
# hands resolution back to the helper, which then honours CLAUDE_AGENT_ID.
#
# AMP_EXPLICIT_ID additionally tells load_config that CLAUDE_AGENT_NAME belongs
# to the CALLER and says nothing about the agent being opened.
_amp_prev=""
for _amp_arg in "$@"; do
    if [ "$_amp_prev" = "--id" ]; then
        export CLAUDE_AGENT_ID="$_amp_arg"
        export AMP_EXPLICIT_ID="$_amp_arg"
        unset AMP_DIR
        break
    fi
    _amp_prev="$_amp_arg"
done
unset _amp_prev _amp_arg

# Source helper functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/amp-helper.sh"

# Parse arguments
FORMAT="text"

while [[ $# -gt 0 ]]; do
    case $1 in
        --json|-j)
            FORMAT="json"
            shift
            ;;
        --brief|-b)
            FORMAT="brief"
            shift
            ;;
        --id)
            shift 2  # Already handled in pre-source parsing
            ;;
        --help|-h)
            echo "Usage: amp-identity [--id UUID] [options]"
            echo ""
            echo "Check and display your AMP identity."
            echo "Run this FIRST to recover your identity after context reset."
            echo ""
            echo "Options:"
            echo "  --id UUID      Operate as this agent (UUID from config.json)"
            echo "  --json, -j     Output as JSON"
            echo "  --brief, -b    One-line summary"
            echo "  --help, -h     Show this help"
            echo ""
            echo "Files:"
            echo "  Identity: ~/.agent-messaging/IDENTITY.md"
            echo "  Config:   ~/.agent-messaging/config.json"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Run 'amp-identity --help' for usage."
            exit 1
            ;;
    esac
done

# Check identity based on format
case "$FORMAT" in
    json)
        check_identity json
        ;;
    brief)
        if is_initialized; then
            load_config
            echo "AMP: ${AMP_ADDRESS} (${AMP_FINGERPRINT})"
        else
            echo "AMP: Not initialized (run: amp-init --auto)"
            exit 1
        fi
        ;;
    *)
        check_identity text
        ;;
esac
