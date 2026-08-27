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

# Pre-source: extract --id to set agent identity before helper resolves it
_amp_prev=""
for _amp_arg in "$@"; do
    if [ "$_amp_prev" = "--id" ]; then
        export CLAUDE_AGENT_ID="$_amp_arg"
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
