# Shutting down and starting dockerhost (VM 101)

Replaces the old `docs/reboot/*` (removed: they said `sudo reboot` and
`docker-compose down`, both banned since the Jan 7 2026 incident). Source: docker#23,
agent-bus thread 015.

**Rules:** no `reboot`/`shutdown` inside the guest, no `docker stop` / `docker-compose down`
beforehand. A container you stop yourself stays down after boot (`unless-stopped`); let
dockerd stop them during the normal systemd shutdown. Brandon runs the host commands.

## 1. Before: `prep-shutdown` (inside dockerhost)
```bash
~/projects/docker/scripts/maintenance/prep-shutdown.sh
```
It **stops nothing**. It:
- saves a snapshot to `~/projects/docker/logs/shutdown-<ts>/` (and `logs/shutdown-latest`) with the
  running containers and their restart policy, health and published ports, the `/mnt` mounts, the
  enabled system and user units, and `iptables-save` when passwordless sudo works,
- records what's *already* broken (unhealthy containers, published ports that don't answer), so the
  reboot isn't blamed for them afterwards,
- runs the database backups (`backup-databases.sh`, GreatReads `backup-db.sh`) and checks that
  Immich's own nightly dump is under 26 h old,
- blocks if a heavy job is running (MediaForge workers, backups, Stash), if
  `agent-bus-router` or `docker.service` isn't enabled, or if a backup failed,
- warns about agent turns in flight (check `!status` in Mattermost) and containers with no restart policy
  (previews, which correctly don't come back).

Go on only if it prints **SAFE TO SHUT DOWN**. `SKIP_BACKUPS=1` skips the dumps.

## 2. The shutdown and start (on proxmox, from Paul in thread 015)
```bash
qm shutdown 101 --timeout 300        # graceful, via the guest agent; waits up to 5 min
qm status 101                        # must say: stopped
qm start 101
qm status 101                        # running
qm agent 101 ping && echo agent-ok
```
If `qm shutdown` times out, **don't** use `--forceStop` or `qm stop`. That's pulling the plug.
Tell Paul, and find what's holding it first (usually a container ignoring SIGTERM).
Pending on this cycle anyway: `discard=on,ssd=1` on both VM disks (harmless).

## 3. After: `verify-boot` (inside dockerhost)
```bash
~/projects/docker/scripts/maintenance/verify-boot.sh          # compares against logs/shutdown-latest
WAIT=600 ~/projects/docker/scripts/maintenance/verify-boot.sh  # slower starters
```
In order:
1. **Storage first:** every `/mnt` mount from the snapshot is mounted and not empty. If not, it
   **stops**, because containers that bind-mount `/mnt/boston` (18 of them) may be running on the empty
   local folder. Fix the mount, then restart those containers (the `kill` + `docker-compose up -d`
   method in CLAUDE.md).
2. Every container with a restart policy is running, and healthy where it has a healthcheck. It retries
   for `WAIT` seconds (default 300).
3. Every published TCP port answers on `localhost`.
4. No DNAT rule points at an IP no container has. This is the "works on 127.0.0.1, times out on Tailscale"
   failure. Needs passwordless sudo, otherwise it's skipped with the manual command printed.
5. `agent-bus-router` is active and Mattermost `:8015` answers.
6. Every system unit that was enabled is still enabled.

One line per problem. It prints **CLEAN BOOT** and exits 0 only if everything matches.

## Known gap: docker doesn't wait for /mnt/boston (proposal, needs Brandon's OK: it's /etc)
fstab mounts `//10.0.0.159/boston` as cifs with no `_netdev`, and nothing orders docker after it.
If the share is late at boot, 18 containers start on an empty directory. Proposed fix:
```ini
# /etc/systemd/system/docker.service.d/wait-for-mounts.conf
[Unit]
RequiresMountsFor=/mnt/boston /mnt/docker
```
Also add `_netdev` to the boston fstab line, then `sudo systemctl daemon-reload`. With
`RequiresMountsFor`, if boston can't mount, **docker doesn't start at all**. That's loud (every app
down, verify-boot fails at step 1) instead of quiet and wrong (apps up on empty folders, downloads
filling the root disk). That's the trade we want.
