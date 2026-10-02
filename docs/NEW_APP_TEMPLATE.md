# New App Template — How Apps Are Built & Deployed on This Server

This is the canonical template for creating a new self-hosted app on dockerhost.
It was synthesized (2026-07-20) from the working patterns in LifeForge, GreatReads,
PokeVault, MealForge, the `docker/` infra repo, and the Dashboard.

Related authority files (read these too, don't duplicate them):
- `/home/brandon/projects/.augment-guidelines` — shared safety rules + authoritative container/port inventory
- `/home/brandon/projects/CLAUDE.md` — agent behavior kernel (auto-loaded by Claude Code for every project)
- `docs/setup/QUICK_REFERENCE.md` — port allocation list for third-party services
- `docs/docker/DOCKER_IPTABLES_PERSISTENCE.md` — port/IP/bridge table + persistence
- `/home/brandon/projects/Dashboard/TAILSCALE_ACCESS_PLAN.md` — future single-443 ingress blueprint

---

## 1. The server in one page

| Fact | Value |
|---|---|
| Host | `dockerhost` (Docker VM on Proxmox; Proxmox SSH `10.0.0.159`) |
| Tailscale IP (canonical access) | `100.69.184.113` |
| MagicDNS | `dockerhost.tailb8b575.ts.net` (tailnet `tailb8b575.ts.net`) |
| LAN IP | `10.0.0.160` (older docs say `192.168.0.158` — stale) |
| Firewall | ufw **inactive**; Docker's own iptables rules are the firewall |
| Reverse proxy | **None.** Every app publishes a host port; users hit `http://100.69.184.113:<port>` over Tailscale. TLS/443 exists only for Vaultwarden via `tailscale serve`. Single-443 path routing is a future plan (`TAILSCALE_ACCESS_PLAN.md`). |
| Bulk media | `/mnt/boston/...` (7.3 TB HDD) |
| Third-party service config | `/home/brandon/<service>/config` (outside the repo, gitignored) |
| Custom-app data | `./data/` inside the app repo, bind-mounted (gitignored) |

**Access model:** phones/tablets/laptops are on the Tailscale tailnet and open
`http://100.69.184.113:<port>` directly. Android "apps" are native WebView wrappers
around those URLs (§7). No public internet exposure except the Cloudflare-tunneled
fileshare (`share.bbell23.xyz`).

## 2. Port allocation

Custom apps live in a sequential block starting at **8002**. Taken (live as of 2026-10-02, from `docker ps`). CodeForge is internal (host network, 8000):

```
8001 Dashboard (host network)   8002 WordForge      8003 ArtForge
8004 LifeForge                  8005 MuseForge Studio (Tailscale IP only)
8006 FunForge                   8007 GreatReads old prod (retired)
8008 PokeVault                  8009 MealForge      8010 NerdNews/booknews
8011 Chess                      8012/8013 WebForge  8014 Dagu
8015 Mattermost (agent-bus)     8016 Grafana
8090/8091/8092 GreatReads web/retired-backend/ereader
5007/5008 Libby prod/test       8098 Dictionary
```

Third-party stacks use upstream defaults: 2283 Immich, 8096 Jellyfin, 13378 ABS,
8083/8084 Calibre, 8085 Trilium, 8222 Vaultwarden, 8880 Jenkins, 2285 qBittorrent,
9117 Jackett, 8998 yt-dlp, 9999 Stash, 8080 RomM, 6595 Deemix.

**Next free app port: 8017.** Don't trust this line blindly: check
`ss -ltn | grep :<port>` before you claim one. **15000–19999 is reserved for PR
previews** (prod port + 10000, §11): never claim an app port there. When you claim one:
1. add it to the inventory table in `/home/brandon/projects/.augment-guidelines`,
2. prefer host port == container port (`8017:8017`) — exceptions cause confusion.

## 3. House stack (the default; deviate only with a reason)

- **Backend:** Python 3.11 · FastAPI · Uvicorn · SQLAlchemy 2.x · SQLite · **Alembic** migrations (LifeForge pattern; do NOT copy GreatReads' hand-rolled `_ensure_columns()` ALTER TABLE approach)
- **Frontend:** Jinja2 server-rendered templates + vanilla JS. Libraries (Bootstrap, Chart.js, etc.) are **vendored into `static/vendor/`** — no CDNs, no npm build. HTMX is fine too (PokeVault).
- **Auth:** JWT-in-cookie, `passlib[bcrypt]` + `python-jose`, `ACCESS_TOKEN_EXPIRE_MINUTES=43200` (30 days). Single-user apps can skip auth if only reachable over Tailscale.
- **Background jobs:** APScheduler inside the FastAPI `lifespan()`, gated by `ENABLE_SCHEDULERS=true` env (GreatReads pattern) — so dev instances don't double-run jobs.
- **API base URL:** same-origin only. JS calls relative `/api/...` paths. Never hardcode `100.69.184.113:<port>` in frontend files (GreatReads' `web/` did; it's their weakest pattern).
- **Versioning:** `version.txt` at repo root; commits via the `gvc` shell function (dotfiles `20-functions.sh`) which bumps patch, commits `vX.Y.Z: msg`, tags, pushes.

## 4. Repo skeleton (LifeForge-style)

```
<App>/
├── src/<app_pkg>/
│   ├── main.py            # FastAPI app + page routes + lifespan/scheduler
│   ├── config.py          # pydantic-settings, env_file=".env"
│   ├── database.py        # engine, SessionLocal, get_db()
│   ├── models/            # SQLAlchemy models
│   ├── routes/            # APIRouter modules, included with prefix="/api/v1"
│   ├── services/          # domain logic, external API clients
│   ├── templates/         # Jinja2
│   └── static/            # css/js + static/vendor/ + manifest.json (PWA optional)
├── alembic/  alembic.ini
├── scripts/
│   ├── container_startup.py   # alembic upgrade head → uvicorn (Docker CMD)
│   └── rebuild-<app>.sh       # one-command deploy wrapper
├── android/               # WebView APK project (§7), + build-apk.sh at root
├── data/                  # SQLite DB, uploads, <app>.apk, version.json (gitignored)
├── Dockerfile  docker-compose.yml  .dockerignore
├── .env.example           # committed; real .env is gitignored — NEVER commit secrets
├── pyproject.toml  version.txt  README.md  CLAUDE.md  <App>.code-workspace
```

## 5. Dockerfile + compose pattern

Dockerfile: `FROM python:3.11-slim` → system deps (`curl`, `tzdata`) →
`pip install -e .` → non-root user (uid 1000) → `EXPOSE <port>` →
`HEALTHCHECK` curl `http://localhost:<port>/health` → `CMD ["python", "scripts/container_startup.py"]`.

```yaml
name: <app>
services:
  <app>:
    build: .
    container_name: <app>_app          # stable name — Dashboard & scripts key off it
    restart: unless-stopped
    ports:
      - "<port>:<port>"
    env_file: .env                     # secrets; .env.example committed
    environment:
      - HOST=0.0.0.0
      - PORT=<port>
      - TZ=America/Denver
      - DATABASE_URL=sqlite:////app/data/<app>.db
      - ENABLE_SCHEDULERS=true
    volumes:
      - ./data:/app/data
      - ./logs:/app/logs
      # dev convenience: - ./src:/app/src  (remember: no --reload; restart to pick up .py changes)
    extra_hosts:
      - "host.docker.internal:host-gateway"   # only if you call other host services
    networks: [<app>_network]
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:<port>/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 40s
    logging:
      driver: json-file
      options: { max-size: "2m", max-file: "10" }
    deploy:
      resources:
        limits: { cpus: "1.0", memory: 512M }
        reservations: { cpus: "0.25", memory: 128M }
networks:
  <app>_network:
    driver: bridge
```

Networking rules:
- One private bridge network per app; no shared external network exists.
- If you ever pin a subnet, use `172.x.0.0/16` — **never** `192.168.x` (LAN collision; see `docs/docker/DOCKER_NETWORKING_FIX.md`).
- To reach other apps, go through their **published host port** via `host.docker.internal` (e.g. GreatReads → Calibre at `http://host.docker.internal:8083`).

## 6. Deploy, restart, and the two famous gotchas

Deploy / redeploy:
```bash
cd /home/brandon/projects/<App> && docker compose up -d --build
```
Wrap this in `scripts/rebuild-<app>.sh` (GreatReads pattern: also passes
`BUILD_STAMP`/`BUILD_DIRTY` build-args so the UI can show "last built").

**Gotcha 1 — restart:** `docker restart` / `docker-compose restart` fail with
"permission denied" on this server. The sanctioned method:
```bash
PID=$(docker inspect <container_name> --format '{{.State.Pid}}')
kill $PID
cd /home/brandon/projects/<App> && docker-compose up -d
```

**Gotcha 2 — stale iptables DNAT:** after a recreate, the app may work on
`127.0.0.1:<port>` but time out on `100.69.184.113:<port>` (a DNAT rule still
points at the old container IP). Diagnose and fix:
```bash
sudo iptables-save | grep "DNAT.*<port>"     # find rule pointing at dead IP
sudo scripts/maintenance/clean-stale-dnat.sh --dry-run   # list every stale one
sudo scripts/maintenance/clean-stale-dnat.sh             # delete them
```
Docker writes your app's rules itself; **don't hardcode container IPs anywhere**.
The old `fix-all-docker-iptables.sh` did, and re-added 18 dead rules at every boot
(docker#34). `docker-post-boot.service` runs `clean-stale-dnat.sh` at boot.

**Testing note:** from the server itself, curl the address users open:
`http://100.69.184.113:<port>` answers from the server now (2026-10-02: :8002, :2283,
:8015 and :8001 in under 2 ms). The old "always times out, exit 28" no longer holds.
`localhost` isn't always enough: an app bound to the Tailscale address only (MuseForge
Studio, 8005) doesn't answer on it, and `127.0.0.1:2283` (Immich) times out while the
LAN and Tailscale addresses return 200.

Backups: cron a SQLite online backup (GreatReads `greatreads/scripts/backup-db.sh`
pattern: `.backup` + `integrity_check`, keep 14, `30 2 * * *`).

## 7. Android app (the WebView pattern — no Capacitor, no Play Store)

Both LifeForge and GreatReads ship a **hand-written native Java WebView wrapper**:

- Gradle project (`android/`): AGP 8.1, compileSdk 34, minSdk 24, Java 17.
- One `MainActivity extends Activity`: WebView + JS + DOM storage enabled,
  `loadUrl("http://100.69.184.113:<port>/")`.
- Manifest: `INTERNET` permission, `android:usesCleartextTraffic="true"` (plain HTTP over Tailscale).
- `versionCode` derived automatically (git `rev-list --count HEAD`, or computed from `version.txt`).
- Debug keystore (`~/.android/debug.keystore`) shared across builds so new APKs install as upgrades.

**Self-update loop (LifeForge pattern — copy this):**
1. `./build-apk.sh` → `gradlew assembleDebug` → copies APK + `version.json` into `data/` (which the container serves at `/download/<file>`).
2. On launch, `MainActivity` fetches `/download/version.json`, compares `versionCode`, downloads the APK and installs it via `PackageInstaller` (`REQUEST_INSTALL_PACKAGES` permission).
3. First install: open `http://100.69.184.113:<port>/download/<app>.apk` in the phone browser.

Optional GreatReads extras when needed: bundle web assets into the APK for offline
(`shouldInterceptRequest`), `window.Android` JS bridge (`@JavascriptInterface`),
foreground media service for background audio.

Also ship `static/manifest.json` (PWA, `display: standalone`) — free install path for iOS devices on the tailnet.

## 8. Dashboard registration (two places, both required)

Daisy owns the Dashboard (`/home/brandon/projects/Dashboard`, Flask, host network,
port 8001). The new service's agent doesn't edit it: she sends Daisy the entry below
(@daisy, with the exact JSON) and Daisy lands it on her branch.

1. **Service entry** in `Dashboard/static/services.json` (`services` list; the page
   renders from it, its `_comment` documents every key):
   ```json
   {"key": "<app>", "name": "<App>", "icon": "fas fa-<icon>",
    "description": "<one line>", "url": "http://100.69.184.113:<port>",
    "url_label": ":<port>", "category": "Projects", "owner": "<agent>",
    "repo": "bmbell23/<App>", "controls": "container",
    "preview_names": ["<other preview project label>"]}
   ```
   - `repo` is **required** for previews: the preview sweeper (§11) looks the PR up
     in this repo. No `repo`, no automatic teardown.
   - `preview_names` only if your previews' `dashboard.preview.project` label isn't
     the `key` (MuseForge Studio: key `museforge-studio`, previews labelled `museforge`).
   - `controls: "container"` gives the row Restart/Recreate; it needs step 2.
2. **Container map** in `Dashboard/app.py` `CONTAINERS`, same key:
   ```python
   '<app>': {'name': '<container_name>', 'service': '<compose service>',
             'compose_dir': '/home/brandon/projects/<App>'},
   ```
   (Relative `compose_dir` resolves under `projects/docker/`; use absolute for apps in
   their own repo. Optional `compose_file` key overrides the default.)

Daisy's merge redeploys the Dashboard; nothing to do on your side.

## 9. Work tracking: GitHub repo + Project board (required for every app)

Every app gets, from day one:
1. **A GitHub repo** `bmbell23/<App>`, with `version.txt` (`0.1.0`) at the root.
2. **A GitHub Project (user-level) board** with Status columns, in order:
   **Scoping → Ready to Implement → In progress → In Review → Done**
   (rename the default `Backlog/Ready/In progress/In review/Done` options — the
   board must match this flow exactly).
3. **`story` + `bug` labels** in the repo.

The workflow (full text in agent-bus; the repo's `CLAUDE.md` points at it):
- **GitHub Issues are the source of truth**; no local planning `.md` files.
  Every issue tagged `STORY:`/`BUG:` (title prefix, first line of body, label).
- **No work without a ticket.** One ticket = one branch = one worktree = one PR
  (`agent-bus/bin/task start <issue#> <slug>`). The main clone stays on `main`.
- The PR body starts with `Closes #<issue#>`; the ticket moves to In Review.
- **Brandon's merge is the blessing.** `bin/ship-pr` (or a merge in the GitHub UI)
  → the reconciler versions, syncs and deploys (§11). Nobody runs `gvc` on main by hand.

## 10. Agent guidance for the new repo

Every app repo gets a `CLAUDE.md`. Model it on `PokeVault/CLAUDE.md` (the best one):
project facts (container, port, URLs), stack, layout, run/test commands, restart
policy ("check with the user before restarting"), domain rules — plus the safety
kernel by reference: "Shared server rules: `/home/brandon/projects/CLAUDE.md` and
`/home/brandon/projects/.augment-guidelines`."

Non-negotiables (from the Jan 7 2026 incident — reboot → Postgres corruption → 117k records lost):
- NEVER `sudo reboot` / `shutdown` / `poweroff`
- NEVER `docker-compose down` on production, `docker stop $(docker ps -aq)`, or `docker system prune -a` ad hoc
- NEVER drop/truncate/delete data or volumes without a verified backup
- Diagnose before acting; the correct fix is usually small (the incident's root cause was a full disk)
- **Verification honesty:** never claim something works without showing evidence (test output, curl response, diff)

## 11. Merge → deploy → preview → teardown (the automated part)

All of this runs every 2 min from `dagu/dags/deploy-reconciler.yaml`. A new app opts in
with two things; everything else is naming discipline.

**Deploy on merge.** Add the repo to `dagu/deploy-repos.yaml` (a docker PR; ask
@dakota) and commit an executable `./deploy` at the app's repo root. On every merge the
reconciler (`scripts/reconcile.sh`) versions main if needed, fast-forwards the main
clone, removes the merged PR's worktree, tags the current images `:previous` and runs
`./deploy`. Biscuit announces it in #infra. A good `./deploy` (see
`MuseForge/deploy`): `docker compose up -d --build <service>`, then poll `/health`
until 200 or fail loudly. Without `./deploy` the clone still syncs but nothing
redeploys.

**Previews.** The rules, and a compose template to copy, live in agent-bus
`README.md`, "Preview containers"; that section wins if the two ever disagree. The
short version, for a PR Brandon should click through:

| Thing | Value |
|---|---|
| Compose project **and** container name | `<project>_pr<N>`, lowercase |
| `N` | **the PR number, not the issue number** |
| Host port | prod + 10000, bound `0.0.0.0` (`8005 → 18005`) |
| Label `dashboard.preview.project` | the services.json `key`, or one of its `preview_names` |
| Label `dashboard.preview.pr` | `N` again, same PR number |
| Label `dashboard.preview.port` / `.path` | host port / URL path (default `/`) |
| Label `dashboard.preview.repo` | optional `owner/name`, overrides services.json `repo` |
| Compose file | scratch dir `/tmp/agentbus/<agent>/preview-pr<N>/`, never in the repo |
| Data | a copy, never prod; schedulers off |

The PR number doesn't exist until `gh pr create` returns it, so the order is:
**open the PR → read its number → bring the preview up as `<project>_pr<N>`.** For a
second round on the same PR, recreate the same project; never reuse another PR's name.

**Teardown is automatic** (`scripts/preview-cleanup.sh`): once PR `N` is MERGED or
CLOSED in the resolved repo, the sweeper removes the preview's containers, networks and
its own `<project>_pr<N>-*` images, and Biscuit posts "Removed preview …". It touches a
container only if **all** of these hold, and otherwise leaves it running and alerts
Brandon once:
- both `dashboard.preview.project` and `dashboard.preview.pr` labels are set,
- the name is `<something>_pr<N>` with the **same N** as the label,
- the compose project equals the container name,
- a repo resolves (label, or the services.json entry's `repo`).

*Learned 2026-10-02:* `museforge_pr85` was labelled `dashboard.preview.pr=99`. 85 was
the issue; 99 was the PR. PR #99 merged, the name and label disagreed, and the sweeper
(correctly) refused to remove it. Check yours with:
```bash
docker ps -a --filter label=dashboard.preview.pr \
  --format '{{.Names}} pr={{.Label "dashboard.preview.pr"}} proj={{.Label "com.docker.compose.project"}}'
~/projects/docker/scripts/preview-cleanup.sh --dry-run   # silent = nothing to do or already alerted
```

## 12. New-app checklist (hand this to the new agent)

The office-wide order, with an owner per step, is agent-bus `docs/NEW_SERVICE.md`
(start there). This is the app-building detail behind it.

Who does what: the new agent owns her repo; Bianca adds her to the office (roster,
persona, `agent-bus` rules); Daisy adds the Dashboard row; Dakota adds the
reconciler entry and owns this doc. Brandon approves each PR.

1. [ ] Pick the next free port (§2), check it with `ss -ltn`, record it in `.augment-guidelines`
2. [ ] GitHub repo `bmbell23/<App>` + Project board + `story`/`bug` labels (§9); first ticket before first code
3. [ ] Scaffold from §4; `version.txt` = `0.1.0`, `.env.example`, `CLAUDE.md` (§10)
4. [ ] Dockerfile + compose from §5 with a `/health` endpoint
5. [ ] First deploy `docker compose up -d --build`; `curl localhost:<port>/health`, then from another device over Tailscale; fix DNAT if needed (§6)
6. [ ] Executable `./deploy` in the repo (§11); ask Dakota to add the repo to `dagu/deploy-repos.yaml`
7. [ ] Ask Daisy for the services.json entry **with `repo`** + `CONTAINERS` entry (§8)
8. [ ] Ask Bianca to put the agent on the roster
9. [ ] First preview: PR first, then `<project>_pr<PR#>` with all four labels (§11); confirm it shows on the Dashboard; after merge, confirm Biscuit posts "Removed preview"
10. [ ] Backup cron once there's real data (§6); tell Peter if it belongs in restic
11. [ ] Android wrapper when the web app is worth wrapping (§7)
