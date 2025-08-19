# 🌟 **Boba in the Woods - Complete Project Guide** 

> **For New Claude Sessions**: This project is a cozy Apple-native boba shop game built in Swift/SpriteKit. The player runs a small boba shop surrounded by looping woods, focusing on ritual, atmosphere, and discovery. **Current focus: Clean, minimalist interactions with context-aware tapping system.**

## 🧋 **Simple Boba Creation System**

### **5 Ingredient Stations:**
1. **Ice Station** (cyan) - Long press cycles: Ice → Lite Ice → No Ice → (repeat)
2. **Boba Station** (black) - Long press toggles: Boba ↔ No Boba  
3. **Foam Station** (cream) - Long press toggles: Foam ↔ No Foam
4. **Tea Station** (brown) - Long press toggles: Tea ↔ No Tea
5. **Lid Station** (gray) - Long press toggles: Lid ↔ No Lid

### **Drink Creation Workflow:**
1. **Long press stations** to add/remove ingredients
2. **Central display** shows current recipe as you build it
3. **Complete drink** = Tea + Lid (minimum required) → drink shakes
4. **Long press shaking drink** → pick up finished boba
5. **Carry and place** bobas anywhere in the shop
6. **Stations auto-reset** → ready to make another different boba

### **Visual Feedback:**
- **Station Alpha**: Active ingredients = bright (1.0), inactive = dim (0.3)
- **Ice Levels**: Full ice = bright, lite ice = medium, no ice = dim
- **Recipe Display**: Shows actual tea color, boba dots, foam layer, lid+straw
- **Completion**: Drink shakes when tea + lid are present
- **Carry State**: Completed bobas float above character, not rotatable
- **Multiple Drinks**: Make unlimited custom bobas and place around shop

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
- **Simple 5-Station Boba System** - Ice, Boba, Foam, Tea, Lid stations with long press interactions
- **Recipe-Accurate Visual Display** - Central drink preview shows actual ingredients being added
- **Multiple Boba Creation** - Make unlimited custom drinks, carry and place around shop
- **Auto-Reset Stations** - After pickup, stations reset for next drink creation
- **Universal Object Pickup** - All small objects pickupable via long press
- **Character Smart Pathfinding** - GameplayKit pathfinding prevents collision teleporting
- **Rotatable Objects** - 4-state rotation with visual feedback (furniture, tables)
- **Movable Tables** - Tables repositionable via tap selection and two-finger rotation
- **Clean Minimalist Design** - No UI elements, selection circles, or visual clutter
- **Gesture System** - Pinch zoom, two-finger rotation, long press interactions

### **🚧 PLANNED FEATURES:**
- NPCs with day/night personality changes
- Woods sections with looping mechanics
- Snail enemy with pursuit behavior
- Time cycling system
- Ingredient gathering mechanics
- Furniture/decoration placement

---

## 🎮 **Current Controls & Interactions**

### **Simple Long Press System:**
- **Long press ingredient stations** → Add/remove ingredients (ice cycles, others toggle)
- **Long press completed shaking drink** → Pick up finished boba (auto-resets stations)
- **Long press carried boba** → Drop boba at current location
- **Long press small objects** → Pick up drinks, furniture, completed bobas
- **Single tap empty space** → Move character with smart pathfinding
- **Single tap tables** → Select for repositioning
- **Two-finger rotate** → Rotate selected tables or carried items (if rotatable)
- **Pinch** → Camera zoom in/out
- **Two-finger tap** → Reset camera zoom to default

### **No UI, Pure World Interaction:**
- **No complex brewing areas** - just simple ingredient stations
- **No selection circles** - clean minimalist visual design
- **No mode conflicts** - long press for interactions, single tap for movement
- **No inventory system** - carry one item at a time

---

## 📁 **Architecture & File Structure**

```
BobaAtDawn/
├── GameScene.swift          // Main orchestrator, camera, long press gestures
├── Character.swift          // Player movement, pathfinding, carrying
├── RotatableObject.swift    // Base class for interactive objects
├── IngredientStation.swift  // Simple ingredient stations (ice, boba, foam, tea, lid)
├── DrinkCreator.swift       // Central drink display and recipe management
└── Assets.xcassets/         // Placeholder sprites
```

**Removed Files:**
- `BobaBrewingStation.swift` - Replaced with simple ingredient station system

### **Key Classes:**

#### **🎬 GameScene** (Main Orchestrator)
- **Handles**: Camera system, world setup, long press gesture recognition
- **Key Methods**: `handleLongPress()`, `setupIngredientStations()`, `updateCamera()`
- **Manages**: Long press routing, object interactions, character movement

#### **🧑‍💼 Character** (Player Logic)  
- **Handles**: Smart pathfinding, collision avoidance, item carrying, movement
- **Features**: GameplayKit GKObstacleGraph pathfinding, multi-waypoint navigation
- **Key Methods**: `moveWithPathfinding()`, `followPath()`, `pickupItem()`

#### **🔄 RotatableObject** (Interactive Objects)
- **Handles**: 4-state rotation, object categorization, visual shapes
- **Types**: `.drink` (test items), `.furniture` (moveable), `.station` (immovable), `.completedDrink` (recipe-accurate bobas)
- **Features**: Shape indicators, no selection UI, carry/arrange permissions

#### **🧋 IngredientStation** (Simple Stations)
- **Handles**: Single ingredient per station, long press interactions, visual feedback
- **Types**: Ice (cycles), Boba/Foam/Tea/Lid (toggles)
- **Features**: Visual state changes, ingredient tracking, reset functionality

#### **🍻 DrinkCreator** (Recipe Display)
- **Handles**: Central drink preview, recipe-accurate visual building, completion detection
- **Features**: Real-time ingredient visualization, shaking animation, auto-reset after pickup

---

## 🔧 **Key Swift Concepts Used**

### **Simple Station Enums:**
```swift
enum StationType {
    case ice, boba, foam, tea, lid
}

enum ObjectType {
    case drink, furniture, station, completedDrink
}
```

### **Long Press Gesture Handling:**
```swift
private func handleLongPress(on node: SKNode, at location: CGPoint) {
    if let station = node as? IngredientStation {
        station.interact()
        drinkCreator.updateDrink(from: ingredientStations)
    } else if node.name == "completed_drink_pickup" {
        if let completedDrink = drinkCreator.createCompletedDrink(from: ingredientStations) {
            character.pickupItem(completedDrink)
            drinkCreator.resetStations(ingredientStations)
        }
    }
}
```

### **Recipe-Accurate Drink Generation:**
```swift
func createCompletedDrink(from stations: [IngredientStation]) -> RotatableObject? {
    guard isComplete else { return nil }
    
    let teaColor = getTeaColor(for: iceLevel) // Different colors per ice level
    let drink = RotatableObject(type: .completedDrink, color: teaColor, shape: "drink")
    
    // Add visual layers for toppings
    if hasBoba { addMiniBoba(to: drink) }
    if hasFoam { addMiniFoam(to: drink) }
    if hasLid { addMiniLid(to: drink) }
    return drink
}
```

---

## 🎯 **How Systems Connect**

### **Simple Long Press Interaction Flow:**
1. User long presses station → `handleLongPress(on:at:)`
2. Station updates its ingredient → `station.interact()`
3. Central display updates → `drinkCreator.updateDrink()`
4. Visual feedback → Station pulse + display changes

### **Drink Completion Flow:**
1. Tea + Lid present → `isComplete = true`
2. Central display shakes → Visual completion indicator
3. User long presses display → `createCompletedDrink()`
4. Generate recipe-accurate boba → Custom visual layers
5. Auto-reset all stations → Ready for next drink

### **Pathfinding Flow:**
1. User taps empty space → `character.moveTo(targetPosition)`
2. System checks for pathfinding graph → `moveWithPathfinding()`
3. Creates start/end nodes → Connect to obstacle graph
4. Finds optimal path → `graph.findPath(from:to:)`
5. Follows waypoints → `followPath()` with smooth animation



---

## 🔍 **Testing Checklist**

### **Simple Boba System:**
- [ ] **Long Press Ice Station**: Cycles through Ice → Lite Ice → No Ice → repeat
- [ ] **Long Press Boba/Foam/Tea/Lid Stations**: Toggle on/off with visual feedback
- [ ] **Central Display Updates**: Shows real-time recipe as ingredients are added
- [ ] **Completion Detection**: Drink shakes when Tea + Lid are present
- [ ] **Drink Pickup**: Long press shaking display picks up completed boba
- [ ] **Auto-Reset**: All stations reset to default after drink pickup

### **Object Types & Behaviors:**
- [ ] **Tables**: Brown squares with corner dots, single tap to select, two-finger rotate
- [ ] **Small Furniture**: Colored objects (red/blue/orange), long press to pick up
- [ ] **Test Drinks**: Green triangle, long press to pick up, rotatable when carried
- [ ] **Recipe Bobas**: Show actual tea colors and toppings, non-rotatable when carried
- [ ] **Ingredient Stations**: 5 colored squares, long press to interact, visual alpha changes

### **Recipe-Accurate Boba System:**
- [ ] **Ice Levels**: Visual brightness changes (full=bright, lite=medium, none=dim)
- [ ] **Toppings Visible**: Black boba dots, cream foam layers in central display
- [ ] **Lid & Straw**: Gray lid with white straw when complete
- [ ] **Custom Combinations**: Each unique recipe creates different visual result
- [ ] **Carry Authenticity**: Carried drinks match the recipe that was created

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
