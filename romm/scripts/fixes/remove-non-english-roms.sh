#!/bin/bash

# Script to remove non-English/non-US ROM files
# Keeps only: (USA), (U), (En), (World), (Europe) if they also have English
# Removes: (Japan), (J), (Germany), (France), (Spain), (Italy), (Asia), etc.

GAMES_DIR="/mnt/boston/media/games"

# Platforms to process
PLATFORMS=("gb" "gba" "gbc" "genesis" "snes" "n64" "nes" "ps1")

echo "🗑️  Removing non-English ROM files..."
echo ""

# Patterns that indicate non-English games (must be in parentheses to avoid false matches)
is_non_english() {
    local filename="$1"

    # Check for non-English region codes in parentheses
    if echo "$filename" | grep -qE '\((Japan|Germany|France|Spain|Italy|Netherlands|Sweden|Denmark|Korea|China|Taiwan|Brazil|Russia|Poland|Czech|Portuguese)\)'; then
        return 0  # Is non-English
    fi

    # Check for "Translated" tag (fan translations from Japanese)
    if echo "$filename" | grep -qE '\(Translated'; then
        return 0  # Is non-English
    fi

    # Check for "Unl" tag specifically in parentheses (unlicensed Asian bootlegs)
    if echo "$filename" | grep -qE '\(.*Unl.*\)'; then
        return 0  # Is non-English
    fi

    # Check for single-letter region codes that are non-English
    if echo "$filename" | grep -qE '\(J\)|\(G\)|\(F\)|\(S\)|\(I\)|\(K\)|\(C\)'; then
        return 0  # Is non-English
    fi

    return 1  # Is English or unknown (keep it)
}

for platform in "${PLATFORMS[@]}"; do
    ROMS_DIR="$GAMES_DIR/$platform/roms"

    if [ ! -d "$ROMS_DIR" ]; then
        echo "⚠️  Skipping $platform - directory not found: $ROMS_DIR"
        continue
    fi

    echo "📁 Processing $platform..."

    deleted=0
    find "$ROMS_DIR" -maxdepth 1 -type f \( -name "*.gba" -o -name "*.gbc" -o -name "*.gb" -o -name "*.smc" -o -name "*.sfc" -o -name "*.z64" -o -name "*.n64" -o -name "*.nes" -o -name "*.bin" -o -name "*.md" -o -name "*.gen" -o -name "*.zip" -o -name "*.7z" \) | while read -r filepath; do
        filename=$(basename "$filepath")

        if is_non_english "$filename"; then
            rm "$filepath"
            deleted=$((deleted + 1))
            echo "   🗑️  $filename"
        fi
    done

    if [ "$deleted" -eq 0 ]; then
        echo "   ✓ No non-English files found"
    fi
    echo ""
done

echo "✅ Done! Non-English games removed."

