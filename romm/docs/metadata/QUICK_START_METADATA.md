# Quick Start: RomM Metadata Setup

## 🚀 Fastest Way to Get Metadata

### Option 1: Automated Setup Script

```bash
cd /home/brandon/projects/docker/romm
./setup-metadata.sh
```

This script will:
- Check if RomM is running
- Guide you through IGDB setup
- Show your ROM collection stats
- Provide next steps

### Option 2: Manual Setup

#### Step 1: Get IGDB Credentials (Required)

1. Go to https://dev.twitch.tv/console/apps
2. Log in with Twitch (create account if needed)
3. Click "Register Your Application"
4. Fill in:
   - Name: `RomM`
   - OAuth Redirect: `http://localhost`
   - Category: `Application Integration`
5. Click "Create"
6. Copy your **Client ID** and **Client Secret**

#### Step 2: Add Credentials to RomM

Edit `.env` file:
```bash
cd /home/brandon/projects/docker/romm
nano .env
```

Add your credentials:
```
IGDB_CLIENT_ID=your_client_id_here
IGDB_CLIENT_SECRET=your_client_secret_here
```

#### Step 3: Restart RomM

```bash
# Use kill method (docker restart doesn't work on this server)
PID=$(docker inspect romm --format '{{.State.Pid}}')
sudo kill $PID
sleep 3
cd /home/brandon/projects/docker/romm
docker-compose up -d
```

#### Step 4: Configure Additional Sources (Optional)

1. Open RomM: http://localhost:8080
2. Go to **Settings → Metadata Sources**
3. Add API keys:
   - **SteamGridDB**: Get from https://www.steamgriddb.com/profile/preferences/api
   - **RetroAchievements**: Get from https://retroachievements.org/

#### Step 5: Scan Your Library

1. In RomM, go to **Settings → Library**
2. Click **"Scan Library"**
3. Wait for the scan to complete
4. RomM will automatically:
   - Identify your ROMs
   - Download metadata from IGDB
   - Fetch artwork from SteamGridDB
   - Match games to their database entries

## 🎯 What Each Provider Does

| Provider | Purpose | Required? | Get API Key |
|----------|---------|-----------|-------------|
| **IGDB** | Game metadata (titles, descriptions, dates) | ✅ Yes | https://dev.twitch.tv/console/apps |
| **SteamGridDB** | High-quality artwork (covers, banners) | ⭐ Recommended | https://www.steamgriddb.com/profile/preferences/api |
| **RetroAchievements** | Achievement tracking | ⚪ Optional | https://retroachievements.org/ |

**Note**: Hasheous (ROM hash matching) requires building from source and is optional. RomM works great with just IGDB and SteamGridDB!

## 📊 Your ROM Collection

Location: `/mnt/boston/media/games/`

Platforms:
- arcade
- atari2600, atari7800
- dos
- FC (NES/Famicom)
- GB, GBC, GBA (Game Boy family)
- MD (Genesis/Mega Drive)
- mame2003, mame2010
- ms (Master System)

## 🐛 Troubleshooting

**No metadata downloading:**
```bash
# Check RomM logs
docker logs romm

# Verify IGDB credentials
docker exec romm env | grep IGDB
```

**ROMs not appearing:**
```bash
# Check if ROMs are in correct structure
ls -la /mnt/boston/media/games/

# Run reorganization script if needed
/home/brandon/projects/docker/scripts/reorganize-roms-for-romm.sh
```

**Artwork missing:**
- Add SteamGridDB API key in RomM settings
- Some games may not have artwork available
- You can manually upload artwork via RomM UI

## 📚 Resources

- Full setup guide: `METADATA_SETUP.md`
- RomM docs: https://docs.romm.app/
- RomM web UI: http://localhost:8080
- Hasheous UI: http://localhost:3001 (if enabled)

