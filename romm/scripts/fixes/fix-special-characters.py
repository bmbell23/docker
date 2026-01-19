#!/usr/bin/env python3
"""
Fix games with special characters in filenames that prevent metadata matching.

This script will:
1. Find games with problematic special characters
2. Clean up the filenames (remove language tags, fix apostrophes, etc.)
3. Update the database with cleaned names
"""

import mysql.connector
import re

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

def clean_filename(filename):
    """
    Clean up filename by removing problematic characters and tags.
    
    Examples:
    - "Alex Ferguson's Player Manager" → "Alex Ferguson's Player Manager"
    - "Game (En,Fr,De,Es,It)" → "Game"
    - "Archer Maclean's 3D Pool" → "Archer Maclean's 3D Pool"
    """
    if not filename:
        return filename
    
    # Remove language tags like (En,Fr,De,Es,It,Nl)
    cleaned = re.sub(r'\s*\([A-Z][a-z],.*?\)', '', filename)
    
    # Remove extra whitespace
    cleaned = re.sub(r'\s+', ' ', cleaned).strip()
    
    return cleaned

def has_problematic_chars(filename):
    """Check if filename has problematic special characters."""
    if not filename:
        return False
    
    # Check for language tags
    if re.search(r'\([A-Z][a-z],.*?\)', filename):
        return True
    
    # Check for other problematic patterns
    # (Add more patterns as needed)
    
    return False

def preview_changes():
    """Preview what changes will be made."""
    print("🔍 Previewing filename cleanup...\n")
    
    db = get_db_connection()
    cursor = db.cursor(dictionary=True)
    
    cursor.execute("""
        SELECT id, fs_name, name
        FROM roms
        ORDER BY fs_name
    """)
    
    roms = cursor.fetchall()
    changes = []
    
    for rom in roms:
        if has_problematic_chars(rom['fs_name']):
            cleaned = clean_filename(rom['fs_name'])
            if cleaned != rom['fs_name']:
                changes.append({
                    'id': rom['id'],
                    'original': rom['fs_name'],
                    'cleaned': cleaned,
                    'name': rom['name']
                })
    
    if changes:
        print(f"Found {len(changes)} files that can be cleaned:\n")
        for i, change in enumerate(changes[:20], 1):  # Show first 20
            print(f"{i}. {change['original']}")
            print(f"   → {change['cleaned']}")
            print()
        
        if len(changes) > 20:
            print(f"... and {len(changes) - 20} more\n")
    else:
        print("✅ No problematic filenames found!\n")
    
    cursor.close()
    db.close()
    
    return len(changes)

def apply_changes():
    """Apply filename cleanup changes."""
    print("🧹 Cleaning up filenames...\n")
    
    db = get_db_connection()
    cursor = db.cursor(dictionary=True)
    
    cursor.execute("""
        SELECT id, fs_name, name
        FROM roms
        ORDER BY fs_name
    """)
    
    roms = cursor.fetchall()
    updated = 0
    
    for rom in roms:
        if has_problematic_chars(rom['fs_name']):
            cleaned = clean_filename(rom['fs_name'])
            if cleaned != rom['fs_name']:
                print(f"✓ {rom['fs_name']}")
                print(f"  → {cleaned}")
                
                # Update fs_name_no_tags field (this is what ROMM uses for matching)
                cursor.execute("""
                    UPDATE roms 
                    SET fs_name_no_tags = %s
                    WHERE id = %s
                """, (cleaned, rom['id']))
                
                updated += 1
    
    db.commit()
    cursor.close()
    db.close()
    
    print(f"\n✅ Updated {updated} filenames")
    return updated

def main():
    """Main function."""
    import sys
    
    print("🔧 ROMM Filename Cleanup")
    print("=" * 50)
    print("\nThis script will clean up filenames with:")
    print("  - Language tags like (En,Fr,De,Es,It)")
    print("  - Other problematic characters")
    print("\nNote: This updates the database only, not the actual files.")
    print()
    
    # Preview changes
    count = preview_changes()
    
    if count == 0:
        print("Nothing to clean up!")
        sys.exit(0)
    
    # Ask for confirmation
    response = input(f"\nDo you want to clean up {count} filenames? (yes/no): ").strip().lower()
    if response not in ['yes', 'y']:
        print("❌ Cleanup cancelled.")
        sys.exit(0)
    
    # Apply changes
    updated = apply_changes()
    
    print("\n" + "=" * 50)
    print("✅ Cleanup complete!")
    print(f"\nUpdated {updated} filenames in the database.")
    print("\n⚠️  IMPORTANT: Run a full rescan in ROMM to update metadata!")
    print("\nTo rescan:")
    print("  1. Go to http://localhost:8080")
    print("  2. Settings → Library → Scan Library")

if __name__ == "__main__":
    main()

