#!/usr/bin/env python3
"""
Parse YouTube filenames and add basic metadata to audio files.
Handles patterns like:
  - "Artist - Song Title"
  - "Song Title by Artist"
  - "Artist - Song (Official Video)"
"""

import os
import re
from pathlib import Path

try:
    from mutagen.oggopus import OggOpus
    from mutagen.mp3 import MP3
    from mutagen.id3 import ID3, TIT2, TPE1, TALB
except ImportError:
    print("Error: mutagen not found. Installing...")
    os.system("pip3 install mutagen --break-system-packages")
    from mutagen.oggopus import OggOpus
    from mutagen.mp3 import MP3
    from mutagen.id3 import ID3, TIT2, TPE1, TALB

MUSIC_DIR = "/mnt/boston/media/music/YouTube-Downloads"

def parse_filename(filename):
    """Extract artist and title from YouTube filename."""
    # Remove extension
    name = Path(filename).stem
    
    # Remove common YouTube suffixes
    name = re.sub(r'\s*\(.*?(Official|Lyric|Music|Audio|Video|HD|4K|Live).*?\)', '', name, flags=re.IGNORECASE)
    name = re.sub(r'\s*\[.*?(Official|Lyric|Music|Audio|Video|HD|4K|Live).*?\]', '', name, flags=re.IGNORECASE)
    
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
    
    # No pattern matched - use filename as title, "Unknown Artist"
    return "Unknown Artist", name.strip()

def tag_opus_file(filepath, artist, title):
    """Add metadata to OPUS file."""
    try:
        audio = OggOpus(filepath)
        audio['artist'] = artist
        audio['title'] = title
        audio['album'] = 'YouTube Downloads'
        audio.save()
        return True
    except Exception as e:
        print(f"  ❌ Error tagging {filepath}: {e}")
        return False

def tag_mp3_file(filepath, artist, title):
    """Add metadata to MP3 file."""
    try:
        audio = MP3(filepath, ID3=ID3)
        try:
            audio.add_tags()
        except:
            pass
        
        audio.tags['TIT2'] = TIT2(encoding=3, text=title)
        audio.tags['TPE1'] = TPE1(encoding=3, text=artist)
        audio.tags['TALB'] = TALB(encoding=3, text='YouTube Downloads')
        audio.save()
        return True
    except Exception as e:
        print(f"  ❌ Error tagging {filepath}: {e}")
        return False

def main():
    print("🎵 YouTube Filename Parser & Tagger")
    print("=" * 60)
    print()
    
    if not os.path.exists(MUSIC_DIR):
        print(f"❌ Directory not found: {MUSIC_DIR}")
        return
    
    files = list(Path(MUSIC_DIR).glob("*.opus")) + list(Path(MUSIC_DIR).glob("*.mp3"))
    
    if not files:
        print(f"❌ No audio files found in {MUSIC_DIR}")
        return
    
    print(f"Found {len(files)} files to process")
    print()
    
    tagged = 0
    failed = 0
    
    for filepath in files:
        artist, title = parse_filename(filepath.name)
        
        print(f"📝 {filepath.name}")
        print(f"   Artist: {artist}")
        print(f"   Title:  {title}")
        
        if filepath.suffix == '.opus':
            success = tag_opus_file(str(filepath), artist, title)
        elif filepath.suffix == '.mp3':
            success = tag_mp3_file(str(filepath), artist, title)
        else:
            print(f"   ⚠️  Unsupported format")
            continue
        
        if success:
            print(f"   ✅ Tagged!")
            tagged += 1
        else:
            failed += 1
        
        print()
    
    print("=" * 60)
    print(f"✅ Successfully tagged: {tagged}")
    print(f"❌ Failed: {failed}")
    print()
    print("Navidrome will pick up changes within 5 minutes!")

if __name__ == "__main__":
    main()

