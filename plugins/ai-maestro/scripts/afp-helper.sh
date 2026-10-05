#!/bin/bash
# =============================================================================
# AFP Helper Functions
# Agent Files Protocol - Core utilities for all AFP scripts
# =============================================================================
#
# This file provides common functions for:
# - Space configuration (~/.agent-files/spaces.json)
# - Space and path validation (spec 02)
# - S3 requests signed with SigV4 (path-style) and presigned links
# - Digest, owner and manifest helpers
# - JSON results and the spec's error codes (spec 03)
#
# Output convention: every command prints one JSON object on stdout. A failure
# prints {"ok":false,"error":{"code":"...","message":"..."}}, mirrors it as an
# "Error: ..." line on stderr (like the amp-* scripts) and exits 1.
#
# Requires: bash 3.2+, curl 7.75+ (--aws-sigv4), jq, openssl, shasum or sha256sum.
# Storage: ~/.agent-files/ (override with AFP_HOME)
#
# This file is sourced and does not use `set -e`: each failure path has to print
# its JSON error before exiting, which `set -e` would skip.
# =============================================================================

# Validation uses character ranges; keep them byte-exact in every locale.
export LC_ALL=C

AFP_VERSION="0.1.0"
AFP_HOME="${AFP_HOME:-$HOME/.agent-files}"
AFP_CONFIG="${AFP_HOME}/spaces.json"
AFP_TMP=""
AFP_MAX_PUT_BYTES=5368709120      # single PUT limit on S3 (5 GiB); no multipart in v0.1
AFP_MAX_LINK_TTL=604800           # 7 days
AFP_DEFAULT_LINK_TTL=3600         # 1 hour

# =============================================================================
# Results and errors
# =============================================================================

afp_cleanup() {
    [ -n "$AFP_TMP" ] && [ -d "$AFP_TMP" ] && rm -rf "$AFP_TMP"
    return 0
}

# afp_fail <code> <message>
# Codes (spec 03): exists not_found digest_mismatch scan_blocked unsupported
# unreachable invalid_path invalid_space forbidden too_large. "usage" is a local
# addition for bad arguments.
afp_fail() {
    local code="$1" msg="$2"
    if command -v jq >/dev/null 2>&1; then
        jq -n --arg c "$code" --arg m "$msg" '{ok:false,error:{code:$c,message:$m}}'
    else
        printf '{"ok":false,"error":{"code":"%s","message":"%s"}}\n' "$code" "$msg"
    fi
    echo "Error: ${code}: ${msg}" >&2
    exit 1
}

# Prepare the temp dir and check the tools every command needs.
afp_init() {
    command -v jq >/dev/null 2>&1 || afp_fail unsupported "jq is required (brew install jq, or apt install jq)"
    command -v curl >/dev/null 2>&1 || afp_fail unsupported "curl is required"
    command -v openssl >/dev/null 2>&1 || afp_fail unsupported "openssl is required"
    if ! command -v shasum >/dev/null 2>&1 && ! command -v sha256sum >/dev/null 2>&1; then
        afp_fail unsupported "shasum or sha256sum is required"
    fi
    local v maj min
    v=$(curl --version 2>/dev/null | head -1 | awk '{print $2}')
    maj=${v%%.*}; min=${v#*.}; min=${min%%.*}
    case "$maj$min" in ''|*[!0-9]*) ;; *)
        if [ "$maj" -lt 7 ] || { [ "$maj" -eq 7 ] && [ "$min" -lt 75 ]; }; then
            afp_fail unsupported "curl 7.75 or newer is required for --aws-sigv4 (found ${v})"
        fi ;;
    esac
    AFP_TMP=$(mktemp -d "${TMPDIR:-/tmp}/afp.XXXXXX") || afp_fail unsupported "cannot create a temp directory"
    trap afp_cleanup EXIT
    trap 'exit 130' INT TERM
}

afp_now_iso() { date -u +%Y-%m-%dT%H:%M:%SZ; }

# afp_iso_in <seconds>  -> ISO 8601 UTC timestamp that many seconds from now
afp_iso_in() { jq -nr --argjson s "$1" '(now + $s) | floor | todate'; }

# afp_ttl_seconds <ttl>  (30s, 15m, 12h, 7d, 2w) -> sets AFP_TTL_SECS, or exits with usage.
# Sets a variable instead of printing, so a failure exits the script, not a subshell.
afp_ttl_seconds() {
    local t="$1" n u
    if [[ ! "$t" =~ ^[0-9]+[smhdw]$ ]]; then
        afp_fail usage "invalid ttl '${t}' (use a number and one of s, m, h, d, w, for example 7d)"
    fi
    n=${t%?}; u=${t#"$n"}
    case "$u" in
        s) AFP_TTL_SECS=$n ;;
        m) AFP_TTL_SECS=$((n * 60)) ;;
        h) AFP_TTL_SECS=$((n * 3600)) ;;
        d) AFP_TTL_SECS=$((n * 86400)) ;;
        w) AFP_TTL_SECS=$((n * 604800)) ;;
    esac
}

# =============================================================================
# Validation (spec 02)
# =============================================================================

afp_valid_space_name() { [[ "$1" =~ ^[a-z0-9][a-z0-9-]{0,62}$ ]]; }

# Paths: [a-zA-Z0-9._/-], no "..", no "." segments, no leading "/", no empty
# segments, at most 512 characters. Anything else, including "%", is rejected,
# which covers double-encoded separators (%2F).
afp_valid_path() {
    local p="$1"
    [ -n "$p" ] || return 1
    [ ${#p} -le 512 ] || return 1
    [[ "$p" =~ ^[a-zA-Z0-9._-]+(/[a-zA-Z0-9._-]+)*$ ]] || return 1
    case "$p" in *..*) return 1 ;; esac
    case "/$p/" in */./*) return 1 ;; esac
    return 0
}

afp_require_space_name() {
    afp_valid_space_name "$1" || afp_fail invalid_space "invalid space name '${1}' (lowercase letters, digits and '-', 1 to 63 characters)"
}

afp_require_path() {
    afp_valid_path "$1" || afp_fail invalid_path "invalid path (allowed: letters, digits, '.', '_', '-' and '/' between segments; no '..', no leading '/', no empty segments, at most 512 characters)"
    case "$1" in *.afp.json) afp_fail invalid_path "paths ending in .afp.json are reserved for manifests" ;; esac
}

# afp_sanitize_filename <name> -> a name that is safe as a path segment
# Same rules as sanitize_filename in amp-helper.sh (spec: AMP attachments).
afp_sanitize_filename() {
    local f
    f=$(basename -- "$1")
    f=$(printf '%s' "$f" | sed 's/[^a-zA-Z0-9._-]/_/g; s/^[. ]*//; s/[. ]*$//')
    f=${f//../_}
    [ ${#f} -gt 200 ] && f=${f:0:200}
    case "$(printf '%s' "${f%%.*}" | tr '[:lower:]' '[:upper:]')" in
        CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9]) f="_${f}" ;;
    esac
    [ -z "$f" ] && f="unnamed_file"
    printf '%s' "$f"
}

# afp_parse_ref <ref-or-json>  Sets AFP_REF_SPACE, AFP_REF_PATH and, when the
# argument is a reference object, AFP_REF_DIGEST, AFP_REF_SIZE, AFP_REF_ENDPOINT,
# AFP_REF_URL. Validates space and path before returning.
afp_parse_ref() {
    local in="$1" ref
    AFP_REF_DIGEST=""; AFP_REF_SIZE=""; AFP_REF_ENDPOINT=""; AFP_REF_URL=""
    case "$in" in
        "{"*)
            printf '%s' "$in" | jq -e 'type == "object"' >/dev/null 2>&1 || afp_fail usage "the reference object is not valid JSON"
            ref=$(printf '%s' "$in" | jq -r '.ref // empty')
            AFP_REF_DIGEST=$(printf '%s' "$in" | jq -r '.digest // empty')
            AFP_REF_SIZE=$(printf '%s' "$in" | jq -r '.size // empty')
            AFP_REF_ENDPOINT=$(printf '%s' "$in" | jq -r '.endpoint // empty')
            AFP_REF_URL=$(printf '%s' "$in" | jq -r '.url // empty')
            ;;
        *) ref="$in" ;;
    esac
    case "$ref" in
        afp://?*/?*) ;;
        *) afp_fail invalid_path "not an AFP reference (expected afp://<space>/<path>)" ;;
    esac
    ref=${ref#afp://}
    AFP_REF_SPACE=${ref%%/*}
    AFP_REF_PATH=${ref#*/}
    afp_require_space_name "$AFP_REF_SPACE"
    afp_require_path "$AFP_REF_PATH"
    if [ -n "$AFP_REF_DIGEST" ] && [[ ! "$AFP_REF_DIGEST" =~ ^sha256:[0-9a-f]{64}$ ]]; then
        afp_fail usage "the reference digest is not sha256:<64 hex digits>"
    fi
}

# =============================================================================
# Digest and file helpers
# =============================================================================

afp_sha256_stdin() {
    if command -v shasum >/dev/null 2>&1; then shasum -a 256 | awk '{print $1}'
    else sha256sum | awk '{print $1}'; fi
}

# afp_file_digest <file> -> sha256:<hex>
afp_file_digest() { printf 'sha256:%s' "$(afp_sha256_stdin < "$1")"; }

afp_file_size() { wc -c < "$1" | tr -d ' '; }

# afp_mime <file> -> a MIME type, or application/octet-stream
afp_mime() {
    local m=""
    command -v file >/dev/null 2>&1 && m=$(file --mime-type -b -- "$1" 2>/dev/null)
    [[ "$m" =~ ^[a-zA-Z0-9][a-zA-Z0-9.+-]*/[a-zA-Z0-9][a-zA-Z0-9.+-]*$ ]] || m="application/octet-stream"
    printf '%s' "$m"
}

# afp_owner -> an AMP address for the manifest, or "unknown"
# Order: AFP_OWNER, then amp-identity.sh (when AMP is installed), else unknown.
afp_owner() {
    local o="${AFP_OWNER:-}" amp=""
    if [ -z "$o" ]; then
        amp=$(command -v amp-identity.sh 2>/dev/null || true)
        [ -z "$amp" ] && [ -x "$HOME/.local/bin/amp-identity.sh" ] && amp="$HOME/.local/bin/amp-identity.sh"
        if [ -n "$amp" ]; then
            o=$("$amp" --json 2>/dev/null </dev/null | jq -r '.primary_address // empty' 2>/dev/null)
        fi
    fi
    [[ "$o" =~ ^[a-zA-Z0-9._@:+-]{1,200}$ ]] || o="unknown"
    printf '%s' "$o"
}

# =============================================================================
# Configuration (~/.agent-files/spaces.json)
# =============================================================================
#
# {
#   "default": "shared",
#   "spaces": {
#     "shared": {
#       "backend": "s3", "endpoint": "http://host:3900", "bucket": "afp",
#       "prefix": "shared/", "region": "garage",
#       "access_key": "GK...", "secret_file": "/path/to/secret",   (or "secret_key")
#       "default_ttl": "7d", "capabilities": ["link", "expire", "ui"]
#     }
#   }
# }

# afp_load_space [name]  Resolves the space (default when empty) and sets
# AFP_SPACE, AFP_ENDPOINT, AFP_BUCKET, AFP_PREFIX, AFP_REGION, AFP_AK, AFP_SK,
# AFP_DEFAULT_TTL, AFP_CAPS, AFP_SCHEMEHOST, AFP_AUTHORITY, AFP_BASEPATH.
afp_load_space() {
    local name="${1:-}" row sf
    [ -f "$AFP_CONFIG" ] || afp_fail invalid_space "no spaces configured (run: afp-config add <name> --endpoint URL --bucket NAME ...)"
    jq -e . "$AFP_CONFIG" >/dev/null 2>&1 || afp_fail invalid_space "cannot read ${AFP_CONFIG} (not valid JSON)"
    if [ -z "$name" ]; then
        name=$(jq -r '.default // empty' "$AFP_CONFIG")
        [ -n "$name" ] || afp_fail invalid_space "no space given and no default space set (afp-config default <name>)"
    fi
    afp_require_space_name "$name"
    row=$(jq -c --arg n "$name" '.spaces[$n] // empty' "$AFP_CONFIG")
    [ -n "$row" ] || afp_fail invalid_space "unknown space '${name}' (see: afp-config list)"
    AFP_SPACE="$name"
    AFP_ENDPOINT=$(printf '%s' "$row" | jq -r '.endpoint // empty')
    AFP_BUCKET=$(printf '%s' "$row" | jq -r '.bucket // empty')
    AFP_PREFIX=$(printf '%s' "$row" | jq -r '.prefix // empty')
    AFP_REGION=$(printf '%s' "$row" | jq -r '.region // "us-east-1"')
    AFP_AK=$(printf '%s' "$row" | jq -r '.access_key // empty')
    AFP_SK=$(printf '%s' "$row" | jq -r '.secret_key // empty')
    sf=$(printf '%s' "$row" | jq -r '.secret_file // empty')
    AFP_DEFAULT_TTL=$(printf '%s' "$row" | jq -r '.default_ttl // empty')
    AFP_CAPS=$(printf '%s' "$row" | jq -c '.capabilities // empty')
    if [ -z "$AFP_SK" ] && [ -n "$sf" ]; then
        [ -r "$sf" ] || afp_fail forbidden "secret file for space '${name}' is not readable"
        AFP_SK=$(head -1 "$sf" | tr -d '\r\n')
    fi
    [ -n "$AFP_ENDPOINT" ] && [ -n "$AFP_BUCKET" ] || afp_fail invalid_space "space '${name}' has no endpoint or bucket"
    [ -n "$AFP_AK" ] && [ -n "$AFP_SK" ] || afp_fail forbidden "space '${name}' has no access key or secret"
    # The curl config file below is quoted with "": refuse characters that break it.
    case "$AFP_AK$AFP_SK" in *\"*|*\\*|*$'\n'*) afp_fail forbidden "access key or secret contains unsupported characters" ;; esac
    afp_split_endpoint
}

# afp_split_endpoint  endpoint http(s)://authority[/base] -> scheme+authority, authority, base path
afp_split_endpoint() {
    local rest
    AFP_ENDPOINT=${AFP_ENDPOINT%/}
    case "$AFP_ENDPOINT" in
        http://*|https://*) ;;
        *) afp_fail invalid_space "endpoint must start with http:// or https://" ;;
    esac
    rest=${AFP_ENDPOINT#*://}
    AFP_AUTHORITY=${rest%%/*}
    AFP_SCHEMEHOST=${AFP_ENDPOINT%%://*}://${AFP_AUTHORITY}
    case "$rest" in */*) AFP_BASEPATH="/${rest#*/}" ;; *) AFP_BASEPATH="" ;; esac
}

# afp_has_cap <name>: true when the space declares the capability, or declares none
afp_has_cap() {
    [ -z "$AFP_CAPS" ] && return 0
    printf '%s' "$AFP_CAPS" | jq -e --arg c "$1" 'index($c) != null' >/dev/null 2>&1
}

# =============================================================================
# S3 requests (SigV4, path-style)
# =============================================================================

# curl with credentials. The key pair goes in through a config file on a pipe,
# never on the command line, so it does not show up in `ps`.
afp_curl() {
    curl -sS --connect-timeout "${AFP_CONNECT_TIMEOUT:-10}" \
        -K <(printf 'user = "%s:%s"\n' "$AFP_AK" "$AFP_SK") \
        --aws-sigv4 "aws:amz:${AFP_REGION}:s3" "$@"
}

# afp_url <key>  Object URL; the key is relative to the space's prefix.
afp_url() { printf '%s%s/%s/%s%s' "$AFP_SCHEMEHOST" "$AFP_BASEPATH" "$AFP_BUCKET" "$AFP_PREFIX" "$1"; }

# afp_req <METHOD> <key> <outfile> [curl args...]
# Sets AFP_HTTP (status code, 000 when nothing answered) and AFP_RC (curl exit code).
afp_req() {
    local method="$1" key="$2" out="$3"; shift 3
    local mflag=(-X "$method")
    [ "$method" = "HEAD" ] && mflag=(-I)
    AFP_HTTP=$(afp_curl "${mflag[@]}" -o "$out" -w '%{http_code}' "$@" "$(afp_url "$key")" 2>"${AFP_TMP}/curl.err")
    AFP_RC=$?
}

# afp_req_query <METHOD> <querystring> <outfile>  Bucket-level request.
afp_req_query() {
    local method="$1" query="$2" out="$3"
    AFP_HTTP=$(afp_curl -X "$method" -o "$out" -w '%{http_code}' "${AFP_SCHEMEHOST}${AFP_BASEPATH}/${AFP_BUCKET}?${query}" 2>"${AFP_TMP}/curl.err")
    AFP_RC=$?
}

# afp_check_reachable: any transport failure, or no HTTP answer, is "unreachable".
afp_check_reachable() {
    if [ "${AFP_RC:-0}" -ne 0 ] || [ "${AFP_HTTP:-000}" = "000" ]; then
        local why
        why=$(head -c 200 "${AFP_TMP}/curl.err" 2>/dev/null | tr '\n' ' ')
        afp_fail unreachable "cannot reach the store for space '${AFP_SPACE}' at ${AFP_SCHEMEHOST} (curl exit ${AFP_RC:-?}${why:+, ${why}})"
    fi
}

# afp_http_fail <what>: map an unexpected status to a spec error code.
afp_http_fail() {
    case "$AFP_HTTP" in
        404) afp_fail not_found "$1: not found" ;;
        401|403) afp_fail forbidden "$1: the store refused the request (HTTP ${AFP_HTTP}); check the access key for space '${AFP_SPACE}'" ;;
        5??) afp_fail unreachable "$1: the store failed (HTTP ${AFP_HTTP})" ;;
        *) afp_fail forbidden "$1: unexpected answer from the store (HTTP ${AFP_HTTP})" ;;
    esac
}

# afp_exists <key>: 0 found, 1 absent. Exits on any other answer.
afp_exists() {
    afp_req HEAD "$1" /dev/null
    afp_check_reachable
    case "$AFP_HTTP" in
        200) return 0 ;;
        404) return 1 ;;
        *) afp_http_fail "checking ${1}" ;;
    esac
}

# afp_remote_digest <key>  Streams the stored object through SHA-256 without
# writing it to disk. Sets AFP_REMOTE_DIGEST (sha256:<hex>).
afp_remote_digest() {
    local key="$1" h rc
    h=$({ afp_curl -f -D "${AFP_TMP}/hdr" -o - "$(afp_url "$key")" 2>"${AFP_TMP}/curl.err"; echo "$?" >"${AFP_TMP}/rc"; } | afp_sha256_stdin)
    rc=$(cat "${AFP_TMP}/rc" 2>/dev/null || echo 1)
    if [ "$rc" != "0" ]; then
        AFP_RC=$rc; AFP_HTTP=000
        if [ "$rc" = "22" ]; then
            AFP_HTTP=$(grep '^HTTP' "${AFP_TMP}/hdr" 2>/dev/null | tail -1 | awk '{print $2}')
            AFP_RC=0
        fi
        afp_check_reachable
        afp_http_fail "reading back ${key}"
    fi
    AFP_REMOTE_DIGEST="sha256:${h}"
}

# afp_fetch_manifest <path>  Sets AFP_MANIFEST_FILE to a file holding the manifest
# and returns 0, or returns 1 when the object has no manifest.
afp_fetch_manifest() {
    AFP_MANIFEST_FILE="${AFP_TMP}/manifest.json"
    afp_req GET "${1}.afp.json" "$AFP_MANIFEST_FILE"
    afp_check_reachable
    case "$AFP_HTTP" in
        200) jq -e 'type == "object"' "$AFP_MANIFEST_FILE" >/dev/null 2>&1 && return 0
             afp_fail forbidden "the manifest for ${1} is not valid JSON" ;;
        404) return 1 ;;
        *) afp_http_fail "reading the manifest for ${1}" ;;
    esac
}

# =============================================================================
# Presigned links (pure bash + openssl, SigV4 query authentication)
# =============================================================================

_afp_hex2bin() {
    local h="$1" i
    for ((i = 0; i < ${#h}; i += 2)); do printf "\\x${h:i:2}"; done
}

_afp_sha256_hex() { openssl dgst -sha256 | awk '{print $NF}'; }

# afp_hmac_sha256_hex <key-hex> <data>  HMAC-SHA256 built from plain `openssl dgst`,
# because LibreSSL (the macOS default) has no -mac option and keys are binary.
afp_hmac_sha256_hex() {
    local keyhex="$1" data="$2" i b t ipad="" opad="" inner
    [ ${#keyhex} -gt 128 ] && keyhex=$(_afp_hex2bin "$keyhex" | _afp_sha256_hex)
    while [ ${#keyhex} -lt 128 ]; do keyhex="${keyhex}00"; done
    for ((i = 0; i < 128; i += 2)); do
        b=$((16#${keyhex:i:2}))
        printf -v t '%02x' $((b ^ 0x36)); ipad="${ipad}${t}"
        printf -v t '%02x' $((b ^ 0x5c)); opad="${opad}${t}"
    done
    inner=$({ _afp_hex2bin "$ipad"; printf '%s' "$data"; } | openssl dgst -sha256 -binary | od -An -v -tx1 | tr -d ' \n')
    { _afp_hex2bin "$opad"; _afp_hex2bin "$inner"; } | _afp_sha256_hex
}

# afp_presign <key> <ttl-seconds>  Prints a presigned GET URL for the object.
afp_presign() {
    local key="$1" ttl="$2"
    local amzdate day scope cred q path creq sts k sig
    amzdate=$(date -u +%Y%m%dT%H%M%SZ)
    day=${amzdate%%T*}
    scope="${day}/${AFP_REGION}/s3/aws4_request"
    cred="${AFP_AK}/${scope}"
    path="${AFP_BASEPATH}/${AFP_BUCKET}/${AFP_PREFIX}${key}"
    q="X-Amz-Algorithm=AWS4-HMAC-SHA256&X-Amz-Credential=${cred//\//%2F}&X-Amz-Date=${amzdate}&X-Amz-Expires=${ttl}&X-Amz-SignedHeaders=host"
    creq=$(printf 'GET\n%s\n%s\nhost:%s\n\nhost\nUNSIGNED-PAYLOAD' "$path" "$q" "$AFP_AUTHORITY")
    sts=$(printf 'AWS4-HMAC-SHA256\n%s\n%s\n%s' "$amzdate" "$scope" "$(printf '%s' "$creq" | _afp_sha256_hex)")
    k=$(printf '%s' "AWS4${AFP_SK}" | od -An -v -tx1 | tr -d ' \n')
    k=$(afp_hmac_sha256_hex "$k" "$day")
    k=$(afp_hmac_sha256_hex "$k" "$AFP_REGION")
    k=$(afp_hmac_sha256_hex "$k" "s3")
    k=$(afp_hmac_sha256_hex "$k" "aws4_request")
    sig=$(afp_hmac_sha256_hex "$k" "$sts")
    printf '%s%s?%s&X-Amz-Signature=%s' "$AFP_SCHEMEHOST" "$path" "$q" "$sig"
}

# afp_ref <path> -> afp://<space>/<path>
afp_ref() { printf 'afp://%s/%s' "$AFP_SPACE" "$1"; }
