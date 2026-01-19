#!/bin/bash

# Master cleanup script - runs all cleanup operations in the correct order

echo "🧹 ROMM Complete Library Cleanup"
echo "=================================="
echo ""
echo "This script will:"
echo "  1. Show you a preview of what will be cleaned"
echo "  2. Remove duplicate games (USA vs Europe, etc.)"
echo "  3. Remove non-playable files (Disc 2+, BIOS)"
echo "  4. Fix filenames with special characters"
echo "  5. Prompt you to rescan your library"
echo ""
echo "⚠️  WARNING: This will DELETE games from your library!"
echo ""

read -p "Do you want to continue? (yes/no): " response
if [[ ! "$response" =~ ^[Yy]([Ee][Ss])?$ ]]; then
    echo "❌ Cleanup cancelled."
    exit 0
fi

echo ""
echo "=" | tr '=' '=' | head -c 50; echo ""
echo ""

# Step 1: Preview
echo "📋 Step 1: Preview"
echo "------------------"
./cleanup-preview.sh
echo ""

read -p "Continue with cleanup? (yes/no): " response
if [[ ! "$response" =~ ^[Yy]([Ee][Ss])?$ ]]; then
    echo "❌ Cleanup cancelled."
    exit 0
fi

echo ""
echo "=" | tr '=' '=' | head -c 50; echo ""
echo ""

# Step 2: Main cleanup
echo "🗑️  Step 2: Removing duplicates and non-playable files"
echo "------------------------------------------------------"
python3 comprehensive-cleanup.py
echo ""

# Step 3: Fix special characters
echo "=" | tr '=' '=' | head -c 50; echo ""
echo ""
echo "🔧 Step 3: Fixing special characters in filenames"
echo "-------------------------------------------------"
python3 fix-special-characters.py
echo ""

# Step 4: Remind to rescan
echo "=" | tr '=' '=' | head -c 50; echo ""
echo ""
echo "✅ All cleanup operations complete!"
echo ""
echo "📊 Next Steps:"
echo ""
echo "1. ⚠️  IMPORTANT: Rescan your library in ROMM"
echo "   - Go to http://localhost:8080"
echo "   - Settings → Library → Scan Library"
echo "   - Wait for the scan to complete"
echo ""
echo "2. Check your library for any issues"
echo ""
echo "3. If you find games that still don't have metadata:"
echo "   - Try manually searching for them in ROMM"
echo "   - Or delete them if they're not needed"
echo ""
echo "🎮 Enjoy your cleaned-up game library!"

