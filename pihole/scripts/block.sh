#!/usr/bin/env bash
# Block one or more sites network-wide (domain + all its subdomains).
# Usage: ./block.sh example.com [another.com ...]
set -euo pipefail

if [ $# -lt 1 ]; then
  echo "usage: $0 <domain> [more domains...]" >&2
  exit 1
fi

docker exec pihole pihole --wild "$@"
echo "Blocked (incl. subdomains): $*"
