#!/bin/bash

echo "🔧 Testing all fixes applied to BobaAtDawn project..."
cd /Users/phelpsmerrell/projects/BobaAtDawn/BobaAtDawn

echo "📋 Checking for critical issues:"

# Check for missing size parameters
echo "1. Checking for scene creation without size parameter..."
grep -r "Scene()" --include="*.swift" BobaAtDawn/ || echo "   ✅ No scenes created without size parameter"

# Check for private access issues
echo "2. Checking for 'inaccessible due to private' issues..."
echo "   - roomEmojis should be internal: $(grep -c "internal let roomEmojis" BobaAtDawn/Forest/ForestScene.swift || echo "0") occurrences"
echo "   - currentRoom should be internal: $(grep -c "internal var currentRoom" BobaAtDawn/Forest/ForestScene.swift || echo "0") occurrences"

# Check for proper initializers
echo "3. Checking scene initializers..."
for scene in "ForestScene" "GameScene" "TitleScene"; do
    init_count=$(grep -c "override init(size:" BobaAtDawn/*/${scene}.swift 2>/dev/null || echo "0")
    echo "   - ${scene} has init(size:): ${init_count} occurrences"
done

echo "4. Quick compilation check..."
# Try to compile just to check for syntax errors
xcodebuild -project BobaAtDawn.xcodeproj -scheme BobaAtDawn -configuration Debug -sdk iphonesimulator build-for-testing 2>&1 | head -20

echo "🔧 Test complete!"
