# Docker Infrastructure

Docker Compose configurations for all self-hosted containers running on the home server (`100.69.184.113`).

## Services

### 📸 Photos
| Directory | Containers | Port | Description |
|---|---|---|---|
| `immich/` | `immich`, `immich-db` | `2283` | Photo management (imagegenius single-container + Postgres) |

### 🎬 Media
| Directory | Containers | Port | Description |
|---|---|---|---|
| `jellyfin/` | `jellyfin` | `8096` / `8920` | Video streaming server |
| `stash/` | `stash` | `9999` | Adult media organizer |
| `audiobookshelf/` | `audiobookshelf` | `13378` | Audiobook & podcast server |

### 📚 Books & Library
| Directory | Containers | Port | Description |
|---|---|---|---|
| `calibre/` | `calibre` | `8083` / `8084` | Ebook library manager |
| `deemix/` | `deemix` | `6595` | Music download client |

### 🎮 Gaming
| Directory | Containers | Port | Description |
|---|---|---|---|
| `romm/` | `romm`, `romm-db` | `8080` | ROM manager + MariaDB |

### ⬇️ Downloads (VPN-protected)
| Directory | Containers | Port | Description |
|---|---|---|---|
| `torrents/` | `mullvad-vpn`, `qbittorrent` | `2285` (WebUI), `6881` | WireGuard VPN + torrent client |
| `jackett/` | `jackett`, `flaresolverr` | `9117` (via VPN) | Torrent indexer + Cloudflare bypass — **routes through `mullvad-vpn`** |
| `youtube-downloader/` | `yt-dlp-web` | `8998` | yt-dlp web UI |

### 🔧 Productivity
| Directory | Containers | Port | Description |
|---|---|---|---|
| `trilium/` | `trilium` | `8085` | Personal knowledge base (TriliumNext) |
| `vaultwarden/` | `vaultwarden` | `8222` | Self-hosted password manager (Bitwarden-compatible) |

## Network Architecture

`jackett` and `flaresolverr` share the network namespace of the `mullvad-vpn` container (from `torrents/`). This means **`torrents/` must be started before `jackett/`**.

```
mullvad-vpn (torrents/)
  ├── qbittorrent   — network_mode: service:vpn
  ├── jackett       — network_mode: container:mullvad-vpn
  └── flaresolverr  — network_mode: container:mullvad-vpn
```

## Startup Order

1. `torrents/` — VPN must come first (other services share its network)
2. Everything else in any order

## Documentation

- `docs/docker/` — Networking, iptables fixes, migration guides
- `docs/reboot/` — Reboot procedures and checklists
- `docs/setup/` — Setup summaries
- `docs/services/` — Service-specific docs (Immich setup, etc.)
- `scripts/` — Utility scripts (backup, maintenance, iptables fixes)

## Version Management

Semantic versioning tracked in `version.txt`. Use the `gvc` function to commit with version bumps:

```bash
gvc "your commit message"       # auto-increment patch
gvc 1.2.0 "your commit message" # specify version
```

## Conventions

- Each service has its own directory with a `docker-compose.yml`
- Never commit `.env` files — use `.env.template` as the committed reference
- Use `.gitignore` to exclude data directories and secrets
