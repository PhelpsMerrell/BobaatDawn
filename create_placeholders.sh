#!/bin/bash

# Create simple 1x1 transparent PNG placeholders
SPRITES=("cup_empty" "drink_regular" "drink_light" "drink_no_ice" "topping_tapioca" "foam_cheese" "lid_straw")

for sprite in "${SPRITES[@]}"; do
    # Create a simple 1x1 transparent PNG using base64
    echo "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==" | base64 -d > "/Users/phelpsmerrell/projects/BobaAtDawn/BobaAtDawn/BobaAtDawn/Assets.xcassets/Boba.spriteatlas/${sprite}.imageset/${sprite}.png"
done

echo "Created placeholder PNGs for all boba sprites"
