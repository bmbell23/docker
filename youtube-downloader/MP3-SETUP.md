# How to Download MP3 Instead of Opus

Jellyfin doesn't support .opus files, so here's how to make yt-dlp-webui download MP3 by default.

## Method 1: Web UI Settings (Recommended)

1. Go to `http://YOUR_SERVER_IP:8998`
2. Log in with your credentials
3. Click the **⚙️ gear icon** (Settings) in the top right
4. Enable **"Extract audio"** toggle
5. In the **"Custom arguments"** field, add:
   ```
   --audio-format mp3 --audio-quality 0 --embed-thumbnail --add-metadata
   ```
6. Click **Save**

Now all downloads will be MP3 instead of opus!

### What these arguments do:
- `--audio-format mp3` - Convert to MP3 format
- `--audio-quality 0` - Best quality (192-320kbps)
- `--embed-thumbnail` - Embed video thumbnail as album art
- `--add-metadata` - Add artist/title metadata

## Method 2: Convert Existing Opus Files

If you already have .opus files, use the conversion script:

```bash
cd /home/brandon/projects/docker
./convert_opus_to_mp3.sh /path/to/file.opus
```

Or convert all opus files in a directory:

```bash
# Convert all .opus files in downloads folder
find /mnt/boston/media/downloads/youtube -name "*.opus" -type f | while read file; do
    ./convert_opus_to_mp3.sh "$file"
done
```

## Verify It's Working

1. Download a test video from the web UI
2. Check the downloads folder:
   ```bash
   ls -lh /mnt/boston/media/downloads/youtube/
   ```
3. You should see `.mp3` files instead of `.opus`

## Troubleshooting

**Still getting .opus files?**
- Make sure you saved the settings in the web UI
- Try refreshing the page and checking settings again
- The settings are saved per-browser, so if you use a different browser you'll need to set it again

**Want to change quality?**
- `--audio-quality 0` = Best (192-320kbps)
- `--audio-quality 5` = Medium (~128kbps)
- `--audio-quality 9` = Lowest (~64kbps)

