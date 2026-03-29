# Disposable Fileshare (miniserve + cloudflared)

This folder is for short-lived, one-off sharing of a specific file or directory with one external recipient.

It is intentionally minimal:
- outbound-only tunnel via Cloudflare
- no host port publishing
- no reverse proxy
- source path mounted read-only
- no local database or persistent app state

## TL;DR (free mode)

```bash
cd /home/brandon/projects/docker/fileshare
cp .env.example .env
# edit .env and set SHARE_PATH
docker compose -f docker-compose.yml -f docker-compose.quick-tunnel.yml up -d
./get-quick-tunnel-url.sh
```

Share the printed `https://...trycloudflare.com` URL.

## When to use this

Use this when you need to briefly share something directly from its original location, then tear everything down.

Do not use this as a permanent portal or multi-user file service.

## Requirements

- Docker + Docker Compose plugin
- For free Quick Tunnel mode: no domain and no Cloudflare token required
- For named tunnel mode (optional): a Cloudflare Tunnel token and a public hostname routed to that tunnel (for example `share.example.com`)

## Setup

1. Create your local env file:

```bash
cd /home/brandon/projects/docker/fileshare
cp .env.example .env
```

2. Edit `.env` and set at least:
- `SHARE_PATH` (file or directory to share)
- For Quick Tunnel mode: only `SHARE_PATH` is required
- For named tunnel mode: `CF_TUNNEL_TOKEN` and `CF_TUNNEL_HOSTNAME`

### Path examples

Directory share:

```bash
SHARE_PATH=/mnt/storage/share-folder
```

Single-file share:

```bash
SHARE_PATH=/mnt/storage/reports/final-report.pdf
```

## Start a share (free Quick Tunnel)

Use this when you want zero cost and do not need a custom domain.

```bash
docker compose -f docker-compose.yml -f docker-compose.quick-tunnel.yml up -d
```

Get the public URL from logs (looks like `https://random-string.trycloudflare.com`):

```bash
docker compose logs -f cloudflared
```

Or use helper script:

```bash
chmod +x ./get-quick-tunnel-url.sh
./get-quick-tunnel-url.sh
```

Share that URL with the recipient.

## Start a share (named tunnel + custom hostname)

```bash
docker compose up -d
```

Recipient URL:
- `https://<CF_TUNNEL_HOSTNAME>`

## Start a share (with basic auth)

1. Set `MINISERVE_AUTH` in `.env` (plain or hashed format).
2. Start with override file.

Named tunnel:

```bash
docker compose -f docker-compose.yml -f docker-compose.auth.yml up -d
```

Quick Tunnel:

```bash
docker compose -f docker-compose.yml -f docker-compose.quick-tunnel.yml -f docker-compose.auth.yml up -d
```

## Stop and clean up

```bash
docker compose down --remove-orphans
```

That fully stops both containers. No app data is persisted by this project.

## Operational runbook

Start free Quick Tunnel:

```bash
docker compose -f docker-compose.yml -f docker-compose.quick-tunnel.yml up -d
```

Start named tunnel:

```bash
docker compose up -d
```

Start with basic auth (Quick Tunnel):

```bash
docker compose -f docker-compose.yml -f docker-compose.quick-tunnel.yml -f docker-compose.auth.yml up -d
```

Start with basic auth (named tunnel):

```bash
docker compose -f docker-compose.yml -f docker-compose.auth.yml up -d
```

Stop and delete containers:

```bash
docker compose down --remove-orphans
```

## Useful commands

```bash
# Follow tunnel logs
docker compose logs -f cloudflared

# Follow miniserve logs
docker compose logs -f miniserve

# Pull latest images before use
docker compose pull
```

## Troubleshooting

No URL appears in Quick Tunnel logs:
- Confirm stack is up: `docker compose ps`
- Check tunnel logs: `docker compose logs cloudflared`
- Restart cleanly: `docker compose down --remove-orphans && docker compose -f docker-compose.yml -f docker-compose.quick-tunnel.yml up -d`

Recipient gets auth prompt unexpectedly:
- You likely started with `docker-compose.auth.yml`; restart without it if auth is not desired.

Miniserve starts but file listing is empty or wrong:
- Verify `SHARE_PATH` in `.env` points to the exact path you intend.
- For files, point to the file path directly (not just parent dir, unless desired).
- Confirm read permissions on host path for Docker.

## Security notes and tradeoffs

- `SHARE_PATH` is mounted read-only into miniserve (`:ro`).
- No host ports are published, so there is no direct inbound listener on this host from this stack.
- TLS terminates at Cloudflare.
- Basic auth is optional and simple, but should still use strong credentials if enabled.
- This design favors simplicity and disposability over advanced access management features.
- Quick Tunnel URLs are temporary and random, which is convenient and free but less stable than a custom hostname.

## Files in this folder

- `docker-compose.yml`: base stack with miniserve + named cloudflared tunnel
- `docker-compose.quick-tunnel.yml`: free mode override (no domain/token)
- `docker-compose.auth.yml`: optional basic auth override for miniserve
- `.env.example`: variable reference template
- `get-quick-tunnel-url.sh`: helper to print current Quick Tunnel URL from logs
