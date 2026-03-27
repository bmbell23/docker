# Libby / OverDrive Integration — Status & Technical Notes

**Last updated:** 2026-03-27

---

## ⚠️ CRITICAL - Download Automation Broken

**READ FIRST**:
- **Current Issue**: Automatic ACSM download not working
- **Full Details**: See `DOWNLOAD-STATUS.md` for problem analysis and recovery plan
- **Testing Guide**: See `TESTING-CHIP-STATUS.md` to verify chip status and test fixes
- **What Still Works**: Everything except automatic download (search, borrow, metadata, import pipeline)

---

## Quick Status

| Capability | Status | Notes |
|---|---|---|
| Search OverDrive catalog | ✅ Working | Thunder API, no auth required |
| Borrow a title | ✅ Working | Via chip + `link_card` auth |
| Return a title | ✅ Working | Via chip + `link_card` auth |
| View loans / holds | ✅ Working | Via chip + `link_card` auth |
| Download ACSM file | ❌ Blocked | `prbn:"l"` chip blocks fulfillment API |
| Calibre ACSM pipeline | ✅ Working | Drop `.acsm` in watch folder → auto-import |

---

## What We Have Built

### 1. Libby Browser Web UI (`libby-web/`, port 5007)
Flask app that provides:
- Search the OverDrive catalog via the Thunder API
- One-click borrow / return by library card
- (Attempted) one-click ACSM download → Calibre watch folder

### 2. Libby CLI (`libby/libby-manager.py`)
Command-line manager: `setup`, `status`, `loans`, `holds`, `borrow`, `return`, `download`.

### 3. Calibre Auto-Import Pipeline
1. `.acsm` file appears in `/mnt/boston/media/downloads/books/`
2. systemd service (`calibre-acsm-watcher.service`) detects it via `watch-acsm.sh`
3. deACSM plugin fulfills the ACSM → DRM-protected EPUB
4. DeDRM plugin strips DRM → clean EPUB
5. Count Pages plugin calculates `#pages` and `#word_count` custom columns
6. `xdotool` sends Ctrl+R to Calibre GUI so the content server updates immediately

---

## The Libby Chip System (How Authentication Works)

Every Libby "device" (phone, computer, odmpy) gets a **chip** — a UUID stored server-side. The chip is represented as a signed JWT sent as `Authorization: Bearer {JWT}` on every API request.

The chip JWT payload looks like this:

```json
{
  "chip": {
    "id": "76ba6cdb-8b7a-48f2-8296-13abf077cae8",
    "pri": "76ba6cdb-...",
    "ag": null,              ← chip-level account group (MUST be non-null for downloads)
    "accounts": [
      {
        "ag": 15289136,      ← account-level ag (populated by link_card, but not enough)
        "id": "114870068",
        "typ": "library",
        "cards": [{ "id": "98675840", "lib": { "id": "92", "key": "ppld" } }]
      }
    ],
    "prbn": "l"              ← patron borrowing level ("l" = limited, blocks downloads)
  }
}
```

### Known `prbn` values
| Value | Meaning | Capabilities |
|---|---|---|
| `"i"` | Initial / inactive (brand new chip, never authenticated) | Nothing |
| `"l"` | Limited (created via `link_card` API or clone) | sync, borrow, return — **no download** |
| `""` or `"m"` | Full (created via the official Libby mobile app) | All including download |

**The core problem:** Any chip created or modified via the Libby REST API always ends up with `prbn:"l"`. The fulfillment endpoints (`/fulfill/` and `/open/`) reject `prbn:"l"` chips with 403.

---

## SSL Certificate Issue

`sentry-read.svc.overdrive.com` presents an SSL certificate issued for `*.odrsre.overdrive.com` — a hostname mismatch. This breaks `odmpy` and any Python `requests` call without a workaround.

**Workaround used throughout:**
```python
import urllib3
urllib3.disable_warnings()
client.libby_session.verify = False
```

This is applied in `libby-manager.py` and `libby-web/app.py`. The SSL issue is separate from the `prbn:"l"` download block.

**Known widespread issue:** odmpy GitHub issue #81 (opened Oct 30, 2024) confirms this affects all odmpy users after OverDrive changed their infrastructure in late 2024. No official fix as of March 2026.

---

## Authentication Attempts — Full History

### ✅ `link_card()` — Direct Library Card Auth
**What it does:** `LibbyClient.link_card(website_id, username, password, ils='default')`

**Result:**
- Creates a chip with `prbn:"l"`, `chip.ag=null`, `account.ag=15289136`
- `syncable: false` (chip is not cloneable)
- Can sync, borrow, return — **cannot download ACSM**

**PPLD credentials used:**
- `website_id = "92"`, `key = "ppld"`
- Card: `420754455`, PIN: `0523`
- `cardId = "98675840"` (server-assigned)

---

### ❌ Clone Flow — Many Attempts

**The flow:**
1. `GET /chip/clone/code` → server issues an 8-digit code tied to our chip
2. User opens Libby app → Menu → Copy to Another Device → enters the code
3. Libby says "data transferred successfully"
4. `POST /chip` → refresh chip JWT

**What happened after each clone:**
- `chip.syncable` changed `false → true` ✅ (clone did something)
- `account.ag` populated (15289136) ✅
- `chip.ag` remained `null` ❌
- `prbn` remained `"l"` ❌
- Fulfillment still returned 403 ❌

**Why it doesn't fix things:**
The clone copies account data but does not change the chip's authorization level. A chip born as `prbn:"l"` stays `prbn:"l"` even after cloning. The server always sets `prbn:"l"` for API-created chips regardless of what clones into them.

**Important mistake made repeatedly:** After generating a clone code with `GET /chip/clone/code`, we called that endpoint again to check status — which **issued a brand new code and invalidated the previous one**. Always wait for user confirmation before touching the clone endpoint again.

---

### ❌ Fresh Chip + Clone (No `link_card`)

Hypothesis: maybe starting without `link_card` would let the clone set a better `prbn`.

**Result:** Fresh chip starts as `prbn:"i"`. After user enters the code in Libby and we refresh: `prbn:"l"`, 0 accounts.

The clone from the phone consistently produces `prbn:"l"`. The phone's full chip properties are not transferred — only account associations.

---

### ❌ odmpy CLI (SSL-patched)

Ran odmpy with monkey-patched SSL verification:
```python
import requests
orig_init = requests.Session.__init__
def new_init(self, *args, **kwargs):
    orig_init(self, *args, **kwargs)
    self.verify = False
requests.Session.__init__ = new_init
```

**Result:** odmpy connected and synced. However, found "No downloadable loans" because the only active loan (`Secret of the Water Dragon`) had no `ebook-epub-adobe` format. Even if a qualifying loan existed, odmpy would call the same blocked fulfill endpoint.

---

### ❌ OverDrive Patron REST API

Tried `POST https://oauth.overdrive.com/token` with various guessed client IDs.

**Result:** `401 {"error":"invalid_client"}` — requires approved developer credentials (client_id + client_secret). OverDrive does not offer public/self-serve API access.

---

### ❌ OverDrive Website Scraping (ppld.overdrive.com)

The OverDrive website is a React SPA. Attempted to find sign-in API endpoints.

**Result:** All guessed endpoints (`/account/ozone/sign-in`, `/account/sign-in`, `/api/sign-in`) returned 404. The React app makes XHR calls that can't be discovered without a running browser. No headless browser available on the server.

---

## Blocked Endpoints — Detail

### `GET /card/{card_id}/loan/{loan_id}/fulfill/ebook-epub-adobe`
- **Returns:** 403 with empty body (no JSON)
- **Cause:** nginx-level rejection before reaching the app — chip's `prbn:"l"` is checked at the gateway
- **With `chip.ag=null`:** Same result

### `GET /open/ebook/card/{card_id}/title/{title_id}`
- **Returns:** 403 `{"result":"client_upgrade_required"}`
- **Cause:** Server rejects limited (`prbn:"l"`) chips on the open/reading endpoint
- **Tried:** Different User-Agent strings, `?client=dewey` param, different loan type paths — all same result

---

## Working Endpoints — Reference

| Endpoint | Method | Works? | Notes |
|---|---|---|---|
| `chip` | GET | ✅ | Create new chip |
| `chip` | POST | ✅ | Refresh chip JWT |
| `chip/clone/code` | GET | ✅ | Generate clone code — **do not call again after issuing** |
| `chip/sync` | GET | ✅ | Full sync (loans, holds, cards) |
| `card/{cid}/loan/{tid}` | POST | ✅ | Borrow title |
| `card/{cid}/loan/{tid}` | DELETE | ✅ | Return title |
| `card/{cid}/loan/{tid}/fulfill/ebook-epub-adobe` | GET | ❌ | 403 empty |
| `open/ebook/card/{cid}/title/{tid}` | GET | ❌ | 403 `client_upgrade_required` |

**Base URL:** `https://sentry-read.svc.overdrive.com/`
**Search API:** `https://thunder.api.overdrive.com/v2/libraries/{key}/media`

---

## Current Working Manual Workaround

1. **Borrow** a title using the Libby Browser web UI at `:5007`
2. Open the **Libby app on your phone** → find the borrowed title
3. Tap **Download** → choose **EPUB (Adobe DRM)** → phone downloads a `.acsm` file
4. Transfer the `.acsm` to the server: `/mnt/boston/media/downloads/books/`
5. **Calibre watcher auto-processes it** — deACSM → DeDRM → library

---

## Future Options

### Option A: Playwright Browser Automation
Install Playwright on the server and automate the OverDrive website:
```bash
pip3 install playwright && playwright install chromium
```
Script would: open ppld.overdrive.com → sign in with library card → navigate to checkouts → click "Download EPUB" → save `.acsm` to watch folder.

### Option B: Wait for odmpy Fix
The odmpy maintainer may address the `prbn:"l"` limitation.
Track: https://github.com/ping/odmpy/issues/81

### Option C: OverDrive Developer API Access
If OverDrive grants API partner access, the patron REST API supports checkout fulfillment with proper OAuth.
Apply: https://developer.overdrive.com

---

## Key File Locations

| File | Purpose |
|---|---|
| `libby/settings/libby.json` | Auth chip + identity JWT (delete to start over) |
| `libby/libby-manager.py` | CLI: loans, holds, borrow, return, download |
| `libby-web/app.py` | Flask web UI backend (port 5007) |
| `libby-web/templates/index.html` | Web UI frontend |
| `calibre/watch-acsm.sh` | ACSM watcher script |
| `calibre/acsm-watcher.log` | Watcher log |

## Container & Service Info

| Service | Port | Container | Compose Dir |
|---|---|---|---|
| Libby Browser | 5007 | `libby-web` | `libby-web/` |
| Calibre GUI | 8084 | `calibre` | `calibre/` |
| Calibre Content Server | 8083 | `calibre` | `calibre/` |

**PPLD:** websiteId=`92`, key=`ppld`, cardId=`98675840`
**Tailscale IP:** `100.69.184.113`
**Watch folder:** `/mnt/boston/media/downloads/books/`
