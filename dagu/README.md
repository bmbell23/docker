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
