#!/bin/bash

# Script to clean ROM filenames by removing:
# 1. Number prefixes (e.g., "0025 - ")
# 2. Region/release tags (e.g., "(U)", "(USA)", "(Europe)", "(J)", etc.)
# 3. Release group tags (e.g., "(Eurasia)", "(Mode7)", "(Independent)", etc.)
#
# Example: "0025 - Super Mario Advance (U)(Eurasia).gba" -> "Super Mario Advance.gba"

GAMES_DIR="/mnt/boston/media/games"

# Platforms to process
PLATFORMS=("gb" "gba" "gbc" "genesis" "snes" "n64" "nes" "ps1")

echo "🎮 Cleaning ROM filenames..."
echo ""

clean_filename() {
    local filename="$1"
    local extension="${filename##*.}"
    local basename="${filename%.*}"

    # Remove number prefix (e.g., "0025 - ")
    basename=$(echo "$basename" | sed -E 's/^[0-9]+ - //')

    # Remove all parenthetical tags (region codes, release groups, etc.)
    # This removes things like (U), (USA), (Europe), (J), (Eurasia), (Mode7), etc.
    basename=$(echo "$basename" | sed -E 's/\([^)]*\)//g')

    # Remove square bracket tags like [!], [a], [b], etc.
    basename=$(echo "$basename" | sed -E 's/\[[^]]*\]//g')

    # Clean up extra spaces and trim
    basename=$(echo "$basename" | sed -E 's/  +/ /g' | sed -E 's/^ +| +$//g')

    # Remove trailing spaces/dashes before extension
    basename=$(echo "$basename" | sed -E 's/[ -]+$//')

    echo "$basename.$extension"
}

for platform in "${PLATFORMS[@]}"; do
    ROMS_DIR="$GAMES_DIR/$platform/roms"

    if [ ! -d "$ROMS_DIR" ]; then
        echo "⚠️  Skipping $platform - directory not found: $ROMS_DIR"
        continue
    fi

    echo "📁 Processing $platform..."

    # Process all ROM files
    renamed=0
    find "$ROMS_DIR" -maxdepth 1 -type f \( -name "*.gba" -o -name "*.gbc" -o -name "*.gb" -o -name "*.smc" -o -name "*.sfc" -o -name "*.z64" -o -name "*.n64" -o -name "*.nes" -o -name "*.bin" -o -name "*.md" -o -name "*.gen" -o -name "*.zip" -o -name "*.7z" \) | while read -r filepath; do
        filename=$(basename "$filepath")
        dirname=$(dirname "$filepath")

        # Clean the filename
        newname=$(clean_filename "$filename")

        if [ "$filename" != "$newname" ]; then
            # Check if target file already exists
            if [ -f "$dirname/$newname" ]; then
                echo "   ⚠️  Skipping $filename - target already exists: $newname"
            else
                mv "$filepath" "$dirname/$newname"
                renamed=$((renamed + 1))
                echo "   ✓ $filename"
                echo "      -> $newname"
            fi
        fi
    done

    if [ "$renamed" -eq 0 ]; then
        echo "   ✓ No files to rename"
    else
        echo "   Renamed $renamed files"
    fi
    echo ""
done

echo "✅ Done! Now restart ROMM and rescan to identify games."

