# 🚀 Deemix Quick Start

## Access Web Interface

**URL:** http://dockerhost:6595 or http://100.69.184.113:6595

## First Time Setup

1. Open the web interface
2. Click the **settings icon** (⚙️)
3. Click **"Login via Browser"**
4. Log in with your **Deezer account** (free account works!)
5. Done!

## Download Music

### From Deezer:
1. Go to [deezer.com](https://www.deezer.com/)
2. Find a song/album/playlist
3. Copy the URL
4. Paste into Deemix
5. Click Download

### From Spotify:
1. Copy a Spotify playlist URL
2. Paste into Deemix
3. It automatically finds matching tracks on Deezer
4. Click Download

## Download Location

All music goes to: `/mnt/boston/media/music/`

## Quality Settings

In the web interface settings, choose:
- **FLAC** - Lossless (best quality, large files)
- **320kbps MP3** - High quality (recommended)
- **128kbps MP3** - Smaller files

## Common Commands

```bash
# View logs
docker logs deemix

# Restart
cd /home/brandon/projects/docker/deemix && docker compose restart

# Stop
cd /home/brandon/projects/docker/deemix && docker compose down

# Start
cd /home/brandon/projects/docker/deemix && docker compose up -d
```

## Tips

- ✅ No rate limits - download as much as you want!
- ✅ Works with Spotify playlists
- ✅ Free Deezer account is enough
- ✅ Files automatically appear in Navidrome/Jellyfin/Beets

