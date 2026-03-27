# YouTube Downloader Usage Guide

## Access the Web Interface

The yt-dlp web interface is available at: **http://100.69.184.113:8998**

Login credentials:
- Username: `brandon`
- Password: `asdSDF#$43pw`

## Download Options

### Option 1: Download Music as MP3

To download audio only (music) as MP3:

1. Go to http://100.69.184.113:8998
2. Paste your YouTube URL in the input box
3. **In the "Format" dropdown**, select: `bestaudio` or `audio only`
4. **In the "Audio Format" field**, enter: `mp3`
5. **Check the box for "Extract Audio"**
6. **Optional:** Check "Embed Thumbnail" to add album art
7. Click "Download"

**Advanced Options (click "Show Advanced Options"):**
- Audio Quality: `0` (best quality)
- Output Template: `/downloads/music/%(title)s.%(ext)s`

### Option 2: Download Full Video

To download the full video in best quality:

1. Go to http://100.69.184.113:8998
2. Paste your YouTube URL in the input box
3. **In the "Format" dropdown**, select: `bestvideo+bestaudio` or `best`
4. **DO NOT check "Extract Audio"**
5. Click "Download"

**Advanced Options:**
- Merge Output Format: `mp4`
- Output Template: `/downloads/video/%(title)s.%(ext)s`

## Common Issues

### Issue: Only downloading .webp thumbnail images

**Problem:** The web interface might be configured to only download thumbnails.

**Solution:** 
1. Make sure you select a proper format (not "thumbnail")
2. Ensure "Extract Audio" is checked for music downloads
3. For video downloads, ensure "Extract Audio" is NOT checked
4. Select `bestaudio` or `bestvideo+bestaudio` in the format dropdown

### Issue: Downloads not appearing

**Problem:** Files might be downloading to the wrong location.

**Solution:** Check the download location:
- Music should go to: `/downloads/music/`
- Videos should go to: `/downloads/video/`
- On the host system: `/mnt/boston/media/downloads/youtube/music/` or `/mnt/boston/media/downloads/youtube/video/`

## Download Locations

- **Container path:** `/downloads/`
- **Host path:** `/mnt/boston/media/downloads/youtube/`
- **Music subfolder:** `/mnt/boston/media/downloads/youtube/music/`
- **Video subfolder:** `/mnt/boston/media/downloads/youtube/video/`

## Using the Dashboard (Port 8001)

The Docker Dashboard at port 8001 has a YouTube download feature:

1. Go to http://100.69.184.113:8001
2. Find the YouTube download section
3. Paste your URL
4. Click "Download"

**Note:** The dashboard currently only supports MP3 audio downloads. For video downloads, use the yt-dlp web interface at port 8998.

## Command Line Alternative

You can also download directly using docker exec:

### Download as MP3:
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

### Download as Video:
```bash
docker exec yt-dlp-web yt-dlp \
  --format "bestvideo[ext=mp4]+bestaudio[ext=m4a]/best[ext=mp4]/best" \
  --merge-output-format mp4 \
  --add-metadata \
  --output "/downloads/video/%(title)s.%(ext)s" \
  "YOUR_YOUTUBE_URL"
```

## Troubleshooting

### Restart the container:
```bash
cd /home/brandon/projects/docker/youtube-downloader
docker compose down
docker compose up -d
```

### Check container logs:
```bash
docker logs yt-dlp-web
```

### Verify downloads:
```bash
ls -lh /mnt/boston/media/downloads/youtube/music/
ls -lh /mnt/boston/media/downloads/youtube/video/
```

