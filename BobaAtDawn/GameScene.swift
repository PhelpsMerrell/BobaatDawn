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
    
    // MARK: - Game Objects (Internal - accessible to extensions)
    internal var ingredientStations: [IngredientStation] = []
    private var drinkCreator: DrinkCreator!
    
    // MARK: - Time System (Internal - accessible to extensions)
    internal var timeBreaker: PowerBreaker!
    internal var timeWindow: Window!
    internal var timeLabel: SKLabelNode!
    //MARK: - Physics 
    private var physicsContactHandler: PhysicsContactHandler!
    // MARK: - World Areas
    private var shopFloor: SKSpriteNode!
    
    // MARK: - Grid Visual Debug (Optional)
    private var showGridOverlay = false  // DISABLED: Grid overlay hidden
    
    // MARK: - NPC System
    private var npcs: [NPC] = []
    private var lastNPCSpawnTime: TimeInterval = 0
    private lazy var maxNPCs = configService.npcMaxCount
    private var sceneTime: TimeInterval = 0 // Track scene time consistently
    
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
            
            // Optional grid overlay for development
            if showGridOverlay {
                addGridOverlay()
                print("✅ Grid overlay added")
            }
            
            print("🍯 Physics-enabled game initialized with DI!")
            gridService.printGridState()
            
            // Initialize NPC system
            lastNPCSpawnTime = 0 // Use scene time instead of absolute time
            
            print("🦊 NPC system initialized, first spawn in ~1 second")
            
            // IMMEDIATE DEBUG: Force spawn one animal right now
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                self.forceSpawnDebugNPC()
            }
            
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
        shopFloor.zPosition = -10
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
        wallTop.zPosition = -5
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
        wallBottom.zPosition = -5
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
        wallLeft.zPosition = -5
        addChild(wallLeft)
        
        // Add front door using grid positioning
        let frontDoor = SKLabelNode(text: "🚪")
        frontDoor.fontSize = configService.doorSize
        frontDoor.fontName = "Arial"
        frontDoor.horizontalAlignmentMode = .center
        frontDoor.verticalAlignmentMode = .center
        frontDoor.position = GameConfig.doorWorldPosition()  // FIXED: Use grid positioning
        frontDoor.zPosition = 20 // Very high above everything
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
        wallRight.zPosition = -5
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
        validFloorBounds.zPosition = -8
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
            station.zPosition = 50  // Same high z as working red markers
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
        drinkCreator.zPosition = 6
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
            obj.zPosition = 3
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
            table.zPosition = 1
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
        timeBreaker.zPosition = 10
        addChild(timeBreaker)
        
        timeWindow = Window()
        timeWindow.position = timePositions.window
        timeWindow.zPosition = 10
        addChild(timeWindow)
        
        // Add time phase label
        timeLabel = SKLabelNode(text: "DAY")
        timeLabel.fontSize = 24
        timeLabel.fontName = "Arial-Bold"
        timeLabel.fontColor = .black
        timeLabel.horizontalAlignmentMode = .center
        timeLabel.verticalAlignmentMode = .center
        timeLabel.position = timePositions.label
        timeLabel.zPosition = 11 // Above time window
        addChild(timeLabel)
        
        print("🌅 Time system positioned: breaker at grid \(GameConfig.Time.breakerGridPosition), window at grid \(GameConfig.Time.windowGridPosition)")
    }
    

    
    // MARK: - Grid Visual Debug (Optional)
    private func addGridOverlay() {
        // Subtle grid lines for development
        for x in 0...gridService.columns {
            let line = SKSpriteNode(color: SKColor.black.withAlphaComponent(0.1), 
                                   size: CGSize(width: 1, height: CGFloat(gridService.rows) * gridService.cellSize))
            line.position = CGPoint(x: gridService.shopOrigin.x + CGFloat(x) * gridService.cellSize, 
                                   y: gridService.shopOrigin.y + CGFloat(gridService.rows) * gridService.cellSize / 2)
            line.zPosition = -5
            addChild(line)
        }
        
        for y in 0...gridService.rows {
            let line = SKSpriteNode(color: SKColor.black.withAlphaComponent(0.1), 
                                   size: CGSize(width: CGFloat(gridService.columns) * gridService.cellSize, height: 1))
            line.position = CGPoint(x: gridService.shopOrigin.x + CGFloat(gridService.columns) * gridService.cellSize / 2, 
                                   y: gridService.shopOrigin.y + CGFloat(y) * gridService.cellSize)
            line.zPosition = -5
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
        // Update scene time consistently
        if sceneTime == 0 {
            sceneTime = currentTime // Initialize on first frame
        }
        let deltaTime = currentTime - sceneTime
        sceneTime = currentTime
        
        // Update character with physics (NEW)
        character.update(deltaTime: deltaTime)
        
        // Update time system
        timeService.update()
        
        // Update time display
        updateTimeDisplay()
        
        // Update NPC system using scene time
        updateNPCs(sceneTime)
    }
    
    private func updateTimeDisplay() {
        let phase = timeService.currentPhase
        let progress = timeService.phaseProgress
        
        timeLabel.text = "\(phase.description.uppercased()) \(Int(progress * 100))%"
        
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
    
    // MARK: - NPC Management
    private func updateNPCs(_ currentSceneTime: TimeInterval) {
        let deltaTime = 1.0/60.0 // Approximate frame time
        
        // DEBUG: Print NPC system status every 5 seconds
        if Int(currentSceneTime) % 5 == 0 && Int(currentSceneTime * 10) % 50 == 0 {
            let timeSinceLastSpawn = currentSceneTime - lastNPCSpawnTime
            let nextSpawnIn = getSpawnInterval() - timeSinceLastSpawn
            let tablesWithDrinks = countTablesWithDrinks()
            print("🦊 NPC STATUS: \(npcs.count)/\(maxNPCs) NPCs, \(tablesWithDrinks) tables with drinks")
            print("🦊 SPAWN TIMING: last spawn \(String(format: "%.1f", timeSinceLastSpawn))s ago, next in \(String(format: "%.1f", nextSpawnIn))s")
            print("🦊 TIME: \(timeService.currentPhase), active: \(timeService.isTimeActive)")
        }
        
        // Update existing NPCs
        for npc in npcs {
            npc.update(deltaTime: deltaTime)
        }
        
        // Remove NPCs that have left (Phase 6: Enhanced cleanup)
        let initialCount = npcs.count
        npcs.removeAll { npc in
            if npc.parent == nil {
                print("🦊 Cleaned up departed NPC \(npc.animalType.rawValue)")
                return true
            }
            return false
        }
        
        // Log if NPCs were cleaned up
        if npcs.count < initialCount {
            print("🦊 NPC cleanup: \(initialCount - npcs.count) NPCs removed, \(npcs.count) remain")
        }
        
        // Spawn new NPCs
        trySpawnNPC(currentSceneTime)
    }
    
    private func trySpawnNPC(_ currentTime: TimeInterval) {
        // Don't spawn if at capacity
        guard npcs.count < maxNPCs else {
            if Int(currentTime) % 10 == 0 && Int(currentTime * 10) % 100 == 0 {
                print("🦊 Not spawning: at capacity (\(npcs.count)/\(maxNPCs))")
            }
            return
        }
        
        // Calculate spawn interval based on time of day
        let spawnInterval = getSpawnInterval()
        let timeSinceLastSpawn = currentTime - lastNPCSpawnTime
        
        // Check if enough time has passed
        guard timeSinceLastSpawn > spawnInterval else {
            if Int(currentTime) % 10 == 0 && Int(currentTime * 10) % 100 == 0 {
                print("🦊 Not spawning: waiting \(Int(spawnInterval - timeSinceLastSpawn))s more")
            }
            return
        }
        
        // Spawn new NPC using DI
        let isNight = timeService.currentPhase == .night
        let animal = npcService.selectAnimalForSpawn(isNight: isNight)
        let npc = npcService.spawnNPC(animal: animal, at: nil as GridCoordinate?)
        
        addChild(npc)
        npcs.append(npc)
        lastNPCSpawnTime = currentTime
        
        print("🦊 ✨ SPAWNED \(animal.rawValue) at \(npc.position) (\(npcs.count)/\(maxNPCs) NPCs)")
        
        // No need for entrance animation - already handled in service
    }
    
    private func getSpawnInterval() -> TimeInterval {
        // PHASE 5: Enhanced spawn rates based on time of day and shop state
        let baseInterval: TimeInterval
        
        switch timeService.currentPhase {
        case .day:
            baseInterval = 15.0 // Every 15 seconds during day (was 5s for testing)
        case .dusk:
            baseInterval = 25.0 // Every 25 seconds during dusk
        case .night:
            baseInterval = 45.0 // Every 45 seconds during night (mysterious visitors)
        case .dawn:
            return 999 // No spawning during dawn (prep time)
        }
        
        // PHASE 5: Dynamic adjustments based on shop state
        let currentOccupancy = Double(npcs.count) / Double(maxNPCs)
        let occupancyMultiplier = 1.0 + (currentOccupancy * 0.5) // Slower spawning when busy
        
        // Check if there are tables with drinks (encourage spawning)
        let tablesWithDrinks = countTablesWithDrinks()
        let drinkBonus = tablesWithDrinks > 0 ? 0.7 : 1.0 // 30% faster spawning if drinks available
        
        let finalInterval = baseInterval * occupancyMultiplier * drinkBonus
        
        print("🦊 Spawn timing: base=\(baseInterval)s, occupancy=\(String(format: "%.1f", occupancyMultiplier))x, drink_bonus=\(String(format: "%.1f", drinkBonus))x, final=\(String(format: "%.1f", finalInterval))s")
        
        return finalInterval
    }
    
    private func countTablesWithDrinks() -> Int {
        var count = 0
        enumerateChildNodes(withName: "table") { node, _ in
            if let table = node as? RotatableObject {
                if table.children.contains(where: { $0.name == "drink_on_table" }) {
                    count += 1
                }
            }
        }
        return count
    }
    
    // MARK: - Debug Methods
    private func forceSpawnDebugNPC() {
        print("🦊 🚨 FORCE SPAWNING DEBUG NPC NOW!")
        
        let npc = npcService.spawnNPC(animal: .fox, at: nil as GridCoordinate?)
        
        print("🦊 Created NPC at position: \(npc.position)")
        
        addChild(npc)
        npcs.append(npc)
        lastNPCSpawnTime = sceneTime
        
        print("🦊 ✨ FORCE SPAWNED fox - Total NPCs: \(npcs.count)")
        print("🦊 NPC added to scene with zPosition: \(npc.zPosition)")
    }
    
    // MARK: - Table Service System (Phase 2)
    private func placeDrinkOnTable(drink: RotatableObject, table: RotatableObject) {
        // Remove drink from character
        character.dropItemSilently() // We'll add this method
        
        // Create drink sprite as child of table
        let drinkOnTable = createTableDrink(from: drink)
        drinkOnTable.position = configService.tableDrinkOnTableOffset
        drinkOnTable.zPosition = configService.tableDrinkOnTableZPosition
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
