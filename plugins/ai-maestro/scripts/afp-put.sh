#!/bin/bash
# =============================================================================
# AFP Put - Store a File
# =============================================================================
#
# Upload a file to a space and print its reference. The file counts as stored
# only after the object has been read back from the store and its SHA-256
# matches (spec 03), and its manifest has been written.
#
# Usage:
#   afp-put <file> [options]
#
# Examples:
#   afp-put report.pdf
#   afp-put build.tar.gz --space artifacts --path builds/2026/10/build.tar.gz --ttl 7d
#   afp-put notes.md --force
#
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/afp-helper.sh"

FILE=""
SPACE=""
OBJ_PATH=""
TTL=""
CTYPE=""
FORCE=false

show_help() {
    echo "Usage: afp-put <file> [options]"
    echo ""
    echo "Store a file in a space and print its reference."
    echo ""
    echo "Arguments:"
    echo "  file          Local file to upload"
    echo ""
    echo "Options:"
    echo "  --space, -s NAME       Target space (default: the default space)"
    echo "  --path, -p PATH        Object path (default: <yyyy>/<mm>/<filename>)"
    echo "  --ttl, -t TTL          Lifetime, for example 30m, 12h, 7d, 2w (sets 'expires')"
    echo "  --content-type TYPE    MIME type (default: detected)"
    echo "  --force, -f            Replace an existing object at the same path"
    echo "  --json, -j             Accepted for symmetry with amp-*; output is always JSON"
    echo "  --help, -h             Show this help"
    echo ""
    echo "The object is uploaded with a single PUT (limit 5 GiB), read back from the"
    echo "store and compared with the local SHA-256 before 'stored' is reported."
    echo ""
    echo "Examples:"
    echo "  afp-put report.pdf"
    echo "  afp-put build.tar.gz --space artifacts --ttl 7d"
}

while [[ $# -gt 0 ]]; do
    case $1 in
        --space|-s) [ $# -ge 2 ] || afp_fail usage "$1 needs a value"; SPACE="$2"; shift 2 ;;
        --path|-p) [ $# -ge 2 ] || afp_fail usage "$1 needs a value"; OBJ_PATH="$2"; shift 2 ;;
        --ttl|-t) [ $# -ge 2 ] || afp_fail usage "$1 needs a value"; TTL="$2"; shift 2 ;;
        --content-type) [ $# -ge 2 ] || afp_fail usage "$1 needs a value"; CTYPE="$2"; shift 2 ;;
        --force|-f) FORCE=true; shift ;;
        --json|-j) shift ;;
        --help|-h) show_help; exit 0 ;;
        -*) afp_fail usage "Unknown option: $1" ;;
        *) [ -z "$FILE" ] || afp_fail usage "unexpected argument: $1"; FILE="$1"; shift ;;
    esac
done

[ -n "$FILE" ] || { show_help >&2; afp_fail usage "put needs a file"; }

afp_init

# Everything that can be checked without the network is checked first.
[ -f "$FILE" ] && [ -r "$FILE" ] || afp_fail not_found "file not found or not readable: ${FILE}"
if [ -z "$OBJ_PATH" ]; then
    BASE=$(afp_sanitize_filename "$FILE")
    OBJ_PATH="$(date -u +%Y/%m)/${BASE}"
fi
afp_require_path "$OBJ_PATH"
[ -n "$SPACE" ] && afp_require_space_name "$SPACE"
if [ -n "$CTYPE" ] && [[ ! "$CTYPE" =~ ^[a-zA-Z0-9][a-zA-Z0-9.+-]*/[a-zA-Z0-9][a-zA-Z0-9.+-]*$ ]]; then
    afp_fail usage "invalid content type '${CTYPE}'"
fi
SIZE=$(afp_file_size "$FILE")
if [ "$SIZE" -gt "$AFP_MAX_PUT_BYTES" ]; then
    afp_fail too_large "file is ${SIZE} bytes; a single PUT is limited to ${AFP_MAX_PUT_BYTES} (5 GiB)"
fi

afp_load_space "$SPACE"
[ -z "$TTL" ] && TTL="$AFP_DEFAULT_TTL"
EXPIRES=""
if [ -n "$TTL" ]; then
    afp_ttl_seconds "$TTL"
    EXPIRES=$(afp_iso_in "$AFP_TTL_SECS")
fi
[ -z "$CTYPE" ] && CTYPE=$(afp_mime "$FILE")

# Refuse to overwrite unless asked.
if afp_exists "$OBJ_PATH" && [ "$FORCE" != true ]; then
    afp_fail exists "an object already exists at $(afp_ref "$OBJ_PATH") (use --force to replace it)"
fi

DIGEST=$(afp_file_digest "$FILE")

# Upload.
afp_req PUT "$OBJ_PATH" "${AFP_TMP}/put.out" -T "$FILE" -H "Content-Type: ${CTYPE}"
afp_check_reachable
case "$AFP_HTTP" in 200|201|204) ;; *) afp_http_fail "uploading ${OBJ_PATH}" ;; esac

# Read back from the store and compare. A copy that does not match is removed.
afp_remote_digest "$OBJ_PATH"
if [ "$AFP_REMOTE_DIGEST" != "$DIGEST" ]; then
    afp_req DELETE "$OBJ_PATH" /dev/null
    afp_fail digest_mismatch "the store returned different bytes than were sent (local ${DIGEST}, store ${AFP_REMOTE_DIGEST}); the object was removed"
fi

# Manifest, written after the object.
OWNER=$(afp_owner)
jq -n --arg afp "0.1" --arg path "$OBJ_PATH" --arg digest "$DIGEST" --argjson size "$SIZE" \
    --arg ct "$CTYPE" --arg owner "$OWNER" --arg created "$(afp_now_iso)" --arg expires "$EXPIRES" '
    {afp:$afp, path:$path, digest:$digest, size:$size, content_type:$ct, owner:$owner, created:$created}
    + (if $expires != "" then {expires:$expires} else {} end)
    + {scan:"unscanned"}' > "${AFP_TMP}/manifest.json"
afp_req PUT "${OBJ_PATH}.afp.json" "${AFP_TMP}/put.out" -T "${AFP_TMP}/manifest.json" -H "Content-Type: application/json"
if [ "$AFP_RC" -ne 0 ] || { [ "$AFP_HTTP" != "200" ] && [ "$AFP_HTTP" != "201" ] && [ "$AFP_HTTP" != "204" ]; }; then
    # No manifest means no owner, scan or expiry: do not leave a half-stored object.
    afp_req DELETE "$OBJ_PATH" /dev/null
    afp_check_reachable
    afp_http_fail "writing the manifest for ${OBJ_PATH}"
fi

jq -n --arg ref "$(afp_ref "$OBJ_PATH")" --arg digest "$DIGEST" --argjson size "$SIZE" \
    --arg endpoint "$AFP_ENDPOINT" --arg expires "$EXPIRES" --arg space "$AFP_SPACE" '
    {ok:true, stored:true, ref:$ref, digest:$digest, size:$size, endpoint:$endpoint, space:$space}
    + (if $expires != "" then {expires:$expires} else {} end)'
