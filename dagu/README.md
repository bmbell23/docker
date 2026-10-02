# Dagu — the server's job scheduler (port 8014)

Replaces the crontab (and the retired Jenkins) as the place scheduled work is
defined, run, and *looked at*. Web UI: http://100.69.184.113:8014

## Why Dagu
A single Go binary with a web UI that shows schedules, run history, duration,
exit status and the captured stdout/stderr of every run. Jenkins was using
839 MB of RAM to run one job zero times in thirty days; cron ran jobs fine but
showed nothing — `audiobook watch` crashed three times in four days and nothing
said a word (MediaForge #16).

## Where things live
| what | where | in git? |
|---|---|---|
| job definitions (`*.yaml`) | `./dags/` | **yes**, here |
| the scripts jobs run | the project repos (`~/projects/<App>/bin/...`) | yes, in that app's repo |
| run history + captured logs | `./data/` | no (gitignored) |

Job definitions are infrastructure, so they live with this compose file. The
scripts they call belong to the app that owns them and stay in that app's repo.
Nothing is defined only in a web UI — the UI reads these files.

## Adding a job
Drop a YAML file in `dags/`. Dagu picks it up without a restart.

```yaml
name: thing-i-want-to-see
schedule: "*/10 * * * *"
steps:
  - name: run it
    command: /home/brandon/projects/Whatever/bin/thing
```

## Memory caps still work
MediaForge's workers wrap themselves in
`systemd-run --user --scope -p MemoryMax=2G`, which is why they must run on the
host rather than inside this container — hence the `/home/brandon/projects`
mount and plain `command:` steps.

## Gotchas found while setting this up (2026-09-25)

- **Trigger runs as the dagu user**: `docker exec -u 1000 dagu dagu start <name>`.
  A plain `docker exec` bypasses the entrypoint and runs as **root**, which
  creates root-owned log directories that the scheduler (uid 1000) then cannot
  write to — the DAG silently fails on its next scheduled run.
- **Do not set `user:` in the compose file.** The image's entrypoint remaps its
  own `dagu` user from `PUID`/`PGID` and needs to start as root to do it.
- **The image is `ghcr.io/dagucloud/dagu`**, not `dagu-org` (that path 403s).
- This host has no `/etc/timezone` file; `DAGU_TZ` handles the clock.
- Measured footprint after setup: **51 MB** of a 512 MB limit. Jenkins was using
  839 MB to run one job zero times in thirty days.

## Running host jobs (not yet wired — see the open ticket)

Most of the server's scheduled work is **host** scripts: they need the docker
CLI, the host's python venvs, ffmpeg, and `systemd-run` for memory caps. None of
that exists in this container, so the jobs cannot simply be `command:` steps.

The intended answer is an SSH key the container uses to run commands on the host
(`ssh` is already in the image, sshd is running, and the key would be restricted
to the docker bridge with `from="172.16.0.0/12"`). Until that key exists, only
jobs that are pure HTTP or pure container work can live here.

## Recreating or updating Dagu (docker#68)

Never `docker compose up -d --force-recreate dagu` by hand while jobs run: it kills them.
`scripts/dagu-drain.sh` does it like Jenkins' "Prepare for Shutdown": pull the image,
pause the scheduler (Dagu's global pause; manual Start still works), wait until no run is
in flight, tag the old image `updates-rollback/dagu:dagu`, recreate, check `/api/v1/health`
and a green `deploy-reconciler` run, resume. A new image that fails is rolled back; if
anything fails, Dagu is left **paused** and @brandon is pinged in #dagu. Missed ticks
are listed, never replayed (no DAG here has catch-up). Log: `logs/dagu-drain/`.

- **Config change merged** (`docker-compose.yml`, `config.yaml`, `ssh_include`): the repo's
  `./deploy`, run by the reconciler, compares them with `logs/deploy/dagu-applied.sha256`
  and starts `--recreate` (which also takes a newer image). `ssh/config` and `dags/` are
  live and need nothing.
- **Weekly**: `container-updates` (Sun 05:30) launches `--update` first: recreate only if
  the image is newer.
- **By hand**, always detached (it outlives this shell and any Dagu step):
  `systemd-run --user --unit=dagu-drain --collect ~/projects/docker/scripts/dagu-drain.sh --recreate`
  then `journalctl --user -fu dagu-drain`. `--dry-run`, `--no-pull`, `--max-wait 6h`.

The reconciler counts the deploy done once the drain is *launched*; the drain reports its own
result in #dagu. A run that died without cleaning up its `data/proc/*.proc` file holds the
drain until `--max-wait`, then it gives up and resumes.

One-time setup: `cp dagu/.drain.env.example dagu/.drain.env && chmod 600 dagu/.drain.env`
and put an **admin** API token from the Dagu UI in it (or an admin login). The pause
endpoint is admin-only; agents never read this file.
