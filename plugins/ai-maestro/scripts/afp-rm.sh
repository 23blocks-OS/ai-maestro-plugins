#!/bin/bash
# =============================================================================
# AFP Rm - Delete an Object
# =============================================================================
#
# Delete an object and its manifest. Only the owner named in the manifest, or a
# host administrator (--admin), may delete. Success is reported only after the
# store confirms the object is gone.
#
# Usage:
#   afp-rm <ref> [options]
#
# Examples:
#   afp-rm afp://artifacts/2026/10/report.pdf
#   afp-rm afp://shared/old/notes.md --admin
#
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/afp-helper.sh"

REF=""
ADMIN=false

show_help() {
    echo "Usage: afp-rm <ref> [options]"
    echo ""
    echo "Delete an object and its manifest."
    echo ""
    echo "Arguments:"
    echo "  ref           afp://<space>/<path>"
    echo ""
    echo "Options:"
    echo "  --admin       Delete an object that belongs to someone else (host administrator)"
    echo "  --json, -j    Accepted for symmetry with amp-*; output is always JSON"
    echo "  --help, -h    Show this help"
    echo ""
    echo "The owner is read from the manifest. When this machine's identity or the"
    echo "manifest's owner is unknown, the owner check cannot refuse the delete."
}

while [[ $# -gt 0 ]]; do
    case $1 in
        --admin) ADMIN=true; shift ;;
        --json|-j) shift ;;
        --help|-h) show_help; exit 0 ;;
        -*) afp_fail usage "Unknown option: $1" ;;
        *) [ -z "$REF" ] || afp_fail usage "unexpected argument: $1"; REF="$1"; shift ;;
    esac
done

[ -n "$REF" ] || { show_help >&2; afp_fail usage "rm needs a reference"; }

afp_init
afp_parse_ref "$REF"
afp_load_space "$AFP_REF_SPACE"

afp_exists "$AFP_REF_PATH" || {
    # An orphaned manifest can still be cleaned up.
    afp_fetch_manifest "$AFP_REF_PATH" || afp_fail not_found "no object at afp://${AFP_SPACE}/${AFP_REF_PATH}"
}

if afp_fetch_manifest "$AFP_REF_PATH"; then
    MOWNER=$(jq -r '.owner // "unknown"' "$AFP_MANIFEST_FILE")
    ME=$(afp_owner)
    if [ "$ADMIN" != true ] && [ "$MOWNER" != "unknown" ] && [ "$ME" != "unknown" ] && [ "$MOWNER" != "$ME" ]; then
        afp_fail forbidden "this object belongs to ${MOWNER}; only the owner or an administrator (--admin) may delete it"
    fi
fi

for K in "$AFP_REF_PATH" "${AFP_REF_PATH}.afp.json"; do
    afp_req DELETE "$K" /dev/null
    afp_check_reachable
    case "$AFP_HTTP" in 200|204|404) ;; *) afp_http_fail "deleting ${K}" ;; esac
    # Confirm with the store.
    if afp_exists "$K"; then
        afp_fail forbidden "the store accepted the delete but ${K} is still there"
    fi
done

jq -n --arg ref "$(afp_ref "$AFP_REF_PATH")" '{ok:true, removed:$ref}'
