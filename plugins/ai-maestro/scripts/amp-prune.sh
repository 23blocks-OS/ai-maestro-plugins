#!/bin/bash
# =============================================================================
# AMP Prune - Remove old messages and attachments
# =============================================================================
#
# Messages and attachments are never removed by AMP itself, so an inbox grows
# for as long as the agent lives. This removes, for one agent:
#   - READ inbox messages older than N days
#   - ANY sent message older than N days
#   - attachment folders older than N days that no remaining message refers to
#
# Unread inbox messages are kept unless --include-unread is given. Only files
# under the agent's messages/ and attachments/ folders are touched, and
# symlinks are never followed or removed.
#
# Usage:
#   amp-prune.sh                       # dry run: show what would go
#   amp-prune.sh --apply               # delete
#   amp-prune.sh --days 30 --apply
#   amp-prune.sh --include-unread --apply
#
# =============================================================================

# Pre-source: an explicit --id beats an inherited AMP_DIR (see amp-delete.sh).
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

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/amp-helper.sh"

DAYS=90
APPLY=false
INCLUDE_UNREAD=false

show_help() {
    echo "Usage: amp-prune [options]"
    echo ""
    echo "Remove old messages and attachments. Dry run unless --apply is given."
    echo ""
    echo "Options:"
    echo "  --dry-run           Show what would be removed (default)"
    echo "  --apply             Remove it"
    echo "  --days N            Age threshold in days (default: 90)"
    echo "  --include-unread    Also remove unread inbox messages (default: keep them)"
    echo "  --id UUID           Operate as this agent (UUID from config.json)"
    echo "  --help, -h          Show this help"
}

while [[ $# -gt 0 ]]; do
    case $1 in
        --apply) APPLY=true; shift ;;
        --dry-run) APPLY=false; shift ;;
        --include-unread) INCLUDE_UNREAD=true; shift ;;
        --days)
            DAYS="${2:-}"
            shift 2 || { echo "Error: --days needs a value" >&2; exit 1; }
            ;;
        --id) shift 2 ;;
        --help|-h) show_help; exit 0 ;;
        *) echo "Error: unknown option: $1" >&2; show_help >&2; exit 1 ;;
    esac
done

if ! [[ "$DAYS" =~ ^[0-9]+$ ]] || [ "$DAYS" -lt 1 ]; then
    echo "Error: --days must be a whole number of at least 1" >&2
    exit 1
fi

WORK=$(mktemp -d) || exit 1
trap 'rm -rf "$WORK"' EXIT

DEL_MSGS="${WORK}/del_msgs"      # message files to remove
DEL_ATTS="${WORK}/del_atts"      # attachment folders to remove
: > "$DEL_MSGS"; : > "$DEL_ATTS"

msg_bytes=0
msg_count=0
unread_kept=0

# --- Messages ---------------------------------------------------------------
# find without -L never follows symlinks; -type f skips symlinked files.
# Files are only candidates when not modified for N days (reading a message
# rewrites it, so a recently read message is never old enough).
if [ -d "$AMP_SENT_DIR" ]; then
    while IFS= read -r -d '' f; do
        echo "$f" >> "$DEL_MSGS"
    done < <(find "$AMP_SENT_DIR" -type f -name '*.json' -mtime +"$DAYS" -print0 2>/dev/null)
fi

if [ -d "$AMP_INBOX_DIR" ]; then
    while IFS= read -r -d '' f; do
        status=$(jq -r '.local.status // .metadata.status // "unread"' "$f" 2>/dev/null)
        if [ "$status" = "unread" ] && [ "$INCLUDE_UNREAD" != true ]; then
            unread_kept=$((unread_kept + 1))
            continue
        fi
        # A file jq cannot parse yields an empty status: leave it alone.
        [ -n "$status" ] || continue
        echo "$f" >> "$DEL_MSGS"
    done < <(find "$AMP_INBOX_DIR" -type f -name '*.json' -mtime +"$DAYS" -print0 2>/dev/null)
fi

while IFS= read -r f; do
    [ -f "$f" ] && [ ! -L "$f" ] || continue
    msg_bytes=$((msg_bytes + $(wc -c < "$f" | tr -d ' ')))
    msg_count=$((msg_count + 1))
done < "$DEL_MSGS"

# --- Attachments ------------------------------------------------------------
# Every quoted string in a message that will remain (ids, attachment ids).
# Reading raw text rather than parsing keeps this safe for malformed files:
# anything unreadable still protects the folders it mentions.
ALL_MSGS="${WORK}/all_msgs"; KEEP_MSGS="${WORK}/keep_msgs"; REFS="${WORK}/refs"
{
    [ -d "$AMP_INBOX_DIR" ] && find "$AMP_INBOX_DIR" -type f -name '*.json' 2>/dev/null
    [ -d "$AMP_SENT_DIR" ] && find "$AMP_SENT_DIR" -type f -name '*.json' 2>/dev/null
} | sort > "$ALL_MSGS"
sort "$DEL_MSGS" > "${WORK}/del_sorted"
comm -23 "$ALL_MSGS" "${WORK}/del_sorted" > "$KEEP_MSGS"
: > "$REFS"
if [ -s "$KEEP_MSGS" ]; then
    tr '\n' '\0' < "$KEEP_MSGS" | xargs -0 grep -ho '"[^"]*"' 2>/dev/null | sort -u > "$REFS"
fi

att_bytes=0
att_count=0
if [ -d "$AMP_ATTACHMENTS_DIR" ]; then
    while IFS= read -r -d '' d; do
        name=$(basename "$d")
        # Only folders named like attachment or message ids.
        [[ "$name" =~ ^[A-Za-z0-9._-]+$ ]] || continue
        # Anything inside changed recently: keep.
        if [ -n "$(find "$d" -mtime -"$DAYS" -print -quit 2>/dev/null)" ]; then
            continue
        fi
        # A remaining message refers to it: keep.
        if grep -qxF "\"${name}\"" "$REFS" 2>/dev/null; then
            continue
        fi
        echo "$d" >> "$DEL_ATTS"
        kb=$(du -sk "$d" 2>/dev/null | cut -f1)
        att_bytes=$((att_bytes + ${kb:-0} * 1024))
        att_count=$((att_count + 1))
    done < <(find "$AMP_ATTACHMENTS_DIR" -mindepth 1 -maxdepth 1 -type d -mtime +"$DAYS" -print0 2>/dev/null)
fi

# --- Apply ------------------------------------------------------------------
if [ "$APPLY" = true ]; then
    while IFS= read -r f; do
        [ -f "$f" ] && [ ! -L "$f" ] || continue
        case "$f" in
            "${AMP_INBOX_DIR}"/*|"${AMP_SENT_DIR}"/*) rm -f -- "$f" ;;
        esac
    done < "$DEL_MSGS"
    while IFS= read -r d; do
        [ -d "$d" ] && [ ! -L "$d" ] || continue
        case "$d" in
            "${AMP_ATTACHMENTS_DIR}"/*) rm -rf -- "$d" ;;
        esac
    done < "$DEL_ATTS"
    # Sender and recipient folders left empty
    for box in "$AMP_INBOX_DIR" "$AMP_SENT_DIR"; do
        [ -d "$box" ] && find "$box" -mindepth 1 -maxdepth 1 -type d -empty -exec rmdir {} + 2>/dev/null
    done
fi

total=$((msg_bytes + att_bytes))
if [ "$APPLY" = true ]; then verb="Removed"; else verb="Would remove"; fi
echo "${verb}: ${msg_count} message(s), ${att_count} attachment folder(s), ${total} bytes (older than ${DAYS} days)"
[ "$unread_kept" -gt 0 ] && echo "Kept ${unread_kept} old unread message(s); use --include-unread to remove them."
[ "$APPLY" = true ] || echo "Dry run: nothing was deleted. Use --apply to delete."
exit 0
