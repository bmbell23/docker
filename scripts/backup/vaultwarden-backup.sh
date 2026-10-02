#!/bin/bash
# Vaultwarden nightly backup (docker#40). Run by dagu/dags/vaultwarden-backup.yaml, and as
# the pre-update hook in dagu/update-stacks.yaml.
#
# The data dir is root-owned and the image has no sqlite3, so everything goes through the
# container: `vaultwarden backup` (its own online-safe SQLite copy), `cat` it out, then
# rm the copy. Plus rsa_key.pem (without it every login token breaks after a restore),
# and attachments/, sends/, config.json when they exist. icon_cache is skipped.
# The DB copy must pass integrity_check. The archive is gzip-tested, mode 600, written to
# /mnt/boston/documents/vaultwarden-backups (the documents rsync and pve01 restic carry it).
# Skips nights with no change and keeps the newest 30.
# Exit 0 = backed up or unchanged; anything else = failed (alerted).
set -euo pipefail
umask 077

C="${VW_CONTAINER:-vaultwarden}"
DEST="${VW_BACKUP_DEST:-/mnt/boston/documents/vaultwarden-backups}"
KEEP=30
TS=$(date +%Y%m%d-%H%M%S)
log() { echo "[$(date +'%F %T')] $*"; }

mountpoint -q /mnt/boston || { log "ERROR: /mnt/boston is not mounted"; exit 1; }
mkdir -p "$DEST"
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT

out=$(docker exec "$C" /vaultwarden backup 2>&1) || { log "ERROR: vaultwarden backup failed: $out"; exit 1; }
f=$(grep -oE 'db_[0-9_]+\.sqlite3' <<<"$out" | head -1)
[ -n "$f" ] || { log "ERROR: can't find the backup file in: $out"; exit 1; }
docker exec "$C" cat "/data/$f" > "$work/db.sqlite3"
docker exec "$C" rm -f "/data/$f"
[ "$(sqlite3 "$work/db.sqlite3" 'PRAGMA integrity_check;')" = ok ] || { log "ERROR: integrity_check failed on $f"; exit 1; }
users=$(sqlite3 "$work/db.sqlite3" 'SELECT count(*) FROM users;')
ciphers=$(sqlite3 "$work/db.sqlite3" 'SELECT count(*) FROM ciphers;')
[ "$ciphers" -gt 0 ] || { log "ERROR: backup has 0 vault items; refusing to call that a backup"; exit 1; }

extras=$(docker exec "$C" sh -c 'cd /data && for x in rsa_key.pem rsa_key.pub.pem config.json attachments sends; do [ -e "$x" ] && echo "$x"; done; true')
grep -qx rsa_key.pem <<<"$extras" || { log "ERROR: /data/rsa_key.pem missing"; exit 1; }
# shellcheck disable=SC2086
docker exec "$C" tar -C /data -cf - $extras | tar -C "$work" -xf -

# Unchanged? Hash the DB's content (not its file: the copy differs byte-wise every time) + the extras.
sig=$( { sqlite3 "$work/db.sqlite3" .dump; (cd "$work" && find . -type f ! -name db.sqlite3 -print0 | sort -z | xargs -0 -r sha256sum); } | sha256sum | cut -d' ' -f1)
if [ "$(cat "$DEST/.last.sha256" 2>/dev/null)" = "$sig" ] && ls "$DEST"/vaultwarden-*.tar.gz >/dev/null 2>&1; then
    log "vaultwarden-backup: unchanged since the last backup, skipped ($users user(s), $ciphers item(s))"
    exit 0
fi

arch="$DEST/vaultwarden-$TS.tar.gz"
tar -C "$work" -czf "$arch.part" .
gzip -t "$arch.part"
tar -tzf "$arch.part" | grep -qx './db.sqlite3' || { log "ERROR: db.sqlite3 missing from the archive"; rm -f "$arch.part"; exit 1; }
mv "$arch.part" "$arch"
echo "$sig" > "$DEST/.last.sha256"
ls -1t "$DEST"/vaultwarden-*.tar.gz | tail -n +$((KEEP + 1)) | xargs -r rm -f
log "vaultwarden-backup: $arch ($(du -h "$arch" | cut -f1); $users user(s), $ciphers item(s); kept $(ls "$DEST"/vaultwarden-*.tar.gz | wc -l))"
