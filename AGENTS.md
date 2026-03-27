# AI Agent Guidelines for docker (infrastructure)

## 🚨 CRITICAL SYSTEM OPERATION RULES 🚨

### FORBIDDEN OPERATIONS — NEVER DO THESE

- `sudo reboot`, `systemctl reboot`, `shutdown`, `poweroff` — NEVER restart the system
- `pg_resetwal` — NEVER without verified backups
- `DROP DATABASE` — NEVER without explicit permission
- `docker-compose down` on production — NEVER stop all services at once
- `docker system prune -a` — NEVER without permission

### ✅ Restarting Services

**`docker restart` and `docker-compose restart` FAIL on this server.**

```bash
PID=$(docker inspect <container_name> --format '{{.State.Pid}}')
kill $PID
cd /home/brandon/projects/docker
docker-compose up -d
```

### iptables: Stale DNAT Rules After Container Redeploy

**Recurring issue**: When Docker containers are recreated, stale DNAT rules remain in
iptables and hijack traffic before the correct rule fires. The service will work on
`127.0.0.1` but be **unreachable externally** (e.g., via Tailscale `100.69.184.113`).

```bash
sudo iptables-save | grep "DNAT.*<port>"
# Remove the stale rule pointing to the dead container IP:
sudo iptables -t nat -D DOCKER ! -i <old-bridge> -p tcp -m tcp --dport <port> -j DNAT --to-destination <old-ip>:<port>
```

### 🔍 Diagnostic Steps Before Any Action

1. **Check logs**: `docker logs <container>`
2. **Check resources**: `df -h`, `free -h`, `docker stats`
3. **Check status**: `docker ps -a`
4. **Identify root cause**: Don't guess, investigate
5. **Ask user**: If unsure, always ask before proceeding

## Project Guidelines

- **Directory**: `/home/brandon/projects/docker`
- **Tailscale IP**: `100.69.184.113`
- See shared guidelines: `/home/brandon/projects/.augment-guidelines`
