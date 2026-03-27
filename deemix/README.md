# 🎵 Deemix Music Downloader

Deemix is a music downloader that downloads from **Deezer** (not Spotify). It provides high-quality music downloads without API rate limits.

## 🚀 Quick Start

### Start the Container

```bash
cd /home/brandon/projects/docker/deemix
docker compose up -d
```

### Access the Web Interface

Open your browser and go to:
- **http://dockerhost:6595**
- Or: **http://100.69.184.113:6595**

## 🎯 How to Use

### Option 1: Download from Deezer Links

1. Go to [Deezer](https://www.deezer.com/)
2. Find a song, album, or playlist
3. Copy the URL
4. Paste it into the Deemix web interface
5. Click Download

### Option 2: Import Spotify Playlists

Deemix can import Spotify playlists and find matching songs on Deezer!

1. Copy a Spotify playlist URL
2. Paste it into Deemix
3. It will automatically find matching tracks on Deezer
4. Download them in high quality

## ✨ Features

- ✅ **No rate limits** - Download as much as you want
- ✅ **High quality** - FLAC, 320kbps MP3, and more
- ✅ **Spotify playlist import** - Automatically matches Spotify tracks
- ✅ **Full metadata** - Artist, album, cover art, lyrics
- ✅ **Web interface** - Easy to use, no command line needed
- ✅ **Automatic organization** - Files organized by artist/album
- ✅ **Works with your media servers** - Files appear in Navidrome, Jellyfin, Beets

## 📁 Download Location

All downloads go to: `/mnt/boston/media/music/`

## 🔐 Authentication

### First Time Setup

Deemix requires an **ARL token** from Deezer (not username/password):

1. Go to [deezer.com](https://www.deezer.com/) and log in
2. Press **F12** to open browser developer tools
3. Go to **Application** tab → **Cookies** → **https://www.deezer.com**
4. Find the cookie named **arl** and copy its value
5. In Deemix settings (⚙️), paste the ARL token
6. Done!

**📖 Detailed guide:** See [HOW-TO-LOGIN.md](HOW-TO-LOGIN.md) for step-by-step instructions with screenshots.

**Note:** You can use a free Deezer account. You don't need a premium subscription!

## 🛠️ Management Commands

```bash
# View logs
docker logs deemix

# Restart
cd /home/brandon/projects/docker/deemix
docker compose restart

# Stop
docker compose down

# Start
docker compose up -d

# Update to latest version
docker compose pull
docker compose up -d
```

## 💡 Tips

- **Quality Settings:** In the web interface settings, you can choose download quality (FLAC, 320kbps, etc.)
- **Spotify Playlists:** Just paste a Spotify URL and Deemix will automatically find matching tracks on Deezer
- **Batch Downloads:** You can queue multiple albums/playlists at once
- **Automatic Tagging:** All files include proper metadata and album art

## 🆚 Deemix vs spotDL

| Feature | Deemix | spotDL |
|---------|--------|--------|
| Source | Deezer | YouTube Music |
| Quality | FLAC, 320kbps | 128-320kbps MP3 |
| Rate Limits | None | Very restrictive |
| Authentication | Free Deezer account | Spotify API (optional) |
| Spotify Import | ✅ Yes | ✅ Yes |

## ⚠️ Notes

- Deemix downloads from Deezer, not Spotify
- Some songs may not be available if they're not on Deezer
- You need a Deezer account (free works fine)
- Downloads are for personal use only

## 📚 More Information

- [Deemix GitHub](https://github.com/bambanah/deemix)
- [Deezer](https://www.deezer.com/)

