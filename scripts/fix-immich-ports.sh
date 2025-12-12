#!/bin/bash

# Emergency Immich Port Fix Script
# Use this when Immich won't start due to port conflicts

IMMICH_DIR="/home/brandon/projects/docker/immich-main"
PORT=2283

echo "🚨 Emergency Immich Port Fix Script"
echo "=================================="

# Check if port is in use
echo "Checking port $PORT..."
if ! ss -tulpn | grep -q ":$PORT"; then
    echo "✅ Port $PORT is available"
    echo "Try starting Immich: cd $IMMICH_DIR && docker compose up -d"
    exit 0
fi

echo "⚠️  Port $PORT is in use:"
ss -tulpn | grep ":$PORT"
echo ""

# Check for stale docker-proxy processes
STALE_PROXIES=$(ps aux | grep "docker-proxy.*$PORT" | grep -v grep)
if [ ! -z "$STALE_PROXIES" ]; then
    echo "🔍 Found stale docker-proxy processes:"
    echo "$STALE_PROXIES"
    echo ""
    
    # Get PIDs
    PIDS=$(echo "$STALE_PROXIES" | awk '{print $2}' | tr '\n' ' ')
    
    echo "💀 Killing stale processes (PIDs: $PIDS)..."
    echo "$PIDS" | xargs -r sudo kill -9
    
    if [ $? -eq 0 ]; then
        echo "✅ Killed stale processes"
    else
        echo "❌ Failed to kill processes (need sudo?)"
        exit 1
    fi
else
    echo "🔍 No stale docker-proxy processes found"
    echo "Port may be used by another service:"
    lsof -i :$PORT 2>/dev/null || echo "Could not determine what's using the port"
fi

# Wait a moment for cleanup
sleep 2

# Check if port is now free
echo ""
echo "Rechecking port $PORT..."
if ! ss -tulpn | grep -q ":$PORT"; then
    echo "✅ Port $PORT is now available!"
    echo ""
    echo "🚀 Starting Immich..."
    cd "$IMMICH_DIR"
    docker compose up -d
    
    echo ""
    echo "⏳ Waiting for services to start..."
    sleep 10
    
    # Test API
    if curl -s --max-time 10 http://localhost:$PORT/api/server/ping | grep -q "pong"; then
        echo "✅ Immich is running successfully on port $PORT!"
        echo "🌐 Access at: http://localhost:$PORT"
    else
        echo "⚠️  Immich started but API not responding yet"
        echo "Check status: docker compose ps"
    fi
else
    echo "❌ Port $PORT is still in use"
    echo "Manual investigation required:"
    echo "  ss -tulpn | grep :$PORT"
    echo "  lsof -i :$PORT"
    exit 1
fi
