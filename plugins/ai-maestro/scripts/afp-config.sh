#!/bin/bash
# =============================================================================
# AFP Config - Manage Spaces
# =============================================================================
#
# Add, list and remove the spaces this machine can reach, and set the default.
# Spaces live in ~/.agent-files/spaces.json (mode 600). Secrets are never
# printed.
#
# Usage:
#   afp-config add <name> --endpoint URL --bucket NAME [options]
#   afp-config list
#   afp-config remove <name>
#   afp-config default <name>
#
# Examples:
#   afp-config add shared --endpoint http://100.76.17.128:3900 --bucket afp \
#       --region garage --access-key GKabc --secret-file ~/.agent-files/shared.secret --default
#   afp-config list
#
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/afp-helper.sh"

show_help() {
    echo "Usage: afp-config add <name> --endpoint URL --bucket NAME [options]"
    echo "       afp-config list"
    echo "       afp-config remove <name>"
    echo "       afp-config default <name>"
    echo ""
    echo "Manage the spaces this machine can reach (~/.agent-files/spaces.json)."
    echo ""
    echo "Options for add:"
    echo "  --endpoint URL           S3 endpoint, http:// or https:// (path-style)"
    echo "  --bucket NAME            Bucket that holds the space"
    echo "  --prefix PREFIX          Key prefix inside the bucket (optional)"
    echo "  --region NAME            S3 region name (default: us-east-1; Garage: garage)"
    echo "  --access-key KEY         Access key id"
    echo "  --secret-file PATH       File whose first line is the secret key (recommended)"
    echo "  --secret-stdin           Read the secret key from stdin"
    echo "  --secret-key KEY         Secret key on the command line (visible in ps; avoid)"
    echo "  --default-ttl TTL        Expiry for objects put without --ttl, for example 7d"
    echo "  --capabilities LIST      Comma list: link,expire,versions,offline,ui"
    echo "  --default                Make this the default space"
    echo "  --help, -h               Show this help"
    echo ""
    echo "Secrets are stored in the config file (mode 600) or read from --secret-file,"
    echo "and are never printed."
}

[ $# -gt 0 ] || { show_help; exit 0; }
case "$1" in --help|-h) show_help; exit 0 ;; esac

afp_init

CMD="$1"; shift

# Write the config atomically with mode 600.
save_config() {
    local json="$1" tmp
    mkdir -p "$AFP_HOME" && chmod 700 "$AFP_HOME" 2>/dev/null
    tmp=$(umask 077; mktemp "${AFP_HOME}/.spaces.XXXXXX") || afp_fail forbidden "cannot write in ${AFP_HOME}"
    printf '%s\n' "$json" > "$tmp" && chmod 600 "$tmp" && mv "$tmp" "$AFP_CONFIG" || { rm -f "$tmp"; afp_fail forbidden "cannot write ${AFP_CONFIG}"; }
}

current_config() {
    if [ -f "$AFP_CONFIG" ] && jq -e . "$AFP_CONFIG" >/dev/null 2>&1; then cat "$AFP_CONFIG"
    elif [ -f "$AFP_CONFIG" ]; then afp_fail invalid_space "${AFP_CONFIG} is not valid JSON; fix or remove it"
    else echo '{"default":"","spaces":{}}'; fi
}

case "$CMD" in
    add)
        NAME=""; ENDPOINT=""; BUCKET=""; PREFIX=""; REGION="us-east-1"; AK=""; SK=""; SF=""
        DTTL=""; CAPS=""; MAKE_DEFAULT=false; SECRET_STDIN=false
        while [[ $# -gt 0 ]]; do
            case $1 in
                --endpoint) [ $# -ge 2 ] || afp_fail usage "--endpoint needs a value"; ENDPOINT="$2"; shift 2 ;;
                --bucket) [ $# -ge 2 ] || afp_fail usage "--bucket needs a value"; BUCKET="$2"; shift 2 ;;
                --prefix) [ $# -ge 2 ] || afp_fail usage "--prefix needs a value"; PREFIX="$2"; shift 2 ;;
                --region) [ $# -ge 2 ] || afp_fail usage "--region needs a value"; REGION="$2"; shift 2 ;;
                --access-key) [ $# -ge 2 ] || afp_fail usage "--access-key needs a value"; AK="$2"; shift 2 ;;
                --secret-file) [ $# -ge 2 ] || afp_fail usage "--secret-file needs a value"; SF="$2"; shift 2 ;;
                --secret-key) [ $# -ge 2 ] || afp_fail usage "--secret-key needs a value"; SK="$2"; shift 2 ;;
                --secret-stdin) SECRET_STDIN=true; shift ;;
                --default-ttl) [ $# -ge 2 ] || afp_fail usage "--default-ttl needs a value"; DTTL="$2"; shift 2 ;;
                --capabilities) [ $# -ge 2 ] || afp_fail usage "--capabilities needs a value"; CAPS="$2"; shift 2 ;;
                --default) MAKE_DEFAULT=true; shift ;;
                --json|-j) shift ;;
                --help|-h) show_help; exit 0 ;;
                -*) afp_fail usage "Unknown option: $1" ;;
                *) [ -z "$NAME" ] || afp_fail usage "unexpected argument: $1"; NAME="$1"; shift ;;
            esac
        done
        [ -n "$NAME" ] || afp_fail usage "add needs a space name"
        afp_require_space_name "$NAME"
        [ -n "$ENDPOINT" ] && [ -n "$BUCKET" ] || afp_fail usage "add needs --endpoint and --bucket"
        [[ "$ENDPOINT" =~ ^https?://[a-zA-Z0-9._:/-]+$ ]] || afp_fail usage "invalid endpoint (http:// or https:// followed by host[:port][/path])"
        [[ "$BUCKET" =~ ^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$ ]] || afp_fail usage "invalid bucket name"
        [[ "$REGION" =~ ^[a-zA-Z0-9-]+$ ]] || afp_fail usage "invalid region"
        if [ -n "$PREFIX" ]; then
            PREFIX="${PREFIX%/}"
            afp_valid_path "$PREFIX" || afp_fail invalid_path "invalid prefix"
            PREFIX="${PREFIX}/"
        fi
        [ -z "$DTTL" ] || afp_ttl_seconds "$DTTL"
        if [ -n "$CAPS" ]; then
            [[ "$CAPS" =~ ^(link|expire|versions|offline|ui)(,(link|expire|versions|offline|ui))*$ ]] || afp_fail usage "capabilities must be a comma list of: link, expire, versions, offline, ui"
        fi
        if [ "$SECRET_STDIN" = true ]; then
            IFS= read -r SK || true
        fi
        if [ -n "$SF" ]; then
            [ -r "$SF" ] || afp_fail forbidden "secret file is not readable: ${SF}"
        fi
        [ -n "$AK" ] || afp_fail usage "add needs --access-key"
        [ -n "$SK" ] || [ -n "$SF" ] || afp_fail usage "add needs --secret-file, --secret-stdin or --secret-key"
        case "$AK$SK" in *\"*|*\\*) afp_fail usage "access key or secret contains unsupported characters" ;; esac
        [[ "$AK" =~ ^[a-zA-Z0-9._-]+$ ]] || afp_fail usage "invalid access key"

        CONFIG=$(current_config)
        NEW=$(printf '%s' "$CONFIG" | jq \
            --arg name "$NAME" --arg endpoint "${ENDPOINT%/}" --arg bucket "$BUCKET" --arg prefix "$PREFIX" \
            --arg region "$REGION" --arg ak "$AK" --arg sk "$SK" --arg sf "$SF" --arg dttl "$DTTL" \
            --arg caps "$CAPS" --argjson mkdef "$MAKE_DEFAULT" '
            .spaces = (.spaces // {})
            | .spaces[$name] = ({backend:"s3", endpoint:$endpoint, bucket:$bucket, region:$region, access_key:$ak}
                + (if $prefix != "" then {prefix:$prefix} else {} end)
                + (if $sf != "" then {secret_file:$sf} else {secret_key:$sk} end)
                + (if $dttl != "" then {default_ttl:$dttl} else {} end)
                + (if $caps != "" then {capabilities:($caps | split(","))} else {} end))
            | if $mkdef or (.default // "") == "" then .default = $name else . end')
        save_config "$NEW"
        jq -n --arg n "$NAME" --arg d "$(printf '%s' "$NEW" | jq -r '.default')" --arg cfg "$AFP_CONFIG" '{ok:true, space:$n, default:$d, config:$cfg}'
        ;;

    list)
        while [[ $# -gt 0 ]]; do
            case $1 in
                --json|-j) shift ;;
                --help|-h) show_help; exit 0 ;;
                *) afp_fail usage "Unknown option: $1" ;;
            esac
        done
        current_config | jq '{ok:true, default:(.default // ""), spaces:((.spaces // {}) | with_entries(.value |= (
            {backend, endpoint, bucket, prefix, region, access_key, default_ttl, capabilities,
             secret:(if .secret_file then "file" elif .secret_key then "inline" else "unset" end)}
            | with_entries(select(.value != null)))))}'
        ;;

    remove)
        NAME="${1:-}"
        [ -n "$NAME" ] || afp_fail usage "remove needs a space name"
        afp_require_space_name "$NAME"
        CONFIG=$(current_config)
        printf '%s' "$CONFIG" | jq -e --arg n "$NAME" '.spaces[$n] != null' >/dev/null || afp_fail invalid_space "unknown space '${NAME}'"
        NEW=$(printf '%s' "$CONFIG" | jq --arg n "$NAME" 'del(.spaces[$n]) | if .default == $n then .default = "" else . end')
        save_config "$NEW"
        jq -n --arg n "$NAME" '{ok:true, removed:$n}'
        ;;

    default)
        NAME="${1:-}"
        [ -n "$NAME" ] || afp_fail usage "default needs a space name"
        afp_require_space_name "$NAME"
        CONFIG=$(current_config)
        printf '%s' "$CONFIG" | jq -e --arg n "$NAME" '.spaces[$n] != null' >/dev/null || afp_fail invalid_space "unknown space '${NAME}'"
        NEW=$(printf '%s' "$CONFIG" | jq --arg n "$NAME" '.default = $n')
        save_config "$NEW"
        jq -n --arg n "$NAME" '{ok:true, default:$n}'
        ;;

    *) afp_fail usage "unknown command '${CMD}' (use add, list, remove or default)" ;;
esac
