# Scripts Directory

This directory contains maintenance and utility scripts for the Docker infrastructure.

## fix-docker-iptables.sh

**Purpose:** Fixes missing iptables rules for Docker networks after Docker daemon restarts.

**When to use:**
- After Docker daemon restarts
- After system reboots
- When containers cannot communicate with each other despite showing as "healthy"
- When you see "connect ETIMEDOUT" errors in container logs

**Usage:**
```bash
sudo ./scripts/fix-docker-iptables.sh
```

**Automatic execution on boot:**
```bash
sudo cp scripts/fix-docker-iptables.service /etc/systemd/system/
sudo systemctl enable fix-docker-iptables.service
sudo systemctl start fix-docker-iptables.service
```

**What it does:**
- Adds missing DOCKER-ISOLATION-STAGE-1 rules for Docker bridge networks
- Adds missing DOCKER-FORWARD rules for Docker bridge networks
- Adds missing DOCKER inter-container communication rules
- Checks for the following networks:
  - `immich_default` (Immich)
  - `outline_outline_network` (Outline)
  - `jellyfin_default` (Jellyfin)

**See also:** [../docs/DOCKER_NETWORKING_ISSUES.md](../docs/DOCKER_NETWORKING_ISSUES.md)

## fix-docker-iptables.service

**Purpose:** Systemd service file to run `fix-docker-iptables.sh` automatically on boot.

**Installation:**
```bash
sudo cp scripts/fix-docker-iptables.service /etc/systemd/system/
sudo systemctl enable fix-docker-iptables.service
```

**Check status:**
```bash
sudo systemctl status fix-docker-iptables.service
```

**View logs:**
```bash
sudo journalctl -u fix-docker-iptables.service
```

