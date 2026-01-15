#!/bin/bash
# Script to set Navidrome password using the CLI

PASSWORD="$1"
USERNAME="${2:-brandon}"

if [ -z "$PASSWORD" ]; then
    echo "Usage: $0 <password> [username]"
    exit 1
fi

# Use printf to send password twice (for confirmation)
printf "%s\n%s\n" "$PASSWORD" "$PASSWORD" | docker run --rm -i \
    -v /home/brandon/navidrome/data:/data \
    -v /mnt/boston/media/music:/music \
    deluan/navidrome:latest \
    user edit --datafolder /data --musicfolder /music -u "$USERNAME" --set-password

