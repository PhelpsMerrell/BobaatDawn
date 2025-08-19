# 📚 **Boba in the Woods - Study Guide**

## 🎯 **What We Just Implemented**

### **NEW FEATURES:**
- ✅ **Power Breaker System** - Toggle station power on/off
- ✅ **Interaction Mode System** - Browse vs Arrange modes  
- ✅ **Character Class** - Encapsulated player logic
- ✅ **Rotatable Objects** - 4-state rotation with visual feedback
- ✅ **Enhanced Gesture System** - Context-sensitive interactions
- ✅ **Completed Drink System** - Non-rotatable boba drinks
- ✅ **Multi-Drink Creation** - Create and place multiple boba drinks
- ✅ **Selection Indicator Control** - No yellow circles in browse mode
- ✅ **Smart Pathfinding** - GameplayKit pathfinding prevents teleporting through obstacles

---

## 🏗️ **Architecture Overview**

### **Class Hierarchy:**
```
GameScene (Main orchestrator)
├── Character (Player logic)
├── PowerBreaker (Mode switching)
├── BobaBrewingStation : RotatableObject
├── RotatableObject (Base for movable items)
└── Regular SKSpriteNodes (Tables, walls)
```

### **Separation of Concerns:**
- **GameScene**: Camera, world setup, gesture coordination
- **Character**: Movement, carrying, collision avoidance  
- **RotatableObject**: Rotation states, selection, visual shapes
- **PowerBreaker**: Mode switching, visual feedback
- **BobaBrewingStation**: Drink creation, power management

---

## 🎮 **Current Gesture Mapping**

### **BROWSE MODE (Default):**
- **Single Tap** → Move character
- **Long Press small items (drink/completedDrink)** → Pick up and carry
- **Long Press large items (furniture/station)** → Enter arrange mode
- **Long Press power breaker** → Toggle power state
- **Long Press brewing areas** → Interact (if powered)
- **Long Press completed drink in station** → Pick up finished boba
- **Two-finger rotate while carrying rotatable items** → Rotate carried item
- **Pinch** → Camera zoom
- **Two-finger tap** → Reset zoom

### **ARRANGE MODE (Power Off):**
- **Tap objects** → Select for rotation
- **Tap empty space** → Exit arrange mode
- **Two-finger rotate on selected** → Rotate object
- **All other gestures** → Same as browse mode

---

## 🔧 **Key Swift Concepts in Our Code**

### **1. Enums with Associated Values:**
```swift
enum ObjectType {
    case drink        // Small, portable test items
    case furniture    // Large, arrangeable items
    case station      // Boba station parts
    case completedDrink // Finished boba drinks (non-rotatable)
}

enum RotationState: Int, CaseIterable {
    case north = 0, east = 90, south = 180, west = 270
    
    func next() -> RotationState {
        // Cycles through all cases
    }
}
```

### **2. Property Observers (didSet):**
```swift
private var currentMode: InteractionMode = .browse {
    didSet {
        updateModeVisuals() // Called automatically when mode changes
    }
}
```

### **3. Closures/Callbacks:**
```swift
// PowerBreaker calls this when toggled
PowerBreaker { [weak self] isPowered in
    self?.handlePowerStateChange(isPowered)
}
```

### **4. Optional Binding Patterns:**
```swift
// Safe unwrapping
guard let item = carriedItem else { return }

// Multiple optionals
if let touch = touches.first, let view = view {
    // Both exist, safe to use
}
```

### **5. Class Inheritance:**
```swift
class BobaBrewingStation: RotatableObject {
    // Inherits rotation, selection, visual feedback
    // Adds brewing-specific functionality
}
```

---

## 📂 **File Structure & What Each Does**

### **🎯 GameScene.swift** (Main Orchestrator)
**What it handles:**
- Camera system (following, zoom, bounds)
- World setup (walls, tables, layout)
- Gesture recognition and routing
- Mode management (browse/arrange)
- Touch event coordination

**Key Methods to Study:**
- `setupGestures()` - How gestures are wired up
- `handleTap()` - Mode-specific tap behavior
- `updateCamera()` - Smooth camera following
- `findInteractableNode()` - Touch target detection

### **🧑‍💼 Character.swift** (Player Logic)
**What it handles:**
- Smart pathfinding using GameplayKit's GKObstacleGraph
- Collision avoidance with smooth navigation around obstacles
- Item carrying state management
- Physics body setup
- Carried item positioning during movement

**New Pathfinding Features:**
- **GKObstacleGraph**: Uses GameplayKit for professional pathfinding
- **Obstacle detection**: Includes tables, brewing station, and large furniture
- **Buffer zones**: Adds padding around obstacles for smooth navigation
- **Fallback system**: Falls back to direct movement if no path found
- **Multi-waypoint movement**: Follows paths with multiple waypoints smoothly

**Key Concepts:**
- **Encapsulation**: All player logic in one place
- **State Management**: `isCarrying` computed property
- **Smart Navigation**: `moveWithPathfinding()` and `followPath()` methods

### **🔄 RotatableObject.swift** (Rotatable Items)
**What it handles:**
- 4-state rotation system (N/E/S/W)
- Visual shape creation (arrows, L-shapes, triangles)
- Selection highlighting
- Object type categorization (drink/furniture/station)

**Key Features:**
- **Shape Factory**: Different visual indicators for rotation
- **State Machine**: Clean rotation state transitions
- **Visual Feedback**: Selection indicators, animations

### **⚡ PowerBreaker.swift** (Mode Switching)
**What it handles:**
- Power state visualization (green/red light)
- Switch animation (up/down position)
- Callback system for state changes
- Thematic integration (turning off power = arrange mode)

### **🧋 BobaBrewingStation.swift** (Drink Creation)
**What it handles:**
- Drink assembly system (tea + toppings + lid)
- Power-dependent interactions
- Large interaction areas for mobile
- Completed drink creation and pickup
- New boba drink spawning after pickup

**New Features:**
- **Non-rotatable completed drinks**: Uses `.completedDrink` type
- **Automatic station reset**: New drink can be started immediately
- **Proper pickup integration**: Long press completed drink to pick up

---

## 🎯 **Swift vs C# Quick Reference**

### **Properties:**
```swift
// Swift - Computed property
var isCarrying: Bool {
    return carriedItem != nil
}

// C# equivalent
public bool IsCarrying => carriedItem != null;
```

### **Initialization:**
```swift
// Swift - Custom initializer
init(type: ObjectType, color: SKColor) {
    self.objectType = type
    super.init(texture: nil, color: color, size: defaultSize)
    setupVisuals()
}

// C# equivalent
public RotatableObject(ObjectType type, SKColor color) : base(null, color, defaultSize) {
    this.objectType = type;
    SetupVisuals();
}
```

### **Event Handling:**
```swift
// Swift - Closure-based callbacks
PowerBreaker { isPowered in
    self.handlePowerChange(isPowered)
}

// C# equivalent
powerBreaker.PowerChanged += (isPowered) => {
    this.HandlePowerChange(isPowered);
};
```

---

## 🎮 **How the Systems Connect**

### **Power System Flow:**
1. **User long-presses breaker** → `PowerBreaker.toggle()`
2. **Breaker calls callback** → `GameScene.handlePowerStateChange()`
3. **GameScene updates mode** → `currentMode = .arrange` 
4. **Mode change triggers** → `updateModeVisuals()`
5. **Station becomes movable** → `brewingStation.setArrangeMode(true)`

### **Object Interaction Flow:**
1. **Touch detected** → `touchesBegan()`
2. **Find target** → `findInteractableNode()`
3. **Route by mode** → Browse vs Arrange logic
4. **Execute action** → Pick up, rotate, move, or select

### **Character Movement:**
1. **Tap location** → `character.moveTo()`
2. **Collision check** → `getValidPosition()` 
3. **Move character** → SKAction animation
4. **Update carried item** → Follow character position

---

## 🔍 **What to Study Next**

### **For Understanding Swift:**
1. **Optional binding patterns** in `findInteractableNode()`
2. **Enum with methods** in `RotationState`
3. **Closure capture** `[weak self]` in callbacks
4. **Property observers** `didSet` in mode changes

### **For Understanding Architecture:**
1. **Delegation pattern** in PowerBreaker callbacks
2. **State machine** in RotatableObject rotation
3. **Encapsulation** in Character class
4. **Composition** in GameScene coordinating subsystems

### **For Understanding Game Development:**
1. **Touch handling pipeline** from touches to actions
2. **Camera constraints** and smooth following
3. **Visual feedback systems** (selection, animation)
4. **Gesture recognition** and conflict resolution

---

## ✅ **Test Plan**

1. **Build and run** - Should compile cleanly
2. **Find power breaker** - Walk to upper-left, look for gray panel
3. **Test power toggle** - Long press breaker, watch light change
4. **Test arrange mode** - Power off = objects can be selected and rotated
5. **Test object pickup** - Long press any small item (green triangle, boba drinks)
6. **Test rotation** - Carry rotatable items, two-finger rotate to see 4 states
7. **Test brewing** - Power on, long press brewing areas, make complete drink
8. **Test boba pickup** - Complete drink shakes, long press to pick up
9. **Test multiple bobas** - Create, pickup, place multiple drinks around shop
10. **Verify no yellow circles** - Browse mode should show no selection indicators
11. **Test pathfinding** - Try clicking behind tables/obstacles, character should path around
12. **Test navigation** - No more teleporting through collision boxes!

**Fixed Issues:**
- ✅ **Selection indicators removed** in browse mode
- ✅ **All objects now pickupable** (test triangle, furniture in arrange mode)
- ✅ **Boba drinks are non-rotatable** but still carriable
- ✅ **Multiple boba creation** - station resets after each pickup
- ✅ **Smart pathfinding** - Character navigates around obstacles properly
- ✅ **No more teleporting** - Uses GameplayKit's professional pathfinding

The architecture is now properly separated and extensible for your future features!
