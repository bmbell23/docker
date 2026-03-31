# Vaultwarden Setup

## Service Info

- Service: `vaultwarden`
- URL (default): `http://100.69.184.113:8222`
- Compose path: `/home/brandon/projects/docker/vaultwarden/docker-compose.yml`

## First-Time Setup

1. Prepare environment file:
   ```bash
   cd /home/brandon/projects/docker/vaultwarden
   cp .env.example .env
   ```

2. Set required values in `.env`:
   - `ADMIN_TOKEN`
   - `DOMAIN`

3. Start service:
   ```bash
   docker compose up -d
   ```

4. Create your account in web UI.

5. Disable open registration:
   - Set `SIGNUPS_ALLOWED=false`
   - Run `docker compose up -d`

## Enable 2FA

Per user in the web vault:

1. Open `Settings` -> `Two-step Login`
2. Configure one or more options:
   - Authenticator app (TOTP)
   - Security key (WebAuthn/FIDO2)

## Health and Troubleshooting

Check container status:

```bash
docker ps --filter name=vaultwarden
```

Check logs:

```bash
docker logs vaultwarden --tail 100
```

Port test:

```bash
curl -I http://127.0.0.1:8222
curl -I http://100.69.184.113:8222
```

If local works but Tailscale fails, inspect stale iptables DNAT rules as documented in `AGENTS.md`.
