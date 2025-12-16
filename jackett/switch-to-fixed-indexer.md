# URGENT: Switch to Fixed Pirate Bay Indexer

## ❌ Current Problem
You're still using the **BROKEN** "The Pirate Bay" indexer, not the fixed one!

The error shows: `Exception (thepiratebay)` - this is the broken original indexer.

## ✅ Solution: Switch to Fixed Version

### Step 1: Open Jackett Web UI
Go to: **http://100.123.154.40:9117**

### Step 2: Remove the Broken Indexer
1. Look for **"The Pirate Bay"** in your indexer list
2. Click the **trash/delete icon** (🗑️) next to it
3. Confirm deletion

### Step 3: Add the Fixed Indexer
1. Click **"Add indexer"** button
2. In the search box, type: **"pirate bay fixed"**
3. You should see: **"The Pirate Bay (Fixed)"**
4. Click the **"+"** button to add it

### Step 4: Verify the Switch
After adding, you should see:
- **Name:** "The Pirate Bay (Fixed)" 
- **ID:** thepiratebay-fixed (you can see this in the URL when you click on it)

### Step 5: Test the Fixed Indexer
1. Click the **wrench icon** (🔧) next to "The Pirate Bay (Fixed)"
2. Click **"Test"** button
3. Should show: "Test successful"
4. Try a real search - should work without `num_files` error

## 🔍 How to Tell Which One You're Using

**BROKEN (old):**
- Name: "The Pirate Bay"
- Error logs show: `Exception (thepiratebay)`

**FIXED (new):**
- Name: "The Pirate Bay (Fixed)"
- Error logs would show: `Exception (thepiratebay-fixed)` (if any)

## 🚨 If You Can't Find the Fixed Version

If "The Pirate Bay (Fixed)" doesn't appear in the indexer list:

1. Restart Jackett: `docker-compose restart jackett`
2. Wait 10 seconds
3. Refresh the web UI
4. Try adding again

## 🎯 Alternative: Use TorrentGalaxy Instead

If you're still having trouble, just use **TorrentGalaxy** instead:
1. Remove "The Pirate Bay" (broken version)
2. Add "TorrentGalaxy" - it's actually better than TPB
3. Test it - should work perfectly

**TorrentGalaxy is more reliable than The Pirate Bay anyway!**
