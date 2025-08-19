# 📚 **Boba in the Woods - Study Guide**

## 🎯 **What We Just Implemented**

### **NEW FEATURES:**
- ✅ **Day/Night Cycle System** - 32-minute cycle with 4 atmospheric phases
- ✅ **Time Control Breaker** - Activate time progression with long press
- ✅ **Color-Changing Window** - Visual time phase indicator
- ✅ **Character Class** - Encapsulated player logic with smart pathfinding
- ✅ **Rotatable Objects** - 4-state rotation with visual feedback
- ✅ **Swipe Pickup/Drop System** - Forgiving proximity-based object interaction
- ✅ **Completed Drink System** - Recipe-accurate boba drinks
- ✅ **Multi-Drink Creation** - Create and place multiple custom bobas
- ✅ **Context-Aware Movement** - Single tap navigation with obstacle avoidance

---

## 🏗️ **Architecture Overview**

### **Class Hierarchy:**
```
GameScene (Main orchestrator)
├── Character (Player logic)
├── PowerBreaker (Time control)
├── Window (Time phase indicator)
├── TimeManager (Singleton - cycle logic)
├── BobaBrewingStation : RotatableObject
├── RotatableObject (Base for movable items)
└── Regular SKSpriteNodes (Tables, walls)
```

### **Separation of Concerns:**
- **GameScene**: Camera, world setup, gesture coordination
- **Character**: Movement, carrying, collision avoidance  
- **RotatableObject**: Rotation states, selection, visual shapes
- **PowerBreaker**: Time control activation, visual feedback
- **Window**: Color-changing time phase visualization
- **TimeManager**: 32-minute cycle logic, phase transitions
- **BobaBrewingStation**: Drink creation, recipe management

---

## 🎮 **Current Interaction System**

### **CORE INTERACTIONS:**
- **Single Tap** → Move character with smart pathfinding
- **Long Press time breaker** → Activate/pause day/night cycle
- **Long Press brewing areas** → Interact with boba station
- **Long Press completed drink** → Pick up finished boba
- **Swipe toward character** → Pick up nearby objects
- **Swipe away from character** → Drop carried items
- **Two-finger rotate while carrying rotatable items** → Rotate carried item
- **Pinch** → Camera zoom
- **Two-finger tap** → Reset zoom

### **🌅 DAY/NIGHT CYCLE SYSTEM:**

**Time Phases (32 minutes total):**
- **Dawn**: 4 minutes - Soft pink/orange window color
- **Day**: 12 minutes - Bright blue/white window color  
- **Dusk**: 4 minutes - Orange/purple window color
- **Night**: 12 minutes - Dark blue/purple window color

**Time Control:**
- Game starts in **Dawn** and stays there indefinitely
- **Long press time breaker** (upper-left) to activate cycle
- Once activated, time progresses automatically through all phases
- Window (upper-right) changes color to show current time phase
- Smooth color transitions between phases

---

## 🔧 **Key Swift Concepts in Our Code**

### **1. Singleton Pattern:**
```swift
class TimeManager {
    static let shared = TimeManager()
    private init() {}
    
    func startTime() { /* ... */ }
    func update() { /* ... */ }
}

// Usage
TimeManager.shared.startTime()
```

### **2. Enum with Computed Properties:**
```swift
enum TimePhase: CaseIterable {
    case dawn, day, dusk, night
    
    var duration: TimeInterval {
        switch self {
        case .dawn: return 4 * 60  // 4 minutes
        case .day: return 12 * 60  // 12 minutes
        case .dusk: return 4 * 60
        case .night: return 12 * 60
        }
    }
    
    var nextPhase: TimePhase {
        // Cycles through all phases
    }
}
```

### **3. Closure Callbacks:**
```swift
// TimeManager notifies Window of phase changes
TimeManager.shared.onPhaseChanged = { [weak self] newPhase in
    self?.transitionToPhase(newPhase)
}
```

### **4. Color Interpolation:**
```swift
// Smooth color transitions
let colorAction = SKAction.colorize(with: newColor, 
                                   colorBlendFactor: 1.0, 
                                   duration: 2.0)
colorAction.timingMode = .easeInEaseOut
run(colorAction)
```

---

## 📂 **File Structure & What Each Does**

### **🎯 GameScene.swift** (Main Orchestrator)
**What it handles:**
- Camera system (following, zoom, bounds)
- World setup (walls, tables, layout)
- Time system integration and setup
- Touch routing (time breaker, brewing, movement)
- Update loop coordination

**Key Methods to Study:**
- `setupTimeSystem()` - Time breaker and window positioning
- `handleLongPress()` - Time breaker interaction
- `findInteractableNode()` - Includes time breaker detection
- `update()` - Calls TimeManager.shared.update()

### **🧑‍💼 Character.swift** (Player Logic)
**What it handles:**
- Smart pathfinding using GameplayKit's GKObstacleGraph
- Collision avoidance with smooth navigation around obstacles
- Item carrying state management
- Swipe-based pickup/drop interactions

**Key Features:**
- **GameplayKit pathfinding**: Professional obstacle navigation
- **Proximity-based interactions**: Forgiving swipe pickup system
- **Carrying state management**: Visual feedback for carried items

### **🕒 TimeManager.swift** (Singleton - Cycle Logic)
**What it handles:**
- 32-minute cycle timing (Dawn 4min → Day 12min → Dusk 4min → Night 12min)
- Phase progression and transitions
- Progress tracking within each phase (0.0 to 1.0)
- Callback system for phase changes
- Start/stop time control

**Key Features:**
- **Singleton pattern**: `TimeManager.shared`
- **Phase callbacks**: Notify window and other systems of changes
- **Progress updates**: Smooth transitions during long phases
- **Pause/resume capability**: Time breaker controls activation

### **🪟 Window.swift** (Time Indicator)
**What it handles:**
- Color-changing visual time indicator
- Smooth color transitions between phases
- Subtle brightness variations during phases
- Positioned in upper-right corner

**Color System:**
- **Dawn**: Soft pink/orange gradient
- **Day**: Bright blue/white
- **Dusk**: Orange/purple gradient  
- **Night**: Dark blue/purple

### **⏰ PowerBreaker.swift** (Time Control - Renamed from Power System)
**What it handles:**
- Time activation switch (not power/modes anymore)
- Visual feedback for time state (green=active, orange=paused)
- Long press interaction for time control
- Positioned in upper-left corner

**Visual States:**
- **Time Paused**: Orange light, "PAUSED" label
- **Time Active**: Green flowing light, "ACTIVE" label

### **🧋 BobaBrewingStation.swift** (Drink Creation)
**What it handles:**
- Drink assembly system (tea + toppings + lid)
- Recipe-accurate drink generation
- Large interaction areas for mobile
- Completed drink creation and pickup
- Always-powered operation (no power dependency)

---

## 🎯 **Swift vs C# Quick Reference**

### **Singleton Pattern:**
```swift
// Swift - Singleton with private init
class TimeManager {
    static let shared = TimeManager()
    private init() {}
}

// C# equivalent  
public class TimeManager {
    public static TimeManager Instance { get; } = new TimeManager();
    private TimeManager() {}
}
```

### **Enum with Methods:**
```swift
// Swift - Enum with computed properties
enum TimePhase: CaseIterable {
    case dawn, day, dusk, night
    
    var duration: TimeInterval {
        switch self {
        case .dawn: return 4 * 60
        case .day: return 12 * 60
        // ...
        }
    }
}

// C# equivalent
public enum TimePhase {
    Dawn, Day, Dusk, Night
}

public static class TimePhaseExtensions {
    public static TimeSpan Duration(this TimePhase phase) {
        return phase switch {
            TimePhase.Dawn => TimeSpan.FromMinutes(4),
            TimePhase.Day => TimeSpan.FromMinutes(12),
            // ...
        };
    }
}
```

### **Callback Systems:**
```swift
// Swift - Closure-based callbacks
TimeManager.shared.onPhaseChanged = { newPhase in
    self.updateForPhase(newPhase)
}

// C# equivalent
TimeManager.Instance.PhaseChanged += (newPhase) => {
    this.UpdateForPhase(newPhase);
};
```

---

## 🎮 **How the Systems Connect**

### **Time System Flow:**
1. **User long-presses time breaker** → `PowerBreaker.toggle()`
2. **Time breaker activates time** → `TimeManager.shared.startTime()`
3. **TimeManager updates each frame** → `TimeManager.update()` in GameScene
4. **Phase changes trigger callbacks** → `Window.transitionToPhase()`
5. **Window updates color smoothly** → Color interpolation animations
6. **Cycle continues automatically** → Dawn → Day → Dusk → Night → Dawn...

### **Object Interaction Flow:**
1. **Touch detected** → `touchesBegan()`
2. **Find target** → `findInteractableNode()` (includes time breaker)
3. **Route by type** → Time control, brewing, or pickup logic
4. **Execute action** → Toggle time, brew drink, or pick up item

### **Character Movement:**
1. **Tap location** → `character.moveTo()`
2. **Pathfinding** → Navigate around obstacles
3. **Swipe interactions** → Pickup/drop nearby objects
4. **Camera follows** → Smooth tracking with world bounds

---

## 🔍 **What to Study Next**

### **For Understanding Swift:**
1. **Singleton pattern** in `TimeManager.shared`
2. **Enum with computed properties** in `TimePhase`
3. **Closure callbacks** in time system updates
4. **Color interpolation** in Window transitions
5. **Timer-based updates** in cycle management

### **For Understanding Architecture:**
1. **Observer pattern** in time callbacks
2. **State machine** in time phase transitions
3. **Separation of concerns** between time logic and visuals
4. **Centralized time management** with distributed updates

### **For Understanding Game Development:**
1. **Frame-based time updates** in game loop
2. **Smooth visual transitions** for atmospheric changes
3. **User-controlled pacing** with activation switches
4. **Visual feedback systems** for time state indication

---

## ✅ **Test Plan**

### **Time System Testing:**
1. **Build and run** - Should compile cleanly with new time components
2. **Find time breaker** - Upper-left gray panel with "TIME" label
3. **Test time activation** - Long press breaker, watch status change to "ACTIVE"
4. **Observe window colors** - Upper-right window should start pink (dawn)
5. **Watch phase transitions** - Window should smoothly change colors over time
6. **Test time pause** - Long press breaker again to pause cycle
7. **Verify dawn start** - Game should always start in dawn phase

### **Existing System Testing:**
8. **Test object pickup** - Swipe toward character to pick up nearby items
9. **Test object drop** - Swipe away from character to drop carried items
10. **Test brewing** - Long press brewing areas to make drinks
11. **Test boba pickup** - Long press completed drinks to pick up
12. **Test movement** - Single tap for pathfinding navigation
13. **Test camera** - Pinch zoom, two-finger tap to reset
14. **Test rotation** - Two-finger rotation on carried rotatable items

### **Visual Polish Testing:**
15. **Window transitions** - Should be smooth color changes, not instant
16. **Time breaker feedback** - Visual feedback when toggling time
17. **Light animations** - Flowing green when active, pulsing orange when paused
18. **No UI clutter** - Clean minimalist design maintained

**New Architecture:**
- ✅ **Day/Night cycle system** - 32-minute atmospheric timing
- ✅ **Time control integration** - Power breaker now controls time
- ✅ **Color-changing window** - Visual time phase indicator
- ✅ **Swipe pickup/drop** - Forgiving proximity-based interactions
- ✅ **Single tap movement** - Clean context-aware navigation
- ✅ **Long press brewing** - Tactile drink creation restored
- ✅ **Smart pathfinding** - Navigate around obstacles naturally

The game now has a complete atmospheric time system that enhances the cozy, ritual-focused gameplay! 🌅🧋
