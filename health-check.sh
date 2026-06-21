#!/bin/bash

# VPN Torrent Stack Health Check
# Verifies all components are working correctly

echo "========================================="
echo "  VPN Torrent Stack Health Check"
echo "========================================="
echo ""

# Check if containers are running
echo "📦 Container Status:"
echo "-------------------------------------------"
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Image}}" | grep -E "mullvad|qbit|jackett|flare|NAMES" | head -n 5
echo ""

# Check VPN connection
echo "🔐 VPN Connection:"
echo "-------------------------------------------"
VPN_STATUS=$(docker exec mullvad-vpn wg show wg0 2>&1)

if [ $? -eq 0 ]; then
    echo "✅ WireGuard tunnel is UP"
    echo "$VPN_STATUS" | grep -E "latest handshake|transfer" | sed 's/^/  /'
    
    # Check if handshake is recent
    HANDSHAKE=$(echo "$VPN_STATUS" | grep "latest handshake" | awk '{print $3, $4}')
    if [[ "$HANDSHAKE" == *"second"* ]] || [[ "$HANDSHAKE" == *"minute"* ]]; then
        echo "  ✅ Handshake is recent: $HANDSHAKE ago"
    else
        echo "  ⚠️  Handshake might be stale: $HANDSHAKE ago"
    fi
    
    # Check if data is being transferred
    RECEIVED=$(echo "$VPN_STATUS" | grep "transfer:" | awk '{print $2, $3}')
    if [[ "$RECEIVED" != "0 B" ]]; then
        echo "  ✅ Data received: $RECEIVED"
    else
        echo "  ❌ No data received - VPN endpoint may be dead!"
    fi
else
    echo "❌ WireGuard tunnel is DOWN"
fi
echo ""

# Check external IP (force IPv4 for consistency)
echo "🌍 External IP (should be Mullvad):"
echo "-------------------------------------------"
VPN_IP=$(docker exec mullvad-vpn curl -4 -s --max-time 5 https://ifconfig.me 2>&1)
if [ $? -eq 0 ]; then
    echo "  VPN IP: $VPN_IP"
    echo "  ✅ VPN is routing traffic"
else
    echo "  ❌ Cannot reach internet through VPN"
fi
echo ""

# Check DNS
echo "🔍 DNS Resolution:"
echo "-------------------------------------------"
DNS_TEST=$(docker exec mullvad-vpn nslookup google.com 2>&1)
if echo "$DNS_TEST" | grep -q "Address:"; then
    echo "  ✅ DNS is working"
    echo "$DNS_TEST" | grep "Server:" | sed 's/^/  /'
else
    echo "  ❌ DNS resolution failed"
    echo "$DNS_TEST" | head -n 3 | sed 's/^/  /'
fi
echo ""

# Check Jackett uses VPN (force IPv4)
echo "🔎 Jackett VPN Status:"
echo "-------------------------------------------"
JACKETT_IP=$(docker exec jackett curl -4 -s --max-time 5 https://ifconfig.me 2>&1)
if [ $? -eq 0 ]; then
    if [ "$JACKETT_IP" == "$VPN_IP" ]; then
        echo "  ✅ Jackett is using VPN"
        echo "  IP: $JACKETT_IP"
    else
        echo "  ⚠️  Jackett IP ($JACKETT_IP) doesn't match VPN IP ($VPN_IP)"
    fi
else
    echo "  ❌ Jackett cannot reach internet"
fi
echo ""

# Check qBittorrent uses VPN (force IPv4)
echo "📥 qBittorrent VPN Status:"
echo "-------------------------------------------"
QBIT_IP=$(docker exec qbittorrent curl -4 -s --max-time 5 https://ifconfig.me 2>&1)
if [ $? -eq 0 ]; then
    if [ "$QBIT_IP" == "$VPN_IP" ]; then
        echo "  ✅ qBittorrent is using VPN"
        echo "  IP: $QBIT_IP"
    else
        echo "  ⚠️  qBittorrent IP ($QBIT_IP) doesn't match VPN IP ($VPN_IP)"
    fi
else
    echo "  ❌ qBittorrent cannot reach internet"
fi
echo ""

# Check web interfaces
echo "🌐 Web Interface Accessibility:"
echo "-------------------------------------------"

# Jackett
if curl -s -I http://127.0.0.1:9117 --max-time 3 | grep -q "HTTP"; then
    echo "  ✅ Jackett: http://127.0.0.1:9117"
else
    echo "  ❌ Jackett is not accessible"
fi

# qBittorrent
if curl -s -I http://127.0.0.1:2285 --max-time 3 | grep -q "HTTP"; then
    echo "  ✅ qBittorrent: http://127.0.0.1:2285"
else
    echo "  ❌ qBittorrent is not accessible"
fi
echo ""

# Summary
echo "========================================="
echo "  Summary"
echo "========================================="

# Count issues
ISSUES=0

# Check each component
docker ps | grep -q "mullvad-vpn" || ((ISSUES++))
docker ps | grep -q "qbittorrent" || ((ISSUES++))
docker ps | grep -q "jackett" || ((ISSUES++))
docker ps | grep -q "flaresolverr" || ((ISSUES++))

if [ $ISSUES -eq 0 ] && [ "$JACKETT_IP" == "$VPN_IP" ] && [ "$QBIT_IP" == "$VPN_IP" ]; then
    echo "✅ All systems operational!"
else
    echo "⚠️  Found $ISSUES issue(s)"
    echo ""
    echo "Troubleshooting tips:"
    echo "  1. Check VPN-TORRENT-SETUP.md for detailed troubleshooting"
    echo "  2. Run: docker logs mullvad-vpn --tail 50"
    echo "  3. Run: docker exec mullvad-vpn wg show"
fi

echo "========================================="
