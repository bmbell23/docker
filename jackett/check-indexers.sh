#!/bin/bash

echo "=== Jackett Indexer Status Check ==="
echo

echo "1. Checking if fixed indexer definition exists..."
if docker-compose exec -T jackett test -f /config/cardigann/definitions/thepiratebay-fixed.yml; then
    echo "✅ Fixed indexer definition exists"
else
    echo "❌ Fixed indexer definition missing"
    exit 1
fi

echo
echo "2. Checking Jackett logs for recent errors..."
echo "Recent Pirate Bay errors:"
docker-compose logs --tail=50 | grep -E "(thepiratebay|pirate)" | tail -3

echo
echo "3. Current indexer count:"
docker-compose logs --tail=20 | grep "Loaded.*indexers in total" | tail -1

echo
echo "=== DIAGNOSIS ==="
echo
if docker-compose logs --tail=10 | grep -q "Exception (thepiratebay)"; then
    echo "❌ PROBLEM: You're still using the BROKEN 'The Pirate Bay' indexer"
    echo "   Error shows: Exception (thepiratebay)"
    echo
    echo "🔧 SOLUTION:"
    echo "   1. Go to: http://100.123.154.40:9117"
    echo "   2. DELETE 'The Pirate Bay' indexer"
    echo "   3. ADD 'The Pirate Bay (Fixed)' indexer"
    echo
elif docker-compose logs --tail=10 | grep -q "Exception (thepiratebay-fixed)"; then
    echo "⚠️  You're using the fixed indexer but it still has issues"
    echo "   Try TorrentGalaxy instead - it's more reliable"
else
    echo "✅ No recent Pirate Bay errors detected"
    echo "   Either you fixed it or you're not using it"
fi

echo
echo "=== RECOMMENDED ACTION ==="
echo "🎯 Best solution: Use TorrentGalaxy instead of The Pirate Bay"
echo "   - More reliable"
echo "   - Better maintained"
echo "   - No parsing issues"
echo
echo "To add TorrentGalaxy:"
echo "1. Go to Jackett web UI"
echo "2. Click 'Add indexer'"
echo "3. Search for 'TorrentGalaxy'"
echo "4. Add it and test"
