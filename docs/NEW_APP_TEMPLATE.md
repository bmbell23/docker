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

Custom apps live in a sequential block starting at **8002**. Taken (live as of 2026-07-20):

```
8001 Dashboard (host network)   8002 WordForge      8003 ArtForge
8004 LifeForge                  8005 CodeForge (host net, internal)
8006 KidMedia                   8007 GreatReads old prod (retired)
8008 PokeVault                  8009 MealForge      8010 NerdNews/booknews
8090/8091/8092 GreatReads web/retired-backend/ereader
5007/5008 Libby prod/test       8098 Dictionary
```

Third-party stacks use upstream defaults: 2283 Immich, 8096 Jellyfin, 13378 ABS,
8083/8084 Calibre, 8085 Trilium, 8222 Vaultwarden, 8880 Jenkins, 2285 qBittorrent,
9117 Jackett, 8998 yt-dlp, 9999 Stash, 8080 RomM, 6595 Deemix.

**Next free app port: 8011** (then 8012, 8013…). When you claim one:
1. add it to the inventory table in `/home/brandon/projects/.augment-guidelines`,
2. prefer host port == container port (`8011:8011`) — exceptions cause confusion.

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
sudo iptables -t nat -D DOCKER <rule...>     # delete the stale one
```
Related: `scripts/fix-all-docker-iptables.sh` + `docker-iptables.service` +
`docker-post-boot.service` in this repo reapply rules after Docker/boot. Add your
app there if its rules don't survive restarts.

**Testing note:** from the server itself, `curl http://localhost:<port>` — never curl
the Tailscale IP from the server (always times out, exit 28).

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

The Dashboard (`/home/brandon/projects/Dashboard`, Flask, host-network, port 8001) has no config file — registration is code:

1. **Card** in `Dashboard/static/index.html`: copy an existing `<div class="service-card">` block into the right category — set `href="http://100.69.184.113:<port>"`, Font Awesome icon, name, description, `:<port>` footer, and the `restartContainer('<id>')` / `recreateContainer('<id>')` ids.
2. **Backend map** in `Dashboard/app.py` `CONTAINERS` dict (~line 63):
   ```python
   '<id>': {'name': '<container_name>', 'service': '<compose service>',
            'compose_dir': '/home/brandon/projects/<App>'},
   ```
   (Relative `compose_dir` resolves under `projects/docker/`; use absolute for apps in their own repo. Optional `compose_file` key overrides the default.)
3. Redeploy: `cd /home/brandon/projects/Dashboard && docker compose -f compose.yml up -d --build --force-recreate dashboard`

## 9. Work tracking: GitHub repo + Project board (required for every app)

Every app gets, from day one (GreatReads pioneered this; Chess follows it):
1. **A GitHub repo** `bmbell23/<App>` — code, versioned via `version.txt` + `gvc`.
2. **A GitHub Project (user-level) board** with Status columns, in order:
   **Scoping → Ready to Implement → In progress → In Review → Done**
   (rename the default `Backlog/Ready/In progress/In review/Done` options — the
   board must match this flow exactly).
3. **`story` + `bug` labels** in the repo.

The workflow rules (full text in `GreatReads/CLAUDE.md` — copy the adapted version
from `Chess/CLAUDE.md` into each new repo's `CLAUDE.md`):
- **GitHub Issues are the source of truth** — plans/scoping/status live in issues,
  never in local planning `.md` files.
- Every issue tagged `STORY:`/`BUG:` in three synced places (title prefix, first
  line of body, label).
- **No work without a ticket**; new tickets land in Scoping (open questions → ask
  the user) or Ready to Implement (confidently scoped); never skip columns.
- **ONE active ticket** in In progress + In Review at a time; any code change moves
  the ticket to In Review and stays **uncommitted** until the user blesses it Done.
- **Gated actions — always ask first:** DB writes/migrations, container/APK
  rebuilds, and commits/pushes.

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

## 11. New-app checklist

1. [ ] Pick next free port (§2); record it in `.augment-guidelines` inventory
2. [ ] Scaffold repo from §4; `pyproject.toml`, `version.txt` = `0.1.0`, `.env.example`
3. [ ] Dockerfile + compose from §5; `/health` endpoint
4. [ ] `docker compose up -d --build`; verify `curl localhost:<port>/health`
5. [ ] Verify Tailscale reachability from another device; fix DNAT if needed (§6)
6. [ ] Register on Dashboard (§8)
7. [ ] GitHub repo `bmbell23/<App>` + Project board with the five-column flow, `story`/`bug` labels (§9); first ticket before first code
8. [ ] `CLAUDE.md` incl. working rules (§9-10); first commit via `gvc`
8. [ ] Backup cron once there's real data
10. [ ] Android wrapper when the web app is worth wrapping (§7)
