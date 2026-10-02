#!/bin/bash
# Is deemix's Deezer ARL still valid? (docker#42)
# The ARL is a login cookie that Deezer expires every few months; when it dies deemix
# fails downloads quietly. The dagu DAG deemix-arl-check runs this daily at 09:00.
#   deemix-arl-check.sh            check the ARL in deemix/config/login.json (or .arl)
#   deemix-arl-check.sh --stdin    check an ARL read from stdin (used by deemix-set-arl.sh)
# Exit 0 = valid, 1 = Deezer rejected it (or none configured), 2 = couldn't reach Deezer.
# The ARL is a secret: it never goes on a command line or into output. It reaches curl
# as a header on stdin.

set -uo pipefail

CONFIG_DIR="${DEEMIX_CONFIG:-/home/brandon/projects/docker/deemix/config}"
URL='https://www.deezer.com/ajax/gw-light.php?method=deezer.getUserData&input=3&api_version=1.0&api_token='
RENEW='Renew: get the arl cookie from deezer.com in a browser, then run ~/projects/docker/scripts/deemix-set-arl.sh'

if [ "${1:-}" = "--stdin" ]; then
    IFS= read -r arl
else
    arl=$(jq -r '.arl // empty' "$CONFIG_DIR/login.json" 2>/dev/null)
    if [ -z "$arl" ] && [ -f "$CONFIG_DIR/.arl" ]; then
        IFS= read -r arl < "$CONFIG_DIR/.arl"
    fi
fi
arl="${arl//[[:space:]]/}"

if [ -z "$arl" ]; then
    echo "ARL INVALID: none configured in $CONFIG_DIR"
    echo "$RENEW"
    exit 1
fi

resp=$(printf 'Cookie: arl=%s\n' "$arl" | curl -sS -m 30 -H @- "$URL" 2>&1)
rc=$?
unset arl
if [ $rc -ne 0 ]; then
    echo "Deezer unreachable (curl exit $rc): $resp"
    exit 2
fi

if ! jq -e '.results.USER' <<<"$resp" >/dev/null 2>&1; then
    echo "Deezer unreachable or bad reply (not the expected JSON)"
    exit 2
fi

id=$(jq -r '.results.USER.USER_ID // 0' <<<"$resp")
if [ "$id" = "0" ] || [ -z "$id" ] || [ "$id" = "null" ]; then
    echo "ARL INVALID: Deezer sees no logged-in user"
    echo "$RENEW"
    exit 1
fi

name=$(jq -r '.results.USER.BLOG_NAME // .results.USER.NAME // "?"' <<<"$resp")
offer=$(jq -r '.results.OFFER_NAME // empty' <<<"$resp")
echo "ARL valid (user $name, id $id)"
[ -n "$offer" ] && echo "Plan: $offer"
exit 0
