# YouTube Downloader (yt-dlp Web UI)

A web-based interface for downloading videos and audio from YouTube and other platforms using yt-dlp.

## Access

**Web UI:** `http://YOUR_SERVER_IP:8998`

## Features

- Download videos from YouTube and 1000+ other sites
- Extract audio only (MP3, M4A, etc.)
- Choose quality and format
- Download playlists
- Simple web interface

## Usage

### Option 1: Web UI (Simple)

1. Open the web UI at port 8998
2. Paste a YouTube URL
3. Select format (audio only for music)
4. Click download
5. Files save to `/mnt/boston/media/downloads/youtube`

**Note:** Web UI downloads may have limited metadata. Use Option 2 for better tagging.

### Option 2: Command Line Script (Better Metadata)

Use the included script for downloads with proper metadata:

```bash
cd /home/brandon/projects/docker/youtube-downloader
./download-with-metadata.sh "https://youtube.com/watch?v=VIDEO_ID"
```

This will:
- Download as MP3 (high quality)
- Embed thumbnail as album art
- Add metadata (artist, title)
- Save to `/mnt/boston/media/downloads/youtube`

## Auto-Tagging and Organizing Music

### Install Beets (One-time setup)

Beets automatically tags and organizes your music:

```bash
# Install beets
sudo apt install -y beets

# Create config directory
mkdir -p ~/.config/beets

# Create config file
cat > ~/.config/beets/config.yaml << 'EOF'
directory: /mnt/boston/media/music
library: ~/.config/beets/library.db

import:
    move: yes
    copy: no
    write: yes

paths:
    default: $albumartist/$album%aunique{}/$track $title
    singleton: Non-Album/$artist - $title
    comp: Compilations/$album%aunique{}/$track $title
EOF
```

### Tag and Import Downloads

After downloading music, run beets to auto-tag and organize:

```bash
# Import all YouTube downloads
beet import /mnt/boston/media/downloads/youtube/

# Or import a specific file
beet import /mnt/boston/media/downloads/youtube/song.mp3
```

Beets will:
1. Analyze the audio
2. Search MusicBrainz database for matches
3. Ask you to confirm (or manually search)
4. Add proper metadata (artist, album, track #, year, genre)
5. Move to `/mnt/boston/media/music/` organized by Artist/Album
6. Navidrome will auto-scan within 5 minutes

### Manual Move (Not Recommended)

If you skip beets, you can manually move files, but they'll have poor metadata:

```bash
# Move files to music library
mv /mnt/boston/media/downloads/youtube/*.mp3 /mnt/boston/media/music/
```

## Legal Notice

**Only download content you have permission to download:**
- Creative Commons licensed music
- Public domain content
- Content you own
- Content with explicit download permission

Respect copyright laws in your jurisdiction.

## Container Info

- **Image:** marcobaobao/yt-dlp-webui
- **Port:** 8998
- **Downloads:** `/mnt/boston/media/downloads/youtube`
- **Data:** `/home/brandon/youtube-downloader/data`

## Troubleshooting

**Container not starting:**
```bash
cd /home/brandon/projects/docker/youtube-downloader
docker compose logs
```

**Downloads not appearing:**
```bash
ls -la /mnt/boston/media/downloads/youtube
```

**Restart container:**
```bash
docker compose restart
```

