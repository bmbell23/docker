# ROMM Cleanup - Quick Start

## 🎯 What This Does

Cleans up your ROMM game library by removing:
- ✅ Duplicate games (USA vs Europe versions)
- ✅ Non-playable files (Disc 2+, BIOS files)
- ✅ Problematic filenames that prevent metadata matching

## 🚀 How to Run

**One command does it all:**

```bash
cd /home/brandon/projects/docker/romm
./cleanup-all.sh
```

That's it! The script will:
1. Show you what will be cleaned
2. Ask for confirmation
3. Clean up your library
4. Tell you to rescan

## 📊 What to Expect

**Current library:** 8,372 games

**After cleanup:** ~7,249 games

**Removed:**
- ~826 (USA, Europe) duplicates
- ~102 regional duplicates
- ~4 non-playable files
- ~191 beta/proto/demo versions

## ⚠️ Important

**After cleanup, you MUST rescan:**
1. Go to http://localhost:8080
2. Settings → Library → Scan Library
3. Wait for completion

## 📖 More Info

See `CLEANUP_GUIDE.md` for detailed information.

## 🆘 Need Help?

**Preview only (no changes):**
```bash
./cleanup-preview.sh
```

**Run individual steps:**
```bash
python3 comprehensive-cleanup.py  # Remove duplicates
python3 fix-special-characters.py  # Fix filenames
```

