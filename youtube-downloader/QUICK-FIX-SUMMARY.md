# YouTube Downloader Fix Summary

## Problem
The yt-dlp container was downloading only `.webp` thumbnail images instead of actual music or video files.

## Solution Applied

### 1. Created Organized Download Folders
- Created `/mnt/boston/media/downloads/youtube/music/` for MP3 downloads
- Created `/mnt/boston/media/downloads/youtube/video/` for video downloads

### 2. Updated Configuration
- Enhanced `config.yml` with proper yt-dlp options for audio and video downloads
- Added presets for MP3, M4A, and video formats

### 3. Fixed Dashboard Integration
- Corrected the compose directory path from `'ytd'` to `'youtube-downloader'`
- Enhanced the YouTube download API to support both MP3 and video downloads
- Downloads now go to organized subfolders

### 4. Restarted Services
- Restarted yt-dlp-web container
- Restarted dashboard container

## How to Use

### Method 1: yt-dlp Web Interface (Port 8998)
**Best for:** Full control over download options

Access: http://100.69.184.113:8998

**For MP3 Music:**
1. Paste YouTube URL
2. Select format: `bestaudio`
3. Check "Extract Audio"
4. Set audio format: `mp3`
5. Click Download

**For Full Video:**
1. Paste YouTube URL
2. Select format: `bestvideo+bestaudio` or `best`
3. DO NOT check "Extract Audio"
4. Click Download

### Method 2: Dashboard (Port 8001)
**Best for:** Quick downloads

Access: http://100.69.184.113:8001

**For MP3 Music (default):**
```json
POST /api/download/youtube
{
  "url": "https://youtube.com/watch?v=..."
}
```

**For Full Video:**
```json
POST /api/download/youtube
{
  "url": "https://youtube.com/watch?v=...",
  "type": "video"
}
```

### Method 3: Command Line

**Download MP3:**
```bash
docker exec yt-dlp-web yt-dlp \
  --extract-audio \
  --audio-format mp3 \
  --audio-quality 0 \
  --embed-thumbnail \
  --add-metadata \
  --output "/downloads/music/%(title)s.%(ext)s" \
  "YOUR_YOUTUBE_URL"
```

**Download Video:**
```bash
docker exec yt-dlp-web yt-dlp \
  --format "bestvideo[ext=mp4]+bestaudio[ext=m4a]/best[ext=mp4]/best" \
  --merge-output-format mp4 \
  --add-metadata \
  --output "/downloads/video/%(title)s.%(ext)s" \
  "YOUR_YOUTUBE_URL"
```

## Download Locations

| Type | Container Path | Host Path |
|------|---------------|-----------|
| Music (MP3) | `/downloads/music/` | `/mnt/boston/media/downloads/youtube/music/` |
| Video (MP4) | `/downloads/video/` | `/mnt/boston/media/downloads/youtube/video/` |

## Files Changed

1. `youtube-downloader/config.yml` - Added comprehensive yt-dlp options
2. `dashboard/app.py` - Fixed compose directory and added video download support
3. Created `youtube-downloader/USAGE-GUIDE.md` - Detailed usage instructions
4. Created subdirectories for organized downloads

## Next Steps

1. Test downloading a music video as MP3
2. Test downloading a full video
3. Clean up old `.webp` files if desired:
   ```bash
   # BE CAREFUL - this will delete all .webp files
   rm /mnt/boston/media/downloads/youtube/*.webp
   ```

## Troubleshooting

**If downloads still fail:**
1. Check container logs: `docker logs yt-dlp-web`
2. Verify yt-dlp is installed: `docker exec yt-dlp-web yt-dlp --version`
3. Test a simple download: `docker exec yt-dlp-web yt-dlp --version`

**If web interface doesn't work:**
- The `marcobaobao/yt-dlp-webui` image may have its own interface
- Use the command line method or dashboard API instead
- Access the web UI at http://100.69.184.113:8998 and explore the interface

