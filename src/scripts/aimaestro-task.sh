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
  add "<subject>" --project <hostId:projectId> [--assign <agent id or name>] ...                  Add a card to a project (assigned to you unless --assign)
  start <id>                                                  Move to In Progress
  review <id>                                                 Move to Review
  done <id>                                                   Move to Done
  move <id> <status>                                          backlog | pending | in_progress | review | completed
  wait <id> --on juan|outside|hold|<agent-id> [--note "<text>"]   Waiting, and on whom
  comment <id> "<text>"                                       Write on the card (stored and shown; never sent to anyone)
  place <id> q1|q2|q3|q4|none                                 Put a card on the Eisenhower matrix (none = take it off)
  list [--mine] [--waiting-on <who>] [--status <status>] [--quadrant q1|q2|q3|q4|unplaced]   Your board (own, team and project cards assigned to you)
  list --project <hostId:projectId>                           Every card of one project, whoever it is for
  project add "<name>" [--owner <agent>] [--desc "<text>"]    Start a project (stored on the owner's host: the one this command talks to)
  project list                                                Projects on every host you can reach, with their <hostId:projectId>
  project show <hostId:projectId>                             One project with its cards
  show <id>                                                   One card with its comments
  org list                                                    Organizations: records on every host you can reach (the value of the agents' org: tag is the id)
  org add "<name>" [--id <slug>] [--desc "<text>"]            Add an organization record (stored on the host this command talks to; the id comes from the name)
  org label <id> <org>|none                                   Say which organization a card is for (otherwise its assignee's); none clears it
  add ... --org <org>                                         Label the new card for an organization

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
  local method="$1" path="$2" body="${3:-}" out code url
  # A path starting with http is already a full address (a project card lives on its project's host)
  case "$path" in http*) url="$path" ;; *) url="${API}${path}" ;; esac
  if [ -n "$body" ]; then
    out=$(curl -sS --max-time 15 -X "$method" -H 'Content-Type: application/json' -d "$body" -w '\n%{http_code}' "$url" 2>&1) || die "Could not reach AI Maestro at ${url%%/api/*}: ${out}"
  else
    out=$(curl -sS --max-time 15 -X "$method" -w '\n%{http_code}' "$url" 2>&1) || die "Could not reach AI Maestro at ${url%%/api/*}: ${out}"
  fi
  code="${out##*$'\n'}"
  out="${out%$'\n'*}"
  case "$code" in
    2*) printf '%s' "$out" ;;
    *)  die "$(printf '%s' "$out" | jq -r '.message // .error // empty' 2>/dev/null || true) (HTTP ${code})" ;;
  esac
}

board() { call GET "/api/agents/${AGENT}/board"; }

# ---- hosts and projects ----
# The mesh: "<hostId>|<base address>" per enabled host, this one first. Best effort: no host list means this host only.
HOSTS_CACHE=""
hosts_lines() {
  if [ -z "$HOSTS_CACHE" ]; then
    local h
    h=$(curl -sS --max-time 5 "${API}/api/hosts" 2>/dev/null | jq -r --arg api "$API" '.hosts[]? | select(.enabled != false) | [.id, (if .isSelf then $api else .url end)] | join("|")' 2>/dev/null || true)
    HOSTS_CACHE="${h:-self|$API}"
  fi
  printf '%s\n' "$HOSTS_CACHE"
}

# GET without dying: a host that is down or has no such route adds nothing
peer_get() { curl -sS -f --max-time 4 "$1" 2>/dev/null || true; }

# Every project card assigned to me, from every host's projects: a JSON array, each card tagged with its host
project_cards() {
  local out="[]" line base body
  while IFS='|' read -r _ base; do
    [ -n "$base" ] || continue
    body=$(peer_get "${base%/}/api/projects?assignee=${AGENT}")
    [ -n "$body" ] || continue
    out=$(printf '%s' "$out" | jq --argjson b "$body" --arg base "${base%/}" '. + [ ($b.projects // [])[] | .cards[]? | . + {hostBase: $base} ]' 2>/dev/null || printf '%s' "$out")
  done < <(hosts_lines)
  printf '%s' "$out"
}

# A project by "<hostId>:<projectId>" or a unique start of the project id: prints "<base>|<projectId>|<name>"
find_project() {
  local ref="$1" hostpart="" idpart="$1" line hid base body match="" n=0
  case "$ref" in *:*) hostpart="${ref%%:*}"; idpart="${ref#*:}" ;; esac
  [ -n "$idpart" ] || die "A project is needed: <hostId>:<projectId> (see: project list)"
  while IFS='|' read -r hid base; do
    [ -n "$base" ] || continue
    [ -z "$hostpart" ] || [ "$hostpart" = "$hid" ] || continue
    body=$(peer_get "${base%/}/api/projects")
    [ -n "$body" ] || continue
    while IFS= read -r row; do
      [ -n "$row" ] || continue
      match="${base%/}|${row}"; n=$((n + 1))
    done < <(printf '%s' "$body" | jq -r --arg w "$idpart" '.projects[]? | select(.id | startswith($w)) | [.id, .name] | join("|")')
  done < <(hosts_lines)
  [ "$n" -ge 1 ] || die "No project starts with '$idpart' on the hosts I can reach"
  [ "$n" -eq 1 ] || die "More than one project starts with '$idpart'; use <hostId>:<projectId> or more characters"
  printf '%s' "$match"
}

# An agent id from an id or a name this host knows; an unknown name is passed through as given
agent_id_of() {
  local who="$1" id
  case "$who" in
    *-*-*-*-*) printf '%s' "$who"; return ;;
  esac
  id=$(peer_get "${API}/api/agents" | jq -r --arg n "$who" '[.agents[]? | select(.id == $n or .name == $n or .alias == $n)][0].id // empty' 2>/dev/null || true)
  printf '%s' "${id:-$who}"
}

# Find a card on my board (own, team and project cards) by full id or unique prefix;
# prints "<scope>|<teamId or ->|<id>|<host address or ->|<projectId or ->"
# ("|" and not a tab: read collapses empty tab-separated fields)
resolve() {
  local want="$1" b pc matches n
  [ -n "$want" ] || die "A card id is needed"
  b=$(board) || exit 1
  pc=$(project_cards)
  matches=$(
    printf '%s' "$b" | jq -r --arg w "$want" '.cards[] | select(.id | startswith($w)) | [.scope, (.teamId // "-"), .id, "-", "-"] | join("|")'
    printf '%s' "$pc" | jq -r --arg w "$want" '.[] | select(.id | startswith($w)) | ["project", "-", .id, .hostBase, .projectId] | join("|")'
  )
  n=$(printf '%s' "$matches" | /usr/bin/grep -c . || true)
  [ "$n" -ge 1 ] || die "No card on your board starts with '$want'"
  [ "$n" -eq 1 ] || die "More than one card starts with '$want'; use more characters"
  printf '%s' "$matches"
}

# Base API path of a resolved card
card_path() { # scope team id hostBase projectId
  local scope="$1" team="$2" id="$3" hb="${4:--}" pid="${5:--}"
  case "$scope" in
    project) printf '%s/api/projects/%s/tasks/%s' "$hb" "$pid" "$id" ;;
    team) printf '/api/teams/%s/tasks/%s' "$team" "$id" ;;
    *) printf '/api/agents/%s/tasks/%s' "$AGENT" "$id" ;;
  esac
}

update() { # scope team id hostBase projectId json
  local method=PATCH
  case "$1" in team|project) method=PUT ;; esac
  call "$method" "$(card_path "$1" "$2" "$3" "$4" "$5")" "$6" >/dev/null || exit 1
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
    desc=""; deps=(); quadrant=""; project=""; assign=""; org=""
    while [ $# -gt 0 ]; do
      case "$1" in
        --org) [ $# -ge 2 ] || die "--org needs a value"; org="$2"; shift 2 ;;
        --project) [ $# -ge 2 ] || die "--project needs a value"; project="$2"; shift 2 ;;
        --assign) [ $# -ge 2 ] || die "--assign needs a value"; assign="$2"; shift 2 ;;
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
    if [ -n "$org" ]; then
      [ -z "$TEAM" ] || die "--org is for your own cards and project cards; a team board does not keep an organization label"
      json=$(printf '%s' "$json" | jq --arg o "$org" '. + {org:$o}')
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
    if [ -n "$project" ]; then
      [ -z "$TEAM" ] || die "A card goes on a team board or a project board, not both"
      proj=$(find_project "$project") || exit 1
      IFS='|' read -r pbase ppid pname <<< "$proj"
      who=$(agent_id_of "${assign:-$AGENT}")
      json=$(printf '%s' "$json" | jq --arg a "$who" '. + {assigneeAgentId:$a}')
      res=$(call POST "${pbase}/api/projects/${ppid}/tasks" "$json") || exit 1
      id=$(printf '%s' "$res" | jq -r '.task.id')
      echo "Added $(short "$id")  $subject  (project: $pname)"
      exit 0
    elif [ -n "$TEAM" ]; then
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
    IFS='|' read -r scope team full hb pid <<< "$resolved"
    update "$scope" "$team" "$full" "$hb" "$pid" "$(jq -n --arg s "$status" '{status:$s}')"
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
    IFS='|' read -r scope team full hb pid <<< "$resolved"
    update "$scope" "$team" "$full" "$hb" "$pid" "$(jq -n --arg on "$on" --arg n "$note" '{status:"waiting", waitingOn:$on} + (if $n != "" then {waitingNote:$n} else {} end)')"
    echo "$(short "$full")  ->  waiting on $on${note:+ ($note)}"
    ;;

  comment)
    id="${1:-}"; text="${2:-}"
    [ -n "$text" ] || die 'comment needs text: comment <id> "<text>"'
    resolved=$(resolve "$id") || exit 1
    IFS='|' read -r scope team full hb pid <<< "$resolved"
    # An agent comment is kept on the card and shown to people; it is never sent to anyone's prompt.
    call POST "$(card_path "$scope" "$team" "$full" "$hb" "$pid")/comments" "$(jq -n --arg a "$AGENT" --arg t "$text" '{author:{kind:"agent", id:$a}, text:$t}')" >/dev/null || exit 1
    echo "Commented on $(short "$full")"
    ;;

  place)
    id="${1:-}"; q="${2:-}"
    [ -n "$q" ] || die "place needs a quadrant: place <id> q1|q2|q3|q4|none"
    body=$(quadrant_json "$q") || exit 1
    resolved=$(resolve "$id") || exit 1
    IFS='|' read -r scope team full hb pid <<< "$resolved"
    update "$scope" "$team" "$full" "$hb" "$pid" "$body"
    echo "$(short "$full")  ->  $q"
    ;;

  list)
    waiting_on=""; status=""; quadrant=""; project=""
    while [ $# -gt 0 ]; do
      case "$1" in
        --mine) shift ;;
        --project) [ $# -ge 2 ] || die "--project needs a value"; project="$2"; shift 2 ;;
        --quadrant) [ $# -ge 2 ] || die "--quadrant needs a value"; quadrant="$2"; shift 2 ;;
        --waiting-on) [ $# -ge 2 ] || die "--waiting-on needs a value"; waiting_on="$2"; shift 2 ;;
        --status) [ $# -ge 2 ] || die "--status needs a value"; status="$2"; shift 2 ;;
        *) die "Unknown option for list: $1" ;;
      esac
    done
    case "$quadrant" in ""|q1|q2|q3|q4|unplaced) ;; *) die "Unknown quadrant '$quadrant' (q1, q2, q3, q4 or unplaced)" ;; esac
    showwho=""
    if [ -n "$project" ]; then
      # one whole project, whoever its cards are for
      proj=$(find_project "$project") || exit 1
      IFS='|' read -r pbase ppid pname <<< "$proj"
      b=$(call GET "${pbase}/api/projects/${ppid}/tasks" | jq '{cards: .tasks}') || exit 1
      echo "Project $pname"
      showwho=1
    else
      b=$(board) || exit 1
      pc=$(project_cards)
      b=$(printf '%s' "$b" | jq --argjson p "$pc" '.cards += $p')
    fi
    printf '%s' "$b" | jq -r --arg w "$waiting_on" --arg s "$status" --arg q "$quadrant" --arg who "$showwho" '
      .cards
      | map(select(($w == "" or (.status == "waiting" and .waitingOn == $w)) and ($s == "" or .status == $s) and ($q == "" or ($q == "unplaced" and (.quadrant == null)) or .quadrant == $q)))
      | if length == 0 then "No cards." else
          .[] | "\(.id[0:8])  \(.status | . + (" " * (11 - length)))  \(if .quadrant then (.quadrant | ascii_upcase) else "--" end)  \(.subject)"
            + (if .status == "waiting" then "  [waiting on \(.waitingOn)\(if .waitingNote then ": " + .waitingNote else "" end)]" else "" end)
            + (if .scope == "team" then "  (team: \(.teamName // .teamId))" else "" end)
            + (if .scope == "project" and $who == "" then "  (project: \(.projectName // .projectId))" else "" end)
            + (if $who != "" then "  -> \(.assigneeName // (.assigneeAgentId // "nobody" | .[0:8]))" else "" end)
            + (if (.comments // [] | length) > 0 then "  (\(.comments | length) comments)" else "" end)
        end'
    ;;

  show)
    id="${1:-}"
    resolved=$(resolve "$id") || exit 1
    IFS='|' read -r scope team full hb pid <<< "$resolved"
    b=$(board) || exit 1
    pc=$(project_cards)
    b=$(printf '%s' "$b" | jq --argjson p "$pc" '.cards += $p')
    printf '%s' "$b" | jq -r --arg id "$full" '
      .cards[] | select(.id == $id)
      | "\(.id)\nSubject:  \(.subject)\nStatus:   \(.status)" + (if .status == "waiting" then " (on \(.waitingOn)\(if .waitingNote then ": " + .waitingNote else "" end))" else "" end)
        + "\nQuadrant: \(if .quadrant then (.quadrant | ascii_upcase) else "not placed" end)"
        + (if .org then "\nOrg:      \(.org)" else "" end)
        + "\nBoard:    \(.scope)" + (if .scope == "team" then " (\(.teamName // .teamId))" elif .scope == "project" then " (\(.projectName // .projectId))" else "" end)
        + (if .description then "\n\n\(.description)" else "" end)
        + (if (.comments // [] | length) > 0 then "\n\nComments:\n" + ([.comments[] | "  [\(.createdAt[0:16])] \(.author.kind)\(if .author.id then " " + .author.id[0:8] else "" end): \(.text)"] | join("\n")) else "" end)'
    ;;

  org)
    sub="${1:-}"; shift || true
    case "$sub" in
      list)
        found=0
        while IFS='|' read -r hid base; do
          [ -n "$base" ] || continue
          body=$(peer_get "${base%/}/api/orgs")
          [ -n "$body" ] || continue
          rows=$(printf '%s' "$body" | jq -r --arg h "$hid" '.organizations[]? | "\(.id)  \(.name)\(if .description then "  - " + .description else "" end)  [\($h)]"')
          [ -z "$rows" ] || { printf '%s\n' "$rows"; found=1; }
        done < <(hosts_lines)
        [ "$found" -eq 1 ] || echo "No organization records. (Agents can still carry an org:<id> tag.)"
        ;;
      add)
        oname="${1:-}"; [ -n "$oname" ] || die 'org add needs a name: org add "<name>"'; shift
        oid=""; desc=""
        while [ $# -gt 0 ]; do
          case "$1" in
            --id) [ $# -ge 2 ] || die "--id needs a value"; oid="$2"; shift 2 ;;
            --desc) [ $# -ge 2 ] || die "--desc needs a value"; desc="$2"; shift 2 ;;
            *) die "Unknown option for org add: $1" ;;
          esac
        done
        json=$(jq -n --arg n "$oname" --arg i "$oid" --arg d "$desc" '{name:$n} + (if $i != "" then {id:$i} else {} end) + (if $d != "" then {description:$d} else {} end)')
        res=$(call POST "/api/orgs" "$json") || exit 1
        echo "Organization $(printf '%s' "$res" | jq -r '.organization.id')  $oname  (tag agents with org:$(printf '%s' "$res" | jq -r '.organization.id'))"
        ;;
      label)
        id="${1:-}"; o="${2:-}"
        [ -n "$id" ] && [ -n "$o" ] || die "org label needs a card and an organization: org label <id> <org>|none"
        resolved=$(resolve "$id") || exit 1
        IFS='|' read -r scope team full hb pid <<< "$resolved"
        [ "$scope" != "team" ] || die "A team board does not keep an organization label; use your own board or a project"
        if [ "$o" = "none" ]; then body='{"org":null}'; else body=$(jq -n --arg o "$o" '{org:$o}'); fi
        update "$scope" "$team" "$full" "$hb" "$pid" "$body"
        echo "$(short "$full")  ->  org: $o"
        ;;
      *) die "Unknown org command '$sub' (list, add, label). Run: aimaestro-task.sh --help" ;;
    esac
    ;;

  project)
    sub="${1:-}"; shift || true
    case "$sub" in
      add)
        pname="${1:-}"; [ -n "$pname" ] || die 'project add needs a name: project add "<name>"'; shift
        owner=""; desc=""
        while [ $# -gt 0 ]; do
          case "$1" in
            --owner) [ $# -ge 2 ] || die "--owner needs a value"; owner="$2"; shift 2 ;;
            --desc) [ $# -ge 2 ] || die "--desc needs a value"; desc="$2"; shift 2 ;;
            *) die "Unknown option for project add: $1" ;;
          esac
        done
        who=$(agent_id_of "${owner:-$AGENT}")
        json=$(jq -n --arg n "$pname" --arg d "$desc" --arg o "$who" '{name:$n, ownerAgentId:$o} + (if $d != "" then {description:$d} else {} end)')
        res=$(call POST "/api/projects" "$json") || exit 1
        # The reference other commands take: the host this project is stored on, and its id
        hid=$(hosts_lines | /usr/bin/grep -F "|${API}" | head -1 | cut -d'|' -f1)
        echo "Project ${hid:-$(printf '%s' "$res" | jq -r '.project.hostId')}:$(printf '%s' "$res" | jq -r '.project.id')  $pname"
        ;;
      list)
        found=0
        while IFS='|' read -r hid base; do
          [ -n "$base" ] || continue
          body=$(peer_get "${base%/}/api/projects")
          [ -n "$body" ] || continue
          rows=$(printf '%s' "$body" | jq -r --arg h "$hid" '.projects[]? | "\($h):\(.id[0:8])  \(.status | . + (" " * (6 - length)))  \(.name)  (\(.counts.open) open\(if .counts.waiting > 0 then ", \(.counts.waiting) waiting" else "" end))  [\($h)]"')
          [ -z "$rows" ] || { printf '%s\n' "$rows"; found=1; }
        done < <(hosts_lines)
        [ "$found" -eq 1 ] || echo "No projects."
        ;;
      show)
        ref="${1:-}"
        proj=$(find_project "$ref") || exit 1
        IFS='|' read -r pbase ppid pname <<< "$proj"
        body=$(call GET "${pbase}/api/projects/${ppid}/tasks") || exit 1
        printf '%s' "$body" | jq -r '"Project \(.project.name)  (\(.project.status))  owner: \(.project.ownerAgentId // "nobody" | .[0:8])\n\(.project.description // "")"' | /usr/bin/sed '/^$/d'
        printf '%s' "$body" | jq -r '.tasks | if length == 0 then "No cards." else .[] | "  \(.id[0:8])  \(.status | . + (" " * (11 - length)))  \(if .quadrant then (.quadrant | ascii_upcase) else "--" end)  \(.subject)  -> \(.assigneeName // (.assigneeAgentId // "nobody" | .[0:8]))" + (if .status == "waiting" then "  [waiting on \(.waitingOn)]" else "" end) end'
        ;;
      *) die "Unknown project command '$sub' (add, list, show). Run: aimaestro-task.sh --help" ;;
    esac
    ;;

  *) die "Unknown command '$CMD'. Run: aimaestro-task.sh --help" ;;
esac
