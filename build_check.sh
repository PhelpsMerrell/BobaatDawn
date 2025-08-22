#!/bin/bash
echo "🔧 Building project to check for errors..."

cd /Users/phelpsmerrell/projects/BobaAtDawn/BobaAtDawn

# Clean build
xcodebuild -project BobaAtDawn.xcodeproj -scheme BobaAtDawn clean build 2>&1 | grep -E "(error|Error|warning|Warning|Missing|missing|inaccessible)"

echo "🔧 Build check complete"
