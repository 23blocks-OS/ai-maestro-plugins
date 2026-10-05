#!/bin/bash
# =============================================================================
# AFP Ls - List Objects
# =============================================================================
#
# List the objects in a space, read from their manifests.
#
# Usage:
#   afp-ls [options]
#
# Examples:
#   afp-ls
#   afp-ls --space artifacts --prefix builds/2026/ --limit 20
#
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/afp-helper.sh"

SPACE=""
PREFIX=""
LIMIT=100

show_help() {
    echo "Usage: afp-ls [options]"
    echo ""
    echo "List objects in a space (reads each object's manifest)."
    echo ""
    echo "Options:"
    echo "  --space, -s NAME     Space to list (default: the default space)"
    echo "  --prefix, -p PREFIX  Only paths starting with this prefix"
    echo "  --limit, -n N        Maximum number of objects (default: 100)"
    echo "  --json, -j           Accepted for symmetry with amp-*; output is always JSON"
    echo "  --help, -h           Show this help"
    echo ""
    echo "Objects without a manifest are not listed."
}

while [[ $# -gt 0 ]]; do
    case $1 in
        --space|-s) [ $# -ge 2 ] || afp_fail usage "$1 needs a value"; SPACE="$2"; shift 2 ;;
        --prefix|-p) [ $# -ge 2 ] || afp_fail usage "$1 needs a value"; PREFIX="$2"; shift 2 ;;
        --limit|-n) [ $# -ge 2 ] || afp_fail usage "$1 needs a value"; LIMIT="$2"; shift 2 ;;
        --json|-j) shift ;;
        --help|-h) show_help; exit 0 ;;
        *) afp_fail usage "Unknown option: $1" ;;
    esac
done

afp_init

[[ "$LIMIT" =~ ^[0-9]+$ ]] && [ "$LIMIT" -ge 1 ] && [ "$LIMIT" -le 1000 ] || afp_fail usage "--limit must be a number from 1 to 1000"
# A prefix may end in "/" (a folder); otherwise it is validated like a path.
if [ -n "$PREFIX" ]; then
    CHECK="${PREFIX%/}"
    [ -n "$CHECK" ] && afp_valid_path "$CHECK" || afp_fail invalid_path "invalid prefix"
fi
[ -n "$SPACE" ] && afp_require_space_name "$SPACE"

afp_load_space "$SPACE"

ITEMS="${AFP_TMP}/items.ndjson"
: > "$ITEMS"
FULL_PREFIX="${AFP_PREFIX}${PREFIX}"
ENC_PREFIX="${FULL_PREFIX//\//%2F}"
COUNT=0
TOKEN=""
TRUNCATED=false

while :; do
    Q="list-type=2&max-keys=1000"
    [ -n "$TOKEN" ] && Q="${Q}&continuation-token=${TOKEN}"
    [ -n "$FULL_PREFIX" ] && Q="${Q}&prefix=${ENC_PREFIX}"
    afp_req_query GET "$Q" "${AFP_TMP}/list.xml"
    afp_check_reachable
    [ "$AFP_HTTP" = "200" ] || afp_http_fail "listing space '${AFP_SPACE}'"

    for KEY in $(grep -o '<Key>[^<]*</Key>' "${AFP_TMP}/list.xml" | sed 's:<Key>\(.*\)</Key>:\1:' | grep -E '^[a-zA-Z0-9._/-]+\.afp\.json$'); do
        REL=${KEY#"$AFP_PREFIX"}
        OBJ=${REL%.afp.json}
        afp_valid_path "$OBJ" || continue
        if [ "$COUNT" -ge "$LIMIT" ]; then TRUNCATED=true; break; fi
        afp_req GET "$REL" "${AFP_TMP}/m.json"
        afp_check_reachable
        [ "$AFP_HTTP" = "200" ] || continue
        jq -c --arg ref "$(afp_ref "$OBJ")" 'select(type == "object") | {ref:$ref, size, digest, owner, created, expires, scan, content_type}
            | with_entries(select(.value != null))' "${AFP_TMP}/m.json" >> "$ITEMS" 2>/dev/null && COUNT=$((COUNT + 1))
    done
    [ "$TRUNCATED" = true ] && break
    if grep -q '<IsTruncated>true</IsTruncated>' "${AFP_TMP}/list.xml"; then
        TOKEN=$(grep -o '<NextContinuationToken>[^<]*</NextContinuationToken>' "${AFP_TMP}/list.xml" | sed 's:<NextContinuationToken>\(.*\)</NextContinuationToken>:\1:')
        [ -n "$TOKEN" ] || break
        TOKEN=$(printf '%s' "$TOKEN" | sed 's/+/%2B/g; s/=/%3D/g; s:/:%2F:g')
    else
        break
    fi
done

jq -s --arg space "$AFP_SPACE" --argjson truncated "$TRUNCATED" '{ok:true, space:$space, items:., truncated:$truncated}' "$ITEMS"
