# 🏗️ **Boba in the Woods - Swift Project Structure**

## 📁 **Project Architecture Overview**

```
BobaAtDawn/
├── 🎮 Core Game Files
│   ├── GameScene.swift          # Main shop scene (SpriteKit)
│   ├── Character.swift          # Player movement & item carrying
│   ├── NPC.swift               # Forest animal customers
│   └── TitleScene.swift        # Game entry point
│
├── 🌲 Forest System
│   └── Forest/
│       └── ForestScene.swift   # 5-room looping exploration
│
├── 🍃 Grid System (Custom Framework)
│   └── Grid/
│       ├── GridWorld.swift     # Singleton grid manager
│       ├── GridCoordinate.swift # Grid position struct
│       └── GameObject.swift    # Grid object wrapper
│
├── 🧋 Boba Creation System
│   ├── IngredientStation.swift # Ice/Tea/Boba/Foam/Lid stations
│   ├── DrinkCreator.swift      # Recipe display & drink building
│   └── RotatableObject.swift   # Interactive world objects
│
├── ⏰ Time & Systems
│   ├── TimeManager.swift       # Day/night cycle singleton
│   ├── PowerBreaker.swift      # Time system control
│   └── Window.swift           # Time display UI
│
└── 🎨 Assets
    ├── Assets.xcassets/        # Sprites & images
    ├── GameScene.sks          # SpriteKit scene file
    └── Actions.sks            # SpriteKit actions
```

---

## 🎯 **Scene Architecture (SpriteKit)**

### **Two Main Scenes:**
- **`GameScene`**: Boba shop with NPC customers & boba creation
- **`ForestScene`**: 5-room exploration area with transitions

### **Scene Transition Pattern:**
```swift
// Shop → Forest (long press door)
let forestScene = ForestScene(size: self?.size ?? CGSize(width: 1024, height: 768))
forestScene.scaleMode = .aspectFill
self?.view?.presentScene(forestScene, transition: SKTransition.fade(withDuration: 0.5))

// Forest → Shop (same pattern, reversed)
```

---

## 🔧 **Key Swift Patterns & Practices**

### **1. Singleton Pattern (Shared State)**
```swift
// GridWorld - manages 33x25 game grid
class GridWorld {
    static let shared = GridWorld()
    private init() {} // Prevent multiple instances
    
    private var occupiedCells: [GridCoordinate: GameObject] = [:]
    private var reservedCells: Set<GridCoordinate> = []
}

// TimeManager - handles day/night cycle
class TimeManager {
    static let shared = TimeManager()
    private init() {}
    
    var currentPhase: TimePhase = .day
    var isTimeActive: Bool = true
}
```

### **2. Enum-Driven Design**
```swift
enum TimePhase: CaseIterable {
    case dawn, day, dusk, night
    
    var duration: TimeInterval {
        switch self {
        case .dawn, .dusk: return 240 // 4 minutes
        case .day, .night: return 480 // 8 minutes
        }
    }
    
    var description: String {
        switch self {
        case .dawn: return "Dawn"
        case .day: return "Day"
        case .dusk: return "Dusk"
        case .night: return "Night"
        }
    }
}

enum ObjectType {
    case drink, furniture, station, completedDrink
}

enum AnimalType: String, CaseIterable {
    case fox = "🦊", rabbit = "🐰", hedgehog = "🦔"
    // ... more animals
    
    static var dayAnimals: [AnimalType] { 
        [.fox, .rabbit, .hedgehog, .frog, .duck, .bear, .raccoon, .squirrel] 
    }
    static var nightAnimals: [AnimalType] { 
        [.owl, .bat, .wolf] 
    }
}
```

### **3. Struct-Based Coordinates**
```swift
struct GridCoordinate: Hashable, Equatable {
    let x: Int
    let y: Int
    
    func isValid() -> Bool {
        return x >= 0 && x < GridWorld.columns && y >= 0 && y < GridWorld.rows
    }
    
    var adjacentCells: [GridCoordinate] {
        return [
            GridCoordinate(x: x-1, y: y), GridCoordinate(x: x+1, y: y),
            GridCoordinate(x: x, y: y-1), GridCoordinate(x: x, y: y+1)
        ].filter { $0.isValid() }
    }
}
```

### **4. Protocol-Oriented Interactions**
```swift
// Implicit protocol through naming conventions
// All interactive objects respond to long press via findInteractableNode()

private func findInteractableNode(_ node: SKNode) -> SKNode? {
    var current: SKNode? = node
    var depth = 0
    
    while current != nil && depth < 5 {
        // Check for various interactable types
        if current == timeBreaker { return timeBreaker }
        if let station = current as? IngredientStation { return station }
        if current?.name == "completed_drink_pickup" { return current }
        if let rotatable = current as? RotatableObject, rotatable.canBeCarried { 
            return rotatable 
        }
        
        current = current?.parent
        depth += 1
    }
    return nil
}
```

### **5. Action-Based Animations**
```swift
// SpriteKit action sequences for complex behaviors
private func transitionToRoom(_ newRoom: Int) {
    let blackOverlay = SKSpriteNode(color: .black, size: CGSize(width: 4000, height: 3000))
    
    let transitionSequence = SKAction.sequence([
        SKAction.fadeAlpha(to: 1.0, duration: 0.3),        // Fade to black
        SKAction.wait(forDuration: 0.1),                   // Brief pause
        SKAction.run { [weak self] in /* reposition logic */ }, // Instant changes
        SKAction.wait(forDuration: 0.1),                   // Settle time
        SKAction.fadeAlpha(to: 0.0, duration: 0.3),       // Fade back in
        SKAction.run { blackOverlay.removeFromParent() }   // Cleanup
    ])
    
    blackOverlay.run(transitionSequence)
}
```

---

## 🎨 **SpriteKit-Specific Patterns**

### **Node Hierarchy Management**
```swift
// Clean removal of previous room elements
private func setupCurrentRoom() {
    roomIdentifier?.removeFromParent()
    backDoor?.removeFromParent()
    leftMist?.removeFromParent()
    rightMist?.removeFromParent()
    leftHintEmoji?.removeFromParent()
    rightHintEmoji?.removeFromParent()
    
    // Create new room elements...
}
```

### **Camera System**
```swift
private func updateCamera() {
    let targetPosition = character.position
    let currentPosition = gameCamera.position
    
    // Smooth following with lerp
    let deltaX = targetPosition.x - currentPosition.x
    let deltaY = targetPosition.y - currentPosition.y
    
    let newX = currentPosition.x + deltaX * cameraLerpSpeed * 0.016
    let newY = currentPosition.y + deltaY * cameraLerpSpeed * 0.016
    
    // Clamp to world bounds
    gameCamera.position = CGPoint(x: clampedX, y: clampedY)
}
```

### **Gesture Recognition Integration**
```swift
private func setupGestures() {
    guard let view = view else { return }
    
    let pinchGesture = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
    let twoFingerTap = UITapGestureRecognizer(target: self, action: #selector(handleTwoFingerTap(_:)))
    twoFingerTap.numberOfTouchesRequired = 2
    
    view.addGestureRecognizer(pinchGesture)
    view.addGestureRecognizer(twoFingerTap)
}
```

---

## 🧠 **Design Philosophy**

### **1. State Management**
- **Singletons for global state** (GridWorld, TimeManager)
- **Local state in scene classes** (current room, transition flags)
- **No external state management** - pure SpriteKit + Swift

### **2. Touch Handling**
- **Single responsibility principle** - one touch method, multiple handlers
- **Context-aware routing** - same tap does different things based on target
- **Haptic feedback integration** - UIKit + SpriteKit harmony

### **3. Visual Feedback**
- **No UI overlays** - everything embedded in world
- **Animation-driven interactions** - visual state changes
- **Blend modes & effects** - SpriteKit's built-in capabilities

### **4. Performance Patterns**
- **Grid-based spatial partitioning** - O(1) collision detection
- **Action pooling** - reuse SKAction sequences
- **Smart camera bounds** - limit update calculations

---

## 🎓 **Swift Best Practices Demonstrated**

### **✅ Good Patterns:**
- **Enum with computed properties** for game states
- **Struct-based value types** for coordinates
- **Weak references** in closures to prevent retain cycles
- **Guard statements** for early returns
- **Extension methods** for organization
- **Consistent naming conventions**

### **✅ SpriteKit Integration:**
- **Scene lifecycle management**
- **Node hierarchy best practices**
- **Action-based animation sequencing**
- **Gesture recognizer integration**
- **Camera and coordinate system handling**

### **✅ iOS Platform Features:**
- **Haptic feedback** (UIImpactFeedbackGenerator)
- **Natural gestures** (pinch, rotation, long press)
- **Scene transitions** with proper cleanup
- **Memory management** with proper node removal

**This architecture demonstrates solid Swift fundamentals with game-specific patterns for SpriteKit development!** 🎮✨
