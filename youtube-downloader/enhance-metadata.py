#!/usr/bin/env python3
"""
Enhanced metadata tagger for YouTube downloads.
Uses MusicBrainz API to fetch proper artist, album, year, genre, and album art.
"""

import os
import re
import sys
import time
import json
from pathlib import Path
from urllib.request import urlopen, Request
from urllib.parse import quote
import subprocess

try:
    from mutagen.oggopus import OggOpus
    from mutagen.mp3 import MP3
    from mutagen.id3 import ID3, TIT2, TPE1, TALB, TDRC, TCON, APIC
except ImportError:
    print("Installing mutagen...")
    os.system("pip3 install mutagen --break-system-packages")
    from mutagen.oggopus import OggOpus
    from mutagen.mp3 import MP3
    from mutagen.id3 import ID3, TIT2, TPE1, TALB, TDRC, TCON, APIC

MUSIC_DIR = "/mnt/boston/media/music/YouTube-Downloads"
CACHE_DIR = "/tmp/musicbrainz_cache"
USER_AGENT = "YouTubeMetadataEnhancer/1.0 (https://github.com/bmbell23/docker)"

# Rate limiting for MusicBrainz (1 request per second)
LAST_REQUEST_TIME = 0

def rate_limit():
    """Ensure we don't exceed MusicBrainz rate limits."""
    global LAST_REQUEST_TIME
    now = time.time()
    elapsed = now - LAST_REQUEST_TIME
    if elapsed < 1.0:
        time.sleep(1.0 - elapsed)
    LAST_REQUEST_TIME = time.time()

def clean_filename(filename):
    """Extract clean artist and title from YouTube filename."""
    name = Path(filename).stem

    # Remove common YouTube suffixes
    name = re.sub(r'\s*\(.*?(Official|Lyric|Music|Audio|Video|HD|4K|Live|Visualizer).*?\)', '', name, flags=re.IGNORECASE)
    name = re.sub(r'\s*\[.*?(Official|Lyric|Music|Audio|Video|HD|4K|Live|Visualizer).*?\]', '', name, flags=re.IGNORECASE)

    # Remove track numbers at the start
    name = re.sub(r'^\d+\.?\s*', '', name)

    # Pattern 1: "Artist - Title"
    match = re.match(r'^(.+?)\s*[-–—]\s*(.+)$', name)
    if match:
        return match.group(1).strip(), match.group(2).strip()

    # Pattern 2: "Title by Artist"
    match = re.search(r'^(.+?)\s+by\s+(.+)$', name, re.IGNORECASE)
    if match:
        return match.group(2).strip(), match.group(1).strip()

    # Pattern 3: "Artist: Title"
    match = re.match(r'^(.+?)\s*:\s*(.+)$', name)
    if match:
        return match.group(1).strip(), match.group(2).strip()

    return "Unknown Artist", name.strip()

def search_musicbrainz(artist, title):
    """Search MusicBrainz for recording metadata."""
    rate_limit()

    # Build search query
    query = f'artist:"{artist}" AND recording:"{title}"'
    url = f"https://musicbrainz.org/ws/2/recording/?query={quote(query)}&fmt=json&limit=1"

    try:
        req = Request(url, headers={'User-Agent': USER_AGENT})
        with urlopen(req, timeout=10) as response:
            data = json.loads(response.read().decode())

            if data.get('recordings'):
                recording = data['recordings'][0]

                # Extract metadata
                metadata = {
                    'artist': recording.get('artist-credit', [{}])[0].get('name', artist),
                    'title': recording.get('title', title),
                    'album': None,
                    'year': None,
                    'genre': None,
                    'mbid': recording.get('id')
                }

                # Get album info if available
                if recording.get('releases'):
                    release = recording['releases'][0]
                    metadata['album'] = release.get('title')
                    if release.get('date'):
                        metadata['year'] = release['date'][:4]

                    # Get release MBID for cover art
                    metadata['release_mbid'] = release.get('id')

                return metadata
    except Exception as e:
        print(f"  ⚠️  MusicBrainz search failed: {e}")

    return None

def download_cover_art(release_mbid):
    """Download cover art from Cover Art Archive."""
    if not release_mbid:
        return None

    rate_limit()

    url = f"https://coverartarchive.org/release/{release_mbid}/front"

    try:
        req = Request(url, headers={'User-Agent': USER_AGENT})
        with urlopen(req, timeout=10) as response:
            return response.read()
    except Exception as e:
        print(f"  ⚠️  Cover art download failed: {e}")

    return None

def tag_opus_file(filepath, metadata, cover_art=None):
    """Add enhanced metadata to OPUS file."""
    try:
        audio = OggOpus(filepath)
        audio['artist'] = metadata['artist']
        audio['title'] = metadata['title']

        if metadata.get('album'):
            audio['album'] = metadata['album']
        else:
            audio['album'] = 'YouTube Downloads'

        if metadata.get('year'):
            audio['date'] = metadata['year']

        if metadata.get('genre'):
            audio['genre'] = metadata['genre']

        # Embed cover art
        if cover_art:
            from mutagen.flac import Picture
            import base64

            picture = Picture()
            picture.type = 3  # Cover (front)
            picture.mime = 'image/jpeg'
            picture.data = cover_art

            audio['metadata_block_picture'] = [base64.b64encode(picture.write()).decode('ascii')]

        audio.save()
        return True
    except Exception as e:
        print(f"  ❌ Error tagging: {e}")
        return False

def main():
    import argparse

    parser = argparse.ArgumentParser(description='Enhanced YouTube metadata tagger')
    parser.add_argument('--limit', type=int, help='Only process first N files (for testing)')
    parser.add_argument('--skip-art', action='store_true', help='Skip downloading cover art')
    parser.add_argument('--only-unknown', action='store_true', help='Only process files with "Unknown Artist"')
    parser.add_argument('--auto', action='store_true', help='Run without confirmation prompt')
    args = parser.parse_args()

    print("🎵 Enhanced YouTube Metadata Tagger")
    print("=" * 60)
    print()

    if not os.path.exists(MUSIC_DIR):
        print(f"❌ Directory not found: {MUSIC_DIR}")
        return

    files = list(Path(MUSIC_DIR).glob("*.opus"))

    if not files:
        print(f"❌ No OPUS files found in {MUSIC_DIR}")
        return

    # Filter files if needed
    if args.only_unknown:
        filtered = []
        for f in files:
            try:
                audio = OggOpus(str(f))
                if audio.get('artist', [''])[0] == 'Unknown Artist':
                    filtered.append(f)
            except:
                pass
        files = filtered
        print(f"Found {len(files)} files with 'Unknown Artist'")
    else:
        print(f"Found {len(files)} files to process")

    if args.limit:
        files = files[:args.limit]
        print(f"Limiting to first {args.limit} files")

    print()

    # Ask user for confirmation
    if not args.auto:
        response = input("This will query MusicBrainz and download cover art. Continue? (y/n): ")
        if response.lower() != 'y':
            print("Cancelled.")
            return
        print()

    enhanced = 0
    failed = 0
    skipped = 0

    for i, filepath in enumerate(files, 1):
        print(f"[{i}/{len(files)}] 📝 {filepath.name}")

        artist, title = clean_filename(filepath.name)
        print(f"  Parsed: {artist} - {title}")

        # Skip if it's a cover, remix, or soundtrack (MusicBrainz won't have these)
        if any(keyword in filepath.name.lower() for keyword in ['cover', 'remix', 'ost', 'soundtrack', 'piano version']):
            print(f"  ⚠️  Detected cover/remix/soundtrack - keeping basic metadata")
            skipped += 1
            print()
            continue

        # Search MusicBrainz
        metadata = search_musicbrainz(artist, title)

        if metadata:
            print(f"  ✅ Found: {metadata['artist']} - {metadata['title']}")
            if metadata.get('album'):
                print(f"     Album: {metadata['album']}")
            if metadata.get('year'):
                print(f"     Year: {metadata['year']}")

            # Download cover art
            cover_art = None
            if not args.skip_art and metadata.get('release_mbid'):
                print(f"  🖼️  Downloading cover art...")
                cover_art = download_cover_art(metadata['release_mbid'])
                if cover_art:
                    print(f"  ✅ Cover art downloaded ({len(cover_art)} bytes)")

            # Tag file
            if tag_opus_file(str(filepath), metadata, cover_art):
                enhanced += 1
            else:
                failed += 1
        else:
            print(f"  ⚠️  No match found, keeping basic metadata")
            failed += 1

        print()

    print("=" * 60)
    print(f"✅ Enhanced: {enhanced}")
    print(f"⚠️  Failed/Not Found: {failed}")
    print(f"⏭️  Skipped (covers/remixes): {skipped}")
    print()
    print("Navidrome will pick up changes within 5 minutes!")

if __name__ == "__main__":
    main()

