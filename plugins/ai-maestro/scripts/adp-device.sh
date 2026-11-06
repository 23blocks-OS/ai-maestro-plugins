#!/bin/bash
# adp-device.sh - an agent's own devices (the Agent Device Protocol, agentdevices.org).
# It asks the agent's controller, which holds the key and refuses what the protocol refuses. It speaks AI Maestro's
# controller API; apps/controller offers the same operations over MCP.
#
# Version: 1.0.0
set -u -o pipefail

API="${AIMAESTRO_API:-http://localhost:23000}"
API="${API%/}"
AGENT="${AIM_AGENT_ID:-}"

die() { echo "Error: $*" >&2; exit 1; }

command -v curl >/dev/null 2>&1 || die "curl is required"
command -v jq >/dev/null 2>&1 || die "jq is required"

usage() {
  cat <<'USAGE'
Usage: adp-device.sh [--agent <id>] <command> ...

Commands:
  list [--refresh] [--json]          Your devices, and which one is active
  jump <device>                      Make it your active device
  jump none                          No active device
  health <device>                    Works on any of your devices
  snapshot <device>                  Take a picture; prints the file path
  watch <device> [seconds]           Live camera, 1 to 30 s (default 5); prints the last frame's path
  listen <device> [seconds]          Record the microphone, 1 to 10 s (default 5); prints the WAV path
  show <device> "<text>"             Show text on the device's display
  show-image <device> <file>         Show a PNG or JPEG, up to 256 KiB
  say <device> "<text>"              Say up to 500 bytes of text
  run <device> <custom.owner.action> [--arg name=value]...   A capability the device's owner defined
                                     --arg makes true, false and numbers typed; --string keeps text as text

<device> is the name or the key. Sensors, output and custom capabilities need the active device: jump first.
The device's own grants still apply: if one is refused, ask the person at the device.
USAGE
}

while [ $# -gt 0 ]; do
  case "$1" in
    --agent) [ $# -ge 2 ] || die "--agent needs an id"; AGENT="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) break ;;
  esac
done
[ $# -ge 1 ] || { usage; exit 1; }
[ -n "$AGENT" ] || die "AIM_AGENT_ID is not set: this command runs inside an AI Maestro agent, or give --agent <id>"
BASE="$API/api/agents/$(jq -rn --arg a "$AGENT" '$a | @uri')/devices"

# Args: method url [json]. Prints the body; fails with the server's own message.
request() {
  local method="$1" url="$2" json="${3:-}" out body code
  local args=(-s -m 60 -X "$method" -w '\n%{http_code}')
  if [ -n "$json" ]; then args+=(-H 'Content-Type: application/json' --data-binary @-); fi
  out=$(printf '%s' "$json" | curl "${args[@]}" "$url") || die "AI Maestro did not answer at $API"
  code="${out##*$'\n'}"
  body="${out%$'\n'*}"
  if [ "$code" -ge 400 ] || [ "$(jq -r '.ok == false' <<<"$body" 2>/dev/null)" = "true" ]; then
    die "$(jq -r '.message // .error // "request failed"' <<<"$body" 2>/dev/null || echo "HTTP $code")"
  fi
  jq -e . >/dev/null 2>&1 <<<"$body" || die "AI Maestro at $API did not answer with JSON: is it 0.106.77 or newer?"
  printf '%s' "$body"
}

# Name or key to KEY. Sets a variable: `die` inside $(...) would end only the subshell.
KEY=""
resolve() {
  local want="$1" devices
  devices=$(request GET "$BASE") || exit 1
  KEY=$(jq -r --arg w "$want" '[.devices[] | select(.key == $w or .name == $w) | .key] | if length == 1 then .[0] else "" end' <<<"$devices")
  [ -n "$KEY" ] || die "No single device called \"$want\". See: adp-device.sh list"
}

invoke() {
  local key="$1" capability="$2" args="${3:-}"
  [ -n "$args" ] || args='{}'
  # Through stdin: Linux refuses one argument over 128 KB, and an image is more
  request POST "$BASE/$key/invoke" "$(jq -c --arg c "$capability" '{capability: $c, args: .}' <<<"$args")"
}

cmd="$1"; shift
case "$cmd" in
  list)
    url="$BASE"; json=false
    for a in "$@"; do
      case "$a" in
        --refresh) url="$BASE?refresh=1" ;;
        --json) json=true ;;
        *) die "Unknown option: $a" ;;
      esac
    done
    body=$(request GET "$url") || exit 1
    if [ "$json" = true ]; then jq '.devices' <<<"$body"; exit 0; fi
    [ "$(jq '.devices | length' <<<"$body")" -gt 0 ] || { echo "No devices."; exit 0; }
    jq -r '.devices[] | "\(if .active then "*" else " " end) \(.name)  \(.state)  \(.capabilities | join(", "))"' <<<"$body"
    ;;
  jump)
    [ $# -eq 1 ] || die "Usage: jump <device> | none"
    if [ "$1" = none ]; then
      devices=$(request GET "$BASE") || exit 1
      first=$(jq -r '.devices[0].key // empty' <<<"$devices")
      [ -n "$first" ] || { echo "No devices."; exit 0; }
      request DELETE "$BASE/$first/jump" >/dev/null; echo "No active device."
    else
      resolve "$1"; request POST "$BASE/$KEY/jump" >/dev/null; echo "Active: $1"
    fi
    ;;
  health)
    [ $# -eq 1 ] || die "Usage: health <device>"
    resolve "$1"; invoke "$KEY" device.health | jq -c '.value'
    ;;
  snapshot)
    [ $# -eq 1 ] || die "Usage: snapshot <device>"
    resolve "$1"; invoke "$KEY" camera.snapshot | jq -r '.value.path'
    ;;
  watch|listen)
    [ $# -ge 1 ] && [ $# -le 2 ] || die "Usage: $cmd <device> [seconds]"
    kind=video; [ "$cmd" = listen ] && kind=microphone
    seconds="${2:-5}"
    [[ "$seconds" =~ ^[0-9]+$ ]] || die "seconds must be a whole number"
    resolve "$1"; request POST "$BASE/$KEY/media" "$(jq -cn --arg k "$kind" --argjson s "$seconds" '{kind: $k, seconds: $s}')" | jq -r '.value.path'
    ;;
  show)
    [ $# -eq 2 ] || die "Usage: show <device> \"<text>\""
    resolve "$1"; invoke "$KEY" display.text "$(jq -cn --arg t "$2" '{text: $t}')" >/dev/null; echo "Shown."
    ;;
  show-image)
    [ $# -eq 2 ] || die "Usage: show-image <device> <file>"
    [ -f "$2" ] || die "No such file: $2"
    case "$2" in
      *.png|*.PNG) mime=image/png ;;
      *.jpg|*.jpeg|*.JPG|*.JPEG) mime=image/jpeg ;;
      *) die "Only PNG and JPEG" ;;
    esac
    [ "$(wc -c < "$2")" -le 262144 ] || die "The image is over 256 KiB"
    resolve "$1"; invoke "$KEY" display.image "$(base64 < "$2" | tr -d '\n' | jq -Rsc --arg m "$mime" '{mime: $m, data: .}')" >/dev/null; echo "Shown."
    ;;
  say)
    [ $# -eq 2 ] || die "Usage: say <device> \"<text>\""
    resolve "$1"; invoke "$KEY" speaker.say "$(jq -cn --arg t "$2" '{text: $t}')" >/dev/null; echo "Said."
    ;;
  run)
    [ $# -ge 2 ] || die "Usage: run <device> <custom.owner.action> [--arg name=value] [--string name=value]..."
    device="$1"; capability="$2"; shift 2
    args='{}'
    while [ $# -gt 0 ]; do
      [ $# -ge 2 ] && [[ "$2" == *=* ]] || die "Use --arg name=value or --string name=value"
      case "$1" in
        # Only these become typed: the protocol's arguments are strings, numbers and booleans, never nested
        --arg) args=$(jq -c --arg k "${2%%=*}" --arg v "${2#*=}" '. + {($k): (if $v == "true" then true elif $v == "false" then false elif ($v | test("^-?(0|[1-9][0-9]*)(\\.[0-9]+)?$")) then ($v | tonumber) else $v end)}' <<<"$args") ;;
        --string) args=$(jq -c --arg k "${2%%=*}" --arg v "${2#*=}" '. + {($k): $v}' <<<"$args") ;;
        *) die "Use --arg name=value or --string name=value" ;;
      esac
      shift 2
    done
    resolve "$device"; invoke "$KEY" "$capability" "$args" | jq -c '.value'
    ;;
  *) usage; die "Unknown command: $cmd" ;;
esac
