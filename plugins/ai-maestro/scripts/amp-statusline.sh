#!/bin/bash
# =============================================================================
# AMP Status Line for Claude Code
# =============================================================================
#
# Displays your AMP agent name, address and folder, the unread message count,
# the model, context size, cost, effort, prompt-cache state and time since the
# last turn in the Claude Code status bar (the lines at the bottom of the
# terminal), and reports the same facts to AI Maestro for the dashboard.
#
# Usage:
#   amp-statusline.sh --install     # Install into Claude Code settings
#   amp-statusline.sh --uninstall   # Remove from Claude Code settings
#   amp-statusline.sh --test        # Test output with current agent
#   amp-statusline.sh               # Called by Claude Code (reads JSON from stdin)
#
# Agent resolution order:
#   1. AMP_AGENT_ID env var (explicit UUID)
#   2. CLAUDE_AGENT_NAME env var (AI Maestro sets this)
#   2.5 Claude Code native session_name (`claude --name`), if it maps to an agent
#   3. tmux session name
#   4. Working directory → AI Maestro API lookup
#   5. Working directory → walk up to .claude/settings.local.json for
#      CLAUDE_AGENT_NAME hint
#
# =============================================================================

SCRIPT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
SETTINGS_FILE="${HOME}/.claude/settings.json"

# --- Install / Uninstall / Test ---
case "${1:-}" in
    --install)
        if [ ! -f "$SETTINGS_FILE" ]; then
            echo '{}' > "$SETTINGS_FILE"
        fi

        # Check if statusLine already exists
        EXISTING=$(jq -r '.statusLine.command // empty' "$SETTINGS_FILE" 2>/dev/null)
        SAME_SCRIPT=0
        if [ -n "$EXISTING" ] && [ "$(basename "$EXISTING")" = "amp-statusline.sh" ]; then
            SAME_SCRIPT=1
        fi
        if [ -n "$EXISTING" ] && [ "$SAME_SCRIPT" = "0" ]; then
            echo "Status line already configured: $EXISTING"
            echo ""
            read -r -p "Replace with AMP status line? [y/N] " CONFIRM
            [ "$CONFIRM" != "y" ] && [ "$CONFIRM" != "Y" ] && exit 0
        fi

        # refreshInterval re-runs the script every 60 s while the session is idle,
        # so "cache warm N m" and "last turn N m ago" stay current. A value the
        # user already set is kept. When the command is already this script
        # (an upgrade) nothing is asked: the other settings are kept as they are.
        jq --arg cmd "$SCRIPT_PATH" \
            '.statusLine = ((.statusLine // {}) + { type: "command", command: $cmd, refreshInterval: (.statusLine.refreshInterval // 60) })' \
            "$SETTINGS_FILE" > "${SETTINGS_FILE}.tmp" && mv "${SETTINGS_FILE}.tmp" "$SETTINGS_FILE"

        if [ "$SAME_SCRIPT" = "1" ]; then
            echo "AMP status line updated."
        else
            echo "AMP status line installed."
        fi
        echo ""
        echo "  Script:   $SCRIPT_PATH"
        echo "  Settings: $SETTINGS_FILE"
        echo ""
        echo "Restart Claude Code to see it. The status bar will show:"
        echo "  name · your-agent@tenant.provider · folder | N unread"
        echo "  Model | ctx 42k (4%) | \$cost | effort high | cache warm 12m | last turn 7m ago"
        echo "  (adds /compact soon at 150k, /compact now over 200k)"
        exit 0
        ;;

    --uninstall)
        if [ ! -f "$SETTINGS_FILE" ]; then
            echo "No settings file found."
            exit 0
        fi
        jq 'del(.statusLine)' "$SETTINGS_FILE" > "${SETTINGS_FILE}.tmp" \
            && mv "${SETTINGS_FILE}.tmp" "$SETTINGS_FILE"
        echo "AMP status line removed. Restart Claude Code."
        exit 0
        ;;

    --test)
        echo '{"model":{"display_name":"Test"},"context_window":{"used_percentage":25},"cost":{"total_cost_usd":0},"workspace":{"current_dir":"'"$PWD"'"}}' \
            | "$SCRIPT_PATH"
        exit 0
        ;;

    --help|-h)
        echo "Usage: amp-statusline.sh [--install | --uninstall | --test]"
        echo ""
        echo "AMP status line for Claude Code."
        echo ""
        echo "Options:"
        echo "  --install    Add AMP status line to Claude Code settings"
        echo "  --uninstall  Remove AMP status line from Claude Code settings"
        echo "  --test       Test output using current working directory"
        echo "  --help       Show this help"
        echo ""
        echo "When called with no arguments, reads Claude Code session JSON"
        echo "from stdin and outputs the status line (called automatically"
        echo "by Claude Code)."
        exit 0
        ;;
esac

# =============================================================================
# Status line output (called by Claude Code via stdin JSON)
# =============================================================================

input=$(cat)

# Extract Claude Code session data
MODEL=$(echo "$input" | jq -r '.model.display_name // "?"')
PCT=$(echo "$input" | jq -r '.context_window.used_percentage // 0' | cut -d. -f1)
# Absolute context size: a percentage hides cost on 1M-context models (79% of
# 1M is ~790k tokens re-read on every step). Every token above 200k is billed
# at the long-context rate (2x).
CTX_TOKENS=$(echo "$input" | jq -r '.context_window.total_input_tokens // 0' | cut -d. -f1)
OVER_200K=$(echo "$input" | jq -r '.exceeds_200k_tokens // false')
COST=$(echo "$input" | jq -r '.cost.total_cost_usd // 0')
CWD=$(echo "$input" | jq -r '.workspace.current_dir // empty')
# Claude Code's native session name (set by `claude --name` / `/rename`). Present
# only when a custom or AI-generated title exists; used below as an identity hint.
SESSION_NAME=$(echo "$input" | jq -r '.session_name // empty')
# Shown on row 2 and reported to AI Maestro (all optional; absent means unknown).
SESSION_ID=$(echo "$input" | jq -r '.session_id // empty')
MODEL_ID=$(echo "$input" | jq -r '.model.id // empty')
CTX_WINDOW=$(echo "$input" | jq -r '.context_window.context_window_size // empty')
EFFORT=$(echo "$input" | jq -r '.effort.level // empty')
# prompt_cache.warm is a boolean: "true", "false", or empty when the block is absent.
CACHE_WARM=$(echo "$input" | jq -r 'if .prompt_cache == null or .prompt_cache.warm == null then "" else (.prompt_cache.warm | tostring) end')
CACHE_EXPIRES=$(echo "$input" | jq -r '.prompt_cache.expires_at // empty')
TRANSCRIPT=$(echo "$input" | jq -r '.transcript_path // empty')

# --- Resolve AMP agent ---
AGENTS_BASE="${HOME}/.agent-messaging/agents"
INDEX_FILE="${AGENTS_BASE}/.index.json"

AGENT_UUID=""
AGENT_NAME=""
AGENT_ADDRESS=""
UNREAD=0

# Priority 1: Explicit agent ID
if [ -n "${AMP_AGENT_ID:-}" ]; then
    AGENT_UUID="$AMP_AGENT_ID"

# Priority 2: Agent name from env
elif [ -n "${CLAUDE_AGENT_NAME:-}" ]; then
    AGENT_NAME="$CLAUDE_AGENT_NAME"

# Priority 2.5: Claude Code's native session name (set by `claude --name`, as
# AI Maestro does when launching an agent). Trust it ONLY when it maps to a known
# agent — an AI-generated session title must not shadow the cwd/hint fallbacks.
elif [ -n "$SESSION_NAME" ] && [ -f "$INDEX_FILE" ] && \
     [ -n "$(jq -r --arg n "$SESSION_NAME" '.[$n] // empty' "$INDEX_FILE" 2>/dev/null)" ]; then
    AGENT_NAME="$SESSION_NAME"

# Priority 3: tmux session name
elif [ -n "${TMUX:-}" ]; then
    AGENT_NAME=$(tmux display-message -p '#S' 2>/dev/null)

# Priority 4: Working directory → AI Maestro API
elif [ -n "$CWD" ]; then
    # Match by working directory, but ONLY when it uniquely identifies one agent.
    # Many agents can share a dir, or claim a broad one ($HOME), so taking the first
    # match silently showed the WRONG identity (every session under $HOME becoming
    # "piano-instructor", or a dev dir picking a random one of the agents there).
    # Pick the MOST SPECIFIC match (longest workingDirectory); if several tie, the cwd
    # is ambiguous, so show nothing rather than a wrong name.
    MAESTRO_AGENT=$(curl -s --connect-timeout 1 "${AMP_MAESTRO_URL:-http://localhost:23000}/api/agents" 2>/dev/null | \
        jq -r --arg cwd "$CWD" '
            [ .agents[]
              | (.workingDirectory // .session.workingDirectory // "") as $wd
              | select($wd != "" and ($cwd == $wd or ($cwd | startswith($wd + "/"))))
              | {name: .name, len: ($wd | length)} ]
            | (map(.len) | max) as $mx
            | map(select(.len == $mx))
            | if length == 1 then .[0].name else empty end
        ' 2>/dev/null)
    [ -n "$MAESTRO_AGENT" ] && AGENT_NAME="$MAESTRO_AGENT"
fi

# Priority 5: Walk up directories for .claude/settings.local.json hint
if [ -z "$AGENT_UUID" ] && [ -z "$AGENT_NAME" ] && [ -n "$CWD" ]; then
    _dir="$CWD"
    while [ "$_dir" != "/" ] && [ "$_dir" != "$HOME" ]; do
        _settings="${_dir}/.claude/settings.local.json"
        if [ -f "$_settings" ]; then
            # Read the REAL env hint, not any occurrence of the string in the file.
            # grep-ing the raw file matched permission allow-list entries like
            # "Bash(CLAUDE_AGENT_NAME=foo amp-send.sh:*)" and showed a bogus identity.
            _hint=$(jq -r '(.env.CLAUDE_AGENT_NAME // .env.AIM_AGENT_NAME // empty)' "$_settings" 2>/dev/null)
            if [ -n "$_hint" ]; then
                AGENT_NAME="$_hint"
                break
            fi
        fi
        _dir=$(dirname "$_dir")
    done
fi

# Resolve name → UUID via index
if [ -z "$AGENT_UUID" ] && [ -n "$AGENT_NAME" ] && [ -f "$INDEX_FILE" ]; then
    AGENT_UUID=$(jq -r --arg n "$AGENT_NAME" '.[$n] // empty' "$INDEX_FILE" 2>/dev/null)
    # Case-insensitive fallback
    if [ -z "$AGENT_UUID" ]; then
        _lower=$(echo "$AGENT_NAME" | tr '[:upper:]' '[:lower:]')
        AGENT_UUID=$(jq -r --arg n "$_lower" \
            'to_entries[] | select(.key | ascii_downcase == $n) | .value' \
            "$INDEX_FILE" 2>/dev/null | head -1)
    fi
fi

# Read identity and count unread
if [ -n "$AGENT_UUID" ]; then
    CONFIG_FILE="${AGENTS_BASE}/${AGENT_UUID}/config.json"
    if [ -f "$CONFIG_FILE" ]; then
        AGENT_ADDRESS=$(jq -r '.agent.address // empty' "$CONFIG_FILE" 2>/dev/null)
    fi

    INBOX_DIR="${AGENTS_BASE}/${AGENT_UUID}/messages/inbox"
    if [ -d "$INBOX_DIR" ]; then
        while IFS= read -r -d '' msg_file; do
            STATUS=$(jq -r '.local.status // .metadata.status // "unread"' "$msg_file" 2>/dev/null)
            [ "$STATUS" = "unread" ] && UNREAD=$((UNREAD + 1))
        done < <(find "$INBOX_DIR" -name '*.json' -type f -print0 2>/dev/null)
    fi
fi

# Report this session's cumulative cost to AI Maestro so the agent's "API Cost"
# metric reflects real usage. Best-effort, backgrounded, never blocks the render.
# Only PATCH when the cost has GROWN (monotonic): avoids spamming the API every
# render and avoids the value dipping to ~0 when a new session starts. (Lifetime
# accumulation across sessions is a later OTLP concern.)
if [ -n "$AGENT_UUID" ] && [ -n "$COST" ] && [ -d "${AGENTS_BASE}/${AGENT_UUID}" ]; then
    _cost_cache="${AGENTS_BASE}/${AGENT_UUID}/.last-cost"
    _last_cost=$(cat "$_cost_cache" 2>/dev/null || echo 0)
    if awk -v c="$COST" -v l="$_last_cost" 'BEGIN{exit !(c+0 > l+0)}' 2>/dev/null; then
        echo "$COST" > "$_cost_cache" 2>/dev/null
        curl -s -m 2 -X PATCH "${AMP_MAESTRO_URL:-http://localhost:23000}/api/agents/${AGENT_UUID}/metrics" \
            -H 'Content-Type: application/json' -d "{\"estimatedCost\": ${COST}}" >/dev/null 2>&1 &
    fi
fi

# --- Build status line ---
# Row 1 names the agent: name, AMP address and folder, then the unread count.
# Row 2 (below) is the model, context size and cost.
#
# The name is the one resolved above, else the one in the agent's config. The
# folder is the working directory with $HOME shown as ~. In a narrow pane the
# row is shortened in this order: the folder keeps its last two components, then
# the folder is dropped, then the name (the address already holds it). The width
# comes from COLUMNS, which Claude Code sets before it runs this script.
if [ -z "$AGENT_NAME" ] && [ -n "$AGENT_UUID" ] && [ -f "${AGENTS_BASE}/${AGENT_UUID}/config.json" ]; then
    AGENT_NAME=$(jq -r '.agent.name // empty' "${AGENTS_BASE}/${AGENT_UUID}/config.json" 2>/dev/null)
fi

FOLDER=""
if [ -n "$CWD" ]; then
    TILDE='~'   # shown literally: the folder is for display, not for use as a path
    case "$CWD" in
        "$HOME") FOLDER="$TILDE" ;;
        "$HOME"/*) FOLDER="${TILDE}/${CWD#"$HOME"/}" ;;
        *) FOLDER="$CWD" ;;
    esac
fi

if [ -n "$AGENT_ADDRESS" ]; then
    if [ "$UNREAD" -gt 0 ]; then
        UNREAD_PLAIN="${UNREAD} unread"
        UNREAD_PART="\033[33m${UNREAD} unread\033[0m"
    else
        UNREAD_PLAIN="0 unread"
        UNREAD_PART="0 unread"
    fi

    # Join the non-empty parts with " · ".
    _join() {
        local out="" p
        for p in "$@"; do
            [ -n "$p" ] && out="${out:+$out · }$p"
        done
        printf '%s' "$out"
    }
    # The last two path components, "…/a/b", for a long folder.
    _short_folder() {
        local f="$1" tail
        tail=$(printf '%s' "$f" | awk -F/ '{ n=NF; if (n>2) print $(n-1) "/" $n; else print $0 }')
        if [ "$tail" = "$f" ]; then printf '%s' "$f"; else printf '…/%s' "$tail"; fi
    }
    # Length in characters (UTF-8 aware where the locale allows).
    _len() { printf '%s' "$1" | wc -m | tr -d ' '; }

    COLS="${COLUMNS:-0}"
    case "$COLS" in ''|*[!0-9]*) COLS=0 ;; esac
    SUFFIX_LEN=$(( $(_len " | ${UNREAD_PLAIN}") ))

    ROW1=$(_join "$AGENT_NAME" "$AGENT_ADDRESS" "$FOLDER")
    if [ "$COLS" -gt 0 ] && [ $(( $(_len "$ROW1") + SUFFIX_LEN )) -gt "$COLS" ]; then
        ROW1=$(_join "$AGENT_NAME" "$AGENT_ADDRESS" "$(_short_folder "$FOLDER")")
    fi
    if [ "$COLS" -gt 0 ] && [ $(( $(_len "$ROW1") + SUFFIX_LEN )) -gt "$COLS" ]; then
        ROW1=$(_join "$AGENT_NAME" "$AGENT_ADDRESS")
    fi
    if [ "$COLS" -gt 0 ] && [ $(( $(_len "$ROW1") + SUFFIX_LEN )) -gt "$COLS" ]; then
        ROW1="$AGENT_ADDRESS"
    fi
    AMP_PART="${ROW1} | ${UNREAD_PART}"
else
    AMP_PART="AMP: not configured (run amp-init)"
fi

COST_FMT=$(printf '%.2f' "$COST")

# Recommend /compact before a session gets expensive (AMP_STATUSLINE_COMPACT_AT,
# default 150k tokens: a margin before the 200k long-context price step).
COMPACT_AT="${AMP_STATUSLINE_COMPACT_AT:-150000}"
case "$CTX_TOKENS" in ''|*[!0-9]*) CTX_TOKENS=0 ;; esac
case "$COMPACT_AT" in ''|*[!0-9]*) COMPACT_AT=150000 ;; esac
if [ "$CTX_TOKENS" -ge 1000 ]; then
    CTX_SIZE="$(( (CTX_TOKENS + 500) / 1000 ))k (${PCT}%)"
else
    CTX_SIZE="${PCT}%"
fi
if [ "$OVER_200K" = "true" ] || [ "$CTX_TOKENS" -ge 200000 ]; then
    CTX="\033[31m${CTX_SIZE} · ⚠ /compact now: 2× cost\033[0m"
elif [ "$CTX_TOKENS" -ge "$COMPACT_AT" ]; then
    CTX="\033[33m${CTX_SIZE} · /compact soon\033[0m"
elif [ "$PCT" -ge 80 ]; then
    CTX="\033[31m${CTX_SIZE}\033[0m"
elif [ "$PCT" -ge 50 ]; then
    CTX="\033[33m${CTX_SIZE}\033[0m"
else
    CTX="${CTX_SIZE}"
fi

# --- Row 2: the same facts the dashboard chat header shows ---
# model | ctx | cost | effort | cache | last turn. A part is left out when unknown.
NOW_S=$(date +%s)
case "$CACHE_EXPIRES" in ''|*[!0-9]*) CACHE_EXPIRES="" ;; esac
case "$CTX_WINDOW" in ''|*[!0-9]*) CTX_WINDOW="" ;; esac

ROW2="$MODEL | ctx $CTX | \$$COST_FMT"
[ -n "$EFFORT" ] && ROW2="$ROW2 | effort $EFFORT"

# Cache: warm with time left, or cold. Warm but past its expiry is cold.
if [ "$CACHE_WARM" = "true" ] && [ -n "$CACHE_EXPIRES" ]; then
    if [ "$CACHE_EXPIRES" -gt "$NOW_S" ]; then
        ROW2="$ROW2 | cache warm $(( (CACHE_EXPIRES - NOW_S + 59) / 60 ))m"
    else
        ROW2="$ROW2 | cache cold"
    fi
elif [ "$CACHE_WARM" = "false" ]; then
    ROW2="$ROW2 | cache cold"
fi

# Last turn: the transcript was last written this long ago. Shown after 2 minutes
# of quiet; the idle refresh (refreshInterval) keeps it current.
if [ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ]; then
    # GNU stat first: on Linux `stat -f` means "filesystem status" and prints a
    # block of text (and succeeds in part), so the BSD form must come second.
    MTIME=$(stat -c %Y "$TRANSCRIPT" 2>/dev/null || stat -f %m "$TRANSCRIPT" 2>/dev/null)
    case "$MTIME" in ''|*[!0-9]*) MTIME="" ;; esac
    if [ -n "$MTIME" ] && [ $(( NOW_S - MTIME )) -gt 120 ]; then
        # Same units as the dashboard header: 12m, 3h, 2d.
        IDLE_M=$(( (NOW_S - MTIME) / 60 ))
        if [ "$IDLE_M" -ge 1440 ]; then IDLE_TXT="$(( IDLE_M / 1440 ))d"
        elif [ "$IDLE_M" -ge 60 ]; then IDLE_TXT="$(( IDLE_M / 60 ))h"
        else IDLE_TXT="${IDLE_M}m"; fi
        ROW2="$ROW2 | last turn ${IDLE_TXT} ago"
    fi
fi

# --- Report this session's status to AI Maestro (the dashboard header reads it) ---
# Best effort, backgrounded, silent, never blocks the render. At most once every
# 10 s per agent, and at once when the cost, effort or cache state changed.
if [ -n "$AGENT_UUID" ] && [ -d "${AGENTS_BASE}/${AGENT_UUID}" ]; then
    _snap_cache="${AGENTS_BASE}/${AGENT_UUID}/.last-status-snapshot"
    _snap_key="${COST}|${EFFORT}|${CACHE_WARM}"
    _snap_last=$(cat "$_snap_cache" 2>/dev/null)
    _snap_ts="${_snap_last%%|*}"
    _snap_prev="${_snap_last#*|}"
    case "$_snap_ts" in ''|*[!0-9]*) _snap_ts=0 ;; esac
    if [ "$_snap_prev" != "$_snap_key" ] || [ $(( NOW_S - _snap_ts )) -ge 10 ]; then
        echo "${NOW_S}|${_snap_key}" > "$_snap_cache" 2>/dev/null
        _cost_num="$COST"
        case "$_cost_num" in ''|*[!0-9.]*|*.*.*) _cost_num=0 ;; esac
        _snap_json=$(jq -n -c \
            --arg sessionId "$SESSION_ID" --arg model "$MODEL" --arg modelId "$MODEL_ID" \
            --argjson contextTokens "${CTX_TOKENS:-0}" --arg contextWindow "$CTX_WINDOW" \
            --argjson contextPercent "${PCT:-0}" --argjson cost "$_cost_num" \
            --arg effort "$EFFORT" --arg cacheWarm "$CACHE_WARM" --arg cacheExpiresAt "$CACHE_EXPIRES" \
            --arg exceeds "$OVER_200K" --argjson ts "${NOW_S}000" \
            '{sessionId: (if $sessionId == "" then null else $sessionId end),
              model: $model, modelId: (if $modelId == "" then null else $modelId end),
              contextTokens: $contextTokens,
              contextWindow: (if $contextWindow == "" then null else ($contextWindow | tonumber) end),
              contextPercent: $contextPercent, cost: $cost,
              effort: (if $effort == "" then null else $effort end),
              cacheWarm: (if $cacheWarm == "true" then true elif $cacheWarm == "false" then false else null end),
              cacheExpiresAt: (if $cacheExpiresAt == "" then null else ($cacheExpiresAt | tonumber) end),
              exceeds200k: ($exceeds == "true"), ts: $ts}' 2>/dev/null)
        if [ -n "$_snap_json" ]; then
            curl -s -m 1 -X POST "${AMP_MAESTRO_URL:-http://localhost:23000}/api/agents/${AGENT_UUID}/status-snapshot" \
                -H 'Content-Type: application/json' -d "$_snap_json" >/dev/null 2>&1 &
        fi
    fi
fi

echo -e "$AMP_PART"
echo -e "$ROW2"
