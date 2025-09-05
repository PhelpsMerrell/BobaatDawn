//
//  GameScene.swift
//  BobaAtDawn
//
//  Created by Phelps Merrell on 8/18/25.
//

import SpriteKit

// MARK: - Main Game Scene
class GameScene: BaseGameScene {
    
    // MARK: - Game-Specific Services
    private lazy var npcService: NPCService = serviceContainer.resolve(NPCService.self)
    private lazy var timeService: TimeService = serviceContainer.resolve(TimeService.self)
    private let residentManager = NPCResidentManager.shared
    
    // MARK: - Game Objects (Internal - accessible to extensions)
    internal var ingredientStations: [IngredientStation] = []
    private var drinkCreator: DrinkCreator!
    
    // MARK: - Time System (Internal - accessible to extensions)
    internal var timeBreaker: PowerBreaker!
    internal var timeWindow: Window!
    internal var timeLabel: SKLabelNode!
    
    // MARK: - Debug Controls
    private var timeControlButton: TimeControlButton?
    //MARK: - Physics 
    private var physicsContactHandler: PhysicsContactHandler!
    // MARK: - World Areas
    private var shopFloor: SKSpriteNode!
    
    // MARK: - Grid Visual Debug (Optional)
    private var showGridOverlay = false  // DISABLED: Grid overlay hidden
    
    // MARK: - NPC System (Now managed by ResidentManager)
    // NPCs are now managed by NPCResidentManager for persistent world
    private var npcs: [NPC] = [] // Shop NPCs only
    
    // MARK: - BaseGameScene Template Method Implementation
    override open func setupSpecificContent() {
            print("🔧 GameScene.setupSpecificContent() starting...")
            
            do {
                // NEW: Set up physics world first
                setupPhysicsWorld()
                print("✅ Physics world setup complete")
                
                setupIngredientStations()
                print("✅ Ingredient stations setup complete")
                
                convertExistingObjectsToGrid()
                print("✅ Objects converted to grid")
                
                setupTimeSystem()
                print("✅ Time system setup complete")
                
                // NEW: Initialize resident manager and living world
                setupLivingWorld()
                print("✅ Living world initialized")
                
                // Optional grid overlay for development
                if showGridOverlay {
                    addGridOverlay()
                    print("✅ Grid overlay added")
                }
                
                print("🍯 Physics-enabled game initialized with DI!")
                gridService.printGridState()
                
                print("🔧 GameScene.setupSpecificContent() completed successfully")
                
            } catch {
                print("❌ CRITICAL ERROR in setupSpecificContent(): \(error)")
                // Try to continue with minimal setup
                setupTimeSystem()
            }
        }
    
    // MARK: - Physics Setup (NEW)
    private func setupPhysicsWorld() {
        // Set up complete physics system
        physicsWorld.gravity = PhysicsConfig.World.gravity
        physicsWorld.speed = PhysicsConfig.World.speed
        
        // Set up physics contact handling
        physicsContactHandler = PhysicsContactHandler()
        physicsWorld.contactDelegate = physicsContactHandler
        
        setupPhysicsContactHandling()
        
        print("⚡ Physics world enabled")
    }
    
    private func setupPhysicsContactHandling() {
        physicsContactHandler?.contactDelegate = self
        print("⚡ Physics contact handler delegate set")
    }
    
    override open func setupWorld() {
        print("🌍 GameScene.setupWorld() starting with world dimensions: \(worldWidth) x \(worldHeight)")
        print("🌍 Scene size: \(self.size)")
        
        // Call base implementation
        super.setupWorld()
        
        // CRITICAL: Add size validation before creating sprites
        guard worldWidth > 0 && worldHeight > 0 else {
            print("❌ ERROR: Invalid world dimensions: \(worldWidth) x \(worldHeight)")
            return
        }
        
        let shopFloorSize = CGSize(width: worldWidth, height: worldHeight)
        print("🏠 Creating shop floor with size: \(shopFloorSize)")
        guard shopFloorSize.width > 0 && shopFloorSize.height > 0 else {
            print("❌ ERROR: Invalid shop floor size: \(shopFloorSize)")
            return
        }
        
        shopFloor = SKSpriteNode(color: configService.floorColor, size: shopFloorSize)
        shopFloor.position = CGPoint(x: 0, y: 0)
        shopFloor.zPosition = ZLayers.floor
        addChild(shopFloor)
        
        // Add shop floor boundary (visual only)
        setupShopFloorBounds()
        
        // Add shop walls - WITH SIZE VALIDATION
        let wallThickness = configService.wallThickness
        let wallInset = configService.wallInset
        let wallColor = configService.wallColor
        
        print("🧱 Wall config: thickness=\(wallThickness), inset=\(wallInset)")
        
        // Top wall
        let topWallSize = CGSize(width: worldWidth, height: wallThickness)
        print("🔴 Creating top wall with size: \(topWallSize)")
        guard topWallSize.width > 0 && topWallSize.height > 0 else {
            print("❌ ERROR: Invalid top wall size: \(topWallSize)")
            return
        }
        let wallTop = SKSpriteNode(color: wallColor, size: topWallSize)
        wallTop.position = CGPoint(x: 0, y: worldHeight/2 - wallInset)
        wallTop.zPosition = ZLayers.walls
        addChild(wallTop)
        
        // Bottom wall
        let bottomWallSize = CGSize(width: worldWidth, height: wallThickness)
        print("🔵 Creating bottom wall with size: \(bottomWallSize)")
        guard bottomWallSize.width > 0 && bottomWallSize.height > 0 else {
            print("❌ ERROR: Invalid bottom wall size: \(bottomWallSize)")
            return
        }
        let wallBottom = SKSpriteNode(color: wallColor, size: bottomWallSize)
        wallBottom.position = CGPoint(x: 0, y: -worldHeight/2 + wallInset)
        wallBottom.zPosition = ZLayers.walls
        addChild(wallBottom)
        
        // Left wall
        let leftWallSize = CGSize(width: wallThickness, height: worldHeight)
        print("🟡 Creating left wall with size: \(leftWallSize)")
        guard leftWallSize.width > 0 && leftWallSize.height > 0 else {
            print("❌ ERROR: Invalid left wall size: \(leftWallSize)")
            return
        }
        let wallLeft = SKSpriteNode(color: wallColor, size: leftWallSize)
        wallLeft.position = CGPoint(x: -worldWidth/2 + wallInset, y: 0)
        wallLeft.zPosition = ZLayers.walls
        addChild(wallLeft)
        
        // Add front door using grid positioning
        let frontDoor = SKLabelNode(text: "🚪")
        frontDoor.fontSize = configService.doorSize
        frontDoor.fontName = "Arial"
        frontDoor.horizontalAlignmentMode = .center
        frontDoor.verticalAlignmentMode = .center
        frontDoor.position = GameConfig.doorWorldPosition()  // FIXED: Use grid positioning
        frontDoor.zPosition = ZLayers.doors
        frontDoor.name = "front_door"
        addChild(frontDoor)
        
        print("🚪 EMOJI Front door added at grid \(GameConfig.World.doorGridPosition) = world \(frontDoor.position)")
        
        // Right wall
        let rightWallSize = CGSize(width: wallThickness, height: worldHeight)
        print("🟢 Creating right wall with size: \(rightWallSize)")
        guard rightWallSize.width > 0 && rightWallSize.height > 0 else {
            print("❌ ERROR: Invalid right wall size: \(rightWallSize)")
            return
        }
        let wallRight = SKSpriteNode(color: wallColor, size: rightWallSize)
        wallRight.position = CGPoint(x: worldWidth/2 - wallInset, y: 0)
        wallRight.zPosition = ZLayers.walls
        addChild(wallRight)
        
        print("🌍 GameScene.setupWorld() completed successfully")
    }
    
    private func setupShopFloorBounds() {
        print("🏠 Setting up shop floor bounds...")
        
        // FIXED: Shop floor area using grid positioning
        let shopFloorRect = GameConfig.shopFloorRect()
        print("🏠 Shop floor rect: position=\(shopFloorRect.position), size=\(shopFloorRect.size)")
        
        // CRITICAL: Validate the calculated size
        guard shopFloorRect.size.width > 0 && shopFloorRect.size.height > 0 else {
            print("❌ ERROR: Invalid shop floor rect size: \(shopFloorRect.size)")
            print("❌ This is likely where the crash occurs! Skipping shop floor bounds.")
            return
        }
        
        // Additional size sanity check
        guard shopFloorRect.size.width < 10000 && shopFloorRect.size.height < 10000 else {
            print("❌ ERROR: Shop floor rect size too large: \(shopFloorRect.size)")
            print("❌ This could cause memory issues! Skipping shop floor bounds.")
            return
        }
        
        let shopFloorBounds = createValidatedSprite(color: configService.shopFloorColor, 
                                                   size: shopFloorRect.size, 
                                                   name: "shop floor bounds")
        
        guard let validFloorBounds = shopFloorBounds else {
            print("❌ ERROR: Failed to create shop floor bounds sprite")
            return
        }
        
        validFloorBounds.position = shopFloorRect.position
        validFloorBounds.zPosition = ZLayers.shopFloorBounds
        addChild(validFloorBounds)
        
        print("🏠 Shop floor added: grid area \(GameConfig.World.shopFloorArea) = world rect \(shopFloorRect)")
    }
    

    
    private func setupIngredientStations() {
        // PRESERVED: 5-station boba creation system (adjusted for 60pt grid)
        let stationTypes: [IngredientStation.StationType] = [.ice, .boba, .foam, .tea, .lid]
        let stationCells = [
            GridCoordinate(x: 12, y: 15),  // Ice station
            GridCoordinate(x: 14, y: 15),  // Boba station
            GridCoordinate(x: 16, y: 15),  // Foam station
            GridCoordinate(x: 18, y: 15),  // Tea station
            GridCoordinate(x: 20, y: 15)   // Lid station
        ]
        
        for (index, type) in stationTypes.enumerated() {
            let station = IngredientStation(type: type)
            let cell = stationCells[index]
            let worldPos = gridService.gridToWorld(cell)
            
            station.position = worldPos
            station.zPosition = ZLayers.stations
            addChild(station)
            ingredientStations.append(station)
            
            // Reserve cell and register with grid
            gridService.reserveCell(cell)
            let gameObject = GameObject(skNode: station, gridPosition: cell, objectType: .station, gridService: gridService)
            gridService.occupyCell(cell, with: gameObject)
        }
        
        // DrinkCreator position - also grid-aligned (adjusted for new grid)
        drinkCreator = DrinkCreator()
        let displayCell = GridCoordinate(x: 16, y: 13)  // Below tea station center
        drinkCreator.position = gridService.gridToWorld(displayCell)
        drinkCreator.zPosition = ZLayers.drinkCreator
        addChild(drinkCreator)
        gridService.reserveCell(displayCell)
        
        // PRESERVED: All boba creation logic unchanged
        drinkCreator.updateDrink(from: ingredientStations)
        
        print("🧋 Ingredient stations positioned on grid")
    }
    
    private func convertExistingObjectsToGrid() {
        // Convert sample objects to grid positions (adjusted for 60pt grid)
        let objectConfigs = [
            (gridPos: GridCoordinate(x: 25, y: 15), type: ObjectType.furniture, color: SKColor.red, shape: "arrow"),
            (gridPos: GridCoordinate(x: 8, y: 12), type: ObjectType.furniture, color: SKColor.blue, shape: "L"),
            (gridPos: GridCoordinate(x: 18, y: 10), type: ObjectType.drink, color: SKColor.green, shape: "triangle"),
            (gridPos: GridCoordinate(x: 14, y: 18), type: ObjectType.furniture, color: SKColor.orange, shape: "rectangle")
        ]
        
        for config in objectConfigs {
            let obj = RotatableObject(type: config.type, color: config.color, shape: config.shape)
            let worldPos = gridService.gridToWorld(config.gridPos)
            obj.position = worldPos
            obj.zPosition = ZLayers.groundObjects
            addChild(obj)
            
            // Register with grid
            let gameObject = GameObject(skNode: obj, gridPosition: config.gridPos, objectType: config.type, gridService: gridService)
            gridService.occupyCell(config.gridPos, with: gameObject)
        }
        
        // Convert tables to grid positions (adjusted for 60pt grid)
        let tableGridPositions = [
            GridCoordinate(x: 22, y: 18),
            GridCoordinate(x: 10, y: 10),
            GridCoordinate(x: 26, y: 8),
            GridCoordinate(x: 13, y: 20),
            GridCoordinate(x: 28, y: 14),
            GridCoordinate(x: 6, y: 12),
            GridCoordinate(x: 16, y: 6),
            GridCoordinate(x: 20, y: 12),
            GridCoordinate(x: 14, y: 10)
        ]
        
        for gridPos in tableGridPositions {
            let table = RotatableObject(type: .furniture, color: SKColor(red: 0.4, green: 0.2, blue: 0.1, alpha: 1.0), shape: "table")
            let worldPos = gridService.gridToWorld(gridPos)
            table.position = worldPos
            table.zPosition = ZLayers.tables
            table.name = "table"
            addChild(table)
            
            // Register with grid
            let gameObject = GameObject(skNode: table, gridPosition: gridPos, objectType: .furniture, gridService: gridService)
            gridService.occupyCell(gridPos, with: gameObject)
        }
        
        print("🎯 All objects converted to grid positions")
    }
    
    private func setupTimeSystem() {
        // FIXED: Time system using grid positioning
        let timePositions = GameConfig.timeSystemPositions()
        
        timeBreaker = PowerBreaker()
        timeBreaker.position = timePositions.breaker
        timeBreaker.zPosition = ZLayers.timeSystem
        addChild(timeBreaker)
        
        timeWindow = Window()
        timeWindow.position = timePositions.window
        timeWindow.zPosition = ZLayers.timeSystem
        addChild(timeWindow)
        
        // Add time phase label
        timeLabel = SKLabelNode(text: "DAY")
        timeLabel.fontSize = 24
        timeLabel.fontName = "Arial-Bold"
        timeLabel.fontColor = .black
        timeLabel.horizontalAlignmentMode = .center
        timeLabel.verticalAlignmentMode = .center
        timeLabel.position = timePositions.label
        timeLabel.zPosition = ZLayers.timeSystemLabels
        addChild(timeLabel)
        
        // Add time control button (DEBUG)
        setupTimeControlButton(windowPosition: timePositions.window)
        
        print("🌅 Time system positioned: breaker at grid \(GameConfig.Time.breakerGridPosition), window at grid \(GameConfig.Time.windowGridPosition)")
    }
    
    // MARK: - Time Control Button Setup (DEBUG)
    private func setupTimeControlButton(windowPosition: CGPoint) {
        timeControlButton = TimeControlButton(timeService: timeService)
        
        // Position next to the window (to the right)
        let buttonOffset: CGFloat = 80 // Distance from window
        timeControlButton?.position = CGPoint(
            x: windowPosition.x + buttonOffset,
            y: windowPosition.y
        )
        
        addChild(timeControlButton!)
        
        print("⏰ Time control button added next to window for testing")
    }
    
    // MARK: - Living World Setup (NEW)
    private func setupLivingWorld() {
        // Register this game scene with the resident manager
        residentManager.registerGameScene(self)
        
        // Initialize the world with 3 NPCs in shop and rest in forest
        residentManager.initializeWorld()
        
        print("🌍 Living world initialized with persistent residents")
    }
    
    // MARK: - NPC Creation for Resident Manager
    func createShopNPC(animalType: AnimalType, resident: NPCResident) -> NPC {
        // Create NPC with dependencies injected
        let npc = NPC(animal: animalType, 
                      startPosition: GameConfig.World.doorGridPosition,
                      gridService: gridService,
                      npcService: npcService)
        
        // Add to scene and track locally
        addChild(npc)
        npcs.append(npc)
        
        // Add entrance animation
        addEntranceAnimation(for: npc)
        
        print("🏦 Created shop NPC \(animalType.rawValue) for resident \(resident.npcData.name)")
        return npc
    }
    
    private func addEntranceAnimation(for npc: NPC) {
        npc.alpha = 0.0
        npc.setScale(0.8)
        
        let entranceAnimation = SKAction.group([
            SKAction.fadeIn(withDuration: 0.5),
            SKAction.scale(to: 1.0, duration: 0.5)
        ])
        entranceAnimation.timingMode = .easeOut
        
        npc.run(entranceAnimation)
    }
    

    
    // MARK: - Grid Visual Debug (Optional)
    private func addGridOverlay() {
        // Subtle grid lines for development
        for x in 0...gridService.columns {
            let line = SKSpriteNode(color: SKColor.black.withAlphaComponent(0.1), 
                                   size: CGSize(width: 1, height: CGFloat(gridService.rows) * gridService.cellSize))
            line.position = CGPoint(x: gridService.shopOrigin.x + CGFloat(x) * gridService.cellSize, 
                                   y: gridService.shopOrigin.y + CGFloat(gridService.rows) * gridService.cellSize / 2)
            line.zPosition = ZLayers.gridOverlay
            addChild(line)
        }
        
        for y in 0...gridService.rows {
            let line = SKSpriteNode(color: SKColor.black.withAlphaComponent(0.1), 
                                   size: CGSize(width: CGFloat(gridService.columns) * gridService.cellSize, height: 1))
            line.position = CGPoint(x: gridService.shopOrigin.x + CGFloat(gridService.columns) * gridService.cellSize / 2, 
                                   y: gridService.shopOrigin.y + CGFloat(y) * gridService.cellSize)
            line.zPosition = ZLayers.gridOverlay
            addChild(line)
        }
        
        print("🎯 Grid overlay added for debugging")
    }

    
    // MARK: - BaseGameScene Template Method Implementation
    override open func handleSceneSpecificLongPress(on node: SKNode, at location: CGPoint) {
        handleGameSceneLongPress(on: node, at: location)
    }

    
    private func handleGameSceneLongPress(on node: SKNode, at location: CGPoint) {
        print("🔍 Long press on: \(node.name ?? "unnamed") - \(type(of: node))")
        
        // 1. Drop carried item if long pressing it
        if node == character.carriedItem {
            character.dropItem()
            print("📦 Dropped carried item")
            
        // 2. Power breaker (only works when tripped)
        } else if node == timeBreaker {
            print("⏰ Attempting to toggle time breaker")
            timeBreaker.toggle()
            
        // 3. Ingredient station interactions
        } else if let station = node as? IngredientStation {
            print("🧋 Interacting with \(station.stationType) station")
            
            // Use AnimationService for consistent station interaction feedback
            let pulseAction = animationService.stationInteractionPulse(station)
            animationService.run(pulseAction, on: station, withKey: AnimationKeys.stationInteraction, completion: nil)
            
            station.interact()
            drinkCreator.updateDrink(from: ingredientStations)
            print("🧋 ✅ Updated drink display after station interaction")
            
        // 4. Forest door - enter woods
        } else if node.name == "front_door" {
            // Haptic feedback for entering forest
            transitionService.triggerHapticFeedback(type: .success)
            print("🚪 Entering the mysterious forest...")
            enterForest()
            
        // 5. Pick up completed drink
        } else if node.name == "completed_drink_pickup" {
            print("🧋 🎨 ATTEMPTING TO PICK UP COMPLETED DRINK")
            if character.carriedItem == nil {
                if let completedDrink = drinkCreator.createCompletedDrink(from: ingredientStations) {
                    character.pickupItem(completedDrink)
                    print("🧋 🎆 RESETTING STATIONS AFTER PICKUP...")
                    drinkCreator.resetStations(ingredientStations)
                    print("🧋 ✅ Picked up completed drink and reset stations")
                    
                    // NEW: Show recipe system debug info
                    debugRecipeSystem()
                } else {
                    print("🧋 ❌ Failed to create completed drink!")
                }
            } else {
                print("❌ Already carrying something")
            }
            
        // 6. Handle rotatable objects (including tables)
        } else if let rotatable = node as? RotatableObject {
            
            // SPECIAL CASE: Check if this is the drink display from DrinkCreator
            if rotatable.name == "drink_display" && rotatable.parent == drinkCreator {
                print("🧋 🎨 PICKING UP YOUR CREATION FROM CREATOR")
                if character.carriedItem == nil {
                    
                    // Create a drink that perfectly matches your current creation
                    let yourCreation = drinkCreator.createPickupDrink(from: ingredientStations)
                    character.pickupItem(yourCreation)
                    
                    // ALWAYS reset stations and show new empty cup for next creation
                    print("🧋 💥 RESETTING STATIONS FOR NEXT DRINK...")
                    drinkCreator.resetStations(ingredientStations)
                    print("🧋 ✅ Reset complete - ready for your next creation!")
                    
                    if yourCreation.objectType == .completedDrink {
                        debugRecipeSystem()
                    }
                } else {
                    print("❌ Already carrying something")
                }
                return // Exit early for drink creator interaction
            }
            
            // Check if this is a table and we're carrying a drink
            if rotatable.name == "table" && character.carriedItem != nil {
                if let carriedDrink = character.carriedItem {
                    print("🧋 Attempting to place \(carriedDrink.objectType) on table")
                    placeDrinkOnTable(drink: carriedDrink, table: rotatable)
                }
                return // Exit early for table interaction
            }
            
            // Otherwise handle as pickupable object
            print("📦 Found rotatable object: \(rotatable.objectType), canBeCarried: \(rotatable.canBeCarried)")
            if rotatable.canBeCarried {
                if character.carriedItem == nil {
                    // Remove from grid when picked up
                    if let gameObject = gridService.objectAt(gridService.worldToGrid(rotatable.position)) {
                        gridService.freeCell(gameObject.gridPosition)
                    }
                    
                    character.pickupItem(rotatable)
                    print("📦 Picked up \(rotatable.objectType)")
                } else {
                    print("❌ Already carrying something")
                }
            } else {
                print("❌ Cannot carry this object type")
            }
        } else {
            print("🤷‍♂️ No action for this node")
        }
        
        // Note: Timer cleanup is now handled by InputService
    }

    

    
    // MARK: - BaseGameScene Template Method Implementation
    override open func updateSpecificContent(_ currentTime: TimeInterval) {
        // Update time system
        timeService.update()
        
        // Update time display
        updateTimeDisplay()
        
        // Update time control button
        timeControlButton?.update()
        
        // Update resident manager (handles all NPC lifecycle)
        residentManager.update(deltaTime: 1.0/60.0)
        
        // Update shop NPCs
        updateShopNPCs()
    }
    
    private func updateTimeDisplay() {
        let phase = timeService.currentPhase
        let progress = timeService.phaseProgress
        
        timeLabel.text = "\(phase.displayName.uppercased()) \(Int(progress * 100))%"
        
        // Change label color based on phase
        switch phase {
        case .dawn:
            timeLabel.fontColor = .systemPink
        case .day:
            timeLabel.fontColor = .blue
        case .dusk:
            timeLabel.fontColor = .orange
        case .night:
            timeLabel.fontColor = .purple
        }
    }
    
    // MARK: - Shop NPC Management (NEW)
    private func updateShopNPCs() {
        let deltaTime = 1.0/60.0
        
        // Update existing shop NPCs
        for npc in npcs {
            npc.update(deltaTime: deltaTime)
        }
        
        // Clean up NPCs that have left
        let initialCount = npcs.count
        npcs.removeAll { npc in
            if npc.parent == nil {
                // Notify resident manager when NPC leaves
                let satisfied = npc.state.isExiting && npc.state.displayName.contains("Happy")
                residentManager.npcLeftShop(npc, satisfied: satisfied)
                print("🦊 Cleaned up departed shop NPC \(npc.animalType.rawValue)")
                return true
            }
            return false
        }
        
        // Log if NPCs were cleaned up
        if npcs.count < initialCount {
            print("🦊 Shop NPC cleanup: \(initialCount - npcs.count) NPCs removed, \(npcs.count) remain")
        }
    }
    
    // MARK: - Table Service System (Phase 2)
    private func placeDrinkOnTable(drink: RotatableObject, table: RotatableObject) {
        // Remove drink from character
        character.dropItemSilently() // We'll add this method
        
        // Create drink sprite as child of table
        let drinkOnTable = createTableDrink(from: drink)
        drinkOnTable.position = configService.tableDrinkOnTableOffset
        drinkOnTable.zPosition = ZLayers.childLayer(for: ZLayers.tables)
        drinkOnTable.name = "drink_on_table"
        table.addChild(drinkOnTable)
        
        print("🧋 ✨ Successfully placed \(drink.objectType) on table!")
        print("🧋 Table now has \(table.children.count) child objects")
    }
    
    private func createTableDrink(from originalDrink: RotatableObject) -> SKNode {
        // Create a smaller version that preserves your sprite artwork
        let tableDrink = SKNode()
        
        // Copy all sprite children from the carried drink, preserving your artwork
        for child in originalDrink.children {
            if let spriteChild = child as? SKSpriteNode {
                let copiedSprite = spriteChild.copy() as! SKSpriteNode
                // Scale down for table display (about 60% of carried size) but keep identical positioning
                copiedSprite.setScale(spriteChild.xScale * 0.6)
                copiedSprite.position = spriteChild.position // Keep same relative position (zero)
                copiedSprite.zPosition = spriteChild.zPosition
                copiedSprite.alpha = spriteChild.alpha
                tableDrink.addChild(copiedSprite)
                
                print("🧋 🎨 Copied sprite \(spriteChild.name ?? "unnamed") to table")
            }
        }
        
        print("🧋 🎨 Table drink created with \(tableDrink.children.count) sprite layers")
        return tableDrink
    }
    
    // MARK: - Recipe System Debug
    private func debugRecipeSystem() {
        let ingredients = RecipeConverter.convertToIngredients(from: ingredientStations)
        let evaluation = RecipeConverter.evaluateRecipe(from: ingredientStations)
        
        print("🧋 === Recipe System Debug ===")
        print("🧋 Current Ingredients:")
        for ingredient in ingredients {
            if ingredient.isPresent {
                print("🧋   ✅ \(ingredient.type.displayName): \(ingredient.level.displayName)")
            }
        }
        
        if let recipe = evaluation.recipe {
            print("🧋 📖 Recipe: \(recipe.name)")
            print("🧋 ⭐ Quality: \(evaluation.quality.displayName) \(evaluation.quality.emoji)")
            print("🧋 📝 Description: \(recipe.description)")
        } else {
            print("🧋 ❌ No recipe match found")
        }
        
        // Show improvement hint
        if let hint = RecipeManager.getInstance().getImprovementHint(for: ingredients) {
            print("🧋 💡 Hint: \(hint)")
        }
        
        // Show statistics
        let stats = RecipeManager.getInstance().getRecipeStatistics()
        print("🧋 📈 Stats: \(stats.discoveredRecipes) recipes discovered, \(String(format: "%.1f", stats.averageQuality)) avg quality")
        
        print("🧋 =============================")
    }
    
    // MARK: - Forest Transition
    private func enterForest() {
        print("🌲 Entering the mysterious forest...")
        
        // Use transition service for forest entry
        transitionService.transitionToForest(from: self) {
            print("🌲 Successfully transitioned to forest")
        }
    }
}

// MARK: - Physics Contact Delegate (NEW)
extension GameScene: PhysicsContactDelegate {
    
    func characterContactedStation(_ station: SKNode) {
        if let ingredientStation = station as? IngredientStation {
            print("⚡ Character contacted \(ingredientStation.stationType) station via physics")
            // Could trigger proximity-based highlighting or interaction hints
        }
    }
    
    func characterContactedDoor(_ door: SKNode) {
        if door.name == "front_door" {
            print("⚡ Character contacted forest door via physics")
            // Could show "Press to enter forest" hint
        }
    }
    
    func characterContactedItem(_ item: SKNode) {
        if let rotatable = item as? RotatableObject {
            print("⚡ Character contacted item \(rotatable.objectType) via physics")
            // Could show "Press to pickup" hint
        }
    }
    
    func characterContactedNPC(_ npc: SKNode) {
        if let npcNode = npc as? NPC {
            print("💬 Character contacted \(npcNode.animalType.rawValue) via physics")
            // Could trigger dialogue or interaction hints
        }
    }
    
    func npcContactedDoor(_ npc: SKNode, door: SKNode) {
        if let npcNode = npc as? NPC, door.name == "front_door" {
            print("🦊 \(npcNode.animalType.rawValue) contacted exit door - should leave")
            npcNode.startLeaving(satisfied: true)
        }
    }
    
    func itemContactedFurniture(_ item: SKNode, furniture: SKNode) {
        print("📦 Item contacted furniture via physics")
        // Could handle automatic item placement
    }
}
