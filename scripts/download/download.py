#!/usr/bin/env python3
"""!download: Jackett search -> pick a number -> qBittorrent -> the right library (docker#177).

  download.py help                       the categories
  download.py <search words> [category]  top results by seeders; saved for the pick
  download.py <n>                        add result n of the last search to qBittorrent
  download.py place                      (dagu, every 2 min) hardlink finished downloads into
                                         their library, tag them `placed`, tell Brandon. Movies
                                         land as `Title (Year)/Title (Year).mkv`, TV as
                                         `Show/Season NN/`, minus .nfo/.txt junk (docker#180)

Run by the router as `!download …` (argv only, stdout is the chat reply) and by the dagu job
download-place. Stdlib only. The Jackett API key is read at runtime from KEY_FILE and never
printed; it reaches qBittorrent on stdin, not argv.
"""
import json
import os
import re
import shutil
import subprocess
import sys
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

JACKETT = os.environ.get("JACKETT_URL", "http://127.0.0.1:9117")
KEY_FILE = Path(os.environ.get("JACKETT_KEY_FILE", Path.home() / ".config/download/jackett-api-key"))
STATE = Path(os.environ.get("DOWNLOAD_STATE", Path.home() / ".local/state/download"))
MEDIA = Path(os.environ.get("MEDIA_ROOT", "/mnt/boston/media"))
TORRENTS_HOST = MEDIA / "downloads/torrents"   # qBittorrent's /downloads
SAY = os.environ.get("DOWNLOAD_SAY", "/home/brandon/projects/agent-bus/bin/say")
TOP = 5
INDEXER_TIMEOUT = 30   # seconds per indexer; slower ones are skipped and named (docker#182)

# name: (Jackett/Torznab category ids, library dir under MEDIA, what it feeds)
CATEGORIES = {
    "audiobook": ([3030], "audiobooks", "Audiobookshelf"),
    "book":      ([7000, 7020], "downloads/books", "Calibre (then GreatReads)"),
    "music":     ([3000], "music", "Jellyfin music"),
    "movie":     ([2000], "videos/movies", "Jellyfin"),
    "tv":        ([5000], "videos/shows", "Jellyfin"),
    "xxx":       ([6000], "other", "Stash"),
    "game":      ([1000, 4050], "games", "RomM, by platform"),
}
ALIASES = {"audiobooks": "audiobook", "books": "book", "ebook": "book", "ebooks": "book",
           "movies": "movie", "film": "movie", "show": "tv", "shows": "tv", "games": "game", "porn": "xxx"}

GAME_EXT = {".gba": "gba", ".gb": "gb", ".gbc": "gbc", ".nes": "nes", ".sfc": "snes", ".smc": "snes",
            ".n64": "n64", ".z64": "n64", ".v64": "n64", ".md": "genesis", ".gen": "genesis",
            ".smd": "genesis", ".sms": "mastersystem", ".rvz": "ngc", ".gcm": "ngc", ".gcz": "ngc",
            ".wbfs": "wii", ".nds": "nds", ".3ds": "3ds", ".cue": "ps1", ".a26": "atari2600"}


def fail(msg):
    """Errors go to stdout: only stdout reaches chat (the router relays exit 1)."""
    print(msg)
    sys.exit(1)


def category_of(word):
    w = word.lower()
    return w if w in CATEGORIES else ALIASES.get(w)


def category_from_ids(ids):
    """Our category for a result's Torznab ids (first match), or None."""
    for i in ids:
        if i == 3030:
            return "audiobook"
        if i == 4050 or 1000 <= i < 2000:
            return "game"
        for name, lo in (("movie", 2000), ("music", 3000), ("tv", 5000), ("xxx", 6000), ("book", 7000)):
            if lo <= i < lo + 1000:
                return name
    return None


def human(n):
    for unit in ("B", "KB", "MB", "GB", "TB"):
        if n < 1024 or unit == "TB":
            return f"{n:.0f} {unit}" if unit in ("B", "KB") else f"{n:.1f} {unit}"
        n /= 1024


def help_text():
    rows = "\n".join(f"| `{n}` | {', '.join(map(str, ids))} | {feeds} |" for n, (ids, _, feeds) in CATEGORIES.items())
    return ("**`!download <search> [category]`**: top results by seeders. Then **`!download <n>`** grabs one; "
            "when it finishes it's hardlinked into its library and I DM you.\n\n"
            "| category | Jackett ids | lands in |\n|---|---|---|\n" + rows +
            "\n\nNo category = search everything (the pick still lands by the result's own category).")


# --- Jackett -----------------------------------------------------------------------------

def jackett_get(path, params, timeout):
    """GET a Jackett API path. Raises OSError; never let the URL into a message: it holds the key."""
    url = f"{JACKETT}/api/v2.0/{path}?" + urllib.parse.urlencode([("apikey", api_key())] + params)
    with urllib.request.urlopen(url, timeout=timeout) as r:
        return r.read()


def api_key():
    if not KEY_FILE.is_file():
        fail(f"No Jackett API key yet: put it in `{KEY_FILE}` (Jackett UI, top right), mode 600.")
    return KEY_FILE.read_text().strip()


def indexers_for(cat):
    """Configured indexers [(id, title)] whose caps cover `cat` (all of them when cat is None).
    A cap matches when it sits in the same thousand-block as one of the category's ids."""
    try:
        xml = jackett_get("indexers/all/results/torznab/api", [("t", "indexers"), ("configured", "true")], 15)
    except OSError as e:
        fail(f"Jackett itself didn't answer ({type(e).__name__}). Is the VPN stack up?")
    blocks = {i // 1000 for i in CATEGORIES[cat][0]} if cat else None
    out = []
    for ix in ET.fromstring(xml).findall("indexer"):
        caps = {int(c.get("id")) // 1000 for c in ix.iter("category") if (c.get("id") or "").isdigit()}
        if blocks is None or caps & blocks:
            out.append((ix.get("id"), ix.findtext("title") or ix.get("id")))
    return out


def jackett_search(query, cat):
    """Search each matching indexer in parallel, each with its own timeout, so one dead
    indexer can't sink the whole search (docker#182). Returns (results, [problem, ...])."""
    params = [("Query", query)] + [("Category[]", str(i)) for i in (CATEGORIES[cat][0] if cat else [])]

    def one(ix):
        return json.loads(jackett_get(f"indexers/{ix[0]}/results", params, INDEXER_TIMEOUT)).get("Results", [])

    results, problems = [], []
    with ThreadPoolExecutor(max_workers=8) as pool:
        for ix, fut in [(ix, pool.submit(one, ix)) for ix in indexers_for(cat)]:
            try:
                results += fut.result()
            except (OSError, ValueError) as e:
                if isinstance(e, TimeoutError) or isinstance(getattr(e, "reason", None), TimeoutError):
                    problems.append(f"{ix[1]} (no answer in {INDEXER_TIMEOUT}s)")
                    continue
                problems.append(f"{ix[1]} ({getattr(e, 'code', None) or type(e).__name__})")
    return results, problems


def top_results(results, n=TOP):
    ok = [r for r in results if r.get("MagnetUri") or r.get("Link")]
    ok.sort(key=lambda r: r.get("Seeders") or 0, reverse=True)
    return ok[:n]


def search(words):
    cat = category_of(words[-1]) if len(words) > 1 else None
    query = " ".join(words[:-1] if cat else words)
    found, problems = jackett_search(query, cat)
    picks = top_results(found)
    skipped = f"\n\n_Skipped: {', '.join(problems)}._" if problems else ""
    if not picks:
        return f"Nothing found for **{query}**" + (f" in `{cat}`." if cat else ".") + skipped
    saved = []
    lines = [f"**Top {len(picks)} for \"{query}\"**" + (f" · `{cat}`" if cat else "") + ", by seeders:"]
    for i, r in enumerate(picks, 1):
        rcat = cat or category_from_ids(r.get("Category") or []) or "other"
        saved.append({"title": r.get("Title", "?"), "magnet": r.get("MagnetUri") or "", "link": r.get("Link") or "",
                      "category": rcat})
        lines.append(f"{i}. **{r.get('Title', '?')}** · {human(r.get('Size') or 0)} · "
                     f"{r.get('Seeders') or 0} seeders · {r.get('Tracker', '?')} · `{rcat}`")
    STATE.mkdir(parents=True, exist_ok=True)
    (STATE / "last.json").write_text(json.dumps(saved))
    lines.append("\nGrab one with `!download <n>`.")
    return "\n".join(lines) + skipped


# --- qBittorrent (WebUI API inside its container: localhost auth bypass is on) ------------

def qbit(path, fields=None, stdin_url=None):
    """GET (no fields) or multipart POST to qBittorrent's API. stdin_url goes in as `urls` via
    curl's `<-` so a Jackett link (with its key) never shows on a command line."""
    cmd = ["docker", "exec", "-i", "qbittorrent", "curl", "-sS", "-m", "30", "--fail"]
    for k, v in (fields or {}).items():   # multipart for torrents/add, form-urlencoded for the rest
        cmd += ["-F", f"{k}={v}"] if stdin_url is not None else ["--data-urlencode", f"{k}={v}"]
    if stdin_url is not None:
        cmd += ["-F", "urls=<-"]
    cmd.append(f"http://127.0.0.1:8080/api/v2/{path}")
    out = subprocess.run(cmd, input=stdin_url or "", capture_output=True, text=True, timeout=60)
    if out.returncode:
        fail(f"qBittorrent refused `{path.split('?')[0]}` (curl exit {out.returncode}).")
    return out.stdout


def pick(n):
    try:
        saved = json.loads((STATE / "last.json").read_text())
    except (OSError, ValueError):
        return "No search to pick from yet: `!download <search>` first."
    if not 1 <= n <= len(saved):
        return f"Pick 1–{len(saved)} from the last search."
    r = saved[n - 1]
    qbit("torrents/add", {"category": f"dl-{r['category']}"}, stdin_url=r["magnet"] or r["link"])
    where = CATEGORIES[r["category"]][2] if r["category"] in CATEGORIES else "the torrents folder only (no category)"
    return f"Downloading **{r['title']}** (`dl-{r['category']}`). When it's done it goes to {where}, and I'll DM you."


# --- placement ---------------------------------------------------------------------------

def game_platform(path):
    """RomM platform folder for a game file (or the biggest file in a folder), else None."""
    if path.is_dir():
        files = [f for f in path.rglob("*") if f.is_file()]
        if not files:
            return None
        path = max(files, key=lambda f: f.stat().st_size)
    ext = path.suffix.lower()
    if ext == ".iso":
        try:
            with open(path, "rb") as f:
                head = f.read(0x20)
        except OSError:
            return None
        if head[0x1C:0x20] == b"\xc2\x33\x9f\x3d":
            return "ngc"
        if head[0x18:0x1C] == b"\x5d\x1c\x9e\xa3":
            return "wii"
        return None
    return GAME_EXT.get(ext)


VIDEO_EXT = {".mkv", ".mp4", ".m4v", ".avi", ".mov", ".wmv", ".ts", ".webm", ".mpg"}
SUB_EXT = {".srt", ".ass", ".ssa", ".sub", ".idx", ".vtt"}
JUNK_EXT = {".nfo", ".txt", ".url", ".exe", ".lnk", ".html", ".htm", ".sfv", ".md5"}
SITE = re.compile(r"^\s*(?:\[[^\]]*\]|\(?(?:www\.)?[\w-]+\.(?:org|com|net|to|me|cc|io|xyz|in)\)?)\s*[-_.]*\s*", re.I)
YEAR = re.compile(r"(?<!\d)((?:19|20)\d\d)(?!\d)")
SEASON = re.compile(r"\bS(\d{1,2})(?=E\d|\b|[\s._-])|\bSeason[\s._-]*(\d{1,2})\b", re.I)


def tidy(name):
    """A torrent name as words: extension, site prefixes, dots and underscores gone."""
    if Path(name).suffix.lower() in VIDEO_EXT:
        name = Path(name).stem
    while SITE.match(name) and SITE.sub("", name, count=1) != name:
        name = SITE.sub("", name, count=1)
    return re.sub(r"\s+", " ", re.sub(r"[._]", " ", name)).strip()


def trim(title):
    return re.sub(r"[\s(\[\-]+$", "", title).strip()


def movie_name(name):
    """'www.X.org - The Movie 2023 UHD x265-GRP' -> 'The Movie (2023)'; None without a year."""
    t = tidy(name)
    for m in reversed(list(YEAR.finditer(t))):
        title, year = trim(t[:m.start()]), m.group(1)
        run = re.search(r"((?:19|20)\d\d)(?:\s*,\s*(?:19|20)\d\d)*\s*,$", title)   # "1985,1989,1990"
        if run:
            title, year = trim(title[:run.start()]), run.group(1)
        if title:
            return f"{title} ({year})"
    return None


def show_name(name):
    """'Show.Name.2019.S02E03.1080p' -> ('Show Name (2019)', 2); None without a season."""
    t = tidy(name)
    m = SEASON.search(t)
    if not m:
        return None
    title, season = trim(t[:m.start()]), int(m.group(1) or m.group(2))
    y = YEAR.search(title)
    if y and trim(title[:y.start()]):
        title = f"{trim(title[:y.start()])} ({y.group(1)})"
    return (title, season) if title else None


def season_of(name):
    m = SEASON.search(tidy(name))
    return int(m.group(1) or m.group(2)) if m else None


def media_files(src):
    """Files worth placing: no .nfo/.txt junk, no samples."""
    files = [src] if src.is_file() else sorted(p for p in src.rglob("*") if p.is_file())
    keep = []
    for f in files:
        rel = f.name if src.is_file() else str(f.relative_to(src))
        if f.suffix.lower() in JUNK_EXT or re.search(r"(^|[\s._/-])sample([\s._/-]|$)", rel, re.I):
            continue
        keep.append(f)
    return keep


def movie_plan(lib, src):
    clean = movie_name(src.name)
    if not clean:
        return None
    files = media_files(src)
    videos = [f for f in files if f.suffix.lower() in VIDEO_EXT]
    big = max((f.stat().st_size for f in videos), default=0)
    mains = [f for f in videos if f.stat().st_size * 2 >= big]
    main = mains[0] if len(mains) == 1 else None   # a pack of films keeps its file names
    dest, plan = lib / clean, []
    for f in files:
        if f == main:
            target = dest / f"{clean}{f.suffix.lower()}"
        elif main and f.suffix.lower() in SUB_EXT:
            rest = f.stem[len(main.stem):] if f.stem.startswith(main.stem) else "." + f.stem.split(".")[-1].split("_")[-1]
            target = dest / f"{clean}{rest}{f.suffix.lower()}"
        else:
            target = dest / (f.name if src.is_file() else f.relative_to(src))
        plan.append((f, target))
    return dest, plan


def show_plan(lib, src):
    named = show_name(src.name)
    if not named:
        return None
    show, season = named
    dest, plan = lib / show, []
    for f in media_files(src):
        s = season_of(f.name) or season
        plan.append((f, dest / f"Season {s:02d}" / f.name))
    return dest, plan


def raw_plan(dest, src):
    files = [src] if src.is_file() else sorted(p for p in src.rglob("*") if p.is_file())
    return [(f, dest if src.is_file() else dest / f.relative_to(src)) for f in files]


def link_files(plan):
    """Hardlink each (src, target); copy where the filesystem won't link. Returns files made."""
    made = 0
    for f, target in plan:
        if target.exists():
            continue
        target.parent.mkdir(parents=True, exist_ok=True)
        try:
            os.link(f, target)
        except OSError:
            shutil.copy2(f, target)
        made += 1
    return made


def destination(cat, src):
    """(library path, [(file, target)], note) for a finished download; the note flags a guess."""
    lib = MEDIA / CATEGORIES[cat][1]
    if cat in ("movie", "tv"):
        planned = (movie_plan if cat == "movie" else show_plan)(lib, src)
        if planned:
            return *planned, ""
        what = "a title and year" if cat == "movie" else "a season (S01)"
        return lib / src.name, raw_plan(lib / src.name, src), f" (couldn't read {what}: kept the torrent's name)"
    if cat != "game":
        return lib / src.name, raw_plan(lib / src.name, src), ""
    plat = game_platform(src)
    if plat:
        return lib / plat / src.name, raw_plan(lib / plat / src.name, src), ""
    dest = MEDIA / "games-staging" / src.name
    return dest, raw_plan(dest, src), " (platform unknown: in games-staging, move it to games/<platform>)"


def host_path(container_path):
    p = Path(container_path)
    return TORRENTS_HOST / p.relative_to("/downloads") if p.is_relative_to("/downloads") else p


def place():
    torrents = json.loads(qbit("torrents/info?filter=completed") or "[]")
    done = []
    for t in torrents:
        cat = (t.get("category") or "").removeprefix("dl-")
        if not t.get("category", "").startswith("dl-") or "placed" in (t.get("tags") or "").split(", "):
            continue
        src = host_path(t["content_path"])
        if cat not in CATEGORIES:
            qbit("torrents/addTags", {"hashes": t["hash"], "tags": "placed"})
            done.append(f"✅ **{t['name']}** finished. No category, so it stays in `{src.parent}`.")
            continue
        if not src.exists():
            print(f"{t['name']}: {src} not found; will retry", file=sys.stderr)
            continue
        dest, plan, note = destination(cat, src)
        n = link_files(plan)
        qbit("torrents/addTags", {"hashes": t["hash"], "tags": "placed"})
        done.append(f"✅ **{t['name']}** → `{dest}` ({n} file{'s' * (n != 1)}, {CATEGORIES[cat][2]}){note}")
    if done:
        msg = "\n".join(done)
        print(msg)
        if os.path.exists(SAY):
            subprocess.run([SAY, "dakota", "@brandon", "-"], input=msg, text=True, timeout=200)
    return ""


def main(argv):
    if not argv or argv[0].lower() in ("help", "-h", "--help"):
        return help_text()
    if argv == ["place"]:
        return place()
    if len(argv) == 1 and re.fullmatch(r"\d{1,2}", argv[0]):
        return pick(int(argv[0]))
    return search(argv)


if __name__ == "__main__":
    out = main(sys.argv[1:])
    if out:
        print(out)
