# ROMM Library Cleanup Guide

This guide will help you clean up your ROMM game library by removing:
- Duplicate regional versions (USA vs Europe)
- Non-playable files (multi-disc games, BIOS files)
- Games with problematic filenames

## 🚀 Quick Start (Recommended)

Run the all-in-one cleanup script:

```bash
cd /home/brandon/projects/docker/romm
./cleanup-all.sh
```

This will:
1. Show you a preview of what will be cleaned
2. Ask for confirmation before making changes
3. Remove duplicates and non-playable files
4. Fix filenames with special characters
5. Remind you to rescan your library

**That's it!** The script handles everything for you.

---

## 📖 Manual Step-by-Step (Advanced)

If you prefer to run each step manually:

### 🔍 Step 1: Preview What Will Be Cleaned

First, run the preview script to see what will be removed **without actually deleting anything**:

```bash
cd /home/brandon/projects/docker/romm
./cleanup-preview.sh
```

This will show you:
- How many (USA, Europe) duplicates exist
- How many regional duplicates (same game, different regions)
- Non-playable files (Disc 2+, BIOS)
- Games with special characters
- Games without metadata
- Undesirable versions (Beta, Proto, Demo, Hacks)

## 🧹 Step 2: Run the Cleanup

Once you've reviewed the preview and are ready to proceed:

```bash
cd /home/brandon/projects/docker/romm
python3 comprehensive-cleanup.py
```

The script will:
1. Ask for confirmation before deleting anything
2. Remove (USA, Europe) duplicates when separate USA or Europe versions exist
3. Remove regional duplicates (keeping USA versions over Europe/Japan)
4. Remove non-playable files (Disc 2+, BIOS files)
5. Report games with special characters (but won't delete them)

### What Gets Kept vs Deleted

**Priority Order (keeps highest priority):**
1. ✅ USA versions - `(USA)` or `(U)`
2. ✅ World versions - `(World)`
3. ⚠️ Europe versions - `(Europe)` or `(EU)` - deleted if USA exists
4. ⚠️ Japan versions - `(Japan)` or `(J)` - deleted if USA/Europe exists
5. ❌ Beta/Proto/Demo versions - always deleted if release version exists
6. ❌ Hacks/Bad dumps - always deleted if good dump exists

**Examples:**
- If you have both `Zelda (USA).gba` and `Zelda (Europe).gba`, keeps USA, deletes Europe
- If you have `Zelda (USA, Europe).gba` and `Zelda (USA).gba`, deletes the combined version
- If you have `Final Fantasy VII (Disc 1)`, `(Disc 2)`, `(Disc 3)`, keeps Disc 1, deletes 2 and 3

## 🔄 Step 3: Rescan Your Library

After cleanup, you **must** rescan your library in ROMM:

1. Go to http://localhost:8080
2. Click **Settings** (gear icon)
3. Go to **Library** tab
4. Click **"Scan Library"**
5. Wait for the scan to complete

This will:
- Update the database to reflect deleted games
- Try to fetch metadata for games that didn't have it
- Update cover art and game information

## 📊 What the Cleanup Does

### 1. (USA, Europe) Duplicates

Many games have a combined `(USA, Europe)` version. If you also have separate USA or Europe versions, the combined one is redundant.

**Before:**
- Zelda (USA).gba
- Zelda (Europe).gba
- Zelda (USA, Europe).gba ← Deleted

**After:**
- Zelda (USA).gba
- Zelda (Europe).gba

### 2. Regional Duplicates

When you have the same game in multiple regions, keeps USA version.

**Before:**
- Mario (USA).gba ← Kept
- Mario (Europe).gba ← Deleted
- Mario (Japan).gba ← Deleted

**After:**
- Mario (USA).gba

### 3. Non-Playable Files

Removes files that aren't playable ROMs:

**Deleted:**
- Final Fantasy VII (Disc 2) ← Only Disc 1 is needed
- Final Fantasy VII (Disc 3)
- [BIOS] PlayStation.bin
- System Files.zip

### 4. Special Characters

Games with special characters in filenames are **reported but not deleted**. These might prevent metadata matching:

**Examples:**
- `Alex Ferguson's Player Manager 2002 (Europe) (En,Fr,De,Es,It,Nl).gba`
- `Archer Maclean's 3D Pool (USA).gba`

The script will list these so you can manually review them.

## 🛡️ Safety Features

- **Preview mode**: Run `cleanup-preview.sh` first to see what will happen
- **Confirmation required**: The cleanup script asks for confirmation before deleting
- **Database only**: Only removes entries from the database (files remain on disk)
- **Detailed logging**: Shows exactly what's being deleted

## 📝 Manual Cleanup (Optional)

If you want to manually review games before cleanup:

### Export games without covers:
```bash
./export-games-without-covers.sh
cat games-without-covers.txt
```

### Check specific platforms:
```bash
docker exec romm-db mariadb -uromm-user -promm-password romm -e "
SELECT p.name, COUNT(*) as count 
FROM roms r 
JOIN platforms p ON r.platform_id = p.id 
GROUP BY p.name 
ORDER BY count DESC;
"
```

### Find games with specific patterns:
```bash
docker exec romm-db mariadb -uromm-user -promm-password romm -e "
SELECT fs_name FROM roms WHERE fs_name LIKE '%pattern%';
"
```

## 🔧 Troubleshooting

### "No module named 'mysql.connector'"

Install the MySQL connector:
```bash
pip3 install mysql-connector-python
```

### "Access denied for user"

Make sure the ROMM database container is running:
```bash
docker ps | grep romm-db
```

### Games still showing after cleanup

Run a full rescan in ROMM (Settings → Library → Scan Library)

## 📚 Available Scripts

### Main Scripts (Use These)

- **`cleanup-all.sh`** - ⭐ All-in-one cleanup script (RECOMMENDED)
- **`cleanup-preview.sh`** - Preview what will be cleaned (safe, no changes)
- **`comprehensive-cleanup.py`** - Remove duplicates and non-playable files
- **`fix-special-characters.py`** - Fix filenames with special characters

### Utility Scripts

- `export-games-without-covers.sh` - Export list of games without metadata
- `check-roms.sh` - Count ROMs by platform

### Old Scripts (Deprecated)

- `cleanup-region-duplicates.py` - Use `comprehensive-cleanup.py` instead
- `cleanup-library.sh` - Use `cleanup-all.sh` instead

## ⚠️ Important Notes

1. **Backup first** if you're unsure (though the script only modifies the database)
2. **Run preview first** to see what will be deleted
3. **Rescan after cleanup** to update ROMM
4. **Special characters** are reported but not automatically fixed (manual review recommended)

## 🎯 Expected Results

Based on the current library (8,372 games):

- **~826** (USA, Europe) duplicates removed
- **~102** regional duplicates removed
- **~4** non-playable files removed (Disc 2+, BIOS)
- **~191** undesirable versions removed (Beta, Proto, Demo)
- **~1,373** games with special characters (reported, not deleted)

**Final library: ~7,249 games** (cleaned and deduplicated)

