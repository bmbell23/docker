# RomM - ROM Manager

RomM is a web-based ROM manager that helps you organize, browse, and manage your retro game collection.

## 📊 Your Collection

**Total ROMs: 4,642** across 13 platforms:

| Platform | ROMs | Description |
|----------|------|-------------|
| GB | 1,354 | Game Boy |
| GBA | 879 | Game Boy Advance |
| MD | 848 | Mega Drive / Genesis |
| mame2003 | 410 | MAME 2003 |
| FC | 387 | Famicom / NES |
| ms | 291 | Master System |
| arcade | 247 | Arcade |
| atari7800 | 127 | Atari 7800 |
| mame2010 | 39 | MAME 2010 |
| neogeo | 34 | Neo Geo |
| SFC | 14 | Super Famicom / SNES |
| PS | 8 | PlayStation |
| GBC | 4 | Game Boy Color |

## 🚀 Quick Start

### Access RomM
- **Web UI**: http://localhost:8080
- **Location**: `/home/brandon/projects/docker/romm`
- **ROMs**: `/mnt/boston/media/games/`

### Set Up Metadata (Recommended!)

Run the automated setup:
```bash
cd /home/brandon/projects/docker/romm
./scripts/utils/setup-metadata.sh
```

Or see the quick start guide:
```bash
cat docs/metadata/QUICK_START_METADATA.md
```

## 🎯 What is Metadata?

Metadata includes:
- **Game titles** (proper names, not just filenames)
- **Descriptions** and storylines
- **Release dates** and publishers
- **Cover art** and screenshots
- **Genres** and ratings
- **Achievement data** (optional)

Without metadata, you'll just see filenames. With metadata, you get a beautiful game library!

## 📋 Metadata Providers

### Required: IGDB
- **What**: Game information (titles, descriptions, dates)
- **Get API Key**: https://dev.twitch.tv/console/apps
- **Setup**: Add to `.env` file or use `setup-metadata.sh`

### Recommended: SteamGridDB
- **What**: High-quality artwork (covers, banners, screenshots)
- **Get API Key**: https://www.steamgriddb.com/profile/preferences/api
- **Setup**: Configure in RomM Settings → Metadata Sources

### Recommended: Hasheous
- **What**: ROM identification via hash matching
- **Get API Key**: Not needed (self-hosted)
- **Setup**: Use `docker-compose.with-hasheous.yml`

### Optional: RetroAchievements
- **What**: Achievement tracking for retro games
- **Get API Key**: https://retroachievements.org/
- **Setup**: Configure in RomM Settings → Integrations

## 🔧 Management Commands

```bash
# Start RomM
docker-compose up -d

# Stop RomM
docker-compose down

# Restart RomM (after config changes)
docker-compose restart romm

# View logs
docker logs romm -f

# Check ROM statistics
./scripts/utils/check-roms.sh

# Update RomM
docker-compose pull
docker-compose up -d
```

## 📁 Directory Structure

```
/home/brandon/projects/docker/romm/
├── docs/
│   ├── cleanup/         # Cleanup and deduplication guides
│   ├── metadata/        # Metadata setup documentation
│   └── GET_STARTED.md   # Getting started guide
├── scripts/
│   ├── cleanup/         # ROM cleanup and deduplication scripts
│   ├── fixes/           # ROM fixing and maintenance scripts
│   └── utils/           # Utility scripts (check, export, setup)
├── config/              # Database and settings
├── resources/           # Downloaded artwork and metadata (created at runtime)
├── docker-compose.yml
└── README.md

/mnt/boston/media/games/
├── arcade/          # Arcade ROMs
├── FC/              # NES/Famicom ROMs
├── GB/              # Game Boy ROMs
├── GBA/             # Game Boy Advance ROMs
└── ...              # Other platforms
```

## 🎮 Using RomM

1. **Browse your collection** - View all games with artwork
2. **Search** - Find games by name, platform, or genre
3. **Download** - Download ROMs directly from the web UI
4. **Organize** - Create collections and favorites
5. **Metadata** - Edit game information and artwork
6. **Multi-user** - Share your collection with family/friends

## 📚 Documentation

### Local Documentation
- **Getting Started**: `docs/GET_STARTED.md` - Introduction to RomM
- **Metadata Setup**:
  - `docs/metadata/QUICK_START_METADATA.md` - Fast setup guide
  - `docs/metadata/METADATA_SETUP.md` - Detailed metadata setup
- **Cleanup Guides**:
  - `docs/cleanup/CLEANUP_QUICK_START.md` - Quick cleanup guide
  - `docs/cleanup/CLEANUP_GUIDE.md` - Comprehensive cleanup guide
  - `docs/cleanup/CLEANUP_SUMMARY.md` - Cleanup summary

### Scripts
- **Utilities**: `scripts/utils/` - Check ROMs, export data, setup metadata
- **Cleanup**: `scripts/cleanup/` - Remove duplicates and clean library
- **Fixes**: `scripts/fixes/` - Fix ROM structure, names, and special characters

### External Resources
- **Official Docs**: https://docs.romm.app/
- **GitHub**: https://github.com/rommapp/romm

## 🐛 Troubleshooting

**RomM not starting:**
```bash
docker logs romm
docker logs romm-db
```

**ROMs not showing:**
```bash
# Check ROM directory
ls -la /mnt/boston/media/games/

# Scan library in RomM UI
# Settings → Library → Scan Library
```

**Metadata not downloading:**
```bash
# Verify IGDB credentials
docker exec romm env | grep IGDB

# Check logs
docker logs romm -f
```

## 🔐 Security

- Default auth secret key should be changed in `docker-compose.yml`
- RomM is accessible on port 8080 (local network only)
- Database is not exposed externally
- ROMs are mounted read-only for safety

## 🎉 Next Steps

1. ✅ RomM is running at http://localhost:8080
2. 🔑 Set up IGDB credentials (run `./scripts/utils/setup-metadata.sh`)
3. 🎨 Add SteamGridDB API key (optional but recommended)
4. 📚 Scan your library (Settings → Library → Scan)
5. 🎮 Enjoy your organized game collection!

