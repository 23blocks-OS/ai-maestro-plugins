#!/bin/bash
# =============================================================================
# AMP Reply - Reply to a Message
# =============================================================================
#
# Reply to a message in your inbox.
#
# Usage:
#   amp-reply <message-id> <reply-message>
#   amp-reply <message-id> <reply-message> --priority high
#
# =============================================================================

# Note: set -e is inherited from amp-helper.sh; read_message failure handled via || true

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
MESSAGE_ID=""
REPLY_MESSAGE=""
BODY_FILE=""
BODY_STDIN=false
PRIORITY=""
TYPE="response"
ATTACH_FILES=()
FORCE=false

show_help() {
    echo "Usage: amp-reply <message-id> <reply-message> [options]"
    echo "       amp-reply <message-id> --body-file PATH [options]"
    echo "       amp-reply <message-id> --body-stdin [options]"
    echo ""
    echo "Reply to a message."
    echo ""
    echo "Arguments:"
    echo "  message-id      The message ID to reply to"
    echo "  reply-message   Your reply message (omit if using --body-file or --body-stdin)"
    echo ""
    echo "Options:"
    echo "  --body-file PATH          Read reply body from a file (avoids shell escaping"
    echo "                              issues with backticks, code blocks, box-drawing chars)"
    echo "  --body-stdin              Read reply body from stdin"
    echo "  --priority, -p PRIORITY   Override priority (default: same as original)"
    echo "  --type, -t TYPE           Message type (default: response)"
    echo "  --attach, -a FILE         Attach a file (can be repeated)"
    echo "  --force, -f               Reply even if this is not the message you last read"
    echo "  --id UUID                 Operate as this agent (UUID from config.json)"
    echo "  --help, -h                Show this help"
    echo ""
    echo "Examples:"
    echo "  amp-reply msg_1234567890_abc \"Got it, working on it\""
    echo "  amp-reply msg_1234567890_abc \"Urgent update\" --priority urgent"
    echo "  amp-reply msg_1234567890_abc \"See attached\" --attach report.pdf"
    echo "  amp-reply msg_1234567890_abc --body-file reply.md"
    echo "  cat reply.md | amp-reply msg_1234567890_abc --body-stdin"
}

# Parse positional and optional arguments
POSITIONAL=()
while [[ $# -gt 0 ]]; do
    case $1 in
        --priority|-p)
            PRIORITY="$2"
            shift 2
            ;;
        --type|-t)
            TYPE="$2"
            shift 2
            ;;
        --attach|-a)
            ATTACH_FILES+=("$2")
            shift 2
            ;;
        --body-file)
            BODY_FILE="$2"
            shift 2
            ;;
        --body-stdin)
            BODY_STDIN=true
            shift
            ;;
        --id)
            shift 2  # Already handled in pre-source parsing
            ;;
        --force|-f)
            FORCE=true
            shift
            ;;
        --help|-h)
            show_help
            exit 0
            ;;
        -*)
            echo "Unknown option: $1"
            echo "Run 'amp-reply --help' for usage."
            exit 1
            ;;
        *)
            POSITIONAL+=("$1")
            shift
            ;;
    esac
done

# Resolve body source: positional arg, file, or stdin (mutually exclusive)
_body_sources=0
[ -n "$BODY_FILE" ] && _body_sources=$((_body_sources + 1))
[ "$BODY_STDIN" = true ] && _body_sources=$((_body_sources + 1))
[ ${#POSITIONAL[@]} -ge 2 ] && _body_sources=$((_body_sources + 1))

if [ $_body_sources -gt 1 ]; then
    echo "Error: provide reply body via exactly one of: positional arg, --body-file, --body-stdin"
    exit 1
fi

if [ ${#POSITIONAL[@]} -lt 1 ]; then
    echo "Error: Missing message-id."
    echo ""
    show_help
    exit 1
fi

MESSAGE_ID="${POSITIONAL[0]}"

if [ -n "$BODY_FILE" ]; then
    if [ ! -f "$BODY_FILE" ]; then
        echo "Error: --body-file path not found: $BODY_FILE"
        exit 1
    fi
    REPLY_MESSAGE=$(cat "$BODY_FILE")
elif [ "$BODY_STDIN" = true ]; then
    REPLY_MESSAGE=$(cat)
elif [ ${#POSITIONAL[@]} -ge 2 ]; then
    REPLY_MESSAGE="${POSITIONAL[1]}"
else
    echo "Error: Missing reply body. Provide as positional arg, --body-file PATH, or --body-stdin."
    echo ""
    show_help
    exit 1
fi

# Validate message ID
validate_message_id "$MESSAGE_ID" || {
    echo "Error: Invalid message ID format: ${MESSAGE_ID}"
    exit 1
}

# Require initialization
require_init

# Read the original message
ORIGINAL=$(read_message "$MESSAGE_ID" "inbox" 2>/dev/null) || true

if [ -z "$ORIGINAL" ]; then
    echo "Error: Message not found: ${MESSAGE_ID}"
    echo ""
    echo "Make sure the message ID is correct. Use 'amp-inbox' to list messages."
    exit 1
fi

# Extract original message details
ORIGINAL_FROM=$(echo "$ORIGINAL" | jq -r '.envelope.from')
ORIGINAL_SUBJECT=$(echo "$ORIGINAL" | jq -r '.envelope.subject')
ORIGINAL_PRIORITY=$(echo "$ORIGINAL" | jq -r '.envelope.priority')
ORIGINAL_THREAD=$(echo "$ORIGINAL" | jq -r '.envelope.thread_id // empty')

# Use original priority if not overridden
if [ -z "$PRIORITY" ]; then
    PRIORITY="$ORIGINAL_PRIORITY"
fi

# ── Reply-target safety ──────────────────────────────────────────────────────
# Enforce the invariant "you reply to the message you just read". If the target
# is not the last message read in this terminal, refuse — this is the guard
# against `amp-reply "$(amp-inbox | head -1)" ...` sending your reply to whoever
# happens to be top of the inbox. See amp-helper.sh for the full story. --force
# overrides; reading the target first (amp-read <id>) also clears it naturally.
LAST_READ_ID="$(get_last_read_id)"
if [ -n "$LAST_READ_ID" ] && [ "$LAST_READ_ID" != "$MESSAGE_ID" ] && [ "$FORCE" != true ]; then
    LAST_READ_FROM="$(get_last_read_from)"
    {
        echo "⚠️  Reply-target mismatch — refusing to send."
        echo ""
        echo "  Replying to : ${MESSAGE_ID}"
        echo "     → sender : ${ORIGINAL_FROM}   (re: ${ORIGINAL_SUBJECT})"
        echo ""
        echo "  Last read   : ${LAST_READ_ID}"
        echo "     from      : ${LAST_READ_FROM}"
        echo ""
        echo "  These differ. This is the footgun behind cross-thread misroutes:"
        echo "  a target built from 'amp-inbox | head -1' aims at whatever is top"
        echo "  of the inbox, not at the message you meant to answer."
        echo ""
        echo "  • To reply to the message you just read: amp-reply ${LAST_READ_ID} \"...\""
        echo "  • If you really mean ${MESSAGE_ID}: amp-read ${MESSAGE_ID} first,"
        echo "    or re-run this command with --force."
    } >&2
    exit 1
fi

# Build reply subject
if [[ "$ORIGINAL_SUBJECT" != Re:* ]]; then
    REPLY_SUBJECT="Re: ${ORIGINAL_SUBJECT}"
else
    REPLY_SUBJECT="$ORIGINAL_SUBJECT"
fi

# Create the reply using amp-send
echo "Sending reply to ${ORIGINAL_FROM}..."
echo ""

# Build send command (propagate thread_id from original message for correct threading)
SEND_ARGS=(
    "$ORIGINAL_FROM"
    "$REPLY_SUBJECT"
    "$REPLY_MESSAGE"
    --priority "$PRIORITY"
    --type "$TYPE"
    --reply-to "$MESSAGE_ID"
    --thread-id "$ORIGINAL_THREAD"
)

# Forward attachment flags
for attach_file in "${ATTACH_FILES[@]}"; do
    SEND_ARGS+=(--attach "$attach_file")
done

"${SCRIPT_DIR}/amp-send.sh" "${SEND_ARGS[@]}"
