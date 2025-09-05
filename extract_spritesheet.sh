#!/bin/bash

# Spritesheet Frame Extractor for Boba in the Woods
# This script takes your player spritesheet and creates individual frame files

echo "🎭 Setting up player spritesheet for Boba in the Woods..."

# Configuration
SPRITESHEET_FILE="player_spritesheet.png"  # Your uploaded spritesheet
OUTPUT_DIR="/Users/phelpsmerrell/projects/BobaAtDawn/BobaAtDawn/BobaAtDawn/Assets.xcassets/Player.spriteatlas"

# Spritesheet dimensions (based on your actual file metrics)
FRAME_WIDTH=21    # Width of each frame (exact)
FRAME_HEIGHT=34   # Height of each frame (exact)
MARGIN=2          # Outer transparent border
SPACING=2         # Gutters between tiles
FRAMES_PER_ROW=3  # Number of animation frames per direction
TOTAL_ROWS=8      # Number of direction rows

echo "Frame size: ${FRAME_WIDTH}x${FRAME_HEIGHT}"
echo "Margin: ${MARGIN}px, Spacing: ${SPACING}px"
echo "Layout: ${FRAMES_PER_ROW} frames × ${TOTAL_ROWS} directions"

# Check if ImageMagick is available
if ! command -v magick &> /dev/null; then
    echo "❌ ImageMagick not found. Installing via Homebrew..."
    if command -v brew &> /dev/null; then
        brew install imagemagick
    else
        echo "❌ Please install ImageMagick or Homebrew first"
        echo "Visit: https://imagemagick.org/script/download.php"
        exit 1
    fi
fi

# Check if spritesheet exists
if [ ! -f "$SPRITESHEET_FILE" ]; then
    echo "❌ Spritesheet file not found: $SPRITESHEET_FILE"
    echo "Please place your spritesheet image in the current directory"
    exit 1
fi

echo "✅ Found spritesheet: $SPRITESHEET_FILE"

# Create individual frame files
for row in $(seq 0 $((TOTAL_ROWS - 1))); do
    for frame in $(seq 0 $((FRAMES_PER_ROW - 1))); do
        # Calculate crop position with margin and spacing
        # Formula: MARGIN + (frame * (FRAME_WIDTH + SPACING))
        x=$((MARGIN + frame * (FRAME_WIDTH + SPACING)))
        y=$((MARGIN + row * (FRAME_HEIGHT + SPACING)))
        
        # Output filename
        output_file="${OUTPUT_DIR}/player_${row}_${frame}.imageset"
        mkdir -p "$output_file"
        
        # Extract frame using ImageMagick
        magick "$SPRITESHEET_FILE" -crop "${FRAME_WIDTH}x${FRAME_HEIGHT}+${x}+${y}" "${output_file}/player_${row}_${frame}.png"
        
        # Create Contents.json for this imageset
        cat > "${output_file}/Contents.json" << EOF
{
  "images" : [
    {
      "filename" : "player_${row}_${frame}.png",
      "idiom" : "universal",
      "scale" : "1x"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
EOF
        
        echo "✅ Extracted frame: direction ${row}, frame ${frame}"
    done
done

echo "🎉 Spritesheet extraction complete!"
echo "📁 Frames saved to: $OUTPUT_DIR"
echo ""
echo "Next steps:"
echo "1. Copy your spritesheet image to this directory as 'player_spritesheet.png'"
echo "2. Run this script: ./extract_spritesheet.sh"
echo "3. The animated character will replace the rectangle in your game"
echo ""
echo "Direction mapping:"
echo "Row 0: Down"
echo "Row 1: Down-Right"
echo "Row 2: Right" 
echo "Row 3: Up-Right"
echo "Row 4: Up"
echo "Row 5: Up-Left"
echo "Row 6: Left"
echo "Row 7: Down-Left"
