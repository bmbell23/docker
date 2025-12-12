# YouTube Music Download & Organization - Quick Start

## 🎵 Complete Workflow

### 1. Install Beets (One-time)

```bash
sudo apt install -y beets
mkdir -p ~/.config/beets
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

---

### 2. Download Music

**Option A: Web UI (Simple)**
- Open `http://YOUR_IP:8998`
- Paste YouTube URL
- Select "Audio Only"
- Click Download

**Option B: Command Line (Better Metadata)**
```bash
cd /home/brandon/projects/docker/youtube-downloader
./download-with-metadata.sh "https://youtube.com/watch?v=VIDEO_ID"
```

---

### 3. Tag & Organize with Beets

```bash
# Import all downloads
beet import /mnt/boston/media/downloads/youtube/

# Beets will:
# - Match songs to MusicBrainz database
# - Ask you to confirm matches
# - Add proper metadata (artist, album, year, genre)
# - Move to /mnt/boston/media/music/ organized by Artist/Album
```

**Beets Tips:**
- Press `A` to accept a match
- Press `S` to skip
- Press `U` to use as-is (no tagging)
- Press `E` to manually enter metadata
- Press `I` to search MusicBrainz manually

---

### 4. Wait for Navidrome

Navidrome auto-scans every 5 minutes. Your music will appear automatically!

Or force a scan:
```bash
cd /home/brandon/projects/docker/navidrome
docker compose restart
```

---

## 📋 Quick Commands

```bash
# Download with metadata
cd /home/brandon/projects/docker/youtube-downloader
./download-with-metadata.sh "YOUTUBE_URL"

# Tag and organize
beet import /mnt/boston/media/downloads/youtube/

# Check what's in downloads
ls -lh /mnt/boston/media/downloads/youtube/

# Check what's in music library
ls -lh /mnt/boston/media/music/

# Restart Navidrome to force scan
cd /home/brandon/projects/docker/navidrome && docker compose restart
```

---

## 🏴‍☠️ For Your Existing 400+ Files

You already have ~4GB of music in `/mnt/boston/media/downloads/youtube/`

To tag and organize them all:

```bash
# This will take a while (400+ files!)
beet import /mnt/boston/media/downloads/youtube/

# Beets will ask about each file/album
# You can:
# - Accept matches (A)
# - Skip files you don't want (S)
# - Manually search for better matches (I)
```

**Pro tip:** Start with a few files first to get the hang of it:

```bash
# Just import one file to test
beet import "/mnt/boston/media/downloads/youtube/Morgan Wallen - Last Night (Lyric Video).opus"
```

---

## 🎯 Summary

1. **Download:** Use web UI or `download-with-metadata.sh`
2. **Tag:** Run `beet import /mnt/boston/media/downloads/youtube/`
3. **Enjoy:** Music appears in Navidrome within 5 minutes!

