# Stash Setup

Stash is a self-hosted organizer for your adult media collection.

## Features
- Web-based interface (mobile responsive)
- Video and image gallery support
- Performer/actor tagging and tracking
- Scene organization and metadata
- Video preview generation and scene markers
- Tag-based organization
- Scraping metadata from various sources
- Advanced search and filtering

## Setup Instructions

### 1. Create the required directories
The directories specified in `.env` need to exist before starting the container:

```bash
mkdir -p /home/brandon/stash/{config,generated,metadata,cache}
```

### 2. Start the container
```bash
docker compose up -d
```

### 3. Access Stash
Open your browser and go to:
- **Local**: http://localhost:9999
- **Network**: http://your-server-ip:9999

### 4. Initial Setup
On first launch, Stash will walk you through initial setup:
1. Set up your admin credentials
2. Configure your library paths (already mounted at `/data`)
3. Run initial scan

## Configuration

### Media Location
- **Host path**: `/mnt/boston/media/other`
- **Container path**: `/data` (read-only)

### Data Locations
All Stash data is stored in `/home/brandon/stash/`:
- `config/` - Database and configuration
- `generated/` - Thumbnails, previews, transcodes
- `metadata/` - Scraped metadata
- `cache/` - Temporary cache files

### Port
- **9999** - Web interface

## Mobile Access
While there's no dedicated mobile app, the web interface is fully responsive and works well on mobile browsers. You can:
1. Bookmark `http://your-server-ip:9999` on your phone
2. Add it to your home screen as a PWA (Progressive Web App)

## Useful Commands

### View logs
```bash
docker compose logs -f
```

### Restart
```bash
docker compose restart
```

### Stop
```bash
docker compose down
```

### Update to latest version
```bash
docker compose pull
docker compose up -d
```

## Documentation
- Official Docs: https://docs.stashapp.cc/
- GitHub: https://github.com/stashapp/stash
- Discord: https://discord.gg/2TsNFKt

## Privacy Notes
- The media directory is mounted as **read-only** (`:ro`) so Stash cannot modify your original files
- All metadata and generated content is stored separately in `/home/brandon/stash/`
- The `.env` file is gitignored to keep your local paths private

