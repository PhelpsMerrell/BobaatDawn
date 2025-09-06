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
    
    // MARK: - Save System
    private var saveJournal: SaveSystemButton!
    private var clearDataButton: SaveSystemButton!
    private var npcStatusTracker: SaveSystemButton!
    
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
                
                // NEW: Setup save system
                print("🔧 ABOUT TO CALL setupSaveSystem()")
                setupSaveSystem()
                print("✅ Save system setup complete")
                
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
        // REORDERED: 5-station boba creation system with ice at position 1
        let stationTypes: [IngredientStation.StationType] = [.ice, .tea, .boba, .foam, .lid]
        let stationCells = [
            GridCoordinate(x: 12, y: 15),  // Ice station (Station 1)
            GridCoordinate(x: 14, y: 15),  // Tea station (Station 2)
            GridCoordinate(x: 16, y: 15),  // Boba station (Station 3)
            GridCoordinate(x: 18, y: 15),  // Foam station (Station 4)
            GridCoordinate(x: 20, y: 15)   // Lid station (Station 5)
        ]
        
        print("🧋 🏢 STATION SETUP: Creating stations in new order...")
        print("🧋 Position 1 (leftmost): \(stationTypes[0])")
        print("🧋 Position 2: \(stationTypes[1])")
        print("🧋 Position 3: \(stationTypes[2])")
        print("🧋 Position 4: \(stationTypes[3])")
        print("🧋 Position 5 (rightmost): \(stationTypes[4])")
        
        for (index, type) in stationTypes.enumerated() {
            let station = IngredientStation(type: type)
            let cell = stationCells[index]
            let worldPos = gridService.gridToWorld(cell)
            
            station.position = worldPos
            station.zPosition = ZLayers.stations
            addChild(station)
            ingredientStations.append(station)
            
            print("🧋 🏢 Created \(type) station at position \(index + 1) (grid \(cell), world \(worldPos))")
            print("🧋     -> Station should show \(type) sprite and control \(type) in drink")
            print("🧋     -> Station name: \(station.name ?? "unnamed")")
            print("🧋     -> Station stationType: \(station.stationType)")
            
            // CRITICAL: Verify the station we just created
            print("🧋 🔍 VERIFICATION - Station \(index + 1):")
            print("🧋     hasIce: \(station.hasIce)")
            print("🧋     hasTea: \(station.hasTea)")
            print("🧋     hasBoba: \(station.hasBoba)")
            print("🧋     hasFoam: \(station.hasFoam)")
            print("🧋     hasLid: \(station.hasLid)")
            
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
    
    // MARK: - Save System Setup
    private func setupSaveSystem() {
        print("🔧 setupSaveSystem() STARTED")
        
        // Create save journal button
        saveJournal = SaveSystemButton(type: .saveJournal)
        let journalCell = GridCoordinate(x: 8, y: 17)
        saveJournal.position = gridService.gridToWorld(journalCell)
        saveJournal.zPosition = ZLayers.timeSystem
        addChild(saveJournal)
        print("📔 Save journal added to scene. Parent: \(saveJournal.parent?.name ?? "nil")")
        
        // Create clear data button
        clearDataButton = SaveSystemButton(type: .clearData)
        let clearCell = GridCoordinate(x: 10, y: 17)
        clearDataButton.position = gridService.gridToWorld(clearCell)
        clearDataButton.zPosition = ZLayers.timeSystem
        addChild(clearDataButton)
        print("🗑️ Clear button added to scene. Parent: \(clearDataButton.parent?.name ?? "nil")")
        
        // Create NPC status tracker
        npcStatusTracker = SaveSystemButton(type: .npcStatus)
        let statusCell = GridCoordinate(x: 12, y: 17)
        npcStatusTracker.position = gridService.gridToWorld(statusCell)
        npcStatusTracker.zPosition = ZLayers.timeSystem
        addChild(npcStatusTracker)
        print("📈 Status tracker added to scene. Parent: \(npcStatusTracker.parent?.name ?? "nil")")
        
        print("📔 Save journal positioned at grid \(journalCell)")
        print("🗑️ Clear data button positioned at grid \(clearCell)")
        print("📈 NPC status tracker positioned at grid \(statusCell)")
        
        // DEBUG: Test if buttons are positioned correctly
        print("🔧 DEBUG: Save journal world position: \(saveJournal.position)")
        print("🔧 DEBUG: Clear button world position: \(clearDataButton.position)")
        print("🔧 DEBUG: Status tracker world position: \(npcStatusTracker.position)")
        print("🔧 DEBUG: Scene size: \(self.size)")
        
        // DEBUG: Check if buttons are in scene
        print("🔧 DEBUG: Scene has \(self.children.count) children")
        let saveButtons = self.children.compactMap { $0 as? SaveSystemButton }
        print("🔧 DEBUG: Found \(saveButtons.count) SaveSystemButton children in scene")
        for button in saveButtons {
            print("🔧 DEBUG: - \(button.buttonType.emoji) at \(button.position), zPosition: \(button.zPosition)")
        }
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
            
        // 4. Save journal - save game state
        } else if node.name == "save_journal" {
            print("📔 Saving game state...")
            saveGameState()
            
        // 5. Clear data button - clear all save data
        } else if node.name == "clear_data_button" {
            print("🗑️ Clearing all save data...")
            clearSaveData()
            
        // 6. NPC status tracker - show status report
        } else if node.name == "npc_status_tracker" {
            print("📈 Showing NPC status report...")
            showNPCStatusReport()
            
        // 7. Forest door - enter woods
        } else if let saveButton = node as? SaveSystemButton {
            print("🔧 Interacting with \(saveButton.buttonType) save button")
            
            switch saveButton.buttonType {
            case .saveJournal:
                print("📔 Saving game state...")
                saveGameState()
            case .clearData:
                print("🗑️ Clearing all save data...")
                clearSaveData()
            case .npcStatus:
                print("📈 Showing NPC status report...")
                showNPCStatusReport()
            }
            
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
        // Remove drink from character (using existing dropItem method)
        character.dropItem()
        
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
        // FIXED: Create table drink using same consistent sprite layering system
        let tableDrink = SKNode()
        
        // Use identical sprite system but with smaller table scale
        let bobaAtlas = SKTextureAtlas(named: "Boba")
        
        // Validate atlas exists
        guard bobaAtlas.textureNames.count > 0 else {
            print("❌ ERROR: Boba atlas not found or empty for table drink")
            return tableDrink
        }
        
        let cupTexture = bobaAtlas.textureNamed("cup_empty")
        let tableScale = 15.0 / cupTexture.size().width // Smaller for table display
        
        // Helper function to create perfectly aligned table layers
        func makeTableLayer(_ name: String, z: CGFloat, visible: Bool = true, alpha: CGFloat = 1.0) -> SKSpriteNode? {
            // Validate texture exists before creating sprite
            guard bobaAtlas.textureNames.contains(name) else {
                print("⚠️ WARNING: Texture '\(name)' not found in Boba atlas for table drink")
                return nil
            }
            
            let tex = bobaAtlas.textureNamed(name)
            tex.filteringMode = .nearest
            let node = SKSpriteNode(texture: tex)
            node.anchorPoint = CGPoint(x: 0.5, y: 0.5)   // identical for all
            node.position = .zero                         // identical for all
            node.setScale(tableScale)                     // identical for all
            node.zPosition = z
            node.isHidden = !visible
            node.alpha = alpha
            node.blendMode = .alpha
            node.name = name
            return node
        }
        
        // Recreate drink layers based on original drink's sprite children (preserve your recipe)
        for child in originalDrink.children {
            if let spriteChild = child as? SKSpriteNode, let spriteName = spriteChild.name {
                if let tableLayer = makeTableLayer(spriteName, 
                                                  z: spriteChild.zPosition, 
                                                  visible: !spriteChild.isHidden, 
                                                  alpha: spriteChild.alpha) {
                    tableDrink.addChild(tableLayer)
                    print("🧋 🎨 Created table layer \(spriteName) with consistent scaling")
                }
            }
        }
        
        print("🧋 🎨 Table drink created with \(tableDrink.children.count) perfectly aligned sprite layers")
        return tableDrink
    }
    
  
    // MARK: - Forest Transition
    private func enterForest() {
        print("🌲 Entering the mysterious forest...")
        
        // Use transition service for forest entry
        transitionService.transitionToForest(from: self) {
            print("🌲 Successfully transitioned to forest")
        }
    }
    
    // MARK: - Save System
    private func saveGameState() {
        // Visual feedback - brief glow
        let glowAction = SKAction.sequence([
            SKAction.scale(to: 1.2, duration: 0.1),
            SKAction.scale(to: 1.0, duration: 0.1)
        ])
        saveJournal.run(glowAction)
        
        // Haptic feedback
        transitionService.triggerHapticFeedback(type: .success)
        
        // Save the actual game state
        SaveService.shared.saveCurrentGameState(timeService: timeService, residentManager: residentManager)
        
        print("📔 ✅ Game saved successfully!")
    }
    
    private func clearSaveData() {
        // Visual feedback - brief red glow
        let clearAction = SKAction.sequence([
            SKAction.colorize(with: .red, colorBlendFactor: 0.8, duration: 0.1),
            SKAction.colorize(with: .white, colorBlendFactor: 0.0, duration: 0.1)
        ])
        clearDataButton.run(clearAction)
        
        // Strong haptic feedback for destructive action
        transitionService.triggerHapticFeedback(type: .light)
        
        // Clear all save data
        SaveService.shared.clearAllSaveData()
        
        print("🗑️ ✅ All save data cleared!")
    }
    
    private func showNPCStatusReport() {
        // Visual feedback - brief glow
        let glowAction = SKAction.sequence([
            SKAction.scale(to: 1.2, duration: 0.1),
            SKAction.scale(to: 1.0, duration: 0.1)
        ])
        npcStatusTracker.run(glowAction)
        
        // Haptic feedback
        transitionService.triggerHapticFeedback(type: .selection)
        
        // ALSO: Print SwiftData inspection to console
        SaveService.shared.inspectSwiftDataContents()
        
        // Create and show status bubble
        showNPCStatusBubble()
        
        print("📈 ✅ NPC status report displayed!")
    }
    
    // MARK: - NPC Status Bubble Display
    private func showNPCStatusBubble() {
        // Dismiss any existing dialogue first
        DialogueService.shared.dismissDialogue()
        
        // Get all NPCs from dialogue service
        let allNPCs = DialogueService.shared.getAllNPCs()
        
        // Create status content
        var statusLines: [String] = []
        statusLines.append("📈 NPC STATUS REPORT")
        statusLines.append("")
        
        if allNPCs.isEmpty {
            statusLines.append("🤷‍♂️ No NPCs found")
        } else {
            for npcData in allNPCs {
                if let memory = SaveService.shared.getOrCreateNPCMemory(npcData.id, name: npcData.name, animalType: npcData.animal) {
                    let satisfactionLevel = memory.satisfactionLevel
                    let emoji = satisfactionLevel.emoji
                    
                    statusLines.append("\(npcData.animal) \(npcData.name) \(emoji)")
                    statusLines.append("Satisfaction: \(memory.satisfactionScore)/100")
                    statusLines.append("Interactions: \(memory.totalInteractions)")
                    statusLines.append("")
                } else {
                    statusLines.append("\(npcData.animal) \(npcData.name) - No data")
                    statusLines.append("")
                }
            }
            statusLines.append("📈 Total NPCs: \(allNPCs.count)")
        }
        
        // Create and show status bubble
        let statusBubble = NPCStatusBubble(
            statusLines: statusLines,
            position: npcStatusTracker.position
        )
        
        addChild(statusBubble)
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

// MARK: - NPC Status Bubble
class NPCStatusBubble: SKNode {
    private let bubbleBackground: SKShapeNode
    private let contentNode: SKNode
    private let scrollContainer: SKNode
    private var scrollOffset: CGFloat = 0
    private let maxScrollOffset: CGFloat
    private var longPressTimer: Timer?
    private let longPressDuration: TimeInterval = 0.6
    
    init(statusLines: [String], position: CGPoint) {
        // Fixed bubble size that fits on screen
        let bubbleWidth: CGFloat = 280
        let bubbleHeight: CGFloat = 320
        let lineHeight: CGFloat = 18
        let padding: CGFloat = 15
        
        // Calculate content height for scrolling
        let contentHeight = CGFloat(statusLines.count) * lineHeight + padding
        let visibleHeight = bubbleHeight - padding * 2 - 30 // Leave room for instructions
        maxScrollOffset = max(0, contentHeight - visibleHeight)
        
        // Create bubble background
        bubbleBackground = SKShapeNode(rectOf: CGSize(width: bubbleWidth, height: bubbleHeight), cornerRadius: 12)
        bubbleBackground.fillColor = SKColor.white.withAlphaComponent(0.95)
        bubbleBackground.strokeColor = SKColor.black.withAlphaComponent(0.7)
        bubbleBackground.lineWidth = 2
        
        // Create scroll container
        scrollContainer = SKNode()
        
        // Create content container
        contentNode = SKNode()
        
        super.init()
        
        // Position bubble in center of screen instead of above button
        self.position = CGPoint(x: 0, y: 0) // Center of screen
        self.zPosition = 200 // Very high z-position
        
        // Add background
        addChild(bubbleBackground)
        
        // Add text lines to content
        for (index, line) in statusLines.enumerated() {
            let label = SKLabelNode(text: line)
            label.fontName = line.hasPrefix("📈") ? "Arial-Bold" : "Arial"
            label.fontSize = line.hasPrefix("📈") ? 13 : 11
            label.fontColor = line.hasPrefix("📈") ? SKColor.darkGray : SKColor.black
            label.horizontalAlignmentMode = .center
            label.verticalAlignmentMode = .center
            
            // Position from top down
            let yOffset = (contentHeight/2) - (CGFloat(index) * lineHeight) - padding
            label.position = CGPoint(x: 0, y: yOffset)
            
            contentNode.addChild(label)
        }
        
        // Add content to scroll container
        scrollContainer.addChild(contentNode)
        
        // Clip the scroll area
        let clipFrame = CGRect(x: -bubbleWidth/2 + padding, y: -visibleHeight/2, width: bubbleWidth - padding*2, height: visibleHeight)
        let clipNode = SKCropNode()
        let clipMask = SKSpriteNode(color: .white, size: clipFrame.size)
        clipMask.position = CGPoint(x: clipFrame.midX, y: clipFrame.midY)
        clipNode.maskNode = clipMask
        clipNode.addChild(scrollContainer)
        
        addChild(clipNode)
        
        // Add instructions
        let instructionText = maxScrollOffset > 0 ? "Drag to scroll • Long press to close" : "Long press to close"
        let closeLabel = SKLabelNode(text: instructionText)
        closeLabel.fontName = "Arial"
        closeLabel.fontSize = 9
        closeLabel.fontColor = SKColor.gray
        closeLabel.horizontalAlignmentMode = .center
        closeLabel.verticalAlignmentMode = .center
        closeLabel.position = CGPoint(x: 0, y: -(bubbleHeight/2) + 12)
        addChild(closeLabel)
        
        // Add scroll indicator if needed
        if maxScrollOffset > 0 {
            let scrollIndicator = SKLabelNode(text: "⇅")
            scrollIndicator.fontName = "Arial"
            scrollIndicator.fontSize = 12
            scrollIndicator.fontColor = SKColor.gray
            scrollIndicator.horizontalAlignmentMode = .center
            scrollIndicator.verticalAlignmentMode = .center
            scrollIndicator.position = CGPoint(x: bubbleWidth/2 - 15, y: 0)
            addChild(scrollIndicator)
        }
        
        // Make the bubble interactive
        bubbleBackground.name = "status_bubble"
        isUserInteractionEnabled = true
        
        // Animate bubble appearance
        alpha = 0
        setScale(0.5)
        let showAnimation = SKAction.group([
            SKAction.fadeIn(withDuration: 0.3),
            SKAction.scale(to: 1.0, duration: 0.3)
        ])
        run(showAnimation)
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let location = touch.location(in: self)
        
        // Start long press timer for closing
        startLongPressTimer()
        
        // Don't immediately close - just track touch for potential scrolling
    }
    
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        
        // Cancel long press timer when user starts dragging
        cancelLongPressTimer()
        
        guard maxScrollOffset > 0 else { return }
        
        let location = touch.location(in: self)
        let previousLocation = touch.previousLocation(in: self)
        
        // Only scroll if touch is inside bubble
        if bubbleBackground.contains(location) {
            let deltaY = location.y - previousLocation.y
            
            // Update scroll offset
            let newOffset = scrollOffset + deltaY
            scrollOffset = max(-maxScrollOffset, min(0, newOffset))
            
            // Apply scroll to content
            contentNode.position.y = scrollOffset
        }
    }
    
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        // Cancel long press timer when touch ends
        cancelLongPressTimer()
    }
    
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        // Cancel long press timer when touch is cancelled
        cancelLongPressTimer()
    }
    
    private func startLongPressTimer() {
        cancelLongPressTimer() // Cancel any existing timer
        
        longPressTimer = Timer.scheduledTimer(withTimeInterval: longPressDuration, repeats: false) { [weak self] _ in
            self?.handleLongPress()
        }
    }
    
    private func cancelLongPressTimer() {
        longPressTimer?.invalidate()
        longPressTimer = nil
    }
    
    private func handleLongPress() {
        print("📈 Long press detected - closing status bubble")
        closeBubble()
    }
    
    private func closeBubble() {
        let hideAnimation = SKAction.group([
            SKAction.fadeOut(withDuration: 0.2),
            SKAction.scale(to: 0.8, duration: 0.2)
        ])
        
        let removeAction = SKAction.run {
            self.removeFromParent()
        }
        
        run(SKAction.sequence([hideAnimation, removeAction]))
    }
}
