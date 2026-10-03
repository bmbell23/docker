#!/bin/bash
# Stash nightly metadata pipeline:
#   0. Scan for new files, then Clean out entries whose files are gone (guarded, backed up first)
#   1. Identify scenes via StashDB fingerprint matching
#   2. Enrich performers with photos/bio from StashDB
#   3. Auto-tag scenes by filename against performers/studios/tags in DB

STASH_URL="http://localhost:9999/graphql"
STASHDB_ENDPOINT="https://stashdb.org/graphql"
LOGFILE="/home/brandon/projects/docker/logs/stash-identify.log"
MOUNT="/mnt/boston"
LIBRARY="/mnt/boston/media/other"   # Stash's /data (stash/docker-compose.yml)

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOGFILE"
}

graphql() {
    curl -s -X POST "$STASH_URL" -H "Content-Type: application/json" -d "$1"
}

log "=== Stash nightly metadata pipeline ==="
FAILED=0   # any failed step makes the run exit 1, so Dagu shows red (docker#25)

# Stash answers HTTP 200 even when it can't touch its DB (e.g. NEEDS_MIGRATION after an
# image upgrade), so check its own status before trusting anything else.
STATUS=$(graphql '{"query": "{ systemStatus { status } }"}' | python3 -c "import sys,json; print(json.load(sys.stdin)['data']['systemStatus']['status'])" 2>/dev/null)
if [ "$STATUS" != "OK" ]; then
    log "ERROR: Stash systemStatus is '${STATUS:-unreachable}', not OK (NEEDS_MIGRATION = open the UI and migrate). Stopping."
    exit 1
fi

# Step 0: Scan for new/moved files and folders (creates galleries from new subdirs)
log "Step 0: Scanning library for new files and folders..."
RESPONSE=$(graphql '{"query": "mutation { metadataScan(input: { scanGenerateCovers: true }) }"}')
JOB_ID=$(echo "$RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin)['data']['metadataScan'])" 2>/dev/null)
if [ -n "$JOB_ID" ]; then
    log "  Scan job started (job ID: $JOB_ID) — waiting 30s for it to complete..."
    sleep 30
else
    log "  ERROR: Failed to start scan job. Response: $RESPONSE"; FAILED=1
fi

# Step 0a: Clean entries whose files are gone (docker#108; scan only adds). Stash runs jobs in
# order, so this follows the scan above. Guarded: an unmounted or half-mounted share looks
# exactly like "everything was deleted", and Clean would empty the library.
log "Step 0a: Cleaning entries for deleted files..."
TRACKED=$(graphql '{"query": "{ findScenes(filter:{per_page:-1}) { scenes { files { path } } } findImages(filter:{per_page:-1}) { images { files { path } } } }"}' |
    python3 -c "
import sys, json, os
d = json.load(sys.stdin)['data']
paths = [f['path'] for k, v in (('scenes', d['findScenes']), ('images', d['findImages'])) for i in v[k] for f in i['files']]
print(len(paths), sum(os.path.exists(p.replace('/data/', '$LIBRARY/', 1)) for p in paths))" 2>/dev/null)
read -r N_TRACKED N_PRESENT <<<"$TRACKED"
if ! mountpoint -q "$MOUNT"; then
    log "  ERROR: $MOUNT isn't mounted; not cleaning"; FAILED=1
elif [ -z "$N_TRACKED" ]; then
    log "  ERROR: couldn't list Stash's files; not cleaning"; FAILED=1
elif [ "$N_TRACKED" -gt 0 ] && [ $((N_PRESENT * 2)) -lt "$N_TRACKED" ]; then
    log "  ERROR: only $N_PRESENT of $N_TRACKED tracked files exist under $LIBRARY; not cleaning. Check the share, then Clean by hand (backup first)"; FAILED=1
elif [ "$N_PRESENT" = "$N_TRACKED" ]; then
    log "  all $N_TRACKED tracked files exist; nothing to clean"
else
    graphql '{"query": "mutation { backupDatabase(input: { download: false }) }"}' | grep -q '"errors"' \
        && { log "  ERROR: database backup failed; not cleaning"; FAILED=1; }
    if [ "$FAILED" -eq 0 ]; then
        RESPONSE=$(graphql '{"query": "mutation { metadataClean(input: { dryRun: false }) }"}')
        JOB_ID=$(echo "$RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin)['data']['metadataClean'])" 2>/dev/null)
        if [ -n "$JOB_ID" ]; then
            log "  $((N_TRACKED - N_PRESENT)) of $N_TRACKED tracked files are gone; backed up, Clean job started (job ID: $JOB_ID)"
        else
            log "  ERROR: Failed to start clean job. Response: $RESPONSE"; FAILED=1
        fi
    fi
fi

# Step 0b: Create/update Stash Groups from video subdirectories
log "Step 0b: Syncing video folder Groups..."
python3 /home/brandon/projects/docker/scripts/stash-groups.py 2>&1 | tee -a "$LOGFILE"
if [ "${PIPESTATUS[0]}" -ne 0 ]; then log "  ERROR: stash-groups.py failed"; FAILED=1; fi

# Step 1: Identify scenes via StashDB
log "Step 1: Identifying scenes via StashDB..."
RESPONSE=$(graphql "{\"query\": \"mutation { metadataIdentify(input: { sources: [{ source: { stash_box_endpoint: \\\"$STASHDB_ENDPOINT\\\" } }], options: { setCoverImage: true, setOrganized: false } }) }\"}")
JOB_ID=$(echo "$RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin)['data']['metadataIdentify'])" 2>/dev/null)
if [ -n "$JOB_ID" ]; then
    log "  Identify job started (job ID: $JOB_ID)"
else
    log "  ERROR: Failed to start identify job. Response: $RESPONSE"; FAILED=1
fi

# Step 2: Enrich performers with StashDB profiles (photos, bio, etc.)
log "Step 2: Enriching performers via StashDB..."
RESPONSE=$(graphql "{\"query\": \"mutation { stashBoxBatchPerformerTag(input: { stash_box_endpoint: \\\"$STASHDB_ENDPOINT\\\", refresh: false, createParent: false }) }\"}")
JOB_ID=$(echo "$RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin)['data']['stashBoxBatchPerformerTag'])" 2>/dev/null)
if [ -n "$JOB_ID" ]; then
    log "  Performer tag job started (job ID: $JOB_ID)"
else
    log "  ERROR: Failed to start performer tag job. Response: $RESPONSE"; FAILED=1
fi

# Step 3: Auto-tag by filename against performers/studios/tags already in DB
log "Step 3: Auto-tagging by filename..."
RESPONSE=$(graphql '{"query": "mutation { metadataAutoTag(input: { performers: [\"*\"], studios: [\"*\"], tags: [\"*\"] }) }"}')
JOB_ID=$(echo "$RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin)['data']['metadataAutoTag'])" 2>/dev/null)
if [ -n "$JOB_ID" ]; then
    log "  Auto-tag job started (job ID: $JOB_ID)"
else
    log "  ERROR: Failed to start auto-tag job. Response: $RESPONSE"; FAILED=1
fi

if [ "$FAILED" -ne 0 ]; then
    log "=== Pipeline finished WITH ERRORS ==="
    exit 1
fi
log "=== Pipeline complete ==="
