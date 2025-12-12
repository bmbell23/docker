#!/bin/bash

# Immich Status Check Script

IMMICH_DIR="/home/brandon/projects/docker/immich-main"
PORT=2283

echo "🔍 Immich Status Check"
echo "====================="

# Check port availability
echo "📡 Port $PORT Status:"
if ss -tulpn | grep -q ":$PORT"; then
    echo "  ✅ Port $PORT is in use"
    ss -tulpn | grep ":$PORT" | sed 's/^/    /'
else
    echo "  ❌ Port $PORT is available (Immich not running?)"
fi
echo ""

# Check Docker containers
echo "🐳 Docker Containers:"
cd "$IMMICH_DIR"
if docker compose ps --format table 2>/dev/null | grep -q "immich"; then
    docker compose ps --format table | sed 's/^/  /'
else
    echo "  ❌ No Immich containers found"
fi
echo ""

# Check API health
echo "🌐 API Health:"
if curl -s --max-time 5 http://localhost:$PORT/api/server/ping 2>/dev/null | grep -q "pong"; then
    echo "  ✅ API is responding"
else
    echo "  ❌ API is not responding"
fi
echo ""

# Check for stale processes
echo "👻 Stale Process Check:"
STALE=$(ps aux | grep "docker-proxy.*$PORT" | grep -v grep)
if [ ! -z "$STALE" ]; then
    echo "  ⚠️  Found docker-proxy processes:"
    echo "$STALE" | sed 's/^/    /'
else
    echo "  ✅ No stale docker-proxy processes"
fi
echo ""

# Check recent logs
echo "📋 Recent Activity:"
LOG_FILE="/home/brandon/projects/docker/logs/docker-cleanup.log"
if [ -f "$LOG_FILE" ]; then
    echo "  Last cleanup run:"
    tail -n 3 "$LOG_FILE" | sed 's/^/    /'
else
    echo "  ❌ No cleanup log found"
fi
echo ""

# Check cron jobs
echo "⏰ Scheduled Jobs:"
if crontab -l 2>/dev/null | grep -q "docker-cleanup"; then
    echo "  ✅ Cleanup cron jobs are installed:"
    crontab -l | grep "docker-cleanup" | sed 's/^/    /'
else
    echo "  ❌ No cleanup cron jobs found"
fi
echo ""

# Quick actions
echo "🚀 Quick Actions:"
echo "  Start Immich:    cd $IMMICH_DIR && docker compose up -d"
echo "  Stop Immich:     cd $IMMICH_DIR && docker compose down"
echo "  Fix ports:       ./scripts/fix-immich-ports.sh"
echo "  Manual cleanup:  ./scripts/docker-cleanup.sh"
echo "  View logs:       tail -f logs/docker-cleanup.log"
