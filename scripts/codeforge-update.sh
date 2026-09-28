#!/bin/bash
# Keep the CodeForge clone pulled and its release binary built (docker#6).
# The forge launcher only pulls+builds when launched; a pull made anywhere else
# left target/release/forge stale. Run by the codeforge-update DAG.
#
# Fails loudly (and touches nothing) if the clone is dirty or off main.
# Never resets, stashes, kills a running forge, or runs install.sh.

set -euo pipefail

REPO=/home/brandon/projects/CodeForge
BIN="$REPO/target/release/forge"
CARGO=/home/brandon/.cargo/bin/cargo   # not on the non-login PATH

# Same lock the launcher takes, so the two never build at once.
exec 9>"${XDG_RUNTIME_DIR:-/tmp}/codeforge-update.lock"
if ! flock -n 9; then
    echo "launcher holds the lock (building?) - skipping this turn"
    exit 0
fi

cd "$REPO"

branch=$(git rev-parse --abbrev-ref HEAD)
if [ "$branch" != "main" ]; then
    echo "ERROR: clone is on '$branch', not main - leaving it alone" >&2
    exit 1
fi
if [ -n "$(git status --porcelain --untracked-files=no)" ]; then
    echo "ERROR: clone has uncommitted changes - leaving it alone:" >&2
    git status --short --untracked-files=no >&2
    exit 1
fi

before=$(git rev-parse HEAD)
git pull --ff-only --quiet
after=$(git rev-parse HEAD)

if [ "$before" != "$after" ]; then
    echo "pulled $(git rev-list --count "$before..$after") commit(s): ${before:0:7} -> ${after:0:7}"
elif [ -x "$BIN" ]; then
    echo "up to date at ${after:0:7}, binary present - nothing to build"
    exit 0
else
    echo "up to date at ${after:0:7}, but $BIN is missing"
fi

echo "building..."
nice -n 10 ionice -c3 "$CARGO" build --release -q
echo "built $(stat -c '%y' "$BIN" | cut -d. -f1)"
