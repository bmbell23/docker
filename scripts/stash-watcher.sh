#!/bin/bash
# Stash file watcher — monitors media dirs for new images/videos and triggers a Stash scan.
# Debounces rapid bursts (e.g. a gallery-dl batch) into a single scan after DEBOUNCE_SECS.

STASH_URL="http://localhost:9999/graphql"
LOGFILE="/home/brandon/projects/docker/logs/stash-watcher.log"
DEBOUNCE_SECS=10

# Directories to watch (must exist)
WATCH_DIRS=(
    "/mnt/boston/media/other/Videos/Full"
    "/mnt/boston/media/other/Videos/Short"
    "/mnt/boston/media/other/Pictures"
)

# Image and video extensions to react to
EXTENSIONS="jpg|jpeg|png|gif|webp|bmp|tiff|tif|mp4|mkv|avi|mov|wmv|m4v|webm|flv"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOGFILE"
}

stash_scan() {
    local path="$1"
    log "Triggering Stash scan for: $path"
    curl -s -X POST "$STASH_URL" \
        -H "Content-Type: application/json" \
        -d "{\"query\": \"mutation { metadataScan(input: { paths: [\\\"$path\\\"], scanGenerateCovers: true }) }\"}" \
        > /dev/null
    # If it's a video dir, run groups sync after a short delay
    if [[ "$path" == /data/Videos/* ]]; then
        sleep 15
        python3 /home/brandon/projects/docker/scripts/stash-groups.py >> "$LOGFILE" 2>&1 &
    fi
}

log "=== Stash file watcher started ==="
log "Watching: ${WATCH_DIRS[*]}"

# Pending scan tracker: path -> scheduled time (epoch seconds)
declare -A PENDING

while true; do
    # Read one inotify event (1-second timeout so we can flush debounced scans)
    EVENT=$(inotifywait -r -q --timeout 1 \
        --event close_write,moved_to,create \
        --format "%w%f" \
        "${WATCH_DIRS[@]}" 2>/dev/null)

    if [ -n "$EVENT" ]; then
        # Check extension
        EXT="${EVENT##*.}"
        EXT_LOWER=$(echo "$EXT" | tr '[:upper:]' '[:lower:]')
        if echo "$EXT_LOWER" | grep -qE "^($EXTENSIONS)$"; then
            # Determine which watch root this event belongs to
            for DIR in "${WATCH_DIRS[@]}"; do
                if [[ "$EVENT" == "$DIR"* ]]; then
                    STASH_PATH="${DIR/\/mnt\/boston\/media\/other\//\/data\/}"
                    PENDING["$STASH_PATH"]=$(( $(date +%s) + DEBOUNCE_SECS ))
                    log "Queued scan for $STASH_PATH (debounce ${DEBOUNCE_SECS}s) — triggered by: $EVENT"
                    break
                fi
            done
        fi
    fi

    # Flush any debounced scans whose timer has expired
    NOW=$(date +%s)
    for SPATH in "${!PENDING[@]}"; do
        if [ "$NOW" -ge "${PENDING[$SPATH]}" ]; then
            stash_scan "$SPATH"
            unset PENDING["$SPATH"]
        fi
    done
done
