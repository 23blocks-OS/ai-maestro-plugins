#!/bin/bash
# aimaestro-task.sh - an agent's own board in AI Maestro.
# Add a card when you take on a task, move it when the task moves, say what it waits on,
# and answer comments on it. Cards live where you live (this host), on your own board;
# with --team a card goes on a team board instead.
#
# Version: 1.0.0
set -u -o pipefail

API="${AIMAESTRO_API:-http://localhost:23000}"
API="${API%/}"
AGENT="${AIM_AGENT_ID:-}"
TEAM=""
STATUS_LIST="backlog pending in_progress review waiting completed"

die() { echo "Error: $*" >&2; exit 1; }

command -v curl >/dev/null 2>&1 || die "curl is required"
command -v jq >/dev/null 2>&1 || die "jq is required"

usage() {
  cat <<'USAGE'
Usage: aimaestro-task.sh [--agent <id>] [--team <teamId>] <command> ...

Commands:
  add "<subject>" [--desc "<text>"] [--blocked-by <id>]... [--team <teamId>] [--quadrant q1|q2|q3|q4]   Add a card (starts as To Do)
  start <id>                                                  Move to In Progress
  review <id>                                                 Move to Review
  done <id>                                                   Move to Done
  move <id> <status>                                          backlog | pending | in_progress | review | completed
  wait <id> --on juan|outside|hold|<agent-id> [--note "<text>"]   Waiting, and on whom
  comment <id> "<text>"                                       Write on the card (stored and shown; never sent to anyone)
  place <id> q1|q2|q3|q4|none                                 Put a card on the Eisenhower matrix (none = take it off)
  list [--mine] [--waiting-on <who>] [--status <status>] [--quadrant q1|q2|q3|q4|unplaced]   Your board (own cards + team cards assigned to you)
  show <id>                                                   One card with its comments

<id> is the full id or the first characters shown in "[TASK d773ef06]" (it must be unique).
Quadrants: q1 urgent+important (do first), q2 important only (schedule), q3 urgent only (delegate), q4 neither (delete).
Your agent id comes from AIM_AGENT_ID (set in your session); --agent overrides it.
An operator's instruction on a card arrives in your prompt as "[TASK <id>] ... instruction from the operator".
Answer it with: aimaestro-task.sh comment <id> "<what you did or need>".
USAGE
}

# ---- global flags (before the command) ----
while [ $# -gt 0 ]; do
  case "$1" in
    --agent) [ $# -ge 2 ] || die "--agent needs a value"; AGENT="$2"; shift 2 ;;
    --team)  [ $# -ge 2 ] || die "--team needs a value"; TEAM="$2"; shift 2 ;;
    -h|--help|help) usage; exit 0 ;;
    --) shift; break ;;
    -*) die "Unknown option: $1" ;;
    *) break ;;
  esac
done

CMD="${1:-}"
[ -n "$CMD" ] || { usage; exit 1; }
shift

[ -n "$AGENT" ] || die "I do not know which agent you are: AIM_AGENT_ID is not set. Pass --agent <id>."

# ---- HTTP ----
# call METHOD PATH [json-body]  -> prints the body; fails with the server's message on a non-2xx answer
call() {
  local method="$1" path="$2" body="${3:-}" out code
  if [ -n "$body" ]; then
    out=$(curl -sS --max-time 15 -X "$method" -H 'Content-Type: application/json' -d "$body" -w '\n%{http_code}' "${API}${path}" 2>&1) || die "Could not reach AI Maestro at ${API}: ${out}"
  else
    out=$(curl -sS --max-time 15 -X "$method" -w '\n%{http_code}' "${API}${path}" 2>&1) || die "Could not reach AI Maestro at ${API}: ${out}"
  fi
  code="${out##*$'\n'}"
  out="${out%$'\n'*}"
  case "$code" in
    2*) printf '%s' "$out" ;;
    *)  die "$(printf '%s' "$out" | jq -r '.message // .error // empty' 2>/dev/null || true) (HTTP ${code})" ;;
  esac
}

board() { call GET "/api/agents/${AGENT}/board"; }

# Find a card on the board by full id or unique prefix; prints "<scope>|<teamId or ->|<id>"
# ("|" and not a tab: read collapses empty tab-separated fields)
resolve() {
  local want="$1" b matches n
  [ -n "$want" ] || die "A card id is needed"
  b=$(board) || exit 1
  matches=$(printf '%s' "$b" | jq -r --arg w "$want" '.cards[] | select(.id | startswith($w)) | [.scope, (.teamId // "-"), .id] | join("|")')
  n=$(printf '%s' "$matches" | /usr/bin/grep -c . || true)
  [ "$n" -ge 1 ] || die "No card on your board starts with '$want'"
  [ "$n" -eq 1 ] || die "More than one card starts with '$want'; use more characters"
  printf '%s' "$matches"
}

# Base API path of a resolved card
card_path() {
  local scope="$1" team="$2" id="$3"
  if [ "$scope" = "team" ]; then printf '/api/teams/%s/tasks/%s' "$team" "$id"; else printf '/api/agents/%s/tasks/%s' "$AGENT" "$id"; fi
}

update() { # scope team id json
  local method=PATCH
  [ "$1" = "team" ] && method=PUT
  call "$method" "$(card_path "$1" "$2" "$3")" "$4" >/dev/null || exit 1
}

# q1..q4 -> {"urgent":..,"important":..}; none -> nulls (a card not placed). Anything else is refused.
quadrant_json() {
  case "$1" in
    q1) echo '{"urgent":true,"important":true}' ;;
    q2) echo '{"urgent":false,"important":true}' ;;
    q3) echo '{"urgent":true,"important":false}' ;;
    q4) echo '{"urgent":false,"important":false}' ;;
    none) echo '{"urgent":null,"important":null}' ;;
    *) die "Unknown quadrant '$1' (q1, q2, q3, q4, or none)" ;;
  esac
}

is_status() { case " $STATUS_LIST " in *" $1 "*) return 0 ;; *) return 1 ;; esac; }

short() { printf '%s' "$1" | cut -c1-8; }

# ---- commands ----
case "$CMD" in
  add)
    subject="${1:-}"; [ -n "$subject" ] || die 'add needs a subject: add "<subject>"'; shift
    desc=""; deps=(); quadrant=""
    while [ $# -gt 0 ]; do
      case "$1" in
        --desc) [ $# -ge 2 ] || die "--desc needs a value"; desc="$2"; shift 2 ;;
        --blocked-by) [ $# -ge 2 ] || die "--blocked-by needs a value"; deps+=("$2"); shift 2 ;;
        --team) [ $# -ge 2 ] || die "--team needs a value"; TEAM="$2"; shift 2 ;;
        --quadrant) [ $# -ge 2 ] || die "--quadrant needs a value"; quadrant="$2"; shift 2 ;;
        *) die "Unknown option for add: $1" ;;
      esac
    done
    json=$(jq -n --arg s "$subject" --arg d "$desc" '{subject:$s} + (if $d != "" then {description:$d} else {} end)')
    if [ -n "$quadrant" ]; then
      q=$(quadrant_json "$quadrant") || exit 1
      json=$(printf '%s' "$json" | jq --argjson q "$q" '. + $q')
    fi
    if [ "${#deps[@]}" -gt 0 ]; then
      # blocked-by ids may be short; resolve each
      ids=()
      for d in "${deps[@]}"; do
        r=$(resolve "$d") || exit 1
        ids+=("$(printf '%s' "$r" | cut -d'|' -f3)")
      done
      json=$(printf '%s' "$json" | jq --argjson ids "$(printf '%s\n' "${ids[@]}" | jq -R . | jq -s .)" '. + {blockedBy:$ids}')
    fi
    if [ -n "$TEAM" ]; then
      json=$(printf '%s' "$json" | jq --arg a "$AGENT" '. + {assigneeAgentId:$a}')
      res=$(call POST "/api/teams/${TEAM}/tasks" "$json") || exit 1
    else
      res=$(call POST "/api/agents/${AGENT}/tasks" "$json") || exit 1
    fi
    id=$(printf '%s' "$res" | jq -r '.task.id')
    echo "Added $(short "$id")  $subject"
    ;;

  start|review|done|move)
    id="${1:-}"; shift || true
    case "$CMD" in
      start) status=in_progress ;;
      review) status=review ;;
      done) status=completed ;;
      move) status="${1:-}"; [ -n "$status" ] || die "move needs a status"; shift ;;
    esac
    [ "$status" != "waiting" ] || die "Use: wait <id> --on juan|outside|hold|<agent-id>"
    is_status "$status" || die "Unknown status '$status' (backlog, pending, in_progress, review, completed)"
    resolved=$(resolve "$id") || exit 1
    IFS='|' read -r scope team full <<< "$resolved"
    update "$scope" "$team" "$full" "$(jq -n --arg s "$status" '{status:$s}')"
    echo "$(short "$full")  ->  $status"
    ;;

  wait)
    id="${1:-}"; shift || true
    on=""; note=""
    while [ $# -gt 0 ]; do
      case "$1" in
        --on) [ $# -ge 2 ] || die "--on needs a value"; on="$2"; shift 2 ;;
        --note) [ $# -ge 2 ] || die "--note needs a value"; note="$2"; shift 2 ;;
        *) die "Unknown option for wait: $1" ;;
      esac
    done
    [ -n "$on" ] || die "wait needs --on juan|outside|hold|<agent-id>"
    resolved=$(resolve "$id") || exit 1
    IFS='|' read -r scope team full <<< "$resolved"
    update "$scope" "$team" "$full" "$(jq -n --arg on "$on" --arg n "$note" '{status:"waiting", waitingOn:$on} + (if $n != "" then {waitingNote:$n} else {} end)')"
    echo "$(short "$full")  ->  waiting on $on${note:+ ($note)}"
    ;;

  comment)
    id="${1:-}"; text="${2:-}"
    [ -n "$text" ] || die 'comment needs text: comment <id> "<text>"'
    resolved=$(resolve "$id") || exit 1
    IFS='|' read -r scope team full <<< "$resolved"
    # An agent comment is kept on the card and shown to people; it is never sent to anyone's prompt.
    call POST "$(card_path "$scope" "$team" "$full")/comments" "$(jq -n --arg a "$AGENT" --arg t "$text" '{author:{kind:"agent", id:$a}, text:$t}')" >/dev/null || exit 1
    echo "Commented on $(short "$full")"
    ;;

  place)
    id="${1:-}"; q="${2:-}"
    [ -n "$q" ] || die "place needs a quadrant: place <id> q1|q2|q3|q4|none"
    body=$(quadrant_json "$q") || exit 1
    resolved=$(resolve "$id") || exit 1
    IFS='|' read -r scope team full <<< "$resolved"
    update "$scope" "$team" "$full" "$body"
    echo "$(short "$full")  ->  $q"
    ;;

  list)
    waiting_on=""; status=""; quadrant=""
    while [ $# -gt 0 ]; do
      case "$1" in
        --mine) shift ;;
        --quadrant) [ $# -ge 2 ] || die "--quadrant needs a value"; quadrant="$2"; shift 2 ;;
        --waiting-on) [ $# -ge 2 ] || die "--waiting-on needs a value"; waiting_on="$2"; shift 2 ;;
        --status) [ $# -ge 2 ] || die "--status needs a value"; status="$2"; shift 2 ;;
        *) die "Unknown option for list: $1" ;;
      esac
    done
    b=$(board) || exit 1
    case "$quadrant" in ""|q1|q2|q3|q4|unplaced) ;; *) die "Unknown quadrant '$quadrant' (q1, q2, q3, q4 or unplaced)" ;; esac
    printf '%s' "$b" | jq -r --arg w "$waiting_on" --arg s "$status" --arg q "$quadrant" '
      .cards
      | map(select(($w == "" or (.status == "waiting" and .waitingOn == $w)) and ($s == "" or .status == $s) and ($q == "" or ($q == "unplaced" and (.quadrant == null)) or .quadrant == $q)))
      | if length == 0 then "No cards." else
          .[] | "\(.id[0:8])  \(.status | . + (" " * (11 - length)))  \(if .quadrant then (.quadrant | ascii_upcase) else "--" end)  \(.subject)"
            + (if .status == "waiting" then "  [waiting on \(.waitingOn)\(if .waitingNote then ": " + .waitingNote else "" end)]" else "" end)
            + (if .scope == "team" then "  (team: \(.teamName // .teamId))" else "" end)
            + (if (.comments // [] | length) > 0 then "  (\(.comments | length) comments)" else "" end)
        end'
    ;;

  show)
    id="${1:-}"
    resolved=$(resolve "$id") || exit 1
    IFS='|' read -r scope team full <<< "$resolved"
    b=$(board) || exit 1
    printf '%s' "$b" | jq -r --arg id "$full" '
      .cards[] | select(.id == $id)
      | "\(.id)\nSubject:  \(.subject)\nStatus:   \(.status)" + (if .status == "waiting" then " (on \(.waitingOn)\(if .waitingNote then ": " + .waitingNote else "" end))" else "" end)
        + "\nQuadrant: \(if .quadrant then (.quadrant | ascii_upcase) else "not placed" end)"
        + "\nBoard:    \(.scope)" + (if .scope == "team" then " (\(.teamName // .teamId))" else "" end)
        + (if .description then "\n\n\(.description)" else "" end)
        + (if (.comments // [] | length) > 0 then "\n\nComments:\n" + ([.comments[] | "  [\(.createdAt[0:16])] \(.author.kind)\(if .author.id then " " + .author.id[0:8] else "" end): \(.text)"] | join("\n")) else "" end)'
    ;;

  *) die "Unknown command '$CMD'. Run: aimaestro-task.sh --help" ;;
esac
