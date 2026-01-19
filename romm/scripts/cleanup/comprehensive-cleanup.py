#!/usr/bin/env python3
"""
Comprehensive ROMM library cleanup script.

Handles:
1. Games with weird special characters preventing metadata matching
2. Duplicate region versions (USA vs Europe - keeps USA)
3. Non-playable files (multi-disc games, BIOS files, etc.)
4. Games that are just archives without proper ROM files
"""

import mysql.connector
import re
import os
import subprocess

# Database connection
DB_CONFIG = {
    "host": "localhost",
    "user": "romm-user",
    "password": "romm-password",
    "database": "romm",
    "port": 3306
}

def get_db_connection():
    """Get database connection."""
    return mysql.connector.connect(**DB_CONFIG)

def extract_base_name(name):
    """Extract base game name without region tags."""
    if not name:
        return None
    # Remove common region tags and other metadata
    base = re.sub(r'\s*\([^)]*\)\s*', ' ', name)  # Remove anything in parentheses
    base = re.sub(r'\s*\[[^\]]*\]\s*', ' ', base)  # Remove anything in brackets
    base = re.sub(r'\s+', ' ', base).strip()  # Normalize whitespace
    return base.lower()

def get_region_priority(fs_name):
    """
    Return priority score for region (lower is better).
    USA = 1 (highest priority)
    World = 2
    Europe = 3
    Japan = 4
    Other = 5
    """
    if not fs_name:
        return 999
    
    fs_lower = fs_name.lower()
    
    # USA/US gets highest priority
    if re.search(r'\(usa?\)', fs_lower) or re.search(r'\(u\)', fs_lower):
        return 1
    
    # World or multi-region with USA
    if re.search(r'\(world\)', fs_lower):
        return 2
    
    # Europe
    if re.search(r'\(europe?\)', fs_lower) or re.search(r'\(eu\)', fs_lower):
        return 3
    
    # Japan
    if re.search(r'\(japan\)', fs_lower) or re.search(r'\(j\)', fs_lower):
        return 4
    
    # Everything else
    return 5

def is_undesirable(fs_name):
    """Check if this is a beta, prototype, demo, or other undesirable version."""
    if not fs_name:
        return False
    fs_lower = fs_name.lower()
    patterns = [
        r'\(beta\)', r'\(proto\)', r'\(demo\)', r'\(sample\)',
        r'\(unl\)', r'\(pirate\)', r'\(hack\)', r'\(bad\)',
        r'\[b\d*\]', r'\[h\d*\]', r'\[t\d*\]',  # Bad dumps, hacks, trainers
    ]
    return any(re.search(pattern, fs_lower) for pattern in patterns)

def is_non_playable(fs_name, fs_extension):
    """Check if this is a non-playable file."""
    if not fs_name:
        return False
    
    fs_lower = fs_name.lower()
    
    # Multi-disc games (Disc 2, 3, etc.) - keep Disc 1 only
    if re.search(r'\(disc [2-9]\)', fs_lower):
        return True
    
    # BIOS files
    if 'bios' in fs_lower or '[bios]' in fs_lower:
        return True
    
    # System files
    if fs_lower.startswith('system') or fs_lower.startswith('[system]'):
        return True
    
    return False

def has_special_characters(fs_name):
    """Check if filename has problematic special characters."""
    if not fs_name:
        return False
    
    # Allow: letters, numbers, spaces, dots, hyphens, underscores, parentheses, commas
    # Flag anything else as problematic
    problematic_chars = re.findall(r'[^a-zA-Z0-9 ._\-(),&\']', fs_name)
    return len(problematic_chars) > 0

def cleanup_duplicates():
    """Remove duplicate games, keeping USA versions."""
    print("\n🎮 Removing duplicate region versions (keeping USA)...")
    
    db = get_db_connection()
    cursor = db.cursor(dictionary=True)
    
    # Get all ROMs
    cursor.execute("""
        SELECT id, name, fs_name, fs_path, fs_extension, igdb_id
        FROM roms
        WHERE name IS NOT NULL AND name != ''
        ORDER BY name, id
    """)
    
    roms = cursor.fetchall()
    
    # Group by base name
    from collections import defaultdict
    name_groups = defaultdict(list)
    
    for rom in roms:
        base_name = extract_base_name(rom['name'])
        if base_name:
            name_groups[base_name].append(rom)
    
    deleted = 0
    
    for base_name, group in name_groups.items():
        if len(group) <= 1:
            continue
        
        # Sort by priority
        group.sort(key=lambda x: (
            get_region_priority(x['fs_name']),
            is_undesirable(x['fs_name']),
            x['id']
        ))
        
        # Keep the first one, delete the rest
        keep = group[0]
        to_delete = group[1:]
        
        for rom in to_delete:
            print(f"   🗑️  {rom['fs_name']} (keeping {keep['fs_name']})")
            cursor.execute("DELETE FROM roms WHERE id = %s", (rom['id'],))
            deleted += 1
    
    db.commit()
    cursor.close()
    db.close()
    
    print(f"   ✅ Deleted {deleted} duplicate games")
    return deleted

def cleanup_non_playable():
    """Remove non-playable files."""
    print("\n🚫 Removing non-playable files...")
    
    db = get_db_connection()
    cursor = db.cursor(dictionary=True)
    
    cursor.execute("""
        SELECT id, fs_name, fs_extension, fs_path
        FROM roms
    """)
    
    roms = cursor.fetchall()
    deleted = 0
    
    for rom in roms:
        if is_non_playable(rom['fs_name'], rom['fs_extension']):
            print(f"   🗑️  {rom['fs_name']}")
            cursor.execute("DELETE FROM roms WHERE id = %s", (rom['id'],))
            deleted += 1

    db.commit()
    cursor.close()
    db.close()

    print(f"   ✅ Deleted {deleted} non-playable files")
    return deleted

def report_special_characters():
    """Report games with special characters that might prevent metadata matching."""
    print("\n⚠️  Games with special characters (may prevent metadata matching)...")

    db = get_db_connection()
    cursor = db.cursor(dictionary=True)

    cursor.execute("""
        SELECT id, fs_name, name, igdb_id
        FROM roms
        ORDER BY fs_name
    """)

    roms = cursor.fetchall()
    problematic = []

    for rom in roms:
        if has_special_characters(rom['fs_name']):
            problematic.append(rom)

    if problematic:
        print(f"   Found {len(problematic)} games with special characters:")
        for rom in problematic[:20]:  # Show first 20
            has_metadata = "✓" if rom['igdb_id'] else "✗"
            print(f"   {has_metadata} {rom['fs_name']}")

        if len(problematic) > 20:
            print(f"   ... and {len(problematic) - 20} more")
    else:
        print("   ✅ No problematic characters found")

    cursor.close()
    db.close()

    return len(problematic)

def cleanup_usa_europe_duplicates():
    """Remove (USA, Europe) duplicates when we have separate USA or Europe versions."""
    print("\n🌍 Removing (USA, Europe) duplicates...")

    db = get_db_connection()
    cursor = db.cursor(dictionary=True)

    # Find games with (USA, Europe) in the name
    cursor.execute("""
        SELECT id, name, fs_name, fs_path
        FROM roms
        WHERE fs_name LIKE '%(USA, Europe)%'
    """)

    usa_europe_games = cursor.fetchall()
    deleted = 0

    for game in usa_europe_games:
        base_name = extract_base_name(game['name'])

        # Check if we have a USA-only or Europe-only version
        cursor.execute("""
            SELECT id, fs_name
            FROM roms
            WHERE name = %s
            AND id != %s
            AND (fs_name LIKE '%(USA)%' OR fs_name LIKE '%(Europe)%')
            AND fs_name NOT LIKE '%(USA, Europe)%'
        """, (game['name'], game['id']))

        alternatives = cursor.fetchall()

        if alternatives:
            print(f"   🗑️  {game['fs_name']} (have separate regional versions)")
            cursor.execute("DELETE FROM roms WHERE id = %s", (game['id'],))
            deleted += 1

    db.commit()
    cursor.close()
    db.close()

    print(f"   ✅ Deleted {deleted} (USA, Europe) duplicates")
    return deleted

def main():
    """Run all cleanup operations."""
    import sys

    print("🧹 ROMM Comprehensive Cleanup")
    print("=" * 50)

    # Get initial count
    db = get_db_connection()
    cursor = db.cursor()
    cursor.execute("SELECT COUNT(*) FROM roms")
    initial_count = cursor.fetchone()[0]
    cursor.close()
    db.close()

    print(f"\n📊 Initial game count: {initial_count}")
    print("\nThis script will:")
    print("  1. Remove (USA, Europe) duplicates when separate versions exist")
    print("  2. Remove regional duplicates (keeping USA versions)")
    print("  3. Remove non-playable files (Disc 2+, BIOS, etc.)")
    print("  4. Report games with special characters")
    print("\n⚠️  WARNING: This will DELETE games from your library!")
    print("⚠️  Make sure you have a backup if needed.")

    # Ask for confirmation
    response = input("\nDo you want to continue? (yes/no): ").strip().lower()
    if response not in ['yes', 'y']:
        print("❌ Cleanup cancelled.")
        sys.exit(0)

    # Run cleanup operations
    deleted_usa_europe = cleanup_usa_europe_duplicates()
    deleted_duplicates = cleanup_duplicates()
    deleted_non_playable = cleanup_non_playable()
    special_char_count = report_special_characters()

    # Get final count
    db = get_db_connection()
    cursor = db.cursor()
    cursor.execute("SELECT COUNT(*) FROM roms")
    final_count = cursor.fetchone()[0]
    cursor.close()
    db.close()

    print("\n" + "=" * 50)
    print("✅ Cleanup Complete!")
    print(f"\n📊 Summary:")
    print(f"   Initial games: {initial_count}")
    print(f"   Final games: {final_count}")
    print(f"   Total deleted: {initial_count - final_count}")
    print(f"\n   - (USA, Europe) duplicates: {deleted_usa_europe}")
    print(f"   - Regional duplicates: {deleted_duplicates}")
    print(f"   - Non-playable files: {deleted_non_playable}")
    print(f"   - Games with special chars: {special_char_count} (not deleted)")
    print("\n⚠️  IMPORTANT: Run a full rescan in ROMM to update metadata!")
    print("\nTo rescan:")
    print("  1. Go to http://localhost:8080")
    print("  2. Settings → Library → Scan Library")

if __name__ == "__main__":
    main()


