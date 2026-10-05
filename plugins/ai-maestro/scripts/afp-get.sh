#!/bin/bash
# =============================================================================
# AFP Get - Fetch a File
# =============================================================================
#
# Download the object a reference names and check it against its SHA-256. A
# file that does not match is deleted and reported as digest_mismatch. An
# object whose manifest says suspicious or rejected is not downloaded.
#
# Usage:
#   afp-get <ref> [options]
#
# Examples:
#   afp-get afp://artifacts/2026/10/report.pdf
#   afp-get '{"ref":"afp://shared/a.md","digest":"sha256:...","url":"https://..."}'
#   afp-get @reference.json --dest ./incoming/
#
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/afp-helper.sh"

REF=""
EXPECT=""
DEST=""
FORCE=false

show_help() {
    echo "Usage: afp-get <ref> [options]"
    echo ""
    echo "Download an object and verify its SHA-256."
    echo ""
    echo "Arguments:"
    echo "  ref           afp://<space>/<path>, a reference object (JSON), or @file with one"
    echo ""
    echo "Options:"
    echo "  --digest, -d SHA       Expected digest, sha256:<hex> (default: from the reference,"
    echo "                           else from the object's manifest)"
    echo "  --dest PATH            Directory or file to write (default:"
    echo "                           ~/.agent-files/downloads/<space>/<path>)"
    echo "  --force, -f            Overwrite an existing local file"
    echo "  --json, -j             Accepted for symmetry with amp-*; output is always JSON"
    echo "  --help, -h             Show this help"
    echo ""
    echo "With no access to the space, a reference object that carries a 'url' is fetched"
    echo "through that link. The digest check applies either way."
    echo ""
    echo "Examples:"
    echo "  afp-get afp://artifacts/2026/10/report.pdf"
    echo "  afp-get @reference.json --dest ./incoming/"
}

while [[ $# -gt 0 ]]; do
    case $1 in
        --digest|-d) [ $# -ge 2 ] || afp_fail usage "$1 needs a value"; EXPECT="$2"; shift 2 ;;
        --dest) [ $# -ge 2 ] || afp_fail usage "$1 needs a value"; DEST="$2"; shift 2 ;;
        --force|-f) FORCE=true; shift ;;
        --json|-j) shift ;;
        --help|-h) show_help; exit 0 ;;
        -*) afp_fail usage "Unknown option: $1" ;;
        *) [ -z "$REF" ] || afp_fail usage "unexpected argument: $1"; REF="$1"; shift ;;
    esac
done

[ -n "$REF" ] || { show_help >&2; afp_fail usage "get needs a reference"; }

afp_init

case "$REF" in
    @*) [ -r "${REF#@}" ] || afp_fail not_found "reference file not readable: ${REF#@}"; REF=$(cat "${REF#@}") ;;
esac
afp_parse_ref "$REF"
if [ -n "$EXPECT" ] && [[ ! "$EXPECT" =~ ^sha256:[0-9a-f]{64}$ ]]; then
    afp_fail usage "--digest must look like sha256:<64 hex digits>"
fi
[ -z "$EXPECT" ] && EXPECT="$AFP_REF_DIGEST"

# Credentials when this machine has the space, otherwise the link in the reference.
MODE="credentials"
HAVE_SPACE=false
if [ -f "$AFP_CONFIG" ] && jq -e --arg n "$AFP_REF_SPACE" '.spaces[$n] != null' "$AFP_CONFIG" >/dev/null 2>&1; then
    HAVE_SPACE=true
fi
if [ "$HAVE_SPACE" != true ]; then
    [ -n "$AFP_REF_URL" ] || afp_fail invalid_space "this machine has no access to space '${AFP_REF_SPACE}' and the reference carries no link (see: afp-config list)"
    URL_RE='^https?://[^[:space:]"'"'"'<>`\\]+$'
    [[ "$AFP_REF_URL" =~ $URL_RE ]] || afp_fail usage "the link in the reference is not a plain http(s) URL"
    MODE="url"
fi

SCAN="unknown"
OWNER=""
WARNINGS='[]'

if [ "$MODE" = "credentials" ]; then
    afp_load_space "$AFP_REF_SPACE"
    if afp_fetch_manifest "$AFP_REF_PATH"; then
        SCAN=$(jq -r '.scan // "unscanned"' "$AFP_MANIFEST_FILE")
        OWNER=$(jq -r '.owner // empty' "$AFP_MANIFEST_FILE")
        MDIGEST=$(jq -r '.digest // empty' "$AFP_MANIFEST_FILE")
        if [ -n "$EXPECT" ] && [ -n "$MDIGEST" ] && [ "$EXPECT" != "$MDIGEST" ]; then
            afp_fail digest_mismatch "the reference digest (${EXPECT}) differs from the manifest (${MDIGEST}); the object may have been replaced"
        fi
        [ -z "$EXPECT" ] && EXPECT="$MDIGEST"
        case "$SCAN" in
            clean|basic_clean|unscanned) ;;
            suspicious|rejected) afp_fail scan_blocked "the object's scan result is '${SCAN}'; ask a person to decide, do not fetch it another way" ;;
            *) afp_fail scan_blocked "the object's manifest has an unrecognized scan value '${SCAN}'" ;;
        esac
    else
        SCAN="unscanned"
        WARNINGS='["no manifest: owner and scan result unknown"]'
    fi
fi

[ -n "$EXPECT" ] || afp_fail digest_mismatch "no expected digest: the reference has none and the object has no manifest (pass --digest)"

# Where the file goes.
if [ -z "$DEST" ]; then
    TARGET="${AFP_HOME}/downloads/${AFP_REF_SPACE}/${AFP_REF_PATH}"
elif [ -d "$DEST" ]; then
    TARGET="${DEST%/}/$(afp_sanitize_filename "$AFP_REF_PATH")"
else
    case "$DEST" in */) TARGET="${DEST}$(afp_sanitize_filename "$AFP_REF_PATH")" ;; *) TARGET="$DEST" ;; esac
fi
if [ -e "$TARGET" ] && [ "$FORCE" != true ]; then
    afp_fail exists "a file already exists at ${TARGET} (use --force to overwrite)"
fi
TDIR=$(dirname "$TARGET")
mkdir -p "$TDIR" 2>/dev/null || afp_fail forbidden "cannot create ${TDIR}"
PARTIAL=$(mktemp "${TDIR}/.afp-partial.XXXXXX") || afp_fail forbidden "cannot write in ${TDIR}"
trap 'rm -f "$PARTIAL"; afp_cleanup' EXIT

# Download.
if [ "$MODE" = "credentials" ]; then
    afp_req GET "$AFP_REF_PATH" "$PARTIAL"
    afp_check_reachable
    [ "$AFP_HTTP" = "200" ] || afp_http_fail "fetching ${AFP_REF_PATH}"
else
    AFP_SPACE="$AFP_REF_SPACE"; AFP_SCHEMEHOST="${AFP_REF_URL%%\?*}"
    AFP_HTTP=$(curl -sS --connect-timeout "${AFP_CONNECT_TIMEOUT:-10}" -o "$PARTIAL" -w '%{http_code}' -- "$AFP_REF_URL" 2>"${AFP_TMP}/curl.err")
    AFP_RC=$?
    afp_check_reachable
    case "$AFP_HTTP" in
        200) ;;
        400|401|403) afp_fail forbidden "the link in the reference is not usable (HTTP ${AFP_HTTP}); it has probably expired. Ask the sender for a new link" ;;
        *) afp_http_fail "fetching the link" ;;
    esac
fi

GOT=$(afp_file_digest "$PARTIAL")
if [ "$GOT" != "$EXPECT" ]; then
    rm -f "$PARTIAL"
    afp_fail digest_mismatch "the downloaded bytes do not match: expected ${EXPECT}, got ${GOT}; the file was deleted"
fi

mv -f "$PARTIAL" "$TARGET" || afp_fail forbidden "cannot move the file into place at ${TARGET}"
SIZE=$(afp_file_size "$TARGET")

jq -n --arg ref "afp://${AFP_REF_SPACE}/${AFP_REF_PATH}" --arg path "$TARGET" --arg digest "$GOT" \
    --argjson size "$SIZE" --arg scan "$SCAN" --arg owner "$OWNER" --arg mode "$MODE" --argjson warnings "$WARNINGS" '
    {ok:true, ref:$ref, path:$path, digest:$digest, size:$size, verified:true, scan:$scan, mode:$mode}
    + (if $owner != "" then {owner:$owner} else {} end)
    + (if ($warnings | length) > 0 then {warnings:$warnings} else {} end)'
