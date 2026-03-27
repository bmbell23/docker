#!/usr/bin/env python3
"""Libby Web Browser — search and one-click download ebooks to Calibre."""

import difflib
import json
import os
import re
import subprocess
import time
import urllib.parse
import urllib.request
from pathlib import Path

import urllib3
from flask import Flask, jsonify, render_template, request
from flask_cors import CORS

urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

SETTINGS_DIR = os.environ.get("LIBBY_SETTINGS", "/settings")
WATCH_DIR = Path(os.environ.get("WATCH_DIR", "/books"))
THUNDER_BASE = "https://thunder.api.overdrive.com/v2/libraries"
CREDS_FILE = Path(SETTINGS_DIR) / "overdrive-creds.json"
PLAYWRIGHT_SCRIPT = "/libby/overdrive-download.py"

try:
    from odmpy.libby import LibbyClient, LibbyFormats
except ImportError:
    raise SystemExit("odmpy not installed — rebuild the Docker image")

# ---------------------------------------------------------------------------
# Calibre library cache
# ---------------------------------------------------------------------------
CALIBRE_API = os.environ.get("CALIBRE_API_URL", "http://172.16.6.1:8083")
_CALIBRE_CACHE_TTL = 300  # seconds
_calibre_cache: dict = {"books": None, "expires": 0}


def _norm_title(t: str) -> str:
    t = t.lower().strip()
    t = re.sub(r"[^\w\s]", " ", t)
    t = re.sub(r"\b(the|a|an)\b", " ", t)
    return re.sub(r"\s+", " ", t).strip()


def _norm_author(a: str) -> str:
    return re.sub(r"[^\w\s]", " ", a.lower()).strip()


def get_calibre_library() -> list:
    """Return cached list of (title_norm, [author_norm, …]) from Calibre."""
    global _calibre_cache
    if _calibre_cache["books"] is not None and time.time() < _calibre_cache["expires"]:
        return _calibre_cache["books"]
    try:
        url = f"{CALIBRE_API}/ajax/search?num=2000&sort=title"
        with urllib.request.urlopen(url, timeout=8) as r:
            ids = json.loads(r.read()).get("book_ids", [])
        if not ids:
            _calibre_cache = {"books": [], "expires": time.time() + _CALIBRE_CACHE_TTL}
            return []
        ids_str = ",".join(map(str, ids[:1500]))
        url2 = f"{CALIBRE_API}/ajax/books?ids={ids_str}"
        with urllib.request.urlopen(url2, timeout=20) as r:
            books_data = json.loads(r.read())
        books = []
        for b in books_data.values():
            if b:
                books.append((
                    _norm_title(b.get("title", "")),
                    [_norm_author(a) for a in b.get("authors", [])],
                ))
        _calibre_cache = {"books": books, "expires": time.time() + _CALIBRE_CACHE_TTL}
        return books
    except Exception:
        return []


def is_in_calibre(title: str, author: str) -> bool:
    """Fuzzy-match a title+author against the cached Calibre library."""
    books = get_calibre_library()
    if not books:
        return False
    t_norm = _norm_title(title)
    a_norm = _norm_author(author)
    for lib_title, lib_authors in books:
        t_ratio = difflib.SequenceMatcher(None, t_norm, lib_title).ratio()
        if t_ratio < 0.78:
            continue
        # Title matches — confirm with author (or accept if author unknown)
        if not a_norm or not lib_authors:
            return True
        a_ratio = max(difflib.SequenceMatcher(None, a_norm, la).ratio() for la in lib_authors)
        if a_ratio >= 0.65:
            return True
    return False

app = Flask(__name__)
CORS(app)


def get_client() -> LibbyClient:
    client = LibbyClient(settings_folder=SETTINGS_DIR)
    client.libby_session.verify = False
    return client


def thunder_search(library_key: str, query: str, per_page: int = 40) -> list:
    """Search OverDrive Thunder API for English ebooks in a specific library."""
    params = urllib.parse.urlencode({
        "query": query,
        "mediaTypes": "ebook",
        "languages": "en",
        "perPage": per_page,
    })
    url = f"{THUNDER_BASE}/{library_key}/media?{params}"
    req = urllib.request.Request(url, headers={"Accept": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=10) as r:
            return json.loads(r.read()).get("items", [])
    except Exception:
        return []


def sanitize(name: str) -> str:
    return re.sub(r'[<>:"/\\|?*]', "", name).strip()


# ---------------------------------------------------------------------------
# API Routes
# ---------------------------------------------------------------------------

@app.route("/")
def index():
    return render_template("index.html")


def load_all_creds() -> dict:
    """Load overdrive-creds.json keyed by advantageKey."""
    try:
        return json.loads(CREDS_FILE.read_text()) if CREDS_FILE.exists() else {}
    except Exception:
        return {}


@app.route("/api/cards")
def api_cards():
    try:
        client = get_client()
        sync = client.make_request("chip/sync")
        creds = load_all_creds()
        seen_keys: dict = {}
        for c in sync.get("cards", []):
            card_id = str(c.get("cardId", ""))
            lib = c.get("library", {})
            advantage_key = c.get("advantageKey", "")
            if advantage_key not in seen_keys:
                seen_keys[advantage_key] = {
                    "cardId": card_id,
                    "advantageKey": advantage_key,
                    "name": lib.get("name", advantage_key or "?"),
                    "websiteId": lib.get("websiteId", ""),
                    "counts": c.get("counts", {}),
                    "limits": c.get("limits", {}),
                    "hasCredentials": advantage_key in creds,
                }
        return jsonify({"cards": list(seen_keys.values())})
    except Exception as e:
        return jsonify({"error": str(e)}), 500


@app.route("/api/cards/status")
def api_cards_status():
    """Return all cards with loan/hold counts and credential status."""
    try:
        client = get_client()
        sync = client.make_request("chip/sync")
        creds = load_all_creds()
        # Deduplicate by advantageKey — show one row per library, not per card
        seen_keys: dict = {}
        for c in sync.get("cards", []):
            card_id = str(c.get("cardId", ""))
            lib = c.get("library", {})
            advantage_key = c.get("advantageKey", "")
            counts = c.get("counts", {})
            limits = c.get("limits", {})
            card_creds = creds.get(advantage_key, {})
            if advantage_key not in seen_keys:
                seen_keys[advantage_key] = {
                    "cardId": card_id,  # use first card found for this library
                    "name": lib.get("name", advantage_key or "?"),
                    "advantageKey": advantage_key,
                    "hasCredentials": advantage_key in creds,
                    "credUsername": card_creds.get("username", ""),
                    "credPassword": card_creds.get("password", ""),
                    "loans": counts.get("loan", 0),
                    "holds": counts.get("hold", 0),
                    "loanLimit": limits.get("book", "?"),
                    "holdLimit": limits.get("hold", "?"),
                }
            else:
                # Accumulate loans/holds across multiple cards for same library
                seen_keys[advantage_key]["loans"] += counts.get("loan", 0)
                seen_keys[advantage_key]["holds"] += counts.get("hold", 0)
        return jsonify({"cards": list(seen_keys.values())})
    except Exception as e:
        return jsonify({"error": str(e)}), 500


@app.route("/api/cards/credentials/<advantage_key>", methods=["GET"])
def api_get_credentials(advantage_key):
    """Return stored credentials for a given advantageKey (for pre-filling the edit modal)."""
    creds = load_all_creds()
    entry = creds.get(advantage_key, {})
    return jsonify({"username": entry.get("username", ""), "password": entry.get("password", "")})


@app.route("/api/cards/credentials", methods=["POST"])
def api_cards_credentials():
    """Save OverDrive credentials keyed by advantageKey."""
    data = request.json or {}
    advantage_key = str(data.get("advantage_key", "")).strip().lower()
    username = str(data.get("username", "")).strip()
    password = str(data.get("password", "")).strip()

    if not all([advantage_key, username, password]):
        return jsonify({"error": "advantage_key, username, and password are required"}), 400

    try:
        creds = load_all_creds()
        creds[advantage_key] = {"username": username, "password": password}
        CREDS_FILE.write_text(json.dumps(creds, indent=2))
        return jsonify({"success": True})
    except Exception as e:
        return jsonify({"error": str(e)}), 500


@app.route("/api/search")
def api_search():
    query = request.args.get("q", "").strip()
    library_key = request.args.get("library", "all")
    if not query:
        return jsonify({"results": []})

    try:
        client = get_client()
        sync = client.make_request("chip/sync")
        cards = sync.get("cards", [])

        # Deduplicate: one entry per advantageKey (library), not per card
        unique_keys: dict = {}  # advantageKey → cardId (first card wins)
        for c in cards:
            ak = c.get("advantageKey", "")
            if ak and ak not in unique_keys:
                unique_keys[ak] = str(c.get("cardId", ""))

        if library_key == "all":
            keys = list(unique_keys.keys())
        else:
            keys = [library_key] if library_key in unique_keys else []

        seen: dict = {}
        for key in keys:
            items = thunder_search(key, query)
            for item in items:
                tid = str(item.get("id", ""))
                formats = [f.get("id") for f in item.get("formats", [])]
                if "ebook-epub-adobe" not in formats:
                    continue
                # Hard filter: skip anything not explicitly English
                langs = [l.get("id", "") for l in item.get("languages", [])]
                if langs and "en" not in langs:
                    continue
                lib_avail = item.get("isAvailable", False)
                lib_holds = item.get("holdsCount", 0)
                lib_wait  = item.get("estimatedWaitDays")
                if tid not in seen:
                    i_title = item.get("title", "")
                    i_author = item.get("firstCreatorName", "")
                    ds = item.get("detailedSeries") or {}
                    seen[tid] = {
                        "id": tid,
                        "title": i_title,
                        "author": i_author,
                        "cover": (item.get("covers", {})
                                  .get("cover150Wide", {}).get("href", "")),
                        "isAvailable": lib_avail,
                        "holdsCount": lib_holds,
                        "estimatedWaitDays": lib_wait,
                        "inLibrary": is_in_calibre(i_title, i_author),
                        "series": ds.get("seriesName", ""),
                        "seriesIndex": ds.get("readingOrder", ""),
                        "libraries": [],
                    }
                else:
                    # Promote top-level availability to the best library found
                    if lib_avail and not seen[tid]["isAvailable"]:
                        seen[tid]["isAvailable"] = True
                        seen[tid]["holdsCount"] = lib_holds
                        seen[tid]["estimatedWaitDays"] = lib_wait
                    elif not seen[tid]["isAvailable"] and not lib_avail:
                        # Both unavailable — keep shortest wait
                        cur_wait = seen[tid]["estimatedWaitDays"] or 9999
                        new_wait = lib_wait or 9999
                        if new_wait < cur_wait:
                            seen[tid]["holdsCount"] = lib_holds
                            seen[tid]["estimatedWaitDays"] = lib_wait
                seen[tid]["libraries"].append({
                    "key": key,
                    "cardId": unique_keys[key],
                    "isAvailable": lib_avail,
                    "holdsCount": lib_holds,
                    "estimatedWaitDays": lib_wait,
                })

        return jsonify({"results": list(seen.values())})
    except Exception as e:
        return jsonify({"error": str(e)}), 500


@app.route("/api/holds")
def api_holds():
    """Return all current holds across all cards."""
    try:
        client = get_client()
        sync = client.make_request("chip/sync")
        card_name = {str(c.get("cardId")): c.get("library", {}).get("name", c.get("advantageKey", "?"))
                     for c in sync.get("cards", [])}
        holds = []
        for h in sync.get("holds", []):
            holds.append({
                "id": str(h.get("id", "")),
                "title": h.get("title", ""),
                "author": h.get("firstCreatorName", ""),
                "cover": (h.get("covers", {}).get("cover150Wide", {}).get("href", "")),
                "cardId": str(h.get("cardId", "")),
                "libraryName": card_name.get(str(h.get("cardId", "")), "?"),
                "holdPosition": h.get("holdListPosition"),
                "holdsCount": h.get("holdsCount"),
                "isAvailable": h.get("isAvailable", False),
                "estimatedWaitDays": h.get("estimatedWaitDays"),
                "suspended": h.get("suspensionFlag", False),
                "placedDate": h.get("placedDate", "")[:10],
            })
        return jsonify({"holds": holds})
    except Exception as e:
        return jsonify({"error": str(e)}), 500


@app.route("/api/holds/place", methods=["POST"])
def api_place_hold():
    """Place a hold on a title."""
    data = request.json or {}
    title_id = str(data.get("title_id", ""))
    card_id = str(data.get("card_id", ""))
    if not title_id or not card_id:
        return jsonify({"error": "title_id and card_id required"}), 400
    try:
        client = get_client()
        client.make_request(f"card/{card_id}/hold/{title_id}", method="POST",
                            json_data={"days_to_suspend": 0, "auto_checkout": False})
        return jsonify({"success": True})
    except Exception as e:
        return jsonify({"error": str(e)}), 500


@app.route("/api/holds/cancel", methods=["POST"])
def api_cancel_hold():
    """Cancel a hold."""
    data = request.json or {}
    title_id = str(data.get("title_id", ""))
    card_id = str(data.get("card_id", ""))
    if not title_id or not card_id:
        return jsonify({"error": "title_id and card_id required"}), 400
    try:
        client = get_client()
        client.make_request(f"card/{card_id}/hold/{title_id}", method="DELETE", return_res=True)
        return jsonify({"success": True})
    except Exception as e:
        return jsonify({"error": str(e)}), 500


@app.route("/api/holds/suspend", methods=["POST"])
def api_suspend_hold():
    """Suspend a hold for a number of days (1–180)."""
    data = request.json or {}
    title_id = str(data.get("title_id", ""))
    card_id = str(data.get("card_id", ""))
    days = int(data.get("days", 30))
    if not title_id or not card_id:
        return jsonify({"error": "title_id and card_id required"}), 400
    try:
        client = get_client()
        client.make_request(f"card/{card_id}/hold/{title_id}", method="PUT",
                            json_data={"suspensionFlag": True, "numberOfDaysToSuspend": days})
        return jsonify({"success": True})
    except Exception as e:
        return jsonify({"error": str(e)}), 500


@app.route("/api/holds/unsuspend", methods=["POST"])
def api_unsuspend_hold():
    """Unsuspend (resume) a hold."""
    data = request.json or {}
    title_id = str(data.get("title_id", ""))
    card_id = str(data.get("card_id", ""))
    if not title_id or not card_id:
        return jsonify({"error": "title_id and card_id required"}), 400
    try:
        client = get_client()
        client.make_request(f"card/{card_id}/hold/{title_id}", method="PUT",
                            json_data={"suspensionFlag": False})
        return jsonify({"success": True})
    except Exception as e:
        return jsonify({"error": str(e)}), 500


def get_creds_for_card(card_id: str, client: "LibbyClient") -> tuple[dict, str]:
    """Return (creds_dict, advantage_key) for a cardId by looking up its advantageKey."""
    try:
        sync = client.make_request("chip/sync")
        card = next((c for c in sync.get("cards", [])
                     if str(c.get("cardId")) == card_id), None)
        advantage_key = card.get("advantageKey", "") if card else ""
        all_creds = load_all_creds()
        return all_creds.get(advantage_key, {}), advantage_key
    except Exception:
        return {}, ""


@app.route("/api/download", methods=["POST"])
def api_download():
    data = request.json or {}
    title_id = str(data.get("title_id", ""))
    card_id = str(data.get("card_id", ""))
    if not title_id or not card_id:
        return jsonify({"error": "title_id and card_id required"}), 400

    client = get_client()
    creds, advantage_key = get_creds_for_card(card_id, client)
    if not creds:
        return jsonify({
            "error": f"No OverDrive credentials configured for this library. "
                     f"Go to the Library Cards tab and click '+ Add credentials'."
        }), 400

    try:
        # Download via Playwright (borrows + downloads via OverDrive website)
        app.logger.info(f"Downloading {title_id} via Playwright...")
        result = subprocess.run(
            ["python3", PLAYWRIGHT_SCRIPT,
             advantage_key, creds["username"], creds["password"],
             title_id, str(WATCH_DIR)],
            capture_output=True, text=True, timeout=120,
        )

        output = result.stdout.strip().splitlines()
        last_line = output[-1] if output else ""
        try:
            parsed = json.loads(last_line)
        except Exception:
            parsed = {"success": False, "error": result.stderr[:300] or last_line}

        if not parsed.get("success"):
            app.logger.error(f"Playwright failed: {parsed.get('error','Unknown')}")
            return jsonify({"error": parsed.get("error", "Download failed")}), 500

        # Return the loan via Libby API (ACSM license is embedded and remains valid)
        try:
            client.make_request(f"card/{card_id}/loan/{title_id}", method="DELETE", return_res=True)
        except Exception:
            pass  # Non-fatal

        return jsonify({"success": True, "filename": Path(parsed["path"]).name})

    except Exception as e:
        app.logger.exception(f"Download exception for title {title_id}: {e}")
        return jsonify({"error": str(e)}), 500


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5007, debug=False)
