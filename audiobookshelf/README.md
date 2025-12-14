# Audiobookshelf - Self-Hosted Audiobook Server

Audiobookshelf is an open-source self-hosted media server for your audiobooks and podcasts.

## Features

- **Multi-format Support**: MP3, M4A, M4B, FLAC, OGG, AAC, and more
- **Mobile Apps**: Companion Android and iOS apps with offline listening
- **Multi-user Support**: Custom permissions and progress tracking per user
- **Metadata Management**: Automatic lookup and application of metadata and cover art
- **Chapter Support**: Built-in chapter editor with chapter lookup
- **Podcast Support**: Search, add, and auto-download podcast episodes
- **Ebook Support**: Basic ebook support (EPUB, PDF, CBR, CBZ) with built-in reader
- **Audio Tools**: Embed metadata, merge files, create M4B audiobooks
- **Backup System**: Automated backup scheduling
- **RSS Feeds**: Open RSS feeds for audiobooks and podcast episodes

## Quick Start

1. **Set Environment Variables**:
   ```bash
   export DATA_LOCATION="/path/to/audiobookshelf/data"
   export AUDIOBOOKS_LOCATION="/path/to/your/audiobooks"
   export PODCASTS_LOCATION="/path/to/your/podcasts"  # Optional
   ```

2. **Start the Service**:
   ```bash
   docker-compose up -d
   ```

3. **Access the Web Interface**:
   - URL: http://localhost:13378
   - Create your admin account on first visit

## Directory Structure

### Audiobooks
Recommended directory structure:
```
/audiobooks/
├── Author Name/
│   ├── Book Title/
│   │   ├── Chapter 01.mp3
│   │   ├── Chapter 02.mp3
│   │   └── cover.jpg
│   └── Series Name/
│       └── Book 1 - Title/
│           └── audiobook.m4b
```

### Podcasts
Flat directory structure:
```
/podcasts/
├── Podcast Name/
│   ├── Episode 001.mp3
│   ├── Episode 002.mp3
│   └── cover.jpg
```

## Configuration

### Environment Variables
- `DATA_LOCATION`: Directory for config, database, and metadata
- `AUDIOBOOKS_LOCATION`: Path to your audiobook collection
- `PODCASTS_LOCATION`: Path to your podcast collection (optional)

### Volume Mappings
- `/config`: Database, users, libraries, settings
- `/metadata`: Cache, streams, covers, downloads, backups, logs
- `/audiobooks`: Your audiobook collection
- `/podcasts`: Your podcast collection

## Mobile Apps

- **Android**: Available on Google Play Store
- **iOS**: Available on App Store
- **Features**: Offline listening, progress sync, sleep timer, playback speed control

## Metadata Support

Audiobookshelf supports various metadata sources:
- **ID3 Tags**: Embedded in audio files
- **Folder Structure**: Parsed from directory and file names
- **External Files**: `desc.txt`, `reader.txt`, `.opf` files
- **Online Sources**: Automatic lookup from multiple providers

## Backup & Restore

Backups include:
- Database (users, libraries, progress)
- Metadata and cover images
- Configuration settings

Access backup management through the web interface under Settings > Backups.

## Troubleshooting

### Common Issues
1. **Permission Errors**: Ensure Docker has read/write access to mounted directories
2. **No Books Found**: Check directory structure and file permissions
3. **Metadata Missing**: Verify ID3 tags or add manual metadata

### Logs
Check container logs:
```bash
docker-compose logs -f audiobookshelf
```

## Links

- **Official Website**: https://www.audiobookshelf.org/
- **Documentation**: https://www.audiobookshelf.org/docs
- **GitHub**: https://github.com/advplyr/audiobookshelf
- **Discord**: Join the community Discord server
- **Demo**: https://audiobooks.dev/ (demo/demo)

## Port Information

- **Web Interface**: 13378 (mapped to container port 80)
- **Protocol**: HTTP (use reverse proxy for HTTPS)

## Resource Usage

- **CPU**: 0.5-2.0 cores (depending on transcoding needs)
- **Memory**: 512MB-2GB (scales with library size)
- **Storage**: Minimal for app, depends on your media collection
