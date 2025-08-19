#!/bin/bash

# Create all boba sprite directories and Contents.json files
SPRITES=("drink_regular" "drink_light" "drink_no_ice" "topping_tapioca" "foam_cheese" "lid_straw")

for sprite in "${SPRITES[@]}"; do
    mkdir -p "/Users/phelpsmerrell/projects/BobaAtDawn/BobaAtDawn/BobaAtDawn/Assets.xcassets/Boba.spriteatlas/${sprite}.imageset"
    
    cat > "/Users/phelpsmerrell/projects/BobaAtDawn/BobaAtDawn/BobaAtDawn/Assets.xcassets/Boba.spriteatlas/${sprite}.imageset/Contents.json" << EOF
{
  "images" : [
    {
      "filename" : "${sprite}.png",
      "idiom" : "universal",
      "scale" : "1x"
    },
    {
      "idiom" : "universal",
      "scale" : "2x"
    },
    {
      "idiom" : "universal",
      "scale" : "3x"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
EOF
done
