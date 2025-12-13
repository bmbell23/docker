#!/usr/bin/env python3
"""
LLM-enhanced metadata tagger using Google Gemini.
Intelligently extracts artist, album, year from YouTube filenames.
"""

import os
import re
import sys
import time
import json
from pathlib import Path

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

try:
    import google.generativeai as genai
except ImportError:
    print("Installing google-generativeai...")
    os.system("pip3 install google-generativeai --break-system-packages")
    import google.generativeai as genai

MUSIC_DIR = "/mnt/boston/media/music/YouTube-Downloads"

# Gemini API setup
GEMINI_API_KEY = os.environ.get('GEMINI_API_KEY')

SYSTEM_PROMPT = """You are a music metadata expert. Given a YouTube video filename, extract the proper music metadata.

For each filename, return ONLY a JSON object with these fields:
- artist: The actual artist/composer name (not "Unknown Artist")
- title: The song/track title
- album: The album name (if it's a soundtrack, use the game/movie name + "OST" or "Soundtrack")
- year: Release year if you can infer it (or null)
- genre: Music genre if obvious (or null)

Examples:
Input: "16 Baldur's Gate 3 Original Soundtrack - Last Light.opus"
Output: {"artist": "Borislav Slavov", "title": "Last Light", "album": "Baldur's Gate 3 Original Soundtrack", "year": "2023", "genre": "Video Game Music"}

Input: "Morgan Wallen - Last Night (Lyric Video).opus"
Output: {"artist": "Morgan Wallen", "title": "Last Night", "album": null, "year": "2023", "genre": "Country"}

Input: "Halo 3 - Never Forget (Piano Cover).opus"
Output: {"artist": "Martin O'Donnell & Michael Salvatori", "title": "Never Forget", "album": "Halo 3 Original Soundtrack", "year": "2007", "genre": "Video Game Music"}

Input: "Dan Gibson's Solitudes - Wandering Piper | Celtic Awakening.opus"
Output: {"artist": "Dan Gibson's Solitudes", "title": "Wandering Piper", "album": "Celtic Awakening", "year": null, "genre": "New Age"}

Return ONLY valid JSON, no other text."""

def setup_gemini():
    """Initialize Gemini API."""
    if not GEMINI_API_KEY:
        print("❌ GEMINI_API_KEY environment variable not set!")
        print("\nTo get a free API key:")
        print("1. Go to https://aistudio.google.com/app/apikey")
        print("2. Click 'Create API Key'")
        print("3. Export it: export GEMINI_API_KEY='your-key-here'")
        print("\nThen run this script again.")
        sys.exit(1)

    genai.configure(api_key=GEMINI_API_KEY)
    # Use gemini-flash-latest which has better rate limits (15 RPM instead of 5 RPM)
    return genai.GenerativeModel('gemini-flash-latest')

def extract_metadata_with_llm(model, filename):
    """Use Gemini to extract metadata from filename."""
    max_retries = 3
    retry_delay = 70  # seconds - wait longer than 1 minute for rate limit reset

    for attempt in range(max_retries):
        try:
            prompt = f"{SYSTEM_PROMPT}\n\nFilename: {filename}"
            response = model.generate_content(prompt)

            # Parse JSON response
            text = response.text.strip()
            # Remove markdown code blocks if present
            text = re.sub(r'^```json\s*', '', text)
            text = re.sub(r'\s*```$', '', text)

            metadata = json.loads(text)
            return metadata
        except Exception as e:
            error_str = str(e)
            if '429' in error_str or 'quota' in error_str.lower():
                if attempt < max_retries - 1:
                    print(f"  ⏳ Rate limit hit, waiting {retry_delay} seconds...")
                    time.sleep(retry_delay)
                    continue
                else:
                    print(f"  ⚠️  Rate limit exceeded after {max_retries} retries")
                    return None
            else:
                print(f"  ⚠️  LLM error: {e}")
                return None

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

    parser = argparse.ArgumentParser(description='LLM-enhanced metadata tagger')
    parser.add_argument('--limit', type=int, help='Only process first N files (for testing)')
    parser.add_argument('--only-unknown', action='store_true', help='Only process files with "Unknown Artist"')
    parser.add_argument('--dry-run', action='store_true', help='Show what would be done without tagging')
    args = parser.parse_args()

    print("🤖 LLM-Enhanced YouTube Metadata Tagger (Google Gemini)")
    print("=" * 60)
    print()

    # Setup Gemini
    model = setup_gemini()
    print("✅ Gemini API initialized")
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

    enhanced = 0
    failed = 0

    for i, filepath in enumerate(files, 1):
        print(f"[{i}/{len(files)}] 📝 {filepath.name}")

        # Rate limiting: 15 requests per minute for gemini-flash-latest
        # After every 10 requests, wait 60 seconds to be safe
        if i > 1 and (i - 1) % 10 == 0:
            print(f"  ⏸️  Processed 10 requests, waiting 60 seconds for rate limit reset...")
            time.sleep(60)

        # Use LLM to extract metadata
        metadata = extract_metadata_with_llm(model, filepath.name)

        if metadata:
            print(f"  🤖 LLM extracted:")
            print(f"     Artist: {metadata.get('artist', 'N/A')}")
            print(f"     Title: {metadata.get('title', 'N/A')}")
            if metadata.get('album'):
                print(f"     Album: {metadata['album']}")
            if metadata.get('year'):
                print(f"     Year: {metadata['year']}")
            if metadata.get('genre'):
                print(f"     Genre: {metadata['genre']}")

            if not args.dry_run:
                if tag_opus_file(str(filepath), metadata):
                    print(f"  ✅ Tagged!")
                    enhanced += 1
                else:
                    failed += 1
            else:
                print(f"  ⏭️  Dry run - not tagging")
                enhanced += 1
        else:
            print(f"  ❌ Failed to extract metadata")
            failed += 1

        print()

    print("=" * 60)
    print(f"✅ Enhanced: {enhanced}")
    print(f"❌ Failed: {failed}")
    print()
    if not args.dry_run:
        print("Navidrome will pick up changes within 5 minutes!")

if __name__ == "__main__":
    main()

