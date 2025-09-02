#!/bin/bash

echo "🧹 Cleaning and rebuilding BobaAtDawn project..."

cd "$(dirname "$0")"

# Clean build folder
echo "🧹 Cleaning build folder..."
rm -rf ~/Library/Developer/Xcode/DerivedData/BobaAtDawn-*

# Clean project
echo "🧹 Cleaning Xcode project..."
xcodebuild -project BobaAtDawn.xcodeproj -scheme BobaAtDawn clean

# Build project
echo "🔨 Building project..."
xcodebuild -project BobaAtDawn.xcodeproj -scheme BobaAtDawn -destination "platform=iOS Simulator,name=iPhone 15" build

echo "✅ Build complete! Check for any asset loading errors in the console."
