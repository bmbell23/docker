# RomM Metadata Providers Setup

This guide will help you set up metadata providers for your ROM collection in RomM.

## 🎯 The Chef's Choice Setup

The recommended setup includes:
- **Hasheous** - ROM identification via hash matching
- **IGDB** - Game metadata (titles, descriptions, release dates)
- **SteamGridDB** - Artwork (covers, screenshots, banners)
- **RetroAchievements** - Achievement data

## 📋 Step-by-Step Setup

### 1. IGDB (Internet Game Database)

IGDB provides game metadata like titles, descriptions, release dates, and genres.

**Get API Credentials:**
1. Go to https://dev.twitch.tv/console/apps
2. Log in with your Twitch account (create one if needed)
3. Click "Register Your Application"
4. Fill in:
   - **Name**: RomM (or any name)
   - **OAuth Redirect URLs**: `http://localhost`
   - **Category**: Application Integration
5. Click "Create"
6. You'll get:
   - **Client ID** - Copy this
   - **Client Secret** - Click "New Secret" and copy it

**Add to RomM:**
- Already configured in `docker-compose.yml` (lines 17-18)
- Just need to add your credentials to the environment variables

### 2. SteamGridDB

SteamGridDB provides high-quality artwork for games.

**Get API Key:**
1. Go to https://www.steamgriddb.com/
2. Create an account or log in
3. Go to https://www.steamgriddb.com/profile/preferences/api
4. Generate an API key
5. Copy the key

**Add to RomM:**
- Configure via RomM web UI: Settings → Metadata Sources → SteamGridDB

### 3. Hasheous (Optional but Recommended)

Hasheous helps identify ROMs by their hash values, making metadata matching more accurate.

**Setup:**
- Hasheous is a separate service you can run alongside RomM
- See the docker-compose extension below

### 4. RetroAchievements (Optional)

RetroAchievements adds achievement tracking to your retro games.

**Get API Key:**
1. Go to https://retroachievements.org/
2. Create an account
3. Go to Settings → Keys
4. Generate an API key

**Add to RomM:**
- Configure via RomM web UI: Settings → Integrations → RetroAchievements

## 🚀 Quick Start

### Update Environment Variables

Edit the `.env` file or update `docker-compose.yml` with your IGDB credentials:

```bash
cd /home/brandon/projects/docker/romm
# Edit docker-compose.yml and add your IGDB credentials
```

### Restart RomM

```bash
# Use kill method (docker restart doesn't work on this server)
PID=$(docker inspect romm --format '{{.State.Pid}}')
sudo kill $PID
sleep 3
cd /home/brandon/projects/docker/romm
docker-compose up -d
```

### Configure in Web UI

1. Open RomM: http://localhost:8080
2. Go to Settings → Metadata Sources
3. Add your API keys for:
   - SteamGridDB
   - RetroAchievements (optional)
4. Save settings

### Scan Your Library

1. Go to Settings → Library
2. Click "Scan Library"
3. RomM will:
   - Scan all ROMs in `/mnt/boston/media/games/`
   - Match them against IGDB database
   - Download artwork from SteamGridDB
   - Fetch metadata

## 📁 Your ROM Structure

Your games are located at: `/mnt/boston/media/games/`

Platforms detected:
- arcade
- atari2600
- atari7800
- dos
- FC (Famicom/NES)
- GB (Game Boy)
- GBA (Game Boy Advance)
- GBC (Game Boy Color)
- MD (Mega Drive/Genesis)
- mame2003
- mame2010
- ms (Master System)

## 🔧 Troubleshooting

**ROMs not showing up:**
- Make sure ROMs are in platform subdirectories
- Check that platform names match RomM's expected names
- Run the reorganization script if needed: `/home/brandon/projects/docker/scripts/reorganize-roms-for-romm.sh`

**Metadata not downloading:**
- Verify API keys are correct
- Check RomM logs: `docker logs romm`
- Try manual search for specific games

**Artwork missing:**
- SteamGridDB may not have artwork for all games
- You can manually upload artwork via RomM UI

## 📚 Resources

- RomM Documentation: https://docs.romm.app/
- IGDB API: https://api-docs.igdb.com/
- SteamGridDB: https://www.steamgriddb.com/
- RetroAchievements: https://retroachievements.org/

