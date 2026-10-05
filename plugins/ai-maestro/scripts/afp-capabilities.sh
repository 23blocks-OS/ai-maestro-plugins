#!/bin/bash
# =============================================================================
# AFP Capabilities - What a Space Can Do
# =============================================================================
#
# Report a space's capabilities so an agent does not promise a link on a store
# that cannot make one. By default the answer comes from the space's
# configuration; --probe asks the store.
#
# Usage:
#   afp-capabilities [options]
#
# Examples:
#   afp-capabilities
#   afp-capabilities --space artifacts --probe
#
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/afp-helper.sh"

SPACE=""
PROBE=false

show_help() {
    echo "Usage: afp-capabilities [options]"
    echo ""
    echo "Show what a space can do: link, expire, versions, offline, ui."
    echo ""
    echo "Options:"
    echo "  --space, -s NAME   Space to report (default: the default space)"
    echo "  --probe            Ask the store: confirm it answers and whether an expiry"
    echo "                       rule is set. Fails with 'unreachable' when it does not."
    echo "  --json, -j         Accepted for symmetry with amp-*; output is always JSON"
    echo "  --help, -h         Show this help"
    echo ""
    echo "Without --probe, the list is the one set with: afp-config add --capabilities."
    echo "A space with no list defaults to link only."
}

while [[ $# -gt 0 ]]; do
    case $1 in
        --space|-s) [ $# -ge 2 ] || afp_fail usage "$1 needs a value"; SPACE="$2"; shift 2 ;;
        --probe) PROBE=true; shift ;;
        --json|-j) shift ;;
        --help|-h) show_help; exit 0 ;;
        *) afp_fail usage "Unknown option: $1" ;;
    esac
done

afp_init
[ -n "$SPACE" ] && afp_require_space_name "$SPACE"
afp_load_space "$SPACE"

CAPS="$AFP_CAPS"
[ -z "$CAPS" ] && CAPS='["link"]'

if [ "$PROBE" = true ]; then
    # Reachability and credentials: list at most one key.
    afp_req_query GET "list-type=2&max-keys=1" "${AFP_TMP}/probe.xml"
    afp_check_reachable
    [ "$AFP_HTTP" = "200" ] || afp_http_fail "probing space '${AFP_SPACE}'"
    # An expiry rule on the bucket means objects with an 'expires' time are cleaned up.
    afp_req_query GET "lifecycle" "${AFP_TMP}/lc.xml"
    afp_check_reachable
    if [ "$AFP_HTTP" = "200" ] && grep -q '<Expiration>' "${AFP_TMP}/lc.xml"; then
        CAPS=$(printf '%s' "$CAPS" | jq -c '. + ["expire"] | unique')
    else
        CAPS=$(printf '%s' "$CAPS" | jq -c 'map(select(. != "expire"))')
    fi
fi

jq -n --arg space "$AFP_SPACE" --argjson caps "$CAPS" --argjson probed "$PROBE" \
    '{ok:true, space:$space, backend:"s3", capabilities:$caps, probed:$probed}'
