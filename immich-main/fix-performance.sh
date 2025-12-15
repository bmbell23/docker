#!/bin/bash

# Immich Performance Fix Script
# This script addresses database connection timeouts and slow photo loading

echo "🔧 Fixing Immich Performance Issues..."

# Check if running as root for swap creation
if [[ $EUID -eq 0 ]]; then
    echo "⚠️  Creating swap space to improve memory management..."
    
    # Check if swap already exists
    if ! swapon --show | grep -q "/swapfile"; then
        # Create 2GB swap file
        fallocate -l 2G /swapfile
        chmod 600 /swapfile
        mkswap /swapfile
        swapon /swapfile
        
        # Make swap permanent
        if ! grep -q "/swapfile" /etc/fstab; then
            echo "/swapfile none swap sw 0 0" >> /etc/fstab
        fi
        
        echo "✅ Created 2GB swap space"
    else
        echo "✅ Swap space already exists"
    fi
else
    echo "⚠️  Run with sudo to create swap space for better performance"
fi

echo "🔄 Restarting Immich with performance optimizations..."

# Navigate to Immich directory
cd /home/brandon/projects/docker/immich-main

# Stop Immich services
echo "🛑 Stopping Immich services..."
docker compose down

# Clean up any orphaned containers
docker container prune -f

# Start services with new configuration
echo "🚀 Starting Immich with optimized settings..."
docker compose up -d

# Wait for services to start
echo "⏳ Waiting for services to initialize..."
sleep 30

# Check service health
echo "🏥 Checking service health..."
docker compose ps

echo ""
echo "📊 Current resource usage:"
docker stats --no-stream immich_server immich_machine_learning immich_postgres immich_redis

echo ""
echo "✅ Performance fixes applied!"
echo ""
echo "🔍 Next steps:"
echo "1. Wait 2-3 minutes for all services to fully initialize"
echo "2. Check Immich Admin UI → Settings → Job Settings"
echo "3. Ensure job concurrency is set to low values (1-2 for most jobs)"
echo "4. Monitor performance with: docker stats"
echo ""
echo "If issues persist, check logs with:"
echo "  docker logs immich_server"
echo "  docker logs immich_postgres"
