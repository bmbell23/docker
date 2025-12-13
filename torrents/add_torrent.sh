#!/bin/bash

# qBittorrent torrent management script
# Usage: ./add_torrent.sh <magnet_link_or_torrent_url>

if [ $# -eq 0 ]; then
    echo "Usage: $0 <magnet_link_or_torrent_url>"
    echo "Example: $0 'magnet:?xt=urn:btih:...'"
    echo "Example: $0 'https://example.com/file.torrent'"
    exit 1
fi

TORRENT_INPUT="$1"
CONTAINER_NAME="qbittorrent"

echo "Adding torrent: $TORRENT_INPUT"

# Check if input is a magnet link
if [[ "$TORRENT_INPUT" == magnet:* ]]; then
    echo "Detected magnet link"
    # For magnet links, we can try to add them via the API or create a .torrent file
    echo "$TORRENT_INPUT" > /tmp/magnet_link.txt
    docker cp /tmp/magnet_link.txt $CONTAINER_NAME:/tmp/
    docker exec $CONTAINER_NAME sh -c 'echo "Magnet link saved to /tmp/magnet_link.txt"'
    echo "Magnet link saved. You can manually add it via web UI or API."
    
elif [[ "$TORRENT_INPUT" == http* ]]; then
    echo "Detected torrent URL, downloading..."
    wget -O /tmp/downloaded.torrent "$TORRENT_INPUT"
    if [ $? -eq 0 ]; then
        docker cp /tmp/downloaded.torrent $CONTAINER_NAME:/watch/
        echo "Torrent file copied to watch folder. Download should start automatically."
        rm /tmp/downloaded.torrent
    else
        echo "Failed to download torrent file"
        exit 1
    fi
    
elif [ -f "$TORRENT_INPUT" ]; then
    echo "Detected local torrent file"
    docker cp "$TORRENT_INPUT" $CONTAINER_NAME:/watch/
    echo "Torrent file copied to watch folder. Download should start automatically."
    
else
    echo "Invalid input. Please provide a magnet link, torrent URL, or local .torrent file path."
    exit 1
fi

echo "Done!"
