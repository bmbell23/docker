#!/usr/bin/env python3
"""
Cleanup script to remove duplicate ROMs, keeping USA versions over other regions.

Priority order:
1. USA/US versions (keep these)
2. Europe/EU versions (delete if USA exists)
3. Other regions (delete if USA or Europe exists)
"""

import mysql.connector
import re
import os

# Database connection
db = mysql.connector.connect(
    host="localhost",
    user="romm-user",
    password="romm-password",
    database="romm",
    port=3306
)

cursor = db.cursor(dictionary=True)

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
    World/USA+Europe = 2
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
    if re.search(r'\(world\)', fs_lower) or re.search(r'\(usa?, europe\)', fs_lower):
        return 2
    
    # Europe
    if re.search(r'\(europe?\)', fs_lower) or re.search(r'\(eu\)', fs_lower):
        return 3
    
    # Japan
    if re.search(r'\(japan\)', fs_lower) or re.search(r'\(j\)', fs_lower):
        return 4
    
    # Everything else
    return 5

def is_beta_or_proto(fs_name):
    """Check if this is a beta, prototype, or demo version."""
    if not fs_name:
        return False
    fs_lower = fs_name.lower()
    return bool(re.search(r'\(beta\)|\(proto\)|\(demo\)|\(sample\)', fs_lower))

print("🔍 Finding duplicate ROMs by name...")

# Get all ROMs with their names
cursor.execute("""
    SELECT id, name, fs_name, fs_path, igdb_id, path_cover_s
    FROM roms
    WHERE name IS NOT NULL AND name != ''
    ORDER BY name, id
""")

roms = cursor.fetchall()
print(f"   Found {len(roms)} total ROMs")

# Group by base name
from collections import defaultdict
name_groups = defaultdict(list)

for rom in roms:
    base_name = extract_base_name(rom['name'])
    if base_name:
        name_groups[base_name].append(rom)

# Find duplicates
duplicates_found = 0
duplicates_deleted = 0

print("\n🎮 Processing duplicates (keeping USA versions)...\n")

for base_name, group in name_groups.items():
    if len(group) <= 1:
        continue
    
    # Sort by priority: region priority first, then beta/proto last, then by ID
    group.sort(key=lambda x: (
        get_region_priority(x['fs_name']),
        is_beta_or_proto(x['fs_name']),
        x['id']
    ))
    
    # Keep the first one (best priority), delete the rest
    keep = group[0]
    to_delete = group[1:]
    
    for rom in to_delete:
        duplicates_found += 1
        
        # Show what we're doing
        keep_region = re.search(r'\([^)]*\)', keep['fs_name'])
        delete_region = re.search(r'\([^)]*\)', rom['fs_name'])
        
        keep_tag = keep_region.group(0) if keep_region else "(no region)"
        delete_tag = delete_region.group(0) if delete_region else "(no region)"
        
        print(f"   🗑️  Duplicate: {rom['name']} {delete_tag} (ID: {rom['id']}, keeping {keep_tag} ID: {keep['id']})")
        
        # Delete the ROM
        try:
            cursor.execute("DELETE FROM roms WHERE id = %s", (rom['id'],))
            duplicates_deleted += 1
        except Exception as e:
            print(f"      ❌ Error deleting ROM {rom['id']}: {e}")

# Commit changes
db.commit()

print(f"\n✅ Cleanup complete!")
print(f"   Found {duplicates_found} duplicates")
print(f"   Deleted {duplicates_deleted} ROMs")
print(f"   Kept USA/US versions where available")

cursor.close()
db.close()

