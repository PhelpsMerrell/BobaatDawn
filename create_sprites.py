#!/usr/bin/env python3

# Create placeholder sprites for testing character animation

from PIL import Image, ImageDraw
import os

def create_placeholder_sprite(direction, frame, output_dir):
    """Create a simple placeholder sprite for testing"""
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
    if direction in [0, 7, 1]:  # Down variants
        draw.rectangle([15, 26, 17, 28], fill=(0, 0, 0, 255))  # Bottom dot
    elif direction in [2, 3]:  # Right variants  
        draw.rectangle([22, 15, 24, 17], fill=(0, 0, 0, 255))  # Right dot
    elif direction in [4, 5]:  # Up variants
        draw.rectangle([15, 6, 17, 8], fill=(0, 0, 0, 255))   # Top dot
    else:  # Left variants
        draw.rectangle([8, 15, 10, 17], fill=(0, 0, 0, 255))  # Left dot

    # Save image
    image_path = f"{output_dir}/player_{direction}_{frame}.png"
    img.save(image_path)
    return image_path

def create_contents_json(output_dir, direction, frame):
    """Create Contents.json for imageset"""
    contents = {
        "images": [
            {
                "filename": f"player_{direction}_{frame}.png",
                "idiom": "universal",
                "scale": "1x"
            }
        ],
        "info": {
            "author": "xcode",
            "version": 1
        }
    }
    
    import json
    with open(f"{output_dir}/Contents.json", 'w') as f:
        json.dump(contents, f, indent=2)

def main():
    print("🎭 Creating placeholder character sprites for testing...")
    
    base_dir = "/Users/phelpsmerrell/projects/BobaAtDawn/BobaAtDawn/BobaAtDawn/Assets.xcassets/Player.spriteatlas"
    
    # Create placeholder sprites for all directions and frames
    created_count = 0
    for direction in range(8):
        for frame in range(3):
            output_dir = f"{base_dir}/player_{direction}_{frame}.imageset"
            os.makedirs(output_dir, exist_ok=True)
            
            try:
                image_path = create_placeholder_sprite(direction, frame, output_dir)
                create_contents_json(output_dir, direction, frame)
                created_count += 1
                print(f"✅ Created: direction {direction}, frame {frame}")
            except Exception as e:
                print(f"❌ Error creating direction {direction}, frame {frame}: {e}")
    
    print(f"\n🎉 Created {created_count} placeholder sprites!")
    print("📁 Sprites saved to Player.spriteatlas")
    print("\nDirection color guide:")
    print("  Down (0): Brown")
    print("  Down-Right (1): Saddle Brown")
    print("  Right (2): Tan") 
    print("  Up-Right (3): Burlywood")
    print("  Up (4): Beige")
    print("  Up-Left (5): Bisque")
    print("  Left (6): Peach")
    print("  Down-Left (7): Light Salmon")

if __name__ == "__main__":
    main()
