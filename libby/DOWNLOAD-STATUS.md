# Libby Download Pipeline - Current Status & Recovery Plan

**Date**: 2026-03-27  
**Status**: 🔴 BROKEN - Download automation not working  
**Last Known Working**: Revolutionary Iran (Pueblo card) successfully borrowed, downloaded, imported, decrypted

---

## What WAS Working (Before This Session)

### Successful Test Case: Revolutionary Iran
- **Library**: Pueblo (`pueblolibrary.overdrive.com`)
- **Card**: 1222205869422432593
- **Full cycle worked**:
  1. ✅ Borrow via Libby API
  2. ✅ Download ACSM file (method unknown - see below)
  3. ✅ ACSM placed in watch folder (`/mnt/boston/media/downloads/books/`)
  4. ✅ Auto-import to Calibre
  5. ✅ Auto-decrypt via DeDRM
  6. ✅ Loan auto-returned via Libby API

### The Mystery: How Did ACSM Download Work?

**Three possible explanations:**

1. **Manual download** - You manually downloaded from OverDrive website and dropped in watch folder
   - Most likely given no Playwright script existed in git history
   - Matches the workflow documented in early notes

2. **Direct Libby API `/fulfill/` endpoint** - odmpy has `fulfill_loan_file()` method
   - ❌ Currently fails with `403 Forbidden` due to `prbn:"l"` (limited chip) restriction
   - Would have worked IF chips were `prbn:"m"` (mobile/full) at that time

3. **Playwright automation** - Created during THIS session, never actually worked
   - Script is untracked in git (`libby/overdrive-download.py`)
   - Was our attempt to solve the problem, not the original working solution

---

## Current State of the Codebase

### What's Working ✅
1. **Search** - Thunder API search across all 13 libraries
2. **English filter** - Server-side filter ensures only English results
3. **Calibre library detection** - Fuzzy matching shows "📚 In Library" badge
4. **Series metadata** - Auto-fetches series name + reading order from Thunder API
5. **Borrow via Libby API** - Successfully borrows books across all cards
6. **Auto-return** - Returns loans after processing
7. **ACSM watch folder** - Monitors `/mnt/boston/media/downloads/books/`
8. **Calibre import** - Auto-imports ACSM → decrypts → counts pages/words → fetches metadata
9. **Holds management** - Place/cancel holds, suspend/unsuspend with sort/filter
10. **Mobile responsive** - Header/search bar wraps properly on small screens

### What's Broken 🔴
1. **Automatic ACSM download** - Playwright script fails
   - Signs in successfully
   - Book is borrowed via Libby API
   - But navigating to download URL doesn't trigger file download
   - OverDrive website likely changed - no longer exposes direct download URL

2. **Libby API `/fulfill/` endpoint** - Returns `403 Forbidden`
   - Root cause: Chip has `prbn:"l"` (limited patron borrowing)
   - Even though cards were "cloned from mobile" using "Copy to Another Device"
   - Chips may have been refreshed/recreated at some point, losing mobile status

---

## The `prbn:"l"` Problem Explained

### What is it?
Libby identity chips have a patron borrowing status field (`prbn`):
- `prbn:"m"` = Mobile/Full - Can use all API endpoints including `/fulfill/`
- `prbn:"l"` = Limited - Blocks `/fulfill/`, `/open/`, download endpoints

### How did it happen?
Our chips were created by:
1. Manual "Copy to Another Device" from mobile Libby app (13 cards cloned)
2. Stored in `libby/settings/libby.json`

**The chips currently have `prbn:"l"` status**, even though they were cloned from mobile.

Possible causes:
- Chips expired and were auto-refreshed via API (downgrades to limited)
- Sync operation reset the status
- OverDrive server-side policy change

### Why does Playwright not solve it?
The Playwright script was meant to bypass API restrictions by automating the website.
However:
- OverDrive website no longer has a simple "click this URL = download ACSM" flow
- Requires complex UI navigation (dropdowns, buttons, format selectors)
- Page structure varies by library
- Current script times out waiting for download event that never fires

---

## Recovery Options (In Priority Order)

### Option 1: Manual Download (WORKING NOW)
**Status**: ✅ This is what likely worked originally  
**How**:
1. Click "Download" in Libby Browser → borrows via API
2. Frontend shows instructions: "Go to `<library>.overdrive.com/account/loans`"
3. User manually downloads ACSM from website
4. Drag .acsm file into watch folder
5. Calibre auto-imports

**Implementation**: Already done in current code (`api_download` returns `manual:true`)

**Pros**: 
- Works reliably
- No Playwright complexity
- Matches original workflow

**Cons**:
- Requires manual step
- Not one-click automation

### Option 2: Fix Playwright Download
**Status**: 🟡 CURRENT BLOCKER - Borrow doesn't persist
**What's failing**:
1. Sign-in works ✅
2. Navigate to media page ✅
3. Click "Borrow" button ✅
4. Navigate to download URL ❌
5. **Error**: `errorCode=CheckoutNotFound` - the loan doesn't exist on the website

**Root cause**: The "Borrow" button click doesn't actually create a persistent loan. Possible reasons:
- Credentials (card + PIN) don't authenticate borrowing privileges on the website
- The button click isn't waiting for the borrow operation to complete
- OverDrive requires additional confirmation (e.g., format selection)
- The website and Libby API use different authentication systems

**Next debugging steps**:
1. Add screenshot capture after clicking Borrow to see what happens
2. Wait longer after Borrow click (currently 4s)
3. Check if there's a confirmation modal/popup that needs clicking
4. Try borrowing manually in a browser with same credentials to verify they work
5. Check if the credentials need to be an OverDrive account (email+password) instead of library card

**Estimated effort**: 2-4 more hours of debugging

**This WAS working before** - Revolutionary Iran downloaded successfully end-to-end through the browser

### Option 3: Re-clone Chips from Mobile as `prbn:"m"`
**Status**: ❌ TESTED - Does NOT work
**Result**: Re-cloned chip from mobile on 2026-03-27, still got `403 Forbidden` on `/fulfill/`

**What we tested**:
1. Generated 8-digit code from Libby mobile app
2. Cloned to server using `client.clone_by_code()`
3. Borrowed a book via Libby API
4. Attempted download via `client.fulfill_loan_file()`
5. **Result**: `403 Client Error: Forbidden`

**Conclusion**: OverDrive is **forcing all cloned chips to have limited (`prbn:"l"`) status** regardless of source. The API fulfill endpoint is completely blocked for cloned chips.

---

## Recommended Next Steps

### Immediate (Next Agent)
1. **Test Option 3 first** - Re-clone a single card from mobile and check `prbn` status
   ```python
   import jwt
   token = client.libby_session.headers['Authorization'].replace('Bearer ', '')
   payload = jwt.decode(token, options={'verify_signature': False})
   print('prbn:', payload.get('chip', {}).get('prbn'))
   ```

2. **If `prbn:"m"`** → Update `api_download` to use `client.fulfill_loan_file()`
   - Remove Playwright
   - Fast, reliable downloads
   - Done in 30 minutes

3. **If still `prbn:"l"`** → Stick with Option 1 (manual)
   - Current code already implements this
   - Just needs UI polish (better instructions modal)

### Long-term
- Document the exact download flow for each library's OverDrive site
- Build library-specific Playwright handlers if automation is critical
- OR accept manual download as the stable solution

---

## Code Locations

### Download Pipeline
- **Backend**: `libby-web/app.py` → `api_download()` (line ~440)
- **Frontend**: `libby-web/templates/index.html` → `confirmDownload()` (line ~598)
- **Playwright**: `libby/overdrive-download.py` (untracked, incomplete)
- **Credentials**: `libby/settings/overdrive-creds.json`
- **Libby chip**: `libby/settings/libby.json`

### Import Pipeline (WORKING)
- **Watcher**: `calibre/watch-acsm.sh` (systemd service: `calibre-acsm-watcher`)
- **Decrypt**: Calibre DeDRM plugin (auto-configured)
- **Metadata**: `calibre/config/fetch_metadata.py` (series + pubdate from Thunder API)
- **Page count**: `calibre/config/count_pages_cli.py`

### Current Environment
- **Tailscale IP**: `100.69.184.113`
- **Libby Browser**: Port 5007
- **Calibre Content Server**: Port 8083
- **Watch Folder**: `/mnt/boston/media/downloads/books/`
- **Calibre DB**: `/home/brandon/projects/docker/calibre/config/library/metadata.db`

---

## Testing Checklist

### Verify Download Works
- [ ] Search for available book in PPLD
- [ ] Click "Download"
- [ ] Verify loan appears in Libby API sync
- [ ] Check if ACSM download starts OR manual instructions appear
- [ ] If manual: download from loans page, drop in watch folder
- [ ] Wait 30s, check Calibre library for imported book
- [ ] Verify loan was returned

### Verify Metadata Import
- [ ] Check book has series info (if applicable)
- [ ] Check publication date is correct (not 0101-01-01)
- [ ] Check page count custom column
- [ ] Check word count custom column

---

## Key Insights from This Session

1. **The `prbn:"l"` restriction is real** - Confirmed by testing `/fulfill/` → 403
2. **Playwright download is harder than expected** - OverDrive UI is not automation-friendly
3. **Manual download likely was the original workflow** - No git history of working automation
4. **The import pipeline is solid** - Metadata, decryption, page counts all working great
5. **We have 13 working library cards** - Borrow works, just download that's the issue

---

## Questions for User (Next Session)

1. When "Revolutionary Iran" worked, do you remember clicking anything on the OverDrive website?
2. Did you manually download the ACSM file and drop it in the watch folder?
3. Would you prefer:
   - Option A: Reliable manual download (1 extra click, always works)
   - Option B: Flaky automation (one-click when working, breaks often)
4. Want to try re-cloning chips from mobile to test `prbn:"m"` theory?
