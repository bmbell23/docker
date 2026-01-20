#!/bin/bash
#
# fix-docker-iptables.sh
#
# This script fixes missing iptables rules for Docker networks that prevent
# inter-container communication. This issue occurs after Docker daemon restarts
# when Docker fails to properly recreate iptables rules for certain networks.
#
# PROBLEM:
# After Docker daemon restarts, some Docker bridge networks are missing from
# the DOCKER-ISOLATION-STAGE-1 and DOCKER-FORWARD chains in iptables. This
# prevents containers on those networks from communicating with each other.
#
# SYMPTOMS:
# - Containers show as "healthy" but cannot connect to other containers on the same network
# - Connection timeouts when trying to reach Redis, Postgres, or other services
# - Logs show "connect ETIMEDOUT" errors
#
# SOLUTION:
# This script adds the missing iptables rules for affected Docker networks.
#
# USAGE:
#   sudo ./scripts/fix-docker-iptables.sh
#
# To run automatically on boot, install the systemd service:
#   sudo cp scripts/fix-docker-iptables.service /etc/systemd/system/
#   sudo systemctl enable fix-docker-iptables.service
#

set -e

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== Docker iptables Fix Script ===${NC}"
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}ERROR: This script must be run as root (use sudo)${NC}"
    exit 1
fi

# Function to get bridge name from network name
get_bridge_name() {
    local network_name=$1
    local network_id=$(docker network ls --filter "name=${network_name}" --format "{{.ID}}" 2>/dev/null || true)

    if [ -z "$network_id" ]; then
        echo ""
        return 1
    fi

    echo "br-${network_id:0:12}"
    return 0
}

# Function to add isolation and forward rules for a network
fix_network_rules() {
    local network_name=$1
    local bridge_name=$(get_bridge_name "$network_name")

    if [ -z "$bridge_name" ]; then
        echo -e "${YELLOW}  ⚠ Network '${network_name}' not found, skipping${NC}"
        return
    fi

    # Check if bridge exists
    if ! ip link show "$bridge_name" &>/dev/null; then
        echo -e "${YELLOW}  ⚠ Bridge interface '${bridge_name}' not found, skipping${NC}"
        return
    fi

    echo -e "Processing network: ${GREEN}${network_name}${NC} (${bridge_name})"

    # Check and add DOCKER-ISOLATION-STAGE-1 rule
    if ! iptables -C DOCKER-ISOLATION-STAGE-1 -i "$bridge_name" ! -o "$bridge_name" -j DOCKER-ISOLATION-STAGE-2 2>/dev/null; then
        echo -e "  ${YELLOW}Adding DOCKER-ISOLATION-STAGE-1 rule...${NC}"
        iptables -I DOCKER-ISOLATION-STAGE-1 1 -i "$bridge_name" ! -o "$bridge_name" -j DOCKER-ISOLATION-STAGE-2
        echo -e "  ${GREEN}✓ Added DOCKER-ISOLATION-STAGE-1 rule${NC}"
    else
        echo -e "  ${GREEN}✓ DOCKER-ISOLATION-STAGE-1 rule already exists${NC}"
    fi

    # Check and add DOCKER-FORWARD rules
    if ! iptables -C DOCKER-FORWARD -i "$bridge_name" -o "$bridge_name" -j ACCEPT 2>/dev/null; then
        echo -e "  ${YELLOW}Adding DOCKER-FORWARD rules...${NC}"
        iptables -I DOCKER-FORWARD 1 -i "$bridge_name" -o "$bridge_name" -j ACCEPT
        iptables -I DOCKER-FORWARD 2 -o "$bridge_name" -j ACCEPT
        iptables -I DOCKER-FORWARD 3 -i "$bridge_name" -j ACCEPT
        echo -e "  ${GREEN}✓ Added DOCKER-FORWARD rules${NC}"
    else
        echo -e "  ${GREEN}✓ DOCKER-FORWARD rules already exist${NC}"
    fi

    # Check and add DOCKER chain rule for inter-container communication
    if ! iptables -C DOCKER -i "$bridge_name" -o "$bridge_name" -j ACCEPT 2>/dev/null; then
        echo -e "  ${YELLOW}Adding DOCKER inter-container rule...${NC}"
        iptables -I DOCKER 1 -i "$bridge_name" -o "$bridge_name" -j ACCEPT
        echo -e "  ${GREEN}✓ Added DOCKER inter-container rule${NC}"
    else
        echo -e "  ${GREEN}✓ DOCKER inter-container rule already exists${NC}"
    fi

    echo ""
}

# Fix networks that commonly have issues
echo -e "${YELLOW}Fixing Docker network iptables rules...${NC}"
echo ""

# Immich network
fix_network_rules "immich_default"

# Outline network
fix_network_rules "outline_outline_network"

# Jellyfin network (if it exists)
fix_network_rules "jellyfin_default"

echo -e "${GREEN}=== Done! ===${NC}"
echo ""
echo -e "${YELLOW}NOTE: These iptables rules are NOT persistent across reboots.${NC}"
echo -e "${YELLOW}To make them persistent, install the systemd service:${NC}"
echo -e "  sudo cp scripts/fix-docker-iptables.service /etc/systemd/system/"
echo -e "  sudo systemctl enable fix-docker-iptables.service"
echo ""

