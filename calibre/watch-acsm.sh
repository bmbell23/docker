#!/bin/bash
# =============================================================================
# ACSM Watcher — Auto-imports new .acsm ebook files into Calibre
# =============================================================================
# Monitors /mnt/boston/media/downloads/books/ for new .acsm files.
# For each new file:
#   1. Adds it to the Calibre library (deACSM + DeDRM runs automatically)
#   2. Runs Count Pages (saves page count to #pages, word count to #word_count)
#
# Run as a service: see calibre-acsm-watcher.service
# =============================================================================

WATCH_DIR="/mnt/boston/media/downloads/books"
PROCESSED_FILE="/home/brandon/projects/docker/calibre/processed_acsm.txt"
LOG_FILE="/home/brandon/projects/docker/calibre/acsm-watcher.log"
POLL_INTERVAL=30   # seconds between scans
CALIBRE_COMPOSE_DIR="/home/brandon/projects/docker/calibre"
CALIBRE_IMAGE="lscr.io/linuxserver/calibre:latest"

# calibredb_gui: runs calibredb in a one-shot headless container while the
# GUI container is briefly stopped. This avoids SQLite lock contention with
# the running Calibre desktop process.
calibredb_gui() {
    local args_quoted=""
    local arg
    for arg in "$@"; do
        args_quoted+=" $(printf '%q' "$arg")"
    done

    local rc=0
    (
        set -e
        cd "$CALIBRE_COMPOSE_DIR"
        docker compose stop calibre >/dev/null
        docker run --rm --entrypoint /bin/bash -u 1000:1000 \
            -v /home/brandon/projects/docker/calibre/config:/config \
            -v /mnt/boston/media/downloads/books:/incoming \
            -v /mnt/boston/media/books_calibre_docker:/nas-books \
            "$CALIBRE_IMAGE" \
            -lc "calibredb --with-library /config/library${args_quoted}"
    )
    rc=$?
    (cd "$CALIBRE_COMPOSE_DIR" && docker compose up -d calibre >/dev/null)
    return $rc
}

mkdir -p "$(dirname "$PROCESSED_FILE")"
touch "$PROCESSED_FILE"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

get_book_formats_json() {
    local book_id="$1"
    calibredb_gui list --for-machine --search "id:${book_id}" --fields formats 2>>"$LOG_FILE" | tr -d '\n'
}

is_raw_acsm_import() {
    local formats_json="$1"

    if echo "$formats_json" | grep -qi '\.acsm"' && ! echo "$formats_json" | grep -qiE '\.(epub|pdf)"'; then
        return 0
    fi

    return 1
}

ensure_pages_column() {
    # Create #pages custom column if it doesn't exist
    if ! calibredb_gui custom_columns 2>/dev/null | grep -q "^pages "; then
        log "Creating #pages custom column..."
        calibredb_gui add_custom_column pages "Page Count" int >> "$LOG_FILE" 2>&1
    fi
}

refresh_calibre() {
    # Send Ctrl+R to the Calibre main window.
    # calibredb add writes directly to the DB (bypassing the GUI), so the content
    # server doesn't see new books until the GUI re-scans its library. Ctrl+R
    # triggers that re-scan, after which the content server serves the new book.
    local wid
    wid=$(docker exec -u abc -e DISPLAY=:1 calibre xdotool search --class "calibre" 2>/dev/null | head -1)
    if [ -n "$wid" ]; then
        docker exec -u abc -e DISPLAY=:1 calibre xdotool key --window "$wid" ctrl+r >> "$LOG_FILE" 2>&1
        log "Sent Ctrl+R to Calibre (library + content server refreshed)"
    else
        log "WARNING: Could not find Calibre window — content server may not show new book until next refresh"
    fi
}

process_acsm() {
    local acsm_file="$1"
    local filename
    filename=$(basename "$acsm_file")

    log "New ACSM detected: $filename"
    log "Adding to Calibre library (fulfilling via deACSM + decrypting via DeDRM)..."

    # Add via GUI-connected calibredb so the GUI sees the new book immediately
    local result
    result=$(calibredb_gui add "/incoming/$filename" 2>&1)
    log "$result"

    # Extract the new book ID from "Added book ids: XXXX"
    local book_id
    book_id=$(echo "$result" | grep -oP 'Added book ids: \K[0-9]+')

    if [ -z "$book_id" ]; then
        if echo "$result" | grep -q "already exist in the database"; then
            log "Book already exists in library — marking as processed."
            echo "$filename" >> "$PROCESSED_FILE"
            return 0
        fi
        log "ERROR: Could not extract book ID — import may have failed. Will retry next cycle."
        return 1
    fi

    local formats_json
    formats_json=$(get_book_formats_json "$book_id")

    if is_raw_acsm_import "$formats_json"; then
        log "WARNING: Book $book_id imported only as raw ACSM; DeACSM fulfillment did not complete."
        calibredb_gui remove --permanent "$book_id" >> "$LOG_FILE" 2>&1 || true

        if echo "$result" | grep -q "E_ADEPT_REQUEST_EXPIRED"; then
            log "ACSM appears expired; removed raw import and marking as processed."
            echo "$filename" >> "$PROCESSED_FILE"
            return 0
        fi

        log "Removed raw ACSM import; leaving file unprocessed for retry next cycle."
        return 1
    fi

    log "Book added with ID: $book_id"
    log "Running Count Pages on book $book_id..."

    # Compute page/word counts — prints BOOK_PAGES=N and BOOK_WORDS=N to stdout
    local counts
    counts=$(docker exec -u abc -e DISPLAY=:1 calibre calibre-debug -e /config/count_pages_cli.py "$book_id" 2>>"$LOG_FILE")
    local rc=$?

    if [ $rc -ne 0 ]; then
        log "WARNING: Count Pages script exited with code $rc (book was still imported)"
    else
        local pages words
        pages=$(echo "$counts" | grep "^BOOK_PAGES=" | cut -d= -f2)
        words=$(echo "$counts"  | grep "^BOOK_WORDS=" | cut -d= -f2)

        if [ -n "$pages" ]; then
            calibredb_gui set_custom pages "$book_id" "$pages" >> "$LOG_FILE" 2>&1
            log "Saved page count: $pages"
        fi
        if [ -n "$words" ]; then
            calibredb_gui set_custom word_count "$book_id" "$words" >> "$LOG_FILE" 2>&1
            log "Saved word count: $words"
        fi
    fi

    log "Fetching metadata (series, publication date) for book $book_id..."
    local meta_out
    meta_out=$(docker exec -u abc -e DISPLAY=:1 calibre calibre-debug -e /config/fetch_metadata.py "$book_id" 2>>"$LOG_FILE")
    local meta_rc=$?

    if [ $meta_rc -ne 0 ]; then
        log "WARNING: fetch_metadata.py exited with code $meta_rc"
    else
        local meta_series meta_idx meta_date meta_skip meta_err
        meta_series=$(echo "$meta_out" | grep "^METADATA_SERIES="    | head -1 | cut -d= -f2-)
        meta_idx=$(   echo "$meta_out" | grep "^METADATA_SERIES_INDEX=" | head -1 | cut -d= -f2-)
        meta_date=$(  echo "$meta_out" | grep "^METADATA_PUBDATE="   | head -1 | cut -d= -f2-)
        meta_skip=$(  echo "$meta_out" | grep "^METADATA_SKIPPED="   | head -1 | cut -d= -f2-)
        meta_err=$(   echo "$meta_out" | grep "^METADATA_ERROR="     | head -1 | cut -d= -f2-)

        if [ -n "$meta_skip" ]; then
            log "Metadata: $meta_skip"
        elif [ -n "$meta_err" ]; then
            log "Metadata fetch: $meta_err"
        else
            # Apply series via calibredb (GUI-connected so the UI updates immediately)
            if [ -n "$meta_series" ]; then
                calibredb_gui set_metadata "$book_id" --field "series:$meta_series" >> "$LOG_FILE" 2>&1
                log "Saved series: $meta_series"
            fi
            if [ -n "$meta_idx" ]; then
                calibredb_gui set_metadata "$book_id" --field "series_index:$meta_idx" >> "$LOG_FILE" 2>&1
                log "Saved series index: $meta_idx"
            fi
            if [ -n "$meta_date" ]; then
                calibredb_gui set_metadata "$book_id" --field "pubdate:$meta_date" >> "$LOG_FILE" 2>&1
                log "Saved publication date: $meta_date"
            fi
        fi
    fi

    # Refresh Calibre so the content server immediately serves the new book
    refresh_calibre

    # Mark as processed regardless of count pages result — book is in library
    echo "$filename" >> "$PROCESSED_FILE"
    log "Finished processing: $filename (book ID: $book_id)"
    return 0
}

# ---- Main loop ---------------------------------------------------------------

log "=========================================="
log "ACSM Watcher started"
log "Watching: $WATCH_DIR"
log "Poll interval: ${POLL_INTERVAL}s"
log "=========================================="

# Ensure the #pages custom column exists before we start
ensure_pages_column

while true; do
    shopt -s nullglob
    for acsm_file in "$WATCH_DIR"/*.acsm; do
        filename=$(basename "$acsm_file")

        # Skip if already processed
        if grep -qF "$filename" "$PROCESSED_FILE"; then
            continue
        fi

        process_acsm "$acsm_file"
    done
    shopt -u nullglob

    sleep "$POLL_INTERVAL"
done
