# ROMM Library Cleanup - Summary

## ✅ What's Been Created

I've created a comprehensive cleanup system for your ROMM game library to address:

1. **Weird special characters** preventing metadata matching
2. **Duplicate games** (USA vs Europe versions)
3. **Non-playable files** (zip archives, multi-disc games, BIOS files)

## 📁 New Files Created

### Main Scripts

1. **`cleanup-all.sh`** ⭐ **START HERE**
   - All-in-one script that runs everything
   - Interactive with confirmations
   - Safest and easiest option

2. **`cleanup-preview.sh`**
   - Shows what will be cleaned WITHOUT making changes
   - Safe to run anytime
   - Good for checking before cleanup

3. **`comprehensive-cleanup.py`**
   - Removes duplicate games (keeps USA over Europe/Japan)
   - Removes non-playable files (Disc 2+, BIOS)
   - Removes beta/proto/demo versions when release exists

4. **`fix-special-characters.py`**
   - Fixes filenames with language tags like (En,Fr,De,Es,It)
   - Cleans up problematic characters
   - Helps metadata matching work better

### Documentation

5. **`CLEANUP_GUIDE.md`**
   - Detailed guide with examples
   - Explains what gets kept vs deleted
   - Troubleshooting section

6. **`CLEANUP_QUICK_START.md`**
   - Quick reference
   - One-page guide to get started

7. **`CLEANUP_SUMMARY.md`** (this file)
   - Overview of what's been created

## 🎯 Current State of Your Library

**Total games:** 8,372

**Issues found:**
- 826 (USA, Europe) duplicates
- 102 regional duplicates (same game, different regions)
- 2 multi-disc games (Disc 2+)
- 2 BIOS files
- 191 beta/proto/demo versions
- 1,373 games with special characters
- 3,792 games without IGDB metadata

**Estimated cleanup:** ~1,123 games will be removed
**Final library:** ~7,249 games (cleaned and deduplicated)

## 🚀 How to Use

### Option 1: Quick & Easy (Recommended)

```bash
cd /home/brandon/projects/docker/romm
./cleanup-all.sh
```

Follow the prompts. It will:
1. Show preview
2. Ask for confirmation
3. Clean everything
4. Remind you to rescan

### Option 2: Preview First

```bash
cd /home/brandon/projects/docker/romm
./cleanup-preview.sh
```

Review the output, then run `./cleanup-all.sh` when ready.

### Option 3: Manual Control

```bash
# Step 1: Preview
./cleanup-preview.sh

# Step 2: Remove duplicates
python3 comprehensive-cleanup.py

# Step 3: Fix filenames
python3 fix-special-characters.py

# Step 4: Rescan in ROMM web UI
```

## ⚠️ Important: After Cleanup

**YOU MUST RESCAN YOUR LIBRARY:**

1. Go to http://localhost:8080
2. Click Settings (gear icon)
3. Go to Library tab
4. Click "Scan Library"
5. Wait for completion

This updates ROMM's database and fetches metadata for cleaned games.

## 🛡️ Safety Features

- **Preview mode** - See what will happen before it happens
- **Confirmation prompts** - Script asks before deleting
- **Database only** - Only modifies database, files stay on disk
- **Detailed logging** - Shows exactly what's being done
- **No data loss** - Can always rescan to rebuild database

## 📊 What Gets Removed

### ✅ Kept (Priority Order)

1. USA versions - `(USA)` or `(U)`
2. World versions - `(World)`
3. Europe versions - `(Europe)` or `(EU)` (if no USA exists)
4. Release versions (over beta/proto)

### ❌ Removed

1. (USA, Europe) duplicates when separate versions exist
2. Europe/Japan versions when USA version exists
3. Multi-disc games (Disc 2, 3, etc.)
4. BIOS files
5. Beta/Proto/Demo versions when release exists
6. Hacks and bad dumps

### ⚠️ Reported (Not Deleted)

- Games with special characters (you can fix with `fix-special-characters.py`)

## 🔧 Examples

**Before cleanup:**
```
- Zelda (USA).gba
- Zelda (Europe).gba
- Zelda (USA, Europe).gba
- Final Fantasy VII (Disc 1)
- Final Fantasy VII (Disc 2)
- Final Fantasy VII (Disc 3)
- Mario (USA) (Beta).gba
- Mario (USA).gba
```

**After cleanup:**
```
- Zelda (USA).gba
- Final Fantasy VII (Disc 1)
- Mario (USA).gba
```

## 📝 Next Steps

1. **Run the cleanup:**
   ```bash
   cd /home/brandon/projects/docker/romm
   ./cleanup-all.sh
   ```

2. **Rescan your library** in ROMM web UI

3. **Check the results** - browse your library

4. **Enjoy!** Your library should now have:
   - No duplicates
   - Better metadata matching
   - Only playable games
   - ~7,249 quality games

## 🆘 Troubleshooting

**"No module named 'mysql.connector'"**
```bash
pip3 install mysql-connector-python
```

**"Access denied"**
```bash
docker ps | grep romm-db  # Make sure DB is running
```

**Games still showing after cleanup**
- Run a full rescan in ROMM

**Want to undo?**
- Just rescan your library - ROMM will re-add all games from disk
- The cleanup only modifies the database, not the actual files

## 📚 More Information

- See `CLEANUP_GUIDE.md` for detailed documentation
- See `CLEANUP_QUICK_START.md` for quick reference
- Run `./cleanup-preview.sh` to see what will be cleaned

