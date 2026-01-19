# Get Started with RomM Metadata

## 🎯 Your Mission

Get beautiful metadata and artwork for your **4,642 ROMs** across 13 platforms!

## ⚡ Quick Start (3 Steps)

### Step 1: Get IGDB API Credentials (5 minutes)

1. Go to **https://dev.twitch.tv/console/apps**
2. Log in with Twitch (create free account if needed)
3. Click **"Register Your Application"**
4. Fill in:
   - **Name**: `RomM` (or anything)
   - **OAuth Redirect URLs**: `http://localhost`
   - **Category**: `Application Integration`
5. Click **"Create"**
6. Copy your **Client ID** and **Client Secret**

### Step 2: Add Credentials to RomM

```bash
cd /home/brandon/projects/docker/romm
nano .env
```

Update these lines with your credentials:
```
IGDB_CLIENT_ID=your_client_id_here
IGDB_CLIENT_SECRET=your_client_secret_here
```

Save and exit (Ctrl+X, then Y, then Enter)

### Step 3: Restart RomM

```bash
# Use the kill method (docker restart doesn't work on this server)
PID=$(docker inspect romm --format '{{.State.Pid}}')
sudo kill $PID
sleep 3
docker-compose up -d
```

## 🎨 Step 4: Add SteamGridDB (Optional but Recommended)

For high-quality artwork:

1. Go to **https://www.steamgriddb.com/**
2. Create account (free)
3. Go to **https://www.steamgriddb.com/profile/preferences/api**
4. Generate API key
5. In RomM web UI (http://localhost:8080):
   - Go to **Settings → Metadata Sources**
   - Add your SteamGridDB API key
   - Save

## 📚 Step 5: Scan Your Library

1. Open RomM: **http://localhost:8080**
2. Go to **Settings → Library**
3. Click **"Scan Library"**
4. Wait for the scan to complete (may take a while with 4,642 ROMs!)

RomM will:
- ✅ Identify all your ROMs
- ✅ Download game metadata from IGDB
- ✅ Fetch artwork from SteamGridDB
- ✅ Organize everything beautifully

## 🎮 Your Collection

```
GB (Game Boy):           1,354 ROMs
GBA (Game Boy Advance):    879 ROMs
MD (Genesis):              848 ROMs
MAME 2003:                 410 ROMs
FC (NES):                  387 ROMs
Master System:             291 ROMs
Arcade:                    247 ROMs
Atari 7800:                127 ROMs
+ 5 more platforms
─────────────────────────────────
TOTAL:                   4,642 ROMs
```

## 🔧 Useful Commands

```bash
# Check ROM statistics
cd /home/brandon/projects/docker/romm
./check-roms.sh

# View RomM logs
docker logs romm -f

# Restart RomM (after config changes)
PID=$(docker inspect romm --format '{{.State.Pid}}')
sudo kill $PID
sleep 3
cd /home/brandon/projects/docker/romm
docker-compose up -d

# Check if RomM is running
docker ps | grep romm
```

## 🐛 Troubleshooting

**Metadata not downloading:**
```bash
# Check if IGDB credentials are set
docker exec romm env | grep IGDB

# View logs for errors
docker logs romm --tail 50
```

**ROMs not showing up:**
- Make sure you've scanned the library in RomM UI
- Check Settings → Library → Scan Library

**RomM not starting:**
```bash
# Check logs
docker logs romm

# Check database
docker logs romm-db
```

## 📚 More Information

- **Full Guide**: `METADATA_SETUP.md`
- **README**: `README.md`
- **RomM Docs**: https://docs.romm.app/
- **RomM Web UI**: http://localhost:8080

## 🎉 That's It!

Once you've completed these steps, your ROM collection will have:
- ✅ Proper game titles (not just filenames)
- ✅ Descriptions and storylines
- ✅ Release dates and publishers
- ✅ Cover art and screenshots
- ✅ Genres and ratings

Enjoy your beautifully organized game library! 🎮

