# Video Download Troubleshooting Guide

## Problem
Video downloads were failing with:
- Partial `.part` files that don't play
- Files with format codes like `.f137.mp4` (video only, no audio)
- "Forbidden" errors during download
- Videos that play without audio

## Root Cause
YouTube serves video and audio as separate streams. yt-dlp must:
1. Download the video stream (e.g., format 137)
2. Download the audio stream (e.g., format 140)
3. Merge them together using ffmpeg

If step 2 or 3 fails (network error, rate limiting, forbidden error), you get a partial file.

## Solutions Applied

### 1. Updated Download Script
Enhanced `download-video.sh` with:
- **Better format selection**: Tries multiple fallback formats
- **Retry logic**: 10 retries for network errors
- **No partial files**: `--no-part` prevents `.part` files
- **Verbose output**: Shows exactly what's happening
- **Height limit**: `height<=1080` to avoid huge 4K files that might fail

### 2. Updated Dashboard API
Same improvements applied to the dashboard's YouTube download endpoint.

### 3. Created Test Script
New `test-download.sh` to diagnose issues:
- Shows available formats
- Provides verbose output
- Saves logs for debugging

## How to Use

### Method 1: Updated Download Script (Recommended)
```bash
cd /home/brandon/projects/docker/youtube-downloader
./download-video.sh "YOUR_YOUTUBE_URL"
```

### Method 2: Test Script (For Troubleshooting)
```bash
cd /home/brandon/projects/docker/youtube-downloader
./test-download.sh "YOUR_YOUTUBE_URL"
```

This will:
- Show all available formats
- Attempt download with verbose output
- Save logs to `/tmp/yt-dlp-test.log`

### Method 3: Manual Download with Custom Format
If the automatic format selection fails, you can manually choose formats:

```bash
# Step 1: List available formats
docker exec yt-dlp-web yt-dlp --list-formats "YOUR_URL"

# Step 2: Download with specific format codes
# Example: format 137 (1080p video) + format 140 (audio)
docker exec yt-dlp-web yt-dlp \
  --format "137+140" \
  --merge-output-format mp4 \
  --output "/downloads/video/%(title)s.%(ext)s" \
  "YOUR_URL"
```

## Common Issues and Fixes

### Issue 1: "HTTP Error 403: Forbidden"
**Cause:** YouTube rate limiting or geo-blocking
**Fix:** Add cookies or use a different format

```bash
# Try a simpler format that doesn't require merging
docker exec yt-dlp-web yt-dlp \
  --format "best[ext=mp4]" \
  --output "/downloads/video/%(title)s.%(ext)s" \
  "YOUR_URL"
```

### Issue 2: Video downloads but has no audio
**Cause:** Audio stream download failed, only video stream saved
**Fix:** Use the updated script with retry logic, or manually select a format that includes audio

```bash
# Download pre-merged format (lower quality but more reliable)
docker exec yt-dlp-web yt-dlp \
  --format "best" \
  --output "/downloads/video/%(title)s.%(ext)s" \
  "YOUR_URL"
```

### Issue 3: Download stops at 99% or creates .part files
**Cause:** Network interruption during merge
**Fix:** The updated script uses `--no-part` to prevent this

### Issue 4: "Postprocessing failed"
**Cause:** ffmpeg merge failed
**Fix:** Check ffmpeg is working

```bash
# Verify ffmpeg is installed
docker exec yt-dlp-web ffmpeg -version

# If not installed, restart container
cd /home/brandon/projects/docker/youtube-downloader
docker compose restart
```

## Alternative: Download Lower Quality (More Reliable)

If high-quality downloads keep failing, use a simpler format:

```bash
# Download best single-file format (no merging needed)
docker exec yt-dlp-web yt-dlp \
  --format "best[ext=mp4]/best" \
  --output "/downloads/video/%(title)s.%(ext)s" \
  "YOUR_URL"
```

This downloads a pre-merged file (usually 720p or lower) which is more reliable.

## Checking Download Results

```bash
# List downloaded videos
ls -lh /mnt/boston/media/downloads/youtube/video/

# Play a video to verify it has audio
# (if you have mpv or vlc installed)
mpv /mnt/boston/media/downloads/youtube/video/FILENAME.mp4
```

## Clean Up Failed Downloads

```bash
# Remove partial files
rm /mnt/boston/media/downloads/youtube/video/*.part

# Remove video-only files (format code in filename)
rm /mnt/boston/media/downloads/youtube/video/*.f*.mp4
```

## Next Steps

1. Try downloading a video with the updated script
2. If it fails, run the test script to see detailed output
3. Check the logs for specific error messages
4. Try the manual format selection method if needed

## Updated Files
- `download-video.sh` - Enhanced with retry logic and better format selection
- `dashboard/app.py` - Same improvements for web interface
- `test-download.sh` - New diagnostic tool

