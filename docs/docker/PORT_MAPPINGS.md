# Docker Container Port Mappings

**Last Updated**: 2026-01-15

This is the **authoritative reference** for all Docker container port mappings. If a port doesn't match this table, the container configuration is wrong.

## Port Mapping Table

| Service | External Port | Internal Port | Protocol | Access URL | Notes |
|---------|--------------|---------------|----------|------------|-------|
| **Media Services** |
| Immich | 2283 | 2283 | TCP | http://10.0.0.160:2283 | Photo management ⭐ |
| Jellyfin | 8096 | 8096 | TCP | http://10.0.0.160:8096 | Video streaming ⭐ |
| Jellyfin HTTPS | 8920 | 8920 | TCP | https://10.0.0.160:8920 | Optional HTTPS |
| Jellyfin Discovery | 7359 | 7359 | UDP | - | Service discovery |
| Jellyfin DLNA | 1900 | 1900 | UDP | - | DLNA discovery |
| Stash | 9999 | 9999 | TCP | http://10.0.0.160:9999 | Media organizer |
| **Gaming & ROMs** |
| RomM | 8080 | 8080 | TCP | http://10.0.0.160:8080 | ROM manager ⭐ |
| **Books & Reading** |
| Kavita | 5000 | 5000 | TCP | http://10.0.0.160:5000 | Comic/ebook reader |
| Audiobookshelf | 13378 | 80 | TCP | http://10.0.0.160:13378 | Audiobook server ⭐ |
| **Music Services** |
| Navidrome | 4533 | 4533 | TCP | http://10.0.0.160:4533 | Music streaming |
| Beets | 8337 | 8337 | TCP | http://10.0.0.160:8337 | Music library manager |
| Picard | 5800 | 5800 | TCP | http://10.0.0.160:5800 | Music tagger (VNC) |
| **Download Tools** |
| qBittorrent | 2285 | 8080 | TCP | http://10.0.0.160:2285 | Torrent client (via VPN) ⭐ |
| Jackett | 9117 | 9117 | TCP | http://10.0.0.160:9117 | Torrent indexer (via VPN) |
| Mullvad VPN | 6881 | 6881 | TCP/UDP | - | VPN container for torrents |
| YT-DLP Web | 8998 | 3033 | TCP | http://10.0.0.160:8998 | YouTube downloader |
| FlareSolverr | - | 8191 | TCP | - | Cloudflare bypass (internal) |
| **Productivity & Wiki** |
| Outline | - | 3000 | TCP | - | Wiki/docs (currently restarting) |
| Dashboard | 8001 | 5000 | TCP | http://10.0.0.160:8001 | Custom service dashboard ⭐ |
| **Forge Apps** |
| WordForge | 8002 | 8002 | TCP | http://10.0.0.160:8002 | Writing/document app |
| ArtForge | 8003 | 8003 | TCP | http://10.0.0.160:8003 | Art/creative app |
| LifeForge | 8004 | 8004 | TCP | http://10.0.0.160:8004 | Life management app |
| GreatReads | 8007 | 8006 | TCP | http://10.0.0.160:8007 | Book tracking app ⭐ |
| CodeForge | 8009 | 8000 | TCP | http://10.0.0.160:8009 | Code snippets app |
| **Databases (Internal Only)** |
| Immich Postgres | - | 5432 | TCP | - | Internal only |
| Immich Redis | - | 6379 | TCP | - | Internal only |
| RomM MariaDB | - | 3306 | TCP | - | Internal only |
| Outline Postgres | - | 5432 | TCP | - | Internal only |
| Outline Redis | - | 6379 | TCP | - | Internal only |
| Outline MinIO | 9000-9001 | 9000-9001 | TCP | http://10.0.0.160:9000 | S3 storage for Outline |

## Port Ranges

- **2000-2999**: Special services (Immich 2283, qBittorrent 2285)
- **4000-4999**: Media streaming (Navidrome 4533)
- **5000-5999**: Books/reading (Kavita 5000, Picard 5800)
- **8000-8099**: Primary web services (RomM 8080, Jellyfin 8096, Dashboard 8001, Forge apps 8002-8009)
- **9000-9999**: Utilities (Jackett 9117, Stash 9999, YT-DLP 8998, MinIO 9000-9001)
- **13000+**: High-numbered services (Audiobookshelf 13378)

## Reserved Ports (DO NOT USE)

- **22**: SSH
- **80**: HTTP (system)
- **443**: HTTPS (system)
- **53**: DNS (Pi-hole if installed)
- **3000**: Used by Outline (not exposed externally yet)

## Tailscale Access

All services are accessible via Tailscale IP: `100.123.154.40`

Example: `http://100.123.154.40:8080` for RomM

## Quick Access URLs (Local Network)

**Most Used Services (⭐):**
- Dashboard: http://10.0.0.160:8001
- Immich (Photos): http://10.0.0.160:2283
- Jellyfin (Videos): http://10.0.0.160:8096
- RomM (Games): http://10.0.0.160:8080
- qBittorrent: http://10.0.0.160:2285
- Audiobookshelf: http://10.0.0.160:13378
- GreatReads: http://10.0.0.160:8007

## Notes

- **External Port**: The port you access from your browser/network
- **Internal Port**: The port the application listens on inside the container
- **Format**: `external:internal` in docker-compose.yml (e.g., `8080:8080`)
- All TCP ports unless marked UDP
- Database ports are internal only (not exposed to host)
- Services marked with ⭐ are frequently used

## Maintenance

When adding a new service:
1. Check this table for available ports
2. Update docker-compose.yml with the port mapping
3. Update this table
4. Test access from local network and Tailscale
5. Run `/home/brandon/projects/docker/scripts/docker-port-monitor.sh` to verify

## Removing Services

To remove Kavita and Navidrome (if desired):
```bash
cd /home/brandon/projects/docker/kavita && docker-compose down
cd /home/brandon/projects/docker/navidrome && docker-compose down
```
This will free up ports 5000 and 4533.
