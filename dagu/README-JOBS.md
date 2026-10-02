# What is scheduled here, and what it replaced

Every DAG runs its real work on the **host** over SSH (`ssh dockerhost '…'`),
because the jobs need the docker CLI, python venvs, ffmpeg and `systemd-run` —
none of which exist in this container. The key is restricted to the docker
bridge in `authorized_keys` and is gitignored; this repo is public.

| DAG | schedule | replaces | notes |
|---|---|---|---|
| `mediaforge-audiobook-watch` | `*/2` | cron | CIFS has no inotify, so it polls |
| `mediaforge-chapter-worker` | `*/10` | cron | self-skips on lock / low RAM / high load |
| `mediaforge-align-worker` | `*/20` | cron | 7–90 min of CPU per book |
| `mediaforge-publish-maps` | `04:17` | **nothing — this was never scheduled** | verify, then publish maps for GreatReads |
| `mediaforge-lyrics` | `03:40` | **nothing — one-shot by hand** | new music got no lyrics |
| `server-backups` | `02:00` | three separate crons all at 02:00 | now sequential, not competing |
| `server-docker-cleanup` | `06:00` | two crons | weekly prune is image-only, never `--volumes` |
| `codeforge-notes-sync` | `* * * * *` | cron | ran every minute, invisibly |
| `stash-identify` | `03:00` | cron | |
| `abs-library-scan` | `05:00` | — | pure HTTP, the canary that needs no host access |
| `proxmox-backup-rsync` | `01:00` | Proxmox cron `backup-script.sh` | runs on **Proxmox**; `scripts/proxmox/boston-copy.sh` streamed over ssh; Tier 1 → `/mnt/allston/boston-copy` (sdc1 died) |
| `proxmox-external-sync` | `04:00` | Proxmox cron `backup-external.sh` (disabled) | runs on **Proxmox**; `scripts/proxmox/external-copy.sh`; documents + pictures → `/mnt/external` |
| `proxmox-dotfiles-pull` | `05:00` | — | keeps the Proxmox dotfiles clone current for Brandon's shell; no job depends on it |
| `deploy-reconciler` | `*/2` | `ship-pr`'s versioning when Brandon merges in the GitHub UI; every manual `docker compose up` after a merge | repos in `dagu/deploy-repos.yaml`: version, fast-forward, tidy merged worktrees, run `./deploy`. State in `logs/deploy/state.json`. docker#45. Step 2 `scripts/preview-cleanup.sh`: removes `<project>_pr<N>` previews of merged/closed PRs, then dangling images + build cache >24 h (docker#49). Step 3 `scripts/open-prs.sh`: every open PR across bmbell23 → `logs/deploy/open_prs.json` for the Dashboard (docker#80) |
| `proxmox-config-backup` | `02:00` | Proxmox cron `proxmox-config-backup.sh` | runs on **Proxmox**; `/etc/pve` etc. → boston |
| `container-updates` | Sun `05:30` | nothing: `:latest` only moved on a random recreate | stacks in `dagu/update-stacks.yaml`: pull newer images, backup hook, recreate, health check, revert on failure; never restores a DB by itself. `--check <stack>` runs just the health check. docker#37 |
| `wordforge-backup` | `02:35` | — | WordForge `bin/backup`: SQLite `.backup` → `/mnt/boston/documents/wordforge-backups`, keeps 30 (docker#55) |
| `vaultwarden-backup` | `00:15` | nothing (the script existed, nothing ran it) | `scripts/backup/vaultwarden-backup.sh`: `vaultwarden backup` + rsa_key.pem → `/mnt/boston/documents/vaultwarden-backups`, keeps 30 (docker#40) |
| `secrets-backup` | `00:45` | — | agent-bus `bin/secrets-backup`: gpg-encrypted tar of untracked secrets → `/mnt/boston/documents/agentbus-backups/secrets` (docker#84, agent-bus#145) |
| `mattermost-backup` | `00:30` | — | agent-bus `bin/mm-backup`: Mattermost pg_dump + attachments → `/mnt/boston/documents/agentbus-backups` (docker#76, agent-bus#144) |

## Alerts
Every DAG carries a `handler_on` that runs `scripts/dagu-alert.sh` on the host. It
posts to #dagu as @rabbot (via agent-bus `bin/say`) on every run, pass or fail, with the
run's last output lines (docker#57). `@brandon` is pinged only when a job **turns** red.
Pollers (`audiobook-watch`, `chapter-worker`, `align-worker`, `codeforge-notes-sync`,
`deploy-reconciler`) pass `idle`: their successes post only when the run printed
something, so "nothing new" ticks stay quiet. A new DAG copies the handler block; add
`idle` if it runs more often than hourly. State lives in `~/.local/state/dagu-alerts/`.

## Backup DAGs
A DAG that makes a backup copy carries `tags: [backup]`, and the same PR names it in
`docs/backup-inventory.yaml` (a copy's `dag:`, a `restore_test` or a drive). The
Dashboard's job list picks up every DAG file on its own; its Backup Overview reads the
inventory, so an unlisted backup is invisible there. `scripts/check-backup-inventory.sh`
fails on drift either way (docker#78).

## Still in crontab, deliberately
`immich/watchdog.sh` (every 5 min) is **known broken** — it cannot write
`/var/log/immich-watchdog.log`. Moving a broken job into a scheduler that will
show it failing every five minutes is noise; fix or delete it first.

## Migration rule
A DAG is added here **before** its crontab line is removed, and the crontab line
comes out only after the DAG has run green at least once. Two schedulers running
the same job briefly is harmless — the jobs take locks. A job in neither is not.

## Triggering by hand
`docker exec -u 1000 dagu dagu start <name>`. A plain `docker exec` runs as root
and creates log directories the scheduler cannot write.
| `deemix-arl-check` | `09:00` | — | `scripts/deemix-arl-check.sh`: validates deemix's Deezer ARL against Deezer; red (pings @brandon) when it expires, log has the renewal one-liner (docker#42) |
