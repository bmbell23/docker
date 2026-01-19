# Docker Containers

This repository contains Docker Compose configurations for various containers running on the Docker host.

## Structure

### Services
Each container/service has its own subdirectory:

- `immich-main/` - Main Immich photo management instance
- `audiobookshelf/` - Audiobook and podcast server
- `beets/` - Music library manager
- `calibre-web/` - Ebook library web interface
- `dashboard/` - Custom dashboard application
- `jackett/` - Torrent indexer proxy
- `jellyfin/` - Media server
- `kavita/` - Comic/manga reader
- `navidrome/` - Music streaming server
- `outline/` - Team wiki and knowledge base
- `pi-hole/` - Network-wide ad blocker
- `picard/` - Music tagger
- `romm/` - ROM manager
- `stash/` - Media organizer
- `torrents/` - Torrent client with VPN
- `youtube-downloader/` - YouTube download and organization tools

### Documentation
Documentation is organized in the `docs/` directory:

- `docs/docker/` - Docker networking and configuration guides
- `docs/reboot/` - System reboot procedures and checklists
- `docs/setup/` - Setup and solution summaries
- `docs/ai-guidelines/` - AI agent interaction guidelines
- `docs/services/` - Service-specific documentation

### Scripts
Utility scripts are organized in the `scripts/` directory:

- `scripts/backup/` - Backup automation scripts
- `scripts/conversion/` - Media conversion utilities
- `scripts/maintenance/` - System maintenance scripts
- `scripts/` - General utility scripts

## Version Management

This repo uses semantic versioning tracked in `version.txt`. Use the `gvc` function to commit with version bumps:

```bash
# Auto-increment patch version
gvc "your commit message"

# Specify version manually
gvc 1.2.0 "your commit message"
```

## General Guidelines

- Each container should have its own directory
- Include a `.env.template` file (never commit actual `.env` files with secrets)
- Include a `README.md` documenting the specific container setup
- Use `.gitignore` to exclude data directories and secrets
