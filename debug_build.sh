#!/bin/bash

# Debug build script to identify the size issue
echo "🔧 Building and testing forest scene sizing..."

cd /Users/phelpsmerrell/projects/BobaAtDawn/BobaAtDawn

# Try to build the project
xcodebuild -project BobaAtDawn.xcodeproj -scheme BobaAtDawn clean build

echo "🔧 Build complete. Check for size-related issues above."
