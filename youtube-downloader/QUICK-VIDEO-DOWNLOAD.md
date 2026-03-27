# Quick Video Download Guide

## TL;DR - Just Download a Video

```bash
cd /home/brandon/projects/docker/youtube-downloader
./download-video.sh "YOUR_YOUTUBE_URL"
```

## What Changed?

The script now:
- ✅ Retries 10 times on network errors
- ✅ Prevents partial `.part` files
- ✅ Tries multiple format combinations
- ✅ Limits to 1080p (more reliable than 4K)
- ✅ Shows verbose output so you can see what's happening

## If Download Fails

### Option 1: Use Test Script
```bash
./test-download.sh "YOUR_URL"
```
This shows you exactly what's failing.

### Option 2: Download Lower Quality (More Reliable)
```bash
docker exec yt-dlp-web yt-dlp \
  --format "best" \
  --output "/downloads/video/%(title)s.%(ext)s" \
  "YOUR_URL"
```
This downloads a pre-merged file (usually 720p) which almost always works.

### Option 3: Choose Format Manually
```bash
# See available formats
docker exec yt-dlp-web yt-dlp --list-formats "YOUR_URL"

# Download specific format (example: 22 is usually 720p with audio)
docker exec yt-dlp-web yt-dlp \
  --format "22" \
  --output "/downloads/video/%(title)s.%(ext)s" \
  "YOUR_URL"
```

## Common Format Codes
- `22` - 720p MP4 with audio (most reliable)
- `18` - 360p MP4 with audio (very reliable, lower quality)
- `best` - Best single-file format available
- `bestvideo+bestaudio` - Best quality but requires merging (can fail)

## Check Your Downloads
```bash
ls -lh /mnt/boston/media/downloads/youtube/video/
```

## Clean Up Failed Downloads
```bash
# Remove partial files
rm /mnt/boston/media/downloads/youtube/video/*.part

# Remove video-only files (no audio)
rm /mnt/boston/media/downloads/youtube/video/*.f*.mp4
```

## Full Troubleshooting
See `VIDEO-DOWNLOAD-FIX.md` for detailed troubleshooting.

