#!/bin/bash
# =============================================================================
# AFP Link - Mint a Download Link
# =============================================================================
#
# Print a reference object that carries a time-limited download URL. Anyone
# holding the URL can fetch that one object until it expires, so keep the
# lifetime short. Needs the 'link' capability.
#
# Usage:
#   afp-link <ref> [options]
#
# Examples:
#   afp-link afp://artifacts/2026/10/report.pdf
#   afp-link afp://artifacts/2026/10/report.pdf --ttl 15m
#
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/afp-helper.sh"

REF=""
TTL=""

show_help() {
    echo "Usage: afp-link <ref> [options]"
    echo ""
    echo "Mint a time-limited download link for an object."
    echo ""
    echo "Arguments:"
    echo "  ref           afp://<space>/<path>"
    echo ""
    echo "Options:"
    echo "  --ttl, -t TTL   Link lifetime, for example 30s, 15m, 1h, 2d (default 1h, max 7d)"
    echo "  --json, -j      Accepted for symmetry with amp-*; output is always JSON"
    echo "  --help, -h      Show this help"
    echo ""
    echo "The output is a full reference object (ref, digest, size, endpoint, url) that"
    echo "can go into a message. The link is a bearer credential until it expires."
}

while [[ $# -gt 0 ]]; do
    case $1 in
        --ttl|-t) [ $# -ge 2 ] || afp_fail usage "$1 needs a value"; TTL="$2"; shift 2 ;;
        --json|-j) shift ;;
        --help|-h) show_help; exit 0 ;;
        -*) afp_fail usage "Unknown option: $1" ;;
        *) [ -z "$REF" ] || afp_fail usage "unexpected argument: $1"; REF="$1"; shift ;;
    esac
done

[ -n "$REF" ] || { show_help >&2; afp_fail usage "link needs a reference"; }

afp_init
afp_parse_ref "$REF"

if [ -z "$TTL" ]; then
    AFP_TTL_SECS=$AFP_DEFAULT_LINK_TTL
else
    afp_ttl_seconds "$TTL"
fi
{ [ "$AFP_TTL_SECS" -ge 1 ] && [ "$AFP_TTL_SECS" -le "$AFP_MAX_LINK_TTL" ]; } || afp_fail usage "link lifetime must be between 1 second and 7 days"

afp_load_space "$AFP_REF_SPACE"
afp_has_cap link || afp_fail unsupported "space '${AFP_SPACE}' does not support links"

# The reference needs the digest and size, so the object must have a manifest.
if ! afp_fetch_manifest "$AFP_REF_PATH"; then
    afp_exists "$AFP_REF_PATH" || afp_fail not_found "no object at afp://${AFP_SPACE}/${AFP_REF_PATH}"
    afp_fail not_found "the object has no manifest, so its digest is unknown; put it again with afp-put"
fi
DIGEST=$(jq -r '.digest // empty' "$AFP_MANIFEST_FILE")
SIZE=$(jq -r '.size // empty' "$AFP_MANIFEST_FILE")
[ -n "$DIGEST" ] && [ -n "$SIZE" ] || afp_fail not_found "the manifest has no digest or size"
afp_exists "$AFP_REF_PATH" || afp_fail not_found "the manifest exists but the object does not: afp://${AFP_SPACE}/${AFP_REF_PATH}"

URL=$(afp_presign "$AFP_REF_PATH" "$AFP_TTL_SECS")

jq -n --arg ref "$(afp_ref "$AFP_REF_PATH")" --arg digest "$DIGEST" --argjson size "$SIZE" \
    --arg endpoint "$AFP_ENDPOINT" --arg url "$URL" --arg until "$(afp_iso_in "$AFP_TTL_SECS")" '
    {ok:true, ref:$ref, digest:$digest, size:$size, endpoint:$endpoint, url:$url, url_expires:$until}'
