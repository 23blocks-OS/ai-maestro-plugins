#!/bin/bash
# aimaestro-call.sh - ring a person from an agent.
# The call is started on your host and rings the person's paired phones (the AI Maestro app) through
# push. It is signalling only: the person sees who is calling and answers or declines; there is no
# audio yet. Use it when a person must act now and a message would wait; otherwise send a message.
#
# Version: 1.0.1
set -u -o pipefail

API="${AIMAESTRO_API:-http://localhost:23000}"
API="${API%/}"
AGENT="${AIM_AGENT_ID:-}"

die() { echo "Error: $*" >&2; exit 1; }

command -v curl >/dev/null 2>&1 || die "curl is required"
command -v jq >/dev/null 2>&1 || die "jq is required"

usage() {
  cat <<'USAGE'
Usage: aimaestro-call.sh [--agent <id>] <command> ...

Commands:
  people                                   The people you can call, from every host you can reach
  person "<name, email or person id>" [--ttl <seconds>]
                                           Ring that person's phones; prints the call id. Rings for 30 s
                                           by default (at most 120)
  status <callId>                          The call's state
  wait <callId> [--timeout <seconds>]      Wait until the call is answered or over (default 60 s)
  cancel <callId>                          Stop ringing (before it is answered)
  end <callId>                             Hang up

Exit codes: 0 done (for wait: answered), 1 error, 2 not answered (declined, canceled, timed out,
failed or ended), 3 still ringing when --timeout ran out.
Your agent id comes from AIM_AGENT_ID (set in your session); --agent overrides it.
USAGE
}

while [ $# -gt 0 ]; do
  case "$1" in
    --agent) [ $# -ge 2 ] || die "--agent needs a value"; AGENT="$2"; shift 2 ;;
    -h|--help|help) usage; exit 0 ;;
    --) shift; break ;;
    -*) die "Unknown option: $1" ;;
    *) break ;;
  esac
done

CMD="${1:-}"
[ -n "$CMD" ] || { usage; exit 1; }
shift

# curl that fails on HTTP errors and prints the server's message
call_api() {
  local method="$1" url="$2" body="${3:-}" out code
  if [ -n "$body" ]; then
    out=$(curl -sS -m 15 -X "$method" -H 'Content-Type: application/json' --data "$body" -w '\n%{http_code}' "$url") || die "could not reach $url"
  else
    out=$(curl -sS -m 15 -X "$method" -w '\n%{http_code}' "$url") || die "could not reach $url"
  fi
  code="${out##*$'\n'}"
  out="${out%$'\n'*}"
  if [ "$code" -ge 400 ] 2>/dev/null; then
    die "$(echo "$out" | jq -r '.message // .error // empty' 2>/dev/null || echo "HTTP $code") (HTTP $code)"
  fi
  printf '%s' "$out"
}

# Base URLs of every enabled host: this one first (by $API), then the peers
host_bases() {
  echo "$API"
  curl -sS -m 4 "$API/api/hosts" 2>/dev/null \
    | jq -r '.hosts[]? | select(.enabled != false) | select((.isSelf // false) | not) | .url // empty' 2>/dev/null \
    | sed 's:/*$::' || true
}

# Every active person on every reachable host, one JSON object per line (first host wins on duplicates)
all_people() {
  local base
  host_bases | while read -r base; do
    [ -n "$base" ] || continue
    curl -sS -m 4 "$base/api/people" 2>/dev/null | jq -c '.people[]? | select(.active != false) | {id, displayName, email, hostId}' 2>/dev/null || true
  done | jq -s -c 'unique_by(.id)[]'
}

# Can this person's phone ring? (a paired device on any host with push for calls)
can_ring() {
  local pid="$1" base
  host_bases | while read -r base; do
    [ -n "$base" ] || continue
    curl -sS -m 4 "$base/api/people-devices?personId=$pid" 2>/dev/null \
      | jq -r '.devices[]? | select(.pushEnabled == true and ((.pushTypes // []) | index("call"))) | "yes"' 2>/dev/null || true
  done | head -1
}

event() {
  local id="$1" type="$2"
  [ -n "$AGENT" ] || die "no agent id: set AIM_AGENT_ID or pass --agent"
  call_api POST "$API/api/calls/$id/events" \
    "$(jq -n --arg t "$type" --arg e "$(uuidgen 2>/dev/null || date +%s%N)" --arg a "agent:$AGENT" '{type: $t, eventId: $e, actor: $a}')" >/dev/null
}

case "$CMD" in
  people)
    all_people | jq -r '"\(.displayName)\t\(.email // "-")\t\(.id)\t(\(.hostId))"'
    ;;

  person)
    [ -n "$AGENT" ] || die "no agent id: set AIM_AGENT_ID or pass --agent"
    WHO="${1:-}"; [ -n "$WHO" ] || die "person needs a name, email or person id"
    shift
    TTL=30
    while [ $# -gt 0 ]; do
      case "$1" in
        --ttl) [ $# -ge 2 ] || die "--ttl needs a value"; TTL="$2"; shift 2 ;;
        *) die "Unknown option: $1" ;;
      esac
    done
    PEOPLE=$(all_people)
    MATCH=$(printf '%s\n' "$PEOPLE" | jq -c --arg w "$WHO" 'select(.id == $w or ((.displayName // "") | ascii_downcase) == ($w | ascii_downcase) or ((.email // "") | ascii_downcase) == ($w | ascii_downcase))')
    COUNT=$(printf '%s' "$MATCH" | grep -c . || true)
    [ "$COUNT" -gt 0 ] || die "no person called \"$WHO\" in the directory (see: aimaestro-call.sh people)"
    if [ "$COUNT" -gt 1 ]; then
      echo "More than one person matches \"$WHO\"; use the id:" >&2
      printf '%s\n' "$MATCH" | jq -r '"  \(.displayName)\t\(.email // "-")\t\(.id)"' >&2
      exit 1
    fi
    PID=$(printf '%s' "$MATCH" | jq -r '.id')
    NAME=$(printf '%s' "$MATCH" | jq -r '.displayName')
    OUT=$(call_api POST "$API/api/calls" "$(jq -n --arg c "agent:$AGENT" --arg p "person:$PID" --argjson t "$TTL" '{caller: $c, callee: $p, ttlSeconds: $t}')")
    CID=$(echo "$OUT" | jq -r '.call.callId')
    echo "$CID"
    if [ -z "$(can_ring "$PID")" ]; then
      echo "Note: $NAME's phone has no push for calls yet, so it will not ring; they see the call only if the app is open. Send a message too." >&2
    else
      echo "Ringing $NAME for ${TTL}s. Check with: aimaestro-call.sh wait $CID" >&2
    fi
    ;;

  status)
    ID="${1:-}"; [ -n "$ID" ] || die "status needs a call id"
    call_api GET "$API/api/calls/$ID" | jq -r '.call | "\(.state)\t\(.caller) -> \(.callee)"'
    ;;

  wait)
    ID="${1:-}"; [ -n "$ID" ] || die "wait needs a call id"
    shift
    LIMIT=60
    while [ $# -gt 0 ]; do
      case "$1" in
        --timeout) [ $# -ge 2 ] || die "--timeout needs a value"; LIMIT="$2"; shift 2 ;;
        *) die "Unknown option: $1" ;;
      esac
    done
    END=$(( $(date +%s) + LIMIT ))
    while :; do
      STATE=$(call_api GET "$API/api/calls/$ID" | jq -r '.call.state')
      case "$STATE" in
        accepted|connected) echo "$STATE"; exit 0 ;;
        rejected|canceled|timed_out|failed|ended) echo "$STATE"; exit 2 ;;
      esac
      [ "$(date +%s)" -lt "$END" ] || { echo "$STATE"; exit 3; }
      sleep 2
    done
    ;;

  cancel) [ -n "${1:-}" ] || die "cancel needs a call id"; event "$1" rtc:cancel; echo "canceled" ;;
  end)    [ -n "${1:-}" ] || die "end needs a call id";    event "$1" rtc:end;    echo "ended" ;;

  *) usage; exit 1 ;;
esac
