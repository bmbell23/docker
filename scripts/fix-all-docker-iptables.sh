#!/bin/bash

# Comprehensive Docker iptables fix for ALL containers
# This script ensures all Docker containers have proper NAT and filter rules

set -e

echo "=========================================="
echo "Docker iptables Comprehensive Fix"
echo "=========================================="
echo ""

# Function to add NAT rule if it doesn't exist
add_nat_rule() {
    local bridge=$1
    local host_port=$2
    local container_ip=$3
    local container_port=$4
    local proto=${5:-tcp}
    
    sudo iptables -t nat -C DOCKER ! -i $bridge -p $proto -m $proto --dport $host_port -j DNAT --to-destination $container_ip:$container_port 2>/dev/null || \
        sudo iptables -t nat -A DOCKER ! -i $bridge -p $proto -m $proto --dport $host_port -j DNAT --to-destination $container_ip:$container_port
}

# Function to add filter rule if it doesn't exist
add_filter_rule() {
    local bridge=$1
    local port=$2
    local proto=${3:-tcp}
    
    sudo iptables -C DOCKER ! -i $bridge -o $bridge -p $proto -m $proto --dport $port -j ACCEPT 2>/dev/null || \
        sudo iptables -A DOCKER ! -i $bridge -o $bridge -p $proto -m $proto --dport $port -j ACCEPT
}

# Function to add network isolation and forward rules
add_network_rules() {
    local bridge=$1
    
    # Add to DOCKER-ISOLATION-STAGE-1
    sudo iptables -C DOCKER-ISOLATION-STAGE-1 -i $bridge ! -o $bridge -j DOCKER-ISOLATION-STAGE-2 2>/dev/null || \
        sudo iptables -I DOCKER-ISOLATION-STAGE-1 1 -i $bridge ! -o $bridge -j DOCKER-ISOLATION-STAGE-2
    
    # Add to DOCKER-FORWARD (both directions)
    sudo iptables -C DOCKER-FORWARD -i $bridge -j ACCEPT 2>/dev/null || \
        sudo iptables -I DOCKER-FORWARD 1 -i $bridge -j ACCEPT
    
    sudo iptables -C DOCKER-FORWARD -o $bridge -j ACCEPT 2>/dev/null || \
        sudo iptables -I DOCKER-FORWARD 1 -o $bridge -j ACCEPT
    
    # Allow inter-container communication
    sudo iptables -C DOCKER -i $bridge -o $bridge -j ACCEPT 2>/dev/null || \
        sudo iptables -I DOCKER 1 -i $bridge -o $bridge -j ACCEPT
}

echo "Adding rules for all containers..."
echo ""

# Immich (2283 -> 172.31.0.5)
echo "→ Immich (port 2283)"
add_network_rules "br-63a5fc5a72cf"
add_nat_rule "br-63a5fc5a72cf" 2283 "172.31.0.5" 2283
add_filter_rule "br-63a5fc5a72cf" 2283

# Dashboard (8001 -> 172.22.0.2)
echo "→ Dashboard (port 8001)"
add_network_rules "br-afa60917f2db"
add_nat_rule "br-afa60917f2db" 8001 "172.22.0.2" 5000
add_filter_rule "br-afa60917f2db" 5000

# YT-DLP Web (8998 -> 172.29.0.2)
echo "→ YT-DLP Web (port 8998)"
add_network_rules "br-9deb05da66a0"
add_nat_rule "br-9deb05da66a0" 8998 "172.29.0.2" 3033
add_filter_rule "br-9deb05da66a0" 3033

# Jellyfin (8096 -> 172.23.0.2)
echo "→ Jellyfin (port 8096)"
add_network_rules "br-4d578cc17712"
add_nat_rule "br-4d578cc17712" 8096 "172.23.0.2" 8096
add_filter_rule "br-4d578cc17712" 8096
add_nat_rule "br-4d578cc17712" 8920 "172.23.0.2" 8920
add_filter_rule "br-4d578cc17712" 8920
add_nat_rule "br-4d578cc17712" 1900 "172.23.0.2" 1900 udp
add_filter_rule "br-4d578cc17712" 1900 udp
add_nat_rule "br-4d578cc17712" 7359 "172.23.0.2" 7359 udp
add_filter_rule "br-4d578cc17712" 7359 udp

# Picard (5800 -> 192.168.32.2)
echo "→ Picard (port 5800)"
add_network_rules "br-0ecc35eb449e"
add_nat_rule "br-0ecc35eb449e" 5800 "192.168.32.2" 5800
add_filter_rule "br-0ecc35eb449e" 5800

# Navidrome (4533 -> 172.28.0.2)
echo "→ Navidrome (port 4533)"
add_network_rules "br-0b8c6c77b4ec"
add_nat_rule "br-0b8c6c77b4ec" 4533 "172.28.0.2" 4533
add_filter_rule "br-0b8c6c77b4ec" 4533

# qBittorrent/Jackett via Mullvad VPN (2285, 9117 -> 172.32.0.2)
echo "→ qBittorrent/Jackett (ports 2285, 9117)"
add_network_rules "br-c1ac5e711d83"
add_nat_rule "br-c1ac5e711d83" 2285 "172.32.0.2" 8080
add_filter_rule "br-c1ac5e711d83" 8080
add_nat_rule "br-c1ac5e711d83" 9117 "172.32.0.2" 9117
add_filter_rule "br-c1ac5e711d83" 9117
add_nat_rule "br-c1ac5e711d83" 6881 "172.32.0.2" 6881
add_filter_rule "br-c1ac5e711d83" 6881
add_nat_rule "br-c1ac5e711d83" 6881 "172.32.0.2" 6881 udp
add_filter_rule "br-c1ac5e711d83" 6881 udp

# LifeForge (8004 -> 192.168.112.2)
echo "→ LifeForge (port 8004)"
add_network_rules "br-01aa55656fca"
add_nat_rule "br-01aa55656fca" 8004 "192.168.112.2" 8004
add_filter_rule "br-01aa55656fca" 8004

# CodeForge (8009 -> 172.27.0.2)
echo "→ CodeForge (port 8009)"
add_network_rules "br-63147175c058"
add_nat_rule "br-63147175c058" 8009 "172.27.0.2" 8000
add_filter_rule "br-63147175c058" 8000

# WordForge (8002 -> 172.25.0.2)
echo "→ WordForge (port 8002)"
add_network_rules "br-38852d66c5eb"
add_nat_rule "br-38852d66c5eb" 8002 "172.25.0.2" 8002
add_filter_rule "br-38852d66c5eb" 8002

# GreatReads Prod (8007 -> 172.21.0.2)
echo "→ GreatReads Prod (port 8007)"
add_network_rules "br-67753b61ea19"
add_nat_rule "br-67753b61ea19" 8007 "172.21.0.2" 8006
add_filter_rule "br-67753b61ea19" 8006

# ArtForge (8003 -> 172.26.0.2)
echo "→ ArtForge (port 8003)"
add_network_rules "br-f6142088b2b0"
add_nat_rule "br-f6142088b2b0" 8003 "172.26.0.2" 8003
add_filter_rule "br-f6142088b2b0" 8003

# Kavita (5000 -> 192.168.48.2)
echo "→ Kavita (port 5000)"
add_network_rules "br-37584833251b"
add_nat_rule "br-37584833251b" 5000 "192.168.48.2" 5000
add_filter_rule "br-37584833251b" 5000

# Beets (8337 -> 192.168.96.2)
echo "→ Beets (port 8337)"
add_network_rules "br-291f837586fb"
add_nat_rule "br-291f837586fb" 8337 "192.168.96.2" 8337
add_filter_rule "br-291f837586fb" 8337

# Romm (8082 -> 192.168.80.3)
echo "→ Romm (port 8082)"
add_network_rules "br-1ce630bbb57a"
add_nat_rule "br-1ce630bbb57a" 8082 "192.168.80.3" 8080
add_filter_rule "br-1ce630bbb57a" 8080

# Audiobookshelf (13378 -> 192.168.64.2)
echo "→ Audiobookshelf (port 13378)"
add_network_rules "br-fad0b11692e0"
add_nat_rule "br-fad0b11692e0" 13378 "192.168.64.2" 80
add_filter_rule "br-fad0b11692e0" 80

# GreatReads Dev (8008 -> 172.24.0.2)
echo "→ GreatReads Dev (port 8008)"
add_network_rules "br-7f3b7e15b730"
add_nat_rule "br-7f3b7e15b730" 8008 "172.24.0.2" 8006
add_filter_rule "br-7f3b7e15b730" 8006

echo ""
echo "=========================================="
echo "✅ All iptables rules added successfully!"
echo "=========================================="
echo ""
echo "Verifying NAT rules..."
sudo iptables -t nat -L DOCKER -n | grep -E "2283|8096|8082|8004|8003|8002|8009|8007|8008|13378|2285|9117|8998" | head -20
echo ""
echo "Note: These rules are NOT persistent across reboots."
echo "See DOCKER_IPTABLES_PERSISTENCE.md for persistence options."

