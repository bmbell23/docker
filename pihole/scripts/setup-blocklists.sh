#!/usr/bin/env bash
# Subscribe Pi-hole to the standard blocklists and rebuild gravity.
# Idempotent — safe to re-run; already-subscribed lists are skipped.
#
# Lists:
#   - StevenBlack unified   (ads + malware, ships as the Pi-hole default)
#   - OISD big              (broad ad/tracker/malware list, low false positives)
#   - OISD NSFW             (adult content)
#   - StevenBlack porn-only (adult content, second source)
set -euo pipefail

LISTS=(
  "https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts|StevenBlack unified (ads + malware)"
  "https://big.oisd.nl|OISD big (ads/trackers/malware)"
  "https://nsfw.oisd.nl|OISD NSFW (adult content)"
  "https://raw.githubusercontent.com/StevenBlack/hosts/master/alternates/porn-only/hosts|StevenBlack porn-only"
)

for entry in "${LISTS[@]}"; do
  url="${entry%%|*}"
  comment="${entry#*|}"
  docker exec pihole pihole-FTL sqlite3 /etc/pihole/gravity.db \
    "INSERT OR IGNORE INTO adlist (address, enabled, comment) VALUES ('${url}', 1, '${comment}');"
  echo "subscribed: ${comment}"
done

echo "Rebuilding gravity (downloads all lists, takes a minute)..."
docker exec pihole pihole -g
