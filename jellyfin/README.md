# Jellyfin - Personal Media Server

Jellyfin is a free, open-source media server for managing and streaming your personal media collection.

## Features
- 🎬 Stream movies and TV shows
- 🎵 Music streaming with playlist support
- 📸 Photo libraries
- 📱 Mobile apps for iOS and Android
- 🖥️ Apps for Roku, Fire TV, Android TV, Apple TV, and more
- 🎨 Automatic metadata and artwork fetching
- 👥 Multi-user support with parental controls
- 🔊 Hardware-accelerated transcoding
- 📺 Live TV and DVR support (with tuner hardware)

## Quick Start

### 1. Create required directories
```bash
mkdir -p /home/brandon/jellyfin/{config,cache}
```

### 2. Create .env file
```bash
cd /home/brandon/projects/docker/jellyfin
cp .env.example .env
```

The default paths in `.env.example` should work, but you can customize them if needed.

### 3. Start the container
```bash
docker compose up -d
```

### 4. Access Jellyfin
Open your browser and go to:
- **Local**: http://localhost:8096
- **Network**: http://your-server-ip:8096

### 5. Initial Setup
On first launch, Jellyfin will walk you through setup:
1. Select your preferred language
2. Create your admin account
3. Add media libraries:
   - **Videos**: Already mounted at `/media/videos` (points to `/mnt/boston/media/videos`)
   - You can add more libraries later
4. Configure metadata providers (TMDB, TVDB, etc.)
5. Set up remote access (optional)

## Configuration

### Media Libraries
- **Videos**: `/mnt/boston/media/videos` → `/media/videos` (read-only)

To add more media libraries, uncomment the relevant lines in `docker-compose.yml`:
- Music: `/mnt/boston/media/music` → `/media/music`
- Pictures: `/mnt/boston/media/pictures` → `/media/pictures`

### Data Locations
All Jellyfin data is stored in `/home/brandon/jellyfin/`:
- `config/` - Database, configuration, plugins, metadata
- `cache/` - Transcoding cache, image cache

### Ports
- **8096** - HTTP web interface (primary)
- **8920** - HTTPS web interface (optional, requires SSL setup)
- **7359/udp** - Service discovery (for clients to auto-find server)
- **1900/udp** - DLNA discovery

## Hardware Acceleration

This setup includes Intel QuickSync hardware acceleration via `/dev/dri` device mapping.

To enable hardware acceleration:
1. Go to Dashboard → Playback
2. Select "Video Acceleration API (VAAPI)" or "Intel QuickSync (QSV)"
3. Save settings

This significantly reduces CPU usage during transcoding.

## Mobile Apps

Official Jellyfin apps are available:
- **Android**: Google Play Store
- **iOS**: Apple App Store
- **Android TV**: Google Play Store
- **Fire TV**: Amazon App Store
- **Roku**: Roku Channel Store
- **Apple TV**: Apple App Store

## Management Commands

```bash
# Start Jellyfin
docker compose up -d

# Stop Jellyfin
docker compose down

# View logs
docker compose logs -f

# Restart (after config changes)
docker compose restart

# Update to latest version
docker compose pull
docker compose up -d
```

## Library Management

### Scan for new media
Jellyfin automatically scans for new media periodically. To manually trigger a scan:
1. Go to Dashboard → Libraries
2. Click the three dots next to a library
3. Select "Scan Library"

### Metadata and artwork
Jellyfin automatically downloads metadata and artwork from:
- The Movie Database (TMDB)
- TheTVDB
- MusicBrainz
- And more...

You can customize metadata providers in Dashboard → Libraries → [Library] → Manage Library.

## Troubleshooting

### Videos not showing up
- Check that `/mnt/boston/media/videos` contains video files
- Trigger a library scan (Dashboard → Libraries)
- Check logs: `docker compose logs -f`
- Supported formats: MP4, MKV, AVI, MOV, etc.

### Can't access web interface
- Verify container is running: `docker ps | grep jellyfin`
- Check port 8096 is not in use: `sudo netstat -tlnp | grep 8096`
- Check logs: `docker compose logs`

### Transcoding issues
- Verify hardware acceleration is enabled (Dashboard → Playback)
- Check that `/dev/dri` is accessible: `ls -la /dev/dri`
- Monitor resource usage: `docker stats jellyfin`
- Check transcoding logs in Dashboard → Logs

### Playback stuttering
- Enable hardware acceleration
- Increase cache size in docker-compose.yml
- Check network bandwidth
- Try lowering playback quality in client

## Security Notes

- Media libraries are mounted **read-only** (`:ro`) to prevent accidental modifications
- Change default admin password after first login
- Consider setting up HTTPS for remote access
- Use strong passwords for all user accounts
- Enable two-factor authentication in user settings

## Advanced Features

### Plugins
Install plugins from Dashboard → Plugins → Catalog:
- **Trakt**: Sync watch history
- **Kodi Sync Queue**: Sync with Kodi
- **Anime**: Better anime metadata
- **Fanart**: Additional artwork sources
- **And many more...**

### Live TV & DVR
If you have a TV tuner, you can set up Live TV:
1. Dashboard → Live TV
2. Add tuner device
3. Configure channel guide
4. Set up DVR recording rules

### Collections
Group related movies/shows:
1. Select multiple items
2. Click "Add to Collection"
3. Create or select a collection

## Links
- Official Docs: https://jellyfin.org/docs/
- GitHub: https://github.com/jellyfin/jellyfin
- Forum: https://forum.jellyfin.org/
- Reddit: https://reddit.com/r/jellyfin

## Performance Tips

1. **Enable hardware acceleration** - Reduces CPU usage by 80%+
2. **Use compatible formats** - H.264/H.265 video, AAC audio
3. **Optimize library structure** - Organize files properly for better metadata matching
4. **Regular maintenance** - Clean up old cache files periodically
5. **Monitor resources** - Use `docker stats` to check resource usage

