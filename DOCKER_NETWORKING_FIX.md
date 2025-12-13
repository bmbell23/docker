# Docker Networking Fix for External Access

## Problem
Docker containers were not accessible externally (192.168.0.158:PORT or 100.123.154.40:PORT) even though:
- Localhost access worked fine
- UFW was configured correctly  
- Docker was creating NAT rules
- docker-proxy processes were running

## Root Cause
Docker was assigning new networks to `192.168.16.x/20` subnets which conflicted with the LAN network `192.168.0.x/24`. This caused routing conflicts preventing external access.

Working containers used `172.x.x.x` subnets and worked fine.

## Solution
Force Docker Compose networks to use `172.x.x.x` subnets by explicitly defining IPAM configuration:

```yaml
networks:
  your_network_name:
    driver: bridge
    ipam:
      config:
        - subnet: 172.32.0.0/16
          gateway: 172.32.0.1
```

## Implementation Steps
1. Add explicit subnet configuration to docker-compose.yml
2. Use unique `172.x.x.x` subnets for each project (172.32.x.x, 172.33.x.x, etc.)
3. Restart containers: `docker compose down && docker compose up -d`
4. If still not working, restart Docker daemon: `sudo systemctl restart docker`

## Verification
- Check NAT rules: `sudo iptables -t nat -L DOCKER -n | grep PORT`
- Should show `172.x.x.x` destination, not `192.168.x.x`
- Test external access: `curl -I http://192.168.0.158:PORT`

## Applied To
- ✅ Flood torrent setup (172.32.0.0/16)
- Future containers should use 172.33.0.0/16, 172.34.0.0/16, etc.

Date: 2025-12-13
Status: WORKING ✅
