#!/bin/bash

# Create placeholder sprites for testing while waiting for the real spritesheet

echo "🎭 Creating placeholder character sprites for testing..."

OUTPUT_DIR="/Users/phelpsmerrell/projects/BobaAtDawn/BobaAtDawn/BobaAtDawn/Assets.xcassets/Player.spriteatlas"

# Create placeholder sprites using Python/PIL
create_placeholder_sprite() {
    local direction=$1
    local frame=$2
    local output_dir="${OUTPUT_DIR}/player_${direction}_${frame}.imageset"
    
    mkdir -p "$output_dir"
    
    # Create a simple colored sprite with Python
    python3 -c "
from PIL import Image, ImageDraw
import sys

# Create 32x32 image
size = (32, 32)
img = Image.new('RGBA', size, (0, 0, 0, 0))
draw = ImageDraw.Draw(img)

# Direction colors (for easy identification)
colors = [
    (139, 69, 19, 255),   # 0: Down - Brown
    (160, 82, 45, 255),   # 1: Down-Right - Saddle Brown  
    (210, 180, 140, 255), # 2: Right - Tan
    (222, 184, 135, 255), # 3: Up-Right - Burlywood
    (245, 245, 220, 255), # 4: Up - Beige
    (255, 228, 196, 255), # 5: Up-Left - Bisque
    (255, 218, 185, 255), # 6: Left - Peach
    (255, 160, 122, 255)  # 7: Down-Left - Light Salmon
]

direction = $direction
frame = $frame
color = colors[direction % len(colors)]

# Draw character sprite (simple figure)
margin = 4
# Head
head_size = 8
head_x = 16 - head_size // 2
head_y = margin + 2
draw.ellipse([head_x, head_y, head_x + head_size, head_y + head_size], 
             fill=color, outline=(0, 0, 0, 255))

# Body 
body_width = 12
body_height = 10
body_x = 16 - body_width // 2
body_y = head_y + head_size
draw.rectangle([body_x, body_y, body_x + body_width, body_y + body_height], 
               fill=color, outline=(0, 0, 0, 255))

# Legs (vary by frame for animation)
leg_width = 3
leg_height = 8
leg_y = body_y + body_height

if frame == 0:  # Standing
    draw.rectangle([body_x + 2, leg_y, body_x + 2 + leg_width, leg_y + leg_height], fill=color)
    draw.rectangle([body_x + body_width - 2 - leg_width, leg_y, body_x + body_width - 2, leg_y + leg_height], fill=color)
elif frame == 1:  # Left leg forward
    draw.rectangle([body_x + 1, leg_y, body_x + 1 + leg_width, leg_y + leg_height], fill=color)
    draw.rectangle([body_x + body_width - 3 - leg_width, leg_y, body_x + body_width - 3, leg_y + leg_height], fill=color)
else:  # Right leg forward
    draw.rectangle([body_x + 3, leg_y, body_x + 3 + leg_width, leg_y + leg_height], fill=color)
    draw.rectangle([body_x + body_width - 1 - leg_width, leg_y, body_x + body_width - 1, leg_y + leg_height], fill=color)

# Direction indicator
if direction == 0 or direction == 7 or direction == 1:  # Down variants
    draw.rectangle([15, 26, 17, 28], fill=(0, 0, 0, 255))  # Bottom dot
elif direction == 2 or direction == 3:  # Right variants  
    draw.rectangle([22, 15, 24, 17], fill=(0, 0, 0, 255))  # Right dot
elif direction == 4 or direction == 5:  # Up variants
    draw.rectangle([15, 6, 17, 8], fill=(0, 0, 0, 255))   # Top dot
else:  # Left variants
    draw.rectangle([8, 15, 10, 17], fill=(0, 0, 0, 255))  # Left dot

# Save image
img.save('${output_dir}/player_${direction}_${frame}.png')
print(f'Created placeholder sprite: direction {direction}, frame {frame}')
"
    
    # Create Contents.json for this imageset
    cat > "${output_dir}/Contents.json" << EOF
{
  "images" : [
    {
      "filename" : "player_${direction}_${frame}.png",
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
}

# Check if Python and PIL are available
if ! python3 -c "from PIL import Image" 2>/dev/null; then
    echo "❌ Python PIL not available. Installing..."
    pip3 install Pillow
fi

# Create placeholder sprites for all directions and frames
for direction in {0..7}; do
    for frame in {0..2}; do
        create_placeholder_sprite $direction $frame
    done
done

echo "🎉 Placeholder sprites created!"
echo "📁 Sprites saved to: $OUTPUT_DIR"
echo ""
echo "The character will now appear as a simple colored figure instead of a rectangle."
echo "Different directions will have different colors to help with debugging:"
echo "  Down (0): Brown"
echo "  Down-Right (1): Saddle Brown"
echo "  Right (2): Tan" 
echo "  Up-Right (3): Burlywood"
echo "  Up (4): Beige"
echo "  Up-Left (5): Bisque"
echo "  Left (6): Peach"
echo "  Down-Left (7): Light Salmon"
echo ""
echo "To replace with your real spritesheet:"
echo "1. Name your spritesheet 'player_spritesheet.png'"
echo "2. Place it in the project directory"
echo "3. Run: ./extract_spritesheet.sh"
