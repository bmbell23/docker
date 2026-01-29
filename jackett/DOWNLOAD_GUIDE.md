# Jackett Download Guide

## Understanding Jackett's Download Options

When you search for torrents in Jackett, you see two download options:

### 🧲 Magnet Link (RECOMMENDED)
- **What it does:** Opens the torrent directly in qBittorrent
- **How it works:** Click the magnet icon, your browser opens qBittorrent, download starts
- **Pros:** Fast, simple, no intermediate files
- **Cons:** None really

### 📥 Download Locally (NOT RECOMMENDED)
- **What it does:** Tries to download the `.torrent` file to your browser's Downloads folder
- **How it works:** Downloads a small `.torrent` file, then you manually upload it to qBittorrent
- **Pros:** Can work when magnet links are unavailable
- **Cons:** 
  - Often fails due to browser security, CORS, or VPN routing
  - Requires manual upload to qBittorrent
  - Extra steps for no benefit

## Why "Download Locally" Doesn't Work

The `/downloads` directory in your Jackett container (`/mnt/boston/media/torrents`) is **NOT** where these files go. That directory is for "BlackHole" mode, which is a different feature.

When you click "Download locally":
1. Jackett tries to send the `.torrent` file to your **browser**
2. Your browser should download it to `~/Downloads` on your local machine
3. You would then manually add it to qBittorrent

**Common reasons it fails:**
- Browser blocks the download (CORS policy)
- Torrent site uses redirects that fail
- VPN routing interferes with the download
- Browser's download settings block automatic downloads

## Recommended Workflows

### Method 1: Use Magnet Links (Easiest)
1. Search in Jackett web UI: `http://100.123.154.40:9117`
2. Click the **magnet icon** 🧲 next to the torrent you want
3. Your browser opens qBittorrent
4. Download starts automatically

### Method 2: Use qBittorrent's Search Plugin (Best)
This lets you search directly from qBittorrent without opening Jackett's web UI.

**Setup (one-time):**
1. Open qBittorrent: `http://100.123.154.40:2285`
2. Go to **View → Search Engine** (or press F3)
3. Click **Search plugins** button (bottom right)
4. Click **Install a new one** → **Web link**
5. Enter: `https://raw.githubusercontent.com/qbittorrent/search-plugins/master/nova3/engines/jackett.py`
6. Click **OK**

**Configure Jackett plugin:**
1. In the Search plugins window, find "Jackett"
2. Right-click → **Edit**
3. Set these values:
   - `api_key`: Your Jackett API key (found in Jackett web UI, top right)
   - `url`: `http://100.123.154.40:9117`
4. Save

**Usage:**
1. In qBittorrent, press F3 to open Search
2. Type your search query
3. Select "Jackett" from the plugins dropdown
4. Click Search
5. Double-click any result to start downloading

### Method 3: Use Sonarr/Radarr (Advanced)
For automated TV show and movie downloads, integrate Jackett with Sonarr/Radarr.

## Troubleshooting "Download Locally"

If you really need to use "Download locally" (not recommended):

1. **Check browser's download folder:**
   ```bash
   ls -lah ~/Downloads/*.torrent
   ```

2. **Check browser console for errors:**
   - Press F12 in your browser
   - Click "Console" tab
   - Try downloading again
   - Look for CORS or network errors

3. **Try a different browser:**
   - Some browsers handle torrent downloads better than others

4. **Check if the file is actually downloading:**
   - Look at your browser's download indicator
   - Check browser's Downloads page (Ctrl+J in Chrome/Firefox)

## What is the `/downloads` Directory For?

The `/downloads` directory in Jackett (`/mnt/boston/media/torrents`) is used for **BlackHole mode**:

- **BlackHole mode:** Some apps (like Sonarr/Radarr) can be configured to save `.torrent` files to a folder
- qBittorrent watches that folder and automatically adds any `.torrent` files it finds
- This is an alternative to using the qBittorrent API

**You're not using BlackHole mode**, so this directory will remain empty. That's normal.

## Summary

✅ **DO:** Use magnet links - they work perfectly
✅ **DO:** Consider using qBittorrent's search plugin for convenience
❌ **DON'T:** Rely on "Download locally" - it's unreliable and unnecessary

The magnet link workflow is simpler, faster, and more reliable than downloading `.torrent` files.

