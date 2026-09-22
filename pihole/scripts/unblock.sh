#!/usr/bin/env bash
# Remove a wildcard block added by block.sh.
# Usage: ./unblock.sh example.com [another.com ...]
set -euo pipefail

if [ $# -lt 1 ]; then
  echo "usage: $0 <domain> [more domains...]" >&2
  exit 1
fi

docker exec pihole pihole --wild remove "$@"
echo "Unblocked: $*"
