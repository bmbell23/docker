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
