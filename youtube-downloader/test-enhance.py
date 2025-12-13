#!/usr/bin/env python3
"""
Test enhanced metadata on a few sample files.
"""

import os
import re
import time
import json
from pathlib import Path
from urllib.request import urlopen, Request
from urllib.parse import quote

try:
    from mutagen.oggopus import OggOpus
except ImportError:
    print("Installing mutagen...")
    os.system("pip3 install mutagen --break-system-packages")
    from mutagen.oggopus import OggOpus

MUSIC_DIR = "/mnt/boston/media/music/YouTube-Downloads"
USER_AGENT = "YouTubeMetadataEnhancer/1.0 (https://github.com/bmbell23/docker)"

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
    
    return "Unknown Artist", name.strip()

def search_musicbrainz(artist, title):
    """Search MusicBrainz for recording metadata."""
    query = f'artist:"{artist}" AND recording:"{title}"'
    url = f"https://musicbrainz.org/ws/2/recording/?query={quote(query)}&fmt=json&limit=3"
    
    try:
        req = Request(url, headers={'User-Agent': USER_AGENT})
        with urlopen(req, timeout=10) as response:
            data = json.loads(response.read().decode())
            
            if data.get('recordings'):
                results = []
                for recording in data['recordings'][:3]:
                    metadata = {
                        'artist': recording.get('artist-credit', [{}])[0].get('name', artist),
                        'title': recording.get('title', title),
                        'album': None,
                        'year': None,
                        'score': recording.get('score', 0)
                    }
                    
                    if recording.get('releases'):
                        release = recording['releases'][0]
                        metadata['album'] = release.get('title')
                        if release.get('date'):
                            metadata['year'] = release['date'][:4]
                        metadata['release_mbid'] = release.get('id')
                    
                    results.append(metadata)
                
                return results
    except Exception as e:
        print(f"  ❌ Error: {e}")
    
    return None

def main():
    print("🧪 Testing Enhanced Metadata on Sample Files")
    print("=" * 60)
    print()
    
    # Test on a few different types of files
    test_files = [
        "Morgan Wallen - Last Night (Lyric Video).opus",
        "Aerosmith - Dream On (Audio).opus",
        "Chris Stapleton - Tennessee Whiskey (Official Audio).opus",
        "16 Baldur's Gate 3 Original Soundtrack - Last Light.opus",
        "Halo 3 - Never Forget (Piano Cover).opus",
    ]
    
    for filename in test_files:
        filepath = Path(MUSIC_DIR) / filename
        if not filepath.exists():
            print(f"⚠️  Skipping (not found): {filename}")
            print()
            continue
        
        print(f"📝 {filename}")
        
        artist, title = clean_filename(filename)
        print(f"  Parsed: {artist} - {title}")
        
        print(f"  🔍 Searching MusicBrainz...")
        results = search_musicbrainz(artist, title)
        
        if results:
            print(f"  ✅ Found {len(results)} match(es):")
            for i, metadata in enumerate(results, 1):
                print(f"     [{i}] {metadata['artist']} - {metadata['title']}")
                if metadata.get('album'):
                    print(f"         Album: {metadata['album']}")
                if metadata.get('year'):
                    print(f"         Year: {metadata['year']}")
                print(f"         Score: {metadata['score']}")
        else:
            print(f"  ❌ No matches found")
        
        print()
        time.sleep(1)  # Rate limiting
    
    print("=" * 60)
    print("Test complete! If results look good, run enhance-metadata.py")

if __name__ == "__main__":
    main()

