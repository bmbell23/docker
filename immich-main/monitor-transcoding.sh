#!/bin/bash

# Monitor Immich video transcoding
echo "=== Immich Video Transcoding Monitor ==="
echo "Timestamp: $(date)"
echo ""

# Check if hardware acceleration is working
echo "Hardware Acceleration Status:"
docker exec immich_server ls -la /dev/dri/ 2>/dev/null && echo "✅ DRI devices available" || echo "❌ No DRI devices"
echo ""

# Check recent transcoding activity
echo "Recent Transcoding Activity (last 50 lines):"
docker logs immich_server --tail 50 2>&1 | grep -i -E "(transcode|ffmpeg|video)" | tail -10
echo ""

# Check for video-related errors
echo "Recent Video Errors:"
docker logs immich_server --tail 100 2>&1 | grep -i -E "(error.*video|error.*transcode|unable to send file.*\.mov|unable to send file.*\.mp4)" | tail -5
echo ""

# Check container resource usage
echo "Container Resource Usage:"
docker stats --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}" | grep immich
echo ""

# Check for aspect ratio issues in logs
echo "Aspect Ratio Related Messages:"
docker logs immich_server --tail 100 2>&1 | grep -i -E "(aspect|ratio|resolution|dimension)" | tail -3
echo ""

echo "=== Monitor Complete ==="
