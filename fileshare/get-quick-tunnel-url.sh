#!/usr/bin/env bash
set -euo pipefail

# Print the latest trycloudflare.com URL from cloudflared logs.
# Usage:
#   ./get-quick-tunnel-url.sh
#   ./get-quick-tunnel-url.sh -f   # follow logs after printing URL

FOLLOW=0
if [[ "${1:-}" == "-f" || "${1:-}" == "--follow" ]]; then
  FOLLOW=1
fi

if ! command -v docker >/dev/null 2>&1; then
  echo "docker is not installed or not in PATH" >&2
  exit 1
fi

LOGS=$(docker compose logs cloudflared 2>&1 || true)
URL=$(printf '%s\n' "$LOGS" | grep -Eo 'https://[a-zA-Z0-9.-]+\.trycloudflare\.com' | tail -n 1 || true)

if [[ -n "$URL" ]]; then
  echo "$URL"
else
  echo "Quick Tunnel URL not found yet. Check live logs:" >&2
  echo "docker compose logs -f cloudflared" >&2
  exit 2
fi

if [[ "$FOLLOW" -eq 1 ]]; then
  docker compose logs -f cloudflared
fi
