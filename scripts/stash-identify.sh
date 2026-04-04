#!/bin/bash
# Stash nightly metadata pipeline:
#   1. Identify scenes via StashDB fingerprint matching
#   2. Enrich performers with photos/bio from StashDB
#   3. Auto-tag scenes by filename against performers/studios/tags in DB

STASH_URL="http://localhost:9999/graphql"
STASHDB_ENDPOINT="https://stashdb.org/graphql"
LOGFILE="/home/brandon/projects/docker/logs/stash-identify.log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOGFILE"
}

graphql() {
    curl -s -X POST "$STASH_URL" -H "Content-Type: application/json" -d "$1"
}

log "=== Stash nightly metadata pipeline ==="

# Step 0: Scan for new/moved files and folders (creates galleries from new subdirs)
log "Step 0: Scanning library for new files and folders..."
RESPONSE=$(graphql '{"query": "mutation { metadataScan(input: { scanGenerateCovers: true }) }"}')
JOB_ID=$(echo "$RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin)['data']['metadataScan'])" 2>/dev/null)
if [ -n "$JOB_ID" ]; then
    log "  Scan job started (job ID: $JOB_ID) — waiting 30s for it to complete..."
    sleep 30
else
    log "  ERROR: Failed to start scan job. Response: $RESPONSE"
fi

# Step 0b: Create/update Stash Groups from video subdirectories
log "Step 0b: Syncing video folder Groups..."
python3 /home/brandon/projects/docker/scripts/stash-groups.py 2>&1 | tee -a "$LOGFILE"

# Step 1: Identify scenes via StashDB
log "Step 1: Identifying scenes via StashDB..."
RESPONSE=$(graphql "{\"query\": \"mutation { metadataIdentify(input: { sources: [{ source: { stash_box_endpoint: \\\"$STASHDB_ENDPOINT\\\" } }], options: { setCoverImage: true, setOrganized: false } }) }\"}")
JOB_ID=$(echo "$RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin)['data']['metadataIdentify'])" 2>/dev/null)
if [ -n "$JOB_ID" ]; then
    log "  Identify job started (job ID: $JOB_ID)"
else
    log "  ERROR: Failed to start identify job. Response: $RESPONSE"
fi

# Step 2: Enrich performers with StashDB profiles (photos, bio, etc.)
log "Step 2: Enriching performers via StashDB..."
RESPONSE=$(graphql "{\"query\": \"mutation { stashBoxBatchPerformerTag(input: { stash_box_endpoint: \\\"$STASHDB_ENDPOINT\\\", refresh: false, createParent: false }) }\"}")
JOB_ID=$(echo "$RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin)['data']['stashBoxBatchPerformerTag'])" 2>/dev/null)
if [ -n "$JOB_ID" ]; then
    log "  Performer tag job started (job ID: $JOB_ID)"
else
    log "  ERROR: Failed to start performer tag job. Response: $RESPONSE"
fi

# Step 3: Auto-tag by filename against performers/studios/tags already in DB
log "Step 3: Auto-tagging by filename..."
RESPONSE=$(graphql '{"query": "mutation { metadataAutoTag(input: { performers: [\"*\"], studios: [\"*\"], tags: [\"*\"] }) }"}')
JOB_ID=$(echo "$RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin)['data']['metadataAutoTag'])" 2>/dev/null)
if [ -n "$JOB_ID" ]; then
    log "  Auto-tag job started (job ID: $JOB_ID)"
else
    log "  ERROR: Failed to start auto-tag job. Response: $RESPONSE"
fi

log "=== Pipeline complete ==="
