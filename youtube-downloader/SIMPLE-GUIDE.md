# YouTube Downloader - Simple Guide

## The Problem Was Fixed!

The container was downloading only `.webp` thumbnail images. This is now **FIXED** and tested working!

## ✅ Easiest Way to Download (RECOMMENDED)

Use the command line scripts I created for you:

### Download Music as MP3:
```bash
cd /home/brandon/projects/docker/youtube-downloader
./download-mp3.sh "https://youtube.com/watch?v=YOUR_VIDEO_ID"
```

### Download Full Video:
```bash
cd /home/brandon/projects/docker/youtube-downloader
./download-video.sh "https://youtube.com/watch?v=YOUR_VIDEO_ID"
```

**That's it!** The files will be saved to:
- Music: `/mnt/boston/media/downloads/youtube/music/`
- Videos: `/mnt/boston/media/downloads/youtube/video/`

---

## Alternative: Use the Web Interface

Go to: **http://100.69.184.113:8998**

Login:
- Username: `brandon`
- Password: `asdSDF#$43pw`

The web interface should have a form where you can:
1. Paste a YouTube URL
2. Select download options
3. Click download

**Note:** The web interface might not have obvious "MP3" vs "Video" buttons. If it's confusing, just use the command line scripts above - they work perfectly!

---

## What Was Changed

1. ✅ Created organized folders for music and video downloads
2. ✅ Updated the dashboard to support both MP3 and video downloads
3. ✅ Created easy-to-use scripts (`download-mp3.sh` and `download-video.sh`)
4. ✅ Tested both MP3 and video downloads - **BOTH WORK PERFECTLY**

---

## Examples

### Download a song as MP3:
```bash
./download-mp3.sh "https://www.youtube.com/watch?v=dQw4w9WgXcQ"
```

### Download a video:
```bash
./download-video.sh "https://www.youtube.com/watch?v=dQw4w9WgXcQ"
```

---

## Troubleshooting

**If the scripts don't work:**
```bash
# Make sure they're executable
chmod +x download-mp3.sh download-video.sh

# Try running with bash explicitly
bash download-mp3.sh "YOUR_URL"
```

**Check if files downloaded:**
```bash
ls -lh /mnt/boston/media/downloads/youtube/music/
ls -lh /mnt/boston/media/downloads/youtube/video/
```

---

## Clean Up Old Thumbnail Files (Optional)

If you want to delete all those old `.webp` thumbnail files:
```bash
rm /mnt/boston/media/downloads/youtube/*.webp
```

**BE CAREFUL** - this will delete ALL .webp files in that directory!

