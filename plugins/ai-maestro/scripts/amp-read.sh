#!/bin/bash
# =============================================================================
# AMP Read - Read a Message
# =============================================================================
#
# Read a specific message from your inbox.
#
# Usage:
#   amp-read <message-id>
#   amp-read <message-id> --no-mark-read
#
# =============================================================================

set -e

# Source helper functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/amp-helper.sh"

# Parse arguments
MESSAGE_ID=""
MARK_READ=true
JSON_OUTPUT=false
BOX="inbox"
AUTO_DOWNLOAD=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --no-mark-read|-n)
            MARK_READ=false
            shift
            ;;
        --json|-j)
            JSON_OUTPUT=true
            shift
            ;;
        --sent|-s)
            BOX="sent"
            shift
            ;;
        --download)
            AUTO_DOWNLOAD=true
            shift
            ;;
        --help|-h)
            echo "Usage: amp-read <message-id> [options]"
            echo ""
            echo "Read a specific message."
            echo ""
            echo "Arguments:"
            echo "  message-id      The message ID (from amp-inbox)"
            echo ""
            echo "Options:"
            echo "  --no-mark-read, -n   Don't mark the message as read"
            echo "  --json, -j           Output raw JSON"
            echo "  --sent, -s           Read from sent folder instead of inbox"
            echo "  --download           Auto-download clean attachments after display"
            echo "  --help, -h           Show this help"
            echo ""
            echo "Examples:"
            echo "  amp-read msg_1234567890_abc123"
            echo "  amp-read msg_1234567890_abc123 --no-mark-read"
            exit 0
            ;;
        -*)
            echo "Unknown option: $1"
            echo "Run 'amp-read --help' for usage."
            exit 1
            ;;
        *)
            if [ -z "$MESSAGE_ID" ]; then
                MESSAGE_ID="$1"
            else
                echo "Error: Unexpected argument: $1"
                exit 1
            fi
            shift
            ;;
    esac
done

# Require message ID
if [ -z "$MESSAGE_ID" ]; then
    echo "Error: Message ID required"
    echo ""
    echo "Usage: amp-read <message-id>"
    echo ""
    echo "Get message IDs from: amp-inbox"
    exit 1
fi

# Require initialization
require_init

# Read the message (set -e will exit on failure)
MESSAGE=$(read_message "$MESSAGE_ID" "$BOX")

# Mark as read (inbox only)
if [ "$MARK_READ" = true ] && [ "$BOX" = "inbox" ]; then
    mark_as_read "$MESSAGE_ID" 2>/dev/null || echo "Warning: Could not mark message as read" >&2
fi

# JSON output
if [ "$JSON_OUTPUT" = true ]; then
    echo "$MESSAGE"
    exit 0
fi

# Human-readable output
id=$(echo "$MESSAGE" | jq -r '.envelope.id')
from=$(echo "$MESSAGE" | jq -r '.envelope.from')
to=$(echo "$MESSAGE" | jq -r '.envelope.to')
subject=$(echo "$MESSAGE" | jq -r '.envelope.subject')
priority=$(echo "$MESSAGE" | jq -r '.envelope.priority')
timestamp=$(echo "$MESSAGE" | jq -r '.envelope.timestamp')
thread_id=$(echo "$MESSAGE" | jq -r '.envelope.thread_id')
in_reply_to=$(echo "$MESSAGE" | jq -r '.envelope.in_reply_to // empty')

msg_type=$(echo "$MESSAGE" | jq -r '.payload.type // "notification"')
body=$(echo "$MESSAGE" | jq -r '.payload.message')
context=$(echo "$MESSAGE" | jq '.payload.context // null')

status=$(echo "$MESSAGE" | jq -r '(.local.status // .metadata.status // "unread")')

# Format timestamp
ts_display=$(format_timestamp "$timestamp")

# Display
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "MESSAGE"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "ID:       ${id}"
echo "From:     ${from}"
echo "To:       ${to}"
echo "Subject:  ${subject}"
echo "Date:     ${ts_display}"
echo "Priority: ${priority} $(priority_indicator "$priority")"
echo "Type:     ${msg_type}"

if [ -n "$in_reply_to" ]; then
    echo "Reply to: ${in_reply_to}"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "$body"
echo ""

# Show attachments if present
attachments=$(echo "$MESSAGE" | jq '.payload.attachments // []')
att_count=$(echo "$attachments" | jq 'length')

if [ "$att_count" -gt 0 ]; then
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "ATTACHMENTS (${att_count})"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    while read -r att_b64; do
        att=$(echo "$att_b64" | base64 -d)
        att_id=$(echo "$att" | jq -r '.id')
        att_filename=$(echo "$att" | jq -r '.filename')
        att_size=$(echo "$att" | jq -r '.size')
        att_type=$(echo "$att" | jq -r '.content_type // "unknown"')
        att_scan=$(echo "$att" | jq -r '.scan_status // "unknown"')

        att_size_display=$(format_file_size "$att_size")

        scan_icon="✅"
        if [ "$att_scan" = "rejected" ]; then
            scan_icon="🔴"
        elif [ "$att_scan" = "suspicious" ]; then
            scan_icon="⚠️"
        elif [ "$att_scan" = "pending" ]; then
            scan_icon="⏳"
        elif [ "$att_scan" = "unknown" ]; then
            scan_icon="❓"
        fi

        echo "  ${scan_icon} ${att_filename} (${att_size_display}, ${att_type})"
        echo "     ID: ${att_id} | Scan: ${att_scan}"
    done < <(echo "$attachments" | jq -r '.[] | @base64')

    echo ""
fi

# Show context if present
if [ "$context" != "null" ] && [ "$context" != "{}" ]; then
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "CONTEXT"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "$context" | jq .
    echo ""
fi

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [ "$MARK_READ" = true ] && [ "$BOX" = "inbox" ]; then
    echo "✓ Marked as read"
fi

echo ""
echo "Actions:"
echo "  Reply:    amp-reply ${id} \"Your reply message\""
echo "  Delete:   amp-delete ${id}"
if [ "$att_count" -gt 0 ]; then
    echo "  Download: amp-download ${id} --all"
fi

# Auto-download attachments if requested
if [ "$AUTO_DOWNLOAD" = true ] && [ "$att_count" -gt 0 ]; then
    echo ""
    echo "Auto-downloading attachments..."
    "${SCRIPT_DIR}/amp-download.sh" "$id" --all
fi
