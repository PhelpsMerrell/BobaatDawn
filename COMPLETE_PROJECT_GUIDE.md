# 🌟 **Boba in the Woods - Complete Project Guide** 

> **For New Claude Sessions**: This project is a cozy Apple-native boba shop game built in Swift/SpriteKit. The player runs a small boba shop surrounded by looping woods, focusing on ritual, atmosphere, and discovery. **Current focus: Clean, minimalist interactions with context-aware tapping system.**

## 🧋 **Boba Creation Workflow**

### **Step-by-Step Drink Making:**
1. **Walk to Brewing Station**: Large brown rectangle at (-300, 200)
2. **Select Tea**: Tap left tea area to cycle through tea types (regular → light → no ice)
3. **Add Toppings**: Tap right areas to toggle tapioca and foam
4. **Add Lid**: Tap bottom lid area to complete the drink
5. **Pickup Drink**: When complete, drink shakes - tap anywhere on brewing station to pick up
6. **Auto-Reset**: Station automatically resets, new drink can be started immediately

### **Visual Feedback:**
- **Tea Types**: Different colored liquids (dark brown, light brown, amber)
- **Toppings**: Black tapioca pearls at bottom, cream foam on top
- **Completion**: Drink shakes when ready, indicating it's pickupable
- **Recipe-Accurate Drinks**: Carried bobas show actual tea color and toppings created
- **Carry State**: Completed drinks float above character and are non-rotatable

---

## 🎯 **Project Vision & Core Concept**

### **Game Design Pillars:**
- **🏠 Safe Shop Space**: Central hub where snail enemy never enters
- **🧋 Tactile Boba Making**: Ritualistic, haptic brewing process
- **🌲 Looping Woods**: Mysterious forest that cycles back to shop
- **👻 NPCs with Hidden Sides**: Characters change between day/night
- **🐌 Inevitable Snail Enemy**: Slow but persistent, returns player to shop
- **🔄 Cycles & Discovery**: Time and space repeat with subtle variations

### **Design Philosophy:**
- **No HUD/Menus**: All interactions embodied in world
- **No Inventories**: One item carried at a time
- **No Progression Stats**: Growth through player knowledge
- **Optional Everything**: Brewing, gathering, decorating at player's pace
- **Subtle Consequences**: Actions shift world, effects discovered through play

---

## 🏗️ **Current Implementation Status**

### **✅ COMPLETED SYSTEMS:**
- **Context-Aware Tap System** - Single tap for all interactions, no long press conflicts
- **Recipe-Accurate Boba Drinks** - Drinks visually match ingredients used (tea colors, toppings)
- **Universal Object Pickup** - All small objects pickupable via direct tapping
- **Character Smart Pathfinding** - GameplayKit pathfinding prevents collision teleporting
- **Rotatable Objects** - 4-state rotation with visual feedback (furniture, tables)
- **Multi-Drink Creation** - Create unlimited custom bobas and place around shop
- **Movable Tables** - Tables repositionable via tap selection and two-finger rotation
- **Brewing Station System** - Always functional, tactile drink assembly
- **Clean Minimalist Design** - No UI elements, selection circles, or visual clutter
- **Gesture System** - Pinch zoom, two-finger rotation, tap interactions

### **🚧 PLANNED FEATURES:**
- NPCs with day/night personality changes
- Woods sections with looping mechanics
- Snail enemy with pursuit behavior
- Time cycling system
- Ingredient gathering mechanics
- Furniture/decoration placement

---

## 🎮 **Current Controls & Interactions**

### **Context-Aware Single Tap System:**
- **Tap empty space** → Move character with smart pathfinding
- **Tap small objects** → Pick up and carry (drinks, furniture, completed bobas)
- **Tap brewing areas** → Interact with station (tea, tapioca, foam, lid)
- **Tap brewing station with completed drink** → Pick up finished boba (auto-resets station)
- **Tap carried item** → Drop item at current location
- **Tap tables** → Select for repositioning
- **Two-finger rotate** → Rotate selected tables or carried items (if rotatable)
- **Pinch** → Camera zoom in/out
- **Two-finger tap** → Reset camera zoom to default

### **No Modes, No UI - Pure World Interaction:**
- **No power breaker** - brewing station always functional
- **No selection circles** - clean minimalist visual design
- **No long press conflicts** - immediate responsive interactions
- **No arrange/browse modes** - everything works contextually

---

## 📁 **Architecture & File Structure**

```
BobaAtDawn/
├── GameScene.swift          // Main orchestrator, camera, context-aware gestures
├── Character.swift          // Player movement, pathfinding, carrying
├── RotatableObject.swift    // Base class for interactive objects (no UI elements)
├── BobaBrewingStation.swift // Drink creation with recipe-accurate results
└── Assets.xcassets/         // Placeholder sprites
```

**Removed Files:**
- `PowerBreaker.swift` - Eliminated power/mode system for clean design

### **Key Classes:**

#### **🎬 GameScene** (Main Orchestrator)
- **Handles**: Camera system, world setup, context-aware gesture recognition
- **Key Methods**: `handleContextTap()`, `setupPathfinding()`, `updateCamera()`
- **Manages**: Single tap routing, object interactions, character movement

#### **🧑‍💼 Character** (Player Logic)  
- **Handles**: Smart pathfinding, collision avoidance, item carrying, movement
- **Features**: GameplayKit GKObstacleGraph pathfinding, multi-waypoint navigation
- **Key Methods**: `moveWithPathfinding()`, `followPath()`, `pickupItem()`

#### **🔄 RotatableObject** (Interactive Objects)
- **Handles**: 4-state rotation, object categorization, visual shapes
- **Types**: `.drink` (test items), `.furniture` (moveable), `.station` (immovable), `.completedDrink` (recipe-accurate bobas)
- **Features**: Shape indicators, no selection UI, carry/arrange permissions

#### **🧋 BobaBrewingStation** (Drink Creation)
- **Handles**: Tea brewing, topping assembly, recipe-accurate drink generation
- **Interactions**: Single tap tea areas, topping areas, lid area
- **Features**: Visual drink building, shake animation, auto-reset, recipe preservation

---

## 🔧 **Key Swift Concepts Used**

### **Enums with Methods:**
```swift
enum ObjectType {
    case drink, furniture, station, completedDrink
}

enum RotationState: Int, CaseIterable {
    case north = 0, east = 90, south = 180, west = 270
    func next() -> RotationState { /* cycles through states */ }
}
```

### **Context-Aware Touch Handling:**
```swift
private func handleContextTap(at location: CGPoint, node: SKNode) {
    // Route taps based on what was touched
    if let rotatableObj = node as? RotatableObject {
        if rotatableObj.canBeCarried { character.pickupItem(rotatableObj) }
    } else if let brewingArea = node as? BrewingArea {
        brewingStation.handleInteraction(brewingArea.areaType, at: location)
    } else {
        character.moveTo(location, avoiding: tables) // Default: move
    }
}
```

### **Recipe-Accurate Drink Generation:**
```swift
private func createRecipeAccurateDrink(from state: DrinkState) -> RotatableObject {
    let teaColor = getTeaColor(state.teaType) // Different colors per tea
    let drink = RotatableObject(type: .completedDrink, color: teaColor, shape: "drink")
    
    // Add mini-layers for toppings
    if state.hasTapioca { addMiniTapioca(to: drink) }
    if state.hasFoam { addMiniFoam(to: drink) }
    return drink
}
```

---

## 🎯 **How Systems Connect**

### **Context-Aware Interaction Flow:**
1. User taps anywhere → `handleContextTap(at:node:)`
2. System identifies touched object → Routes to appropriate handler
3. Object-specific action → Pickup, brew, move, or drop
4. Immediate feedback → Visual response and state change

### **Pathfinding Flow:**
1. User taps empty space → `character.moveTo(targetPosition)`
2. System checks for pathfinding graph → `moveWithPathfinding()`
3. Creates start/end nodes → Connect to obstacle graph
4. Finds optimal path → `graph.findPath(from:to:)`
5. Follows waypoints → `followPath()` with smooth animation

### **Recipe-Accurate Boba Creation Flow:**
1. User taps brewing areas → `brewingStation.handleInteraction()`
2. Station updates drink state → Tea, toppings, lid assembly
3. Complete drink shows animation → Shaking effect
4. User taps station → `createRecipeAccurateDrink()` generates custom drink
5. Station resets → Ready for next creation cycle

---

## 🔍 **Testing Checklist**

### **Context-Aware Interactions:**
- [ ] **Single Tap Movement**: Tap empty space moves character with pathfinding
- [ ] **Object Pickup**: Tap objects directly picks them up (no long press needed)
- [ ] **Brewing Interactions**: Tap brewing areas cycles tea, toggles toppings, adds lid
- [ ] **Completed Drink Pickup**: Tap shaking station picks up custom boba
- [ ] **No Selection Circles**: No visual UI elements appear during interactions

### **Object Types & Behaviors:**
- [ ] **Tables**: Brown squares with corner dots, tap to select, two-finger rotate
- [ ] **Small Furniture**: Colored objects (red/blue/orange), directly pickupable
- [ ] **Test Drinks**: Green triangle, pickupable and rotatable when carried
- [ ] **Recipe Bobas**: Show actual tea colors and toppings, non-rotatable
- [ ] **Brewing Station**: Large brown station, immovable, always functional

### **Recipe-Accurate Boba System:**
- [ ] **Tea Colors**: Regular (dark brown), Light (light brown), No Ice (amber)
- [ ] **Toppings Visible**: Black tapioca dots, cream foam layers
- [ ] **Lid & Straw**: Gray lid with white straw when complete
- [ ] **Custom Combinations**: Each recipe creates unique visual result
- [ ] **Carry Authenticity**: Carried drinks match brewing station preview

---

## 🚀 **Next Development Priorities**

### **Immediate (Core Game Loop):**
1. **NPC System**: Basic wandering characters with day/night states
2. **Woods Generation**: Simple looping forest sections
3. **Time Cycle**: Day/night transitions affecting world

### **Medium-term (World Building):**
1. **Snail Enemy**: Slow pursuit behavior, return-to-shop mechanic
2. **Ingredient System**: Gathering resources from woods
3. **Customer Orders**: NPCs requesting specific drinks

### **Long-term (Polish & Depth):**
1. **Sound Design**: Ambient forest sounds, brewing audio
2. **Particle Effects**: Steam, magical elements
3. **Narrative Elements**: Environmental storytelling

---

## 💡 **Architecture Notes for Development**

### **Extension Points:**
- **New Object Types**: Add to `ObjectType` enum and update behavior methods
- **New Interactions**: Extend `handleContextTap()` with new touch logic
- **New Drink Ingredients**: Add to brewing station and recipe generation system

### **Performance Considerations:**
- Pathfinding graph rebuilds when objects move
- Camera updates every frame (consider optimization for many objects)
- Recipe generation creates child nodes dynamically

### **Consistent Patterns:**
- All interactions use single tap (immediate response)
- All objects inherit from RotatableObject for consistency
- Context-aware routing centralized in GameScene
- Visual feedback always accompanies state changes
- No UI elements - pure world-based interactions

---

**🎮 Ready to Continue Development!** 

This foundation provides a clean, minimalist boba shop experience with:
- **Intuitive context-aware interactions** - just tap what you want to use
- **Recipe-authentic boba creation** - drinks that show what you actually made
- **No UI clutter** - pure world-based gameplay
- **Smart pathfinding** - character navigates naturally around obstacles
- **Expandable architecture** - ready for NPCs, woods, and advanced features

Perfect foundation for the full vision of a cozy, atmospheric boba shop game with mysterious woods exploration!
