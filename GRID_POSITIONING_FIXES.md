# Grid Positioning Issues & Fixes

## 🚨 Problems Found

### 1. Grid Origin Off-Center
**Current:** `shopOrigin = (-1000, -750)`  
**Problem:** Grid is not centered in world, causing character to start way off-center

### 2. Mixed Coordinate Systems
- Some objects use **grid coordinates** (stations, tables, character)
- Others use **absolute world coordinates** (time system, doors, walls)
- Shop floor uses weird offset `(0, 150)` that's not grid-aligned

### 3. Poor Grid-to-World Alignment
- Grid: 33x25 cells @ 60pt = 1980x1500 
- World: 2000x1500
- Extra 20pt on width creates asymmetry

## ✅ Recommended Fixes

### Fix 1: Center the Grid
```swift
// Calculate centered grid origin
let gridWidth = CGFloat(columns) * cellSize  // 1980
let gridHeight = CGFloat(rows) * cellSize    // 1500
let shopOrigin = CGPoint(
    x: -gridWidth / 2,   // -990 (centered)
    y: -gridHeight / 2   // -750 (centered)
)
```

### Fix 2: Convert Everything to Grid
```swift
// Time system
static let breakerGridPosition = GridCoordinate(x: 3, y: 20)    // Top-left area
static let windowGridPosition = GridCoordinate(x: 29, y: 18)    // Top-right area

// Door position  
static let doorGridPosition = GridCoordinate(x: 0, y: 12)       // Left wall center

// Shop floor area (grid-aligned rectangle)
static let shopFloorArea = (
    topLeft: GridCoordinate(x: 10, y: 8),
    bottomRight: GridCoordinate(x: 23, y: 18)
)
```

### Fix 3: Consistent Character Starting Position
```swift
// Center of grid world
static let characterStartPosition = GridCoordinate(x: 16, y: 12) // Already good!
```

## 🎯 Benefits of Fixes

1. **Predictable Movement** - Everything snaps to grid properly
2. **Easy Layout** - Position things by grid coordinates, not guessing world positions  
3. **Consistent Feel** - All objects follow same positioning rules
4. **Easier Debugging** - Grid overlay will actually align with objects

## 🚀 Quick Win: Enable Grid Overlay
Set `showGridOverlay = true` in GameScene to see current positioning issues visually.

## Implementation Priority
1. **High Priority:** Fix grid centering (impacts all positioning)
2. **Medium Priority:** Convert time system to grid coordinates
3. **Low Priority:** Clean up shop floor positioning

Current setup makes things hard to position because you're fighting two coordinate systems!
