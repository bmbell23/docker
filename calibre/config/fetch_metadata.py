#!/usr/bin/env python3
"""
Fetch series and publication date from OverDrive Thunder API for a Calibre book.

Searches Thunder API by title+author, finds the best match, and writes
series name, series index, and publication date back to the Calibre library.

Usage (inside container):
    calibre-debug -e /config/fetch_metadata.py <book_id>

Prints to stdout for the watcher script:
    METADATA_SERIES=The Book of Tea
    METADATA_SERIES_INDEX=1
    METADATA_PUBDATE=2022-03-29
    METADATA_SKIPPED=<reason>   (if nothing changed)
    METADATA_ERROR=<message>    (on failure)
"""

import difflib
import json
import re
import sys
import urllib.parse
import urllib.request

THUNDER_BASE = "https://thunder.api.overdrive.com/v2/libraries"
# Libraries to try in order — first hit with a good match wins
SEARCH_LIBRARIES = ["ppld", "pueblolibrary", "arapahoe", "jeffco"]


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _norm(s: str) -> str:
    s = s.lower().strip()
    s = re.sub(r"[^\w\s]", " ", s)
    s = re.sub(r"\b(the|a|an)\b", " ", s)
    return re.sub(r"\s+", " ", s).strip()


def thunder_search(library_key: str, title: str, author: str) -> list:
    query = f"{title} {author}".strip()
    params = urllib.parse.urlencode({
        "query": query,
        "mediaTypes": "ebook",
        "languages": "en",
        "perPage": 10,
    })
    url = f"{THUNDER_BASE}/{library_key}/media?{params}"
    req = urllib.request.Request(url, headers={"Accept": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=12) as r:
            return json.loads(r.read()).get("items", [])
    except Exception as e:
        print(f"  Thunder [{library_key}] error: {e}", file=sys.stderr)
        return []


def best_match(items: list, title: str, author: str):
    """Return the best-matching Thunder item, or None if confidence is too low."""
    t_norm = _norm(title)
    a_norm = _norm(author)
    best, best_score = None, 0.0
    for item in items:
        t_ratio = difflib.SequenceMatcher(
            None, t_norm, _norm(item.get("title", ""))
        ).ratio()
        if t_ratio < 0.75:
            continue
        a_ratio = difflib.SequenceMatcher(
            None, a_norm, _norm(item.get("firstCreatorName", ""))
        ).ratio() if a_norm else 0.6
        score = t_ratio * 0.65 + a_ratio * 0.35
        if score > best_score:
            best_score, best = score, item
    return best if best_score >= 0.70 else None


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    if len(sys.argv) < 2:
        print("Usage: calibre-debug -e /config/fetch_metadata.py <book_id>")
        sys.exit(1)

    book_id = int(sys.argv[1])
    library_path = "/config/library"

    from calibre.db.cache import Cache
    from calibre.db.backend import DB

    db_obj = DB(library_path)
    cache = Cache(db_obj)
    cache.init()

    title = cache.field_for("title", book_id) or ""
    raw_authors = cache.field_for("authors", book_id) or ()
    author = raw_authors[0] if raw_authors else ""
    current_series = cache.field_for("series", book_id) or ""
    current_pubdate = cache.field_for("pubdate", book_id)

    print(f"Book {book_id}: '{title}' by '{author}'", file=sys.stderr)
    print(f"  Current series: '{current_series}' | pubdate: {current_pubdate}", file=sys.stderr)

    # Decide what we need to fetch
    need_series = not current_series
    need_pubdate = (current_pubdate is None or current_pubdate.year < 1800)

    if not need_series and not need_pubdate:
        print("METADATA_SKIPPED=already complete")
        db_obj.close()
        return

    # Search Thunder API
    match = None
    for lib in SEARCH_LIBRARIES:
        items = thunder_search(lib, title, author)
        match = best_match(items, title, author)
        if match:
            print(f"  Matched '{match['title']}' in [{lib}]", file=sys.stderr)
            break

    if not match:
        print("METADATA_ERROR=no matching title found in Thunder API")
        db_obj.close()
        return

    ds = match.get("detailedSeries") or {}
    series_name = ds.get("seriesName", "")
    series_index = ds.get("readingOrder", "")
    publish_date = (match.get("publishDate") or "")[:10]   # "YYYY-MM-DD"

    print(f"  Thunder data: series='{series_name}' #{series_index} date={publish_date}",
          file=sys.stderr)

    # Write back
    if need_series and series_name:
        cache.set_field("series", {book_id: series_name})
        print(f"METADATA_SERIES={series_name}")
        if series_index:
            try:
                cache.set_field("series_index", {book_id: float(series_index)})
                print(f"METADATA_SERIES_INDEX={series_index}")
            except (ValueError, TypeError):
                pass

    if need_pubdate and publish_date:
        try:
            from calibre.utils.date import parse_date
            pd = parse_date(publish_date)
            cache.set_field("pubdate", {book_id: pd})
            print(f"METADATA_PUBDATE={publish_date}")
        except Exception as e:
            print(f"  Date write error: {e}", file=sys.stderr)

    db_obj.close()


if __name__ == "__main__":
    main()
