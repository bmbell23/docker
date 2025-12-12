# Navidrome - Personal Music Streaming Server

Navidrome is a modern, self-hosted music server and streamer compatible with Subsonic/Airsonic clients.

## Features
- 🎵 Stream your music collection from anywhere
- 📱 Compatible with many mobile apps (DSub, Ultrasonic, Substreamer, etc.)
- 🎨 Automatic album art and metadata fetching
- ⭐ Ratings, favorites, and playlists
- 🔊 On-the-fly transcoding
- 👥 Multi-user support
- 🌐 Web interface included

## Quick Start

1. **Create required directories:**
   ```bash
   mkdir -p /home/brandon/navidrome/{data,cache}
   ```

2. **Start the container:**
   ```bash
   cd /home/brandon/projects/docker/navidrome
   docker compose up -d
   ```

3. **Access Navidrome:**
   - Open browser to: http://localhost:4533
   - Or: http://YOUR_SERVER_IP:4533
   - Create your admin account on first visit

4. **Check logs:**
   ```bash
   docker compose logs -f
   ```

## Configuration

Configuration is managed through:
- `.env` file - Host paths for data and cache
- `docker-compose.yml` - Container settings and environment variables

### Music Library
- Location: `/mnt/boston/media/music`
- Mounted as **read-only** for safety
- Scanned every hour (configurable via `ND_SCANSCHEDULE`)

### Data Storage
- Database and config: `/home/brandon/navidrome/data`
- Cache (transcoding, images): `/home/brandon/navidrome/cache`

## Mobile Apps

Navidrome is compatible with Subsonic clients:
- **Android:** DSub, Ultrasonic, Substreamer
- **iOS:** play:Sub, substreamer, Amperfy
- **Desktop:** Sublime Music, Sonixd

## Management Commands

```bash
# Start Navidrome
docker compose up -d

# Stop Navidrome
docker compose down

# View logs
docker compose logs -f

# Restart (after config changes)
docker compose restart

# Update to latest version
docker compose pull
docker compose up -d

# Force music library rescan
docker compose restart
```

## Troubleshooting

### Music not showing up
- Check that `/mnt/boston/media/music` contains music files
- Wait for initial scan to complete (check logs)
- Supported formats: MP3, FLAC, OGG, M4A, WMA, etc.

### Can't access web interface
- Verify container is running: `docker ps | grep navidrome`
- Check port 4533 is not in use: `sudo netstat -tlnp | grep 4533`
- Check logs: `docker compose logs`

### Performance issues
- Increase cache sizes in docker-compose.yml
- Check available disk space in cache location
- Consider adjusting resource limits

## Security Notes

- Music library is mounted **read-only** to prevent accidental modifications
- Change default admin password after first login
- Consider putting behind reverse proxy (nginx) for HTTPS
- Limit port exposure if accessible from internet

## Links
- Official Docs: https://www.navidrome.org/docs/
- GitHub: https://github.com/navidrome/navidrome
- Demo: https://demo.navidrome.org/

