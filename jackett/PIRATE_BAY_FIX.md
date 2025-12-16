# The Pirate Bay Fix - Complete Solution

## Problem Summary
- **Test passes** ✅ but **actual searches fail** ❌
- Error: `Selector "num_files" didn't match`
- Root cause: TPB's API doesn't include the `num_files` field that Jackett expects

## ✅ Solution Applied

I've created a **fixed version** of The Pirate Bay indexer that removes the problematic `files` field.

### What was fixed:
- Removed the `files: selector: num_files` line from the indexer definition
- Created a custom indexer: **"The Pirate Bay (Fixed)"**
- ID: `thepiratebay-fixed`

## 🔧 Next Steps (Manual)

**You need to do this in the Jackett web UI:**

1. **Open Jackett:** http://100.123.154.40:9117

2. **Remove the broken indexer:**
   - Find "The Pirate Bay" in your indexer list
   - Click the trash/delete icon to remove it

3. **Add the fixed indexer:**
   - Click "Add indexer"
   - Search for "The Pirate Bay (Fixed)"
   - Click the "+" button to add it
   - Configure if needed (usually no config required)

4. **Test the fixed indexer:**
   - Click the wrench icon next to "The Pirate Bay (Fixed)"
   - Click "Test" - should show success
   - Try an actual search - should work without errors

## 🔍 Verification

After adding the fixed indexer, test it with a search:
- Search for something common like "ubuntu"
- Should return results without the `num_files` error

## 🚨 If It Still Doesn't Work

Use these **proven alternatives** instead:

### Best Alternatives:
1. **TorrentGalaxy** - Excellent TPB replacement
2. **LimeTorrents** - Very reliable
3. **YTS** - Movies only, high quality
4. **EZTV** - TV shows
5. **Zooqle** - Good general content

### How to add alternatives:
1. In Jackett, click "Add indexer"
2. Search for "TorrentGalaxy"
3. Add it and test
4. Repeat for other alternatives

## 📁 Files Created
- `/config/cardigann/definitions/thepiratebay-fixed.yml` - Fixed indexer definition
- `fix-piratebay-definition.sh` - Script that created the fix

## 🔧 Technical Details
The original indexer tried to parse:
```yaml
files:
  selector: num_files  # ❌ This field doesn't exist in TPB's JSON
```

The fixed version removes this field entirely, so Jackett doesn't try to parse it.
