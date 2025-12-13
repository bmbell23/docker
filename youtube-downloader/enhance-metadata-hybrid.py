#!/usr/bin/env python3
"""
Hybrid metadata tagger: MusicBrainz API first, then Ollama LLM fallback.
Best of both worlds - accurate mainstream data + smart parsing for everything else.
"""

import os
import re
import sys
import time
import json
from pathlib import Path
from urllib.request import Request, urlopen
from urllib.parse import quote

try:
    from mutagen.oggopus import OggOpus
    from mutagen.flac import Picture
    import base64
except ImportError:
    print("Installing mutagen...")
    os.system("pip3 install mutagen --break-system-packages")
    from mutagen.oggopus import OggOpus
    from mutagen.flac import Picture
    import base64

MUSIC_DIR = "/mnt/boston/media/music/YouTube-Downloads"
USER_AGENT = "YouTubeMetadataEnhancer/1.0 (brandon@example.com)"

# Rate limiting for MusicBrainz
last_request_time = 0

def rate_limit():
    """Ensure we don't exceed 1 request per second for MusicBrainz."""
    global last_request_time
    current_time = time.time()
    time_since_last = current_time - last_request_time
    if time_since_last < 1.0:
        time.sleep(1.0 - time_since_last)
    last_request_time = time.time()

def clean_filename(filename):
    """Extract artist and title from YouTube filename."""
    # Remove file extension
    name = filename.replace('.opus', '')

    # Remove common YouTube suffixes
    suffixes = [
        r'\s*\(Official.*?\)',
        r'\s*\(Lyric.*?\)',
        r'\s*\(Music Video\)',
        r'\s*\(Audio\)',
        r'\s*\(HD\)',
        r'\s*\(4K\)',
        r'\s*\(Live\)',
        r'\s*\[Official.*?\]',
        r'\s*\[Lyric.*?\]',
    ]
    for suffix in suffixes:
        name = re.sub(suffix, '', name, flags=re.IGNORECASE)

    # Try to extract artist and title
    patterns = [
        r'^(.+?)\s*[-–—]\s*(.+)$',  # "Artist - Title"
        r'^(.+?)\s+by\s+(.+)$',      # "Title by Artist"
        r'^(.+?)\s*:\s*(.+)$',       # "Artist: Title"
    ]

    for pattern in patterns:
        match = re.match(pattern, name)
        if match:
            return match.group(1).strip(), match.group(2).strip()

    return None, name.strip()

def search_musicbrainz(artist, title):
    """Search MusicBrainz for recording metadata."""
    if not artist or artist == "Unknown Artist":
        return None

    rate_limit()

    query = f'artist:"{artist}" AND recording:"{title}"'
    url = f"https://musicbrainz.org/ws/2/recording/?query={quote(query)}&fmt=json&limit=1"

    try:
        req = Request(url, headers={'User-Agent': USER_AGENT})
        with urlopen(req, timeout=10) as response:
            data = json.loads(response.read().decode())

            if data.get('recordings'):
                recording = data['recordings'][0]

                metadata = {
                    'artist': recording.get('artist-credit', [{}])[0].get('name', artist),
                    'title': recording.get('title', title),
                    'album': None,
                    'year': None,
                    'genre': None,
                }

                if recording.get('releases'):
                    release = recording['releases'][0]
                    metadata['album'] = release.get('title')
                    if release.get('date'):
                        metadata['year'] = release['date'][:4]

                return metadata
    except Exception as e:
        pass

    return None

def extract_with_ollama(filename):
    """Use local Ollama to extract metadata from filename."""
    try:
        import requests

        prompt = f"""Extract music metadata from this YouTube video filename. Return ONLY valid JSON with these fields:
- artist: The actual artist/composer name (or null if unknown)
- title: The song/track title
- album: The album name (or null)
- year: Release year (or null)
- genre: Music genre (or null)

Filename: {filename}

Return ONLY the JSON object, no other text."""

        response = requests.post('http://localhost:11434/api/generate',
                                json={
                                    'model': 'llama3.2',
                                    'prompt': prompt,
                                    'stream': False
                                },
                                timeout=60)

        if response.status_code == 200:
            result = response.json()
            text = result.get('response', '').strip()

            # Remove markdown code blocks if present
            text = re.sub(r'^```json\s*', '', text)
            text = re.sub(r'\s*```$', '', text)

            metadata = json.loads(text)
            return metadata
    except Exception as e:
        print(f"  ⚠️  Ollama error: {e}")

    return None

def tag_opus_file(filepath, metadata):
    """Add metadata to OPUS file."""
    try:
        audio = OggOpus(filepath)

        if metadata.get('artist'):
            audio['artist'] = metadata['artist']

        if metadata.get('title'):
            audio['title'] = metadata['title']

        if metadata.get('album'):
            audio['album'] = metadata['album']
        else:
            audio['album'] = 'YouTube Downloads'

        if metadata.get('year'):
            audio['date'] = str(metadata['year'])

        if metadata.get('genre'):
            audio['genre'] = metadata['genre']

        audio.save()
        return True
    except Exception as e:
        print(f"  ❌ Error tagging: {e}")
        return False

def main():
    import argparse

    parser = argparse.ArgumentParser(description='Hybrid metadata tagger (MusicBrainz + Ollama)')
    parser.add_argument('--limit', type=int, help='Only process first N files')
    parser.add_argument('--only-unknown', action='store_true', help='Only process files with "Unknown Artist"')
    args = parser.parse_args()

    print("🎵 Hybrid Metadata Tagger (MusicBrainz + Ollama)")
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

    musicbrainz_success = 0
    ollama_success = 0
    failed = 0

    for i, filepath in enumerate(files, 1):
        print(f"[{i}/{len(files)}] 📝 {filepath.name}")

        # Step 1: Try to parse filename
        artist, title = clean_filename(filepath.name)
        if artist:
            print(f"  📋 Parsed: {artist} - {title}")
        else:
            print(f"  📋 Parsed: {title}")

        metadata = None

        # Step 2: Try MusicBrainz first
        if artist and artist != "Unknown Artist":
            print(f"  🔍 Searching MusicBrainz...")
            metadata = search_musicbrainz(artist, title)

            if metadata:
                print(f"  ✅ MusicBrainz found: {metadata['artist']} - {metadata['title']}")
                if metadata.get('album'):
                    print(f"     Album: {metadata['album']}")
                if metadata.get('year'):
                    print(f"     Year: {metadata['year']}")
                musicbrainz_success += 1

        # Step 3: If MusicBrainz failed, try Ollama
        if not metadata:
            print(f"  🤖 Trying Ollama LLM...")
            metadata = extract_with_ollama(filepath.name)

            if metadata:
                print(f"  ✅ Ollama extracted:")
                print(f"     Artist: {metadata.get('artist', 'N/A')}")
                print(f"     Title: {metadata.get('title', 'N/A')}")
                if metadata.get('album'):
                    print(f"     Album: {metadata['album']}")
                if metadata.get('year'):
                    print(f"     Year: {metadata['year']}")
                if metadata.get('genre'):
                    print(f"     Genre: {metadata['genre']}")
                ollama_success += 1

        # Step 4: Tag the file
        if metadata:
            if tag_opus_file(str(filepath), metadata):
                print(f"  ✅ Tagged!")
            else:
                failed += 1
        else:
            print(f"  ❌ No metadata found")
            failed += 1

        print()

    print("=" * 60)
    print(f"✅ MusicBrainz: {musicbrainz_success}")
    print(f"🤖 Ollama: {ollama_success}")
    print(f"❌ Failed: {failed}")
    print()
    print("Navidrome will pick up changes within 5 minutes!")

if __name__ == "__main__":
    main()

