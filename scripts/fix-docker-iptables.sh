#!/bin/bash

# Fix Docker iptables rules for Jellyfin and Immich
# This script adds missing NAT and filter rules that Docker should have created automatically

echo "Fixing Docker iptables rules..."

# Jellyfin rules
echo "Adding Jellyfin rules (port 8096 -> 192.168.16.2)..."
sudo iptables -t nat -C DOCKER ! -i br-bab1eaec371f -p tcp -m tcp --dport 8096 -j DNAT --to-destination 192.168.16.2:8096 2>/dev/null || \
  sudo iptables -t nat -A DOCKER ! -i br-bab1eaec371f -p tcp -m tcp --dport 8096 -j DNAT --to-destination 192.168.16.2:8096

sudo iptables -C DOCKER ! -i br-bab1eaec371f -o br-bab1eaec371f -p tcp -m tcp --dport 8096 -j ACCEPT 2>/dev/null || \
  sudo iptables -A DOCKER ! -i br-bab1eaec371f -o br-bab1eaec371f -p tcp -m tcp --dport 8096 -j ACCEPT

# Immich rules - Allow all traffic within the immich network
echo "Adding Immich inter-container communication rules..."
sudo iptables -C DOCKER -i br-63a5fc5a72cf -o br-63a5fc5a72cf -j ACCEPT 2>/dev/null || \
  sudo iptables -I DOCKER 1 -i br-63a5fc5a72cf -o br-63a5fc5a72cf -j ACCEPT

# Add immich network to Docker isolation and forward chains
sudo iptables -C DOCKER-ISOLATION-STAGE-1 -i br-63a5fc5a72cf ! -o br-63a5fc5a72cf -j DOCKER-ISOLATION-STAGE-2 2>/dev/null || \
  sudo iptables -I DOCKER-ISOLATION-STAGE-1 1 -i br-63a5fc5a72cf ! -o br-63a5fc5a72cf -j DOCKER-ISOLATION-STAGE-2

sudo iptables -C DOCKER-FORWARD -i br-63a5fc5a72cf -j ACCEPT 2>/dev/null || \
  sudo iptables -I DOCKER-FORWARD 1 -i br-63a5fc5a72cf -j ACCEPT

sudo iptables -C DOCKER-FORWARD -o br-63a5fc5a72cf -j ACCEPT 2>/dev/null || \
  sudo iptables -I DOCKER-FORWARD 1 -o br-63a5fc5a72cf -j ACCEPT

# Immich NAT rule for external access
echo "Adding Immich NAT rule (port 2283 -> 172.31.0.5)..."
sudo iptables -t nat -C DOCKER ! -i br-63a5fc5a72cf -p tcp -m tcp --dport 2283 -j DNAT --to-destination 172.31.0.5:2283 2>/dev/null || \
  sudo iptables -t nat -A DOCKER ! -i br-63a5fc5a72cf -p tcp -m tcp --dport 2283 -j DNAT --to-destination 172.31.0.5:2283

sudo iptables -C DOCKER ! -i br-63a5fc5a72cf -o br-63a5fc5a72cf -p tcp -m tcp --dport 2283 -j ACCEPT 2>/dev/null || \
  sudo iptables -A DOCKER ! -i br-63a5fc5a72cf -o br-63a5fc5a72cf -p tcp -m tcp --dport 2283 -j ACCEPT

echo "Done! Rules added."
echo ""
echo "Verifying rules..."
echo "NAT rules:"
sudo iptables -t nat -L DOCKER -n | grep -E "8096|2283"
echo ""
echo "Filter rules:"
sudo iptables -L DOCKER -n | grep -E "8096|2283|br-63a5fc5a72cf"

