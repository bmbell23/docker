#!/bin/bash
# Allow Tailscale to access Docker containers
# This fixes the issue where Docker containers aren't accessible via Tailscale IP

# Allow traffic from Tailscale to Docker
iptables -I DOCKER-USER -i tailscale0 -j ACCEPT 2>/dev/null || true
iptables -I DOCKER-USER -o tailscale0 -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT 2>/dev/null || true

# Allow forwarding between Tailscale and Docker networks
# Get all Docker bridge interfaces
for bridge in $(docker network ls --format '{{.Name}}' | xargs -I {} docker network inspect {} --format '{{.Name}} {{index .Options "com.docker.network.bridge.name"}}' 2>/dev/null | grep -v "^host\|^none" | awk '{print $2}' | grep -v '^$'); do
    iptables -I FORWARD -i tailscale0 -o $bridge -j ACCEPT 2>/dev/null || true
    iptables -I FORWARD -i $bridge -o tailscale0 -j ACCEPT 2>/dev/null || true
done

echo "Tailscale Docker routing enabled"

