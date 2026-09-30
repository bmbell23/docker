#!/bin/bash
# Get dockerhost (VM 101) ready for a graceful shutdown, and record what "running"
# looks like so verify-boot.sh can prove it all came back (docker#23, thread 015).
#
# It STOPS NOTHING. Containers are left for dockerd to stop during the systemd
# shutdown: a container you `docker stop` yourself stays down after boot
# (unless-stopped), which is the trap this avoids.
#
#   scripts/maintenance/prep-shutdown.sh            snapshot + backups + checks
#   SKIP_BACKUPS=1 scripts/maintenance/prep-shutdown.sh
#
# Prints SAFE TO SHUT DOWN (exit 0) or the list of blockers (exit 1).
# Snapshot: ~/projects/docker/logs/shutdown-<ts>/  (logs/ is gitignored)

set -uo pipefail

REPO=/home/brandon/projects/docker
TS=$(date +%Y%m%d-%H%M%S)
SNAP_ROOT="${SNAP_ROOT:-$REPO/logs}"   # override for testing
SNAP="$SNAP_ROOT/shutdown-$TS"
mkdir -p "$SNAP"

blockers=()
warnings=()
say() { echo "[$(date +%H:%M:%S)] $*"; }

say "snapshot -> $SNAP"

# 1. Containers: name, restart policy, state, health, published host ports.
docker ps -q | xargs -r docker inspect --format \
    '{{.Name}}	{{.HostConfig.RestartPolicy.Name}}	{{.State.Status}}	{{if .State.Health}}{{.State.Health.Status}}{{else}}-{{end}}	{{range $p, $b := .NetworkSettings.Ports}}{{range $b}}{{.HostPort}}:{{$p}},{{end}}{{end}}' \
    | sed 's#^/##' | sort > "$SNAP/containers.tsv"
say "containers running: $(wc -l < "$SNAP/containers.tsv")"

# Running containers that won't restart on boot (no restart policy).
while IFS=$'\t' read -r name policy _ _ _; do
    case "$policy" in always|unless-stopped|on-failure) ;;
        *) warnings+=("$name has restart policy '${policy:-none}': it will NOT come back after boot") ;;
    esac
done < "$SNAP/containers.tsv"

# Unhealthy now = it won't be healthy after boot either; know that before, not after.
awk -F'\t' '$4=="unhealthy"{print $1}' "$SNAP/containers.tsv" | while read -r c; do
    echo "$c"; done > "$SNAP/unhealthy-before.txt"
[ -s "$SNAP/unhealthy-before.txt" ] && warnings+=("already unhealthy before shutdown: $(tr '\n' ' ' < "$SNAP/unhealthy-before.txt")")

# Published TCP ports that already don't answer: not the reboot's fault afterwards.
cut -f5 "$SNAP/containers.tsv" | tr ',' '\n' | grep -E '/tcp$' | cut -d: -f1 | sort -un | while read -r port; do
    timeout 3 bash -c "exec 3<>/dev/tcp/127.0.0.1/$port" 2>/dev/null || echo "$port"
done > "$SNAP/ports-dead-before.txt"
[ -s "$SNAP/ports-dead-before.txt" ] && warnings+=("published ports already not answering: $(tr '\n' ' ' < "$SNAP/ports-dead-before.txt")")

# 2. Mounts, enabled units, firewall.
findmnt -rn -o TARGET,SOURCE,FSTYPE | awk '$1 ~ /^\/mnt\// && $3 != "overlay"' > "$SNAP/mounts.txt"
systemctl list-unit-files --state=enabled --no-legend 2>/dev/null | awk '{print $1}' | sort > "$SNAP/units-system.txt"
systemctl --user list-unit-files --state=enabled --no-legend 2>/dev/null | awk '{print $1}' | sort > "$SNAP/units-user.txt"
if [ "${NO_SUDO:-0}" != 1 ] && sudo -n iptables-save > "$SNAP/iptables-save.txt" 2>/dev/null; then
    say "iptables saved"
else
    rm -f "$SNAP/iptables-save.txt"
    warnings+=("iptables not saved (needs passwordless sudo); stale-DNAT check after boot will be skipped")
fi

for u in agent-bus-router.service; do
    systemctl --user is-enabled "$u" >/dev/null 2>&1 \
        || blockers+=("user unit $u is not enabled: it will not start at boot")
done
grep -qx 'docker.service' "$SNAP/units-system.txt" || blockers+=("docker.service is not enabled")

# 3. Nothing heavy mid-flight.
busy=$(pgrep -af 'align-cron|worker-cron|bin/audiobook|backup-databases|backup-db\.sh|stash-identify' | grep -v pgrep || true)
[ -n "$busy" ] && blockers+=("jobs still running: $(echo "$busy" | awk '{print $2" "$3}' | tr '\n' ';')")
turns=$(pgrep -fc 'claude -p' || true)
[ "${turns:-0}" -gt 0 ] && warnings+=("$turns agent turn(s) in flight (includes this one if an agent ran me); check !status in Mattermost")

# 4. Fresh database backups (the same scripts server-backups runs nightly).
if [ "${SKIP_BACKUPS:-0}" != "1" ]; then
    say "running database backups..."
    if "$REPO/scripts/backup/backup-databases.sh" > "$SNAP/backup-databases.log" 2>&1; then
        say "  databases ok"
    else
        blockers+=("backup-databases.sh failed (see $SNAP/backup-databases.log)")
    fi
    if /home/brandon/projects/GreatReads/greatreads/scripts/backup-db.sh > "$SNAP/backup-greatreads.log" 2>&1; then
        say "  greatreads ok"
    else
        blockers+=("GreatReads backup failed (see $SNAP/backup-greatreads.log)")
    fi
fi
# Immich dumps itself nightly; just make sure the newest dump is recent.
newest=$(ls -t /mnt/boston/media/pictures/immich-storage/backups/immich-db-backup-*.sql.gz 2>/dev/null | head -n 1)
if [ -z "$newest" ] || [ -n "$(find "$newest" -mmin +1560)" ]; then
    warnings+=("newest Immich DB dump is missing or older than 26h: ${newest:-none}")
else
    say "immich dump ok: $(basename "$newest")"
fi

# 5. Verdict.
{
    printf 'blockers:\n'; printf '  %s\n' "${blockers[@]:-none}"
    printf 'warnings:\n'; printf '  %s\n' "${warnings[@]:-none}"
} > "$SNAP/verdict.txt"
ln -sfn "$SNAP" "$SNAP_ROOT/shutdown-latest"

echo
for w in "${warnings[@]}"; do echo "WARN: $w"; done
if [ "${#blockers[@]}" -gt 0 ]; then
    for b in "${blockers[@]}"; do echo "BLOCKED: $b"; done
    echo "NOT SAFE TO SHUT DOWN (snapshot kept: $SNAP)"
    exit 1
fi
echo "SAFE TO SHUT DOWN. Snapshot: $SNAP"
echo "After boot, run: $REPO/scripts/maintenance/verify-boot.sh"
