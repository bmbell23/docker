# Vaultwarden - Self-Hosted Password Manager

Vaultwarden is a lightweight, open-source Bitwarden-compatible server for personal or family password management.

## What You Get

- Web vault at `https://dockerhost.tailb8b575.ts.net` (recommended)
- Optional direct HTTP access at `http://100.69.184.113:8222` for troubleshooting only
- Bitwarden-compatible browser/mobile/desktop clients
- Built-in support for 2FA (TOTP, WebAuthn/FIDO2)
- Self-hosted data and backups under your control

## Quick Start

1. Copy the environment template:
   ```bash
   cd /home/brandon/projects/docker/vaultwarden
   cp .env.example .env
   ```

2. Edit `.env` and set at minimum:
   - `ADMIN_TOKEN` to a long random value
   - `DOMAIN` to your real access URL
   - Keep SMTP variables commented unless you are actively configuring email

3. Start the service:
   ```bash
   docker compose up -d
   ```

4. Open Vaultwarden:
   - `https://dockerhost.tailb8b575.ts.net`

Note: Browser crypto features require a secure context. If you open Vaultwarden over plain HTTP by IP, login/setup can fail with a secure-context error.

5. Create your account(s), then lock registration:
   - Set `SIGNUPS_ALLOWED=false` in `.env`
   - Restart service:
     ```bash
     docker compose up -d
     ```

## Recommended Security Baseline

1. Keep service reachable only on your Tailscale/private network.
2. Use a strong master password (passphrase length > 20 chars).
3. Enable 2FA immediately per account:
   - Web vault -> `Settings` -> `Two-step Login`.
4. Keep `SIGNUPS_ALLOWED=false` after setup.
5. Keep `INVITATIONS_ALLOWED=false` unless you actively need it.
6. Rotate `ADMIN_TOKEN` if leaked or exposed.

## Admin Panel

- URL: `http://100.69.184.113:8222/admin`
- URL: `https://dockerhost.tailb8b575.ts.net/admin`
- Auth: `ADMIN_TOKEN` from `.env`

## Backups

Use the backup script:

```bash
/home/brandon/projects/docker/scripts/backup/vaultwarden-backup.sh
```

By default this saves backups under:

- `/home/brandon/projects/docker/vaultwarden/backups/`

## Restore Notes

1. Stop Vaultwarden container.
2. Extract a backup archive.
3. Replace `vaultwarden/data/` with extracted data.
4. Start Vaultwarden container.

## Useful Commands

```bash
cd /home/brandon/projects/docker/vaultwarden
docker compose ps
docker compose logs -f vaultwarden
docker compose pull
docker compose up -d
```

## Official Links

- Vaultwarden: https://github.com/dani-garcia/vaultwarden
- Bitwarden clients: https://bitwarden.com/download/
