# Audiobookshelf Quick Start Guide

## 🎧 Your Audiobookshelf server is now running!

### Access Your Server
- **Web Interface**: http://localhost:13378
- **Status**: ✅ Running and accessible

### First Time Setup
1. **Open your browser** and go to http://localhost:13378
2. **Create your admin account** on the first visit
3. **Set up your first library**:
   - Click "Add Library" 
   - Choose "Books" as the media type
   - Set the folder path to `/audiobooks`
   - Click "Add Library"

### Directory Structure
Your audiobooks should be organized in `/mnt/boston/media/audiobooks/` like this:
```
/mnt/boston/media/audiobooks/
├── Author Name/
│   ├── Book Title/
│   │   ├── Chapter 01.mp3
│   │   ├── Chapter 02.mp3
│   │   └── cover.jpg
│   └── Series Name/
│       └── Book 1 - Title/
│           └── audiobook.m4b
```

### Adding Audiobooks
1. Copy your audiobook files to `/mnt/boston/media/audiobooks/`
2. Organize them by author and book title
3. In Audiobookshelf web interface, go to your library
4. Click the "Scan" button to detect new books

### Supported Formats
- **Audio**: MP3, M4A, M4B, FLAC, OGG, AAC, WAV
- **Ebooks**: EPUB, PDF, CBR, CBZ (basic support)

### Mobile Apps
- **Android**: Search "Audiobookshelf" on Google Play Store
- **iOS**: Search "Audiobookshelf" on App Store
- **Server Address**: Use your server's IP address and port 13378

### Container Management
```bash
# View logs
cd /home/brandon/projects/docker/audiobookshelf
docker-compose logs -f

# Restart container
docker-compose restart

# Stop container
docker-compose down

# Start container
docker-compose up -d
```

### Data Locations
- **Config & Database**: `/home/brandon/projects/docker/audiobookshelf/data/`
- **Audiobooks**: `/mnt/boston/media/audiobooks/`
- **Podcasts**: `/mnt/boston/media/podcasts/`

### Next Steps
1. Visit http://localhost:13378 to set up your admin account
2. Create your first library pointing to `/audiobooks`
3. Add some audiobook files to `/mnt/boston/media/audiobooks/`
4. Scan your library to import the books
5. Download the mobile app for listening on the go!

### Troubleshooting
- **Can't access web interface**: Check if container is running with `docker ps`
- **Books not showing**: Verify file permissions and run a library scan
- **Mobile app can't connect**: Use your server's IP address, not localhost

Enjoy your self-hosted audiobook server! 🎧📚
