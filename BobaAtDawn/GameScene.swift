//
//  GameScene.swift
//  BobaAtDawn
//
//  Created by Phelps Merrell on 8/18/25.
//

import SpriteKit

// MARK: - Main Game Scene
class GameScene: SKScene, InputServiceDelegate {
    
    // MARK: - Dependency Injection (Internal)
    private lazy var serviceContainer: GameServiceContainer = ServiceSetup.createGameServices()
    private lazy var configService: ConfigurationService = serviceContainer.resolve(ConfigurationService.self)
    private lazy var gridService: GridService = serviceContainer.resolve(GridService.self)
    private lazy var npcService: NPCService = serviceContainer.resolve(NPCService.self)
    private lazy var timeService: TimeService = serviceContainer.resolve(TimeService.self)
    private lazy var transitionService: SceneTransitionService = serviceContainer.resolve(SceneTransitionService.self)
    private lazy var inputService: InputService = serviceContainer.resolve(InputService.self)
    private lazy var animationService: AnimationService = serviceContainer.resolve(AnimationService.self)
    
    // MARK: - Camera System
    private var gameCamera: SKCameraNode!
    private lazy var cameraLerpSpeed: CGFloat = configService.cameraLerpSpeed
    private lazy var cameraState = CameraState(
        defaultScale: configService.cameraDefaultScale,
        minZoom: configService.cameraMinZoom,
        maxZoom: configService.cameraMaxZoom
    )
    private var lastPinchScale: CGFloat = 1.0
    private var isHandlingPinch = false
    
    // MARK: - World Settings
    private lazy var worldWidth: CGFloat = configService.worldWidth
    private lazy var worldHeight: CGFloat = configService.worldHeight
    
    // MARK: - Game Objects
    private var character: Character!
    private var ingredientStations: [IngredientStation] = []
    private var drinkCreator: DrinkCreator!
    
    // MARK: - Time System (PRESERVED)
    private var timeBreaker: PowerBreaker!
    private var timeWindow: Window!
    private var timeLabel: SKLabelNode!
    
    // MARK: - World Areas
    private var shopFloor: SKSpriteNode!
    
    // MARK: - Grid Visual Debug (Optional)
    private var showGridOverlay = false
    
    // MARK: - NPC System
    private var npcs: [NPC] = []
    private var lastNPCSpawnTime: TimeInterval = 0
    private lazy var maxNPCs = configService.npcMaxCount
    private var sceneTime: TimeInterval = 0 // Track scene time consistently
    
    // MARK: - Scene Setup
    override func didMove(to view: SKView) {
        setupCamera()
        setupWorld()
        setupCharacter()
        setupIngredientStations()
        convertExistingObjectsToGrid()
        setupTimeSystem()
        setupGestures()
        
        // Optional grid overlay for development
        if showGridOverlay {
            addGridOverlay()
        }
        
        print("🍯 Grid-based game initialized with DI!")
        gridService.printGridState()
        
        // Initialize NPC system
        lastNPCSpawnTime = 0 // Use scene time instead of absolute time
        
        print("🦊 NPC system initialized, first spawn in ~1 second")
        
        // IMMEDIATE DEBUG: Force spawn one animal right now
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.forceSpawnDebugNPC()
        }
    }
    
    private func setupCamera() {
        gameCamera = SKCameraNode()
        camera = gameCamera
        addChild(gameCamera)
    }
    
    private func setupWorld() {
        backgroundColor = configService.backgroundColor
        
        shopFloor = SKSpriteNode(color: configService.floorColor, size: CGSize(width: worldWidth, height: worldHeight))
        shopFloor.position = CGPoint(x: 0, y: 0)
        shopFloor.zPosition = -10
        addChild(shopFloor)
        
        // Add shop floor boundary (visual only)
        setupShopFloorBounds()
        
        // Add shop walls
        let wallThickness = configService.wallThickness
        let wallInset = configService.wallInset
        let wallColor = configService.wallColor
        
        let wallTop = SKSpriteNode(color: wallColor, size: CGSize(width: worldWidth, height: wallThickness))
        wallTop.position = CGPoint(x: 0, y: worldHeight/2 - wallInset)
        wallTop.zPosition = -5
        addChild(wallTop)
        
        let wallBottom = SKSpriteNode(color: wallColor, size: CGSize(width: worldWidth, height: wallThickness))
        wallBottom.position = CGPoint(x: 0, y: -worldHeight/2 + wallInset)
        wallBottom.zPosition = -5
        addChild(wallBottom)
        
        let wallLeft = SKSpriteNode(color: wallColor, size: CGSize(width: wallThickness, height: worldHeight))
        wallLeft.position = CGPoint(x: -worldWidth/2 + wallInset, y: 0)
        wallLeft.zPosition = -5
        addChild(wallLeft)
        
        // Add front door EMOJI in left wall
        let frontDoor = SKLabelNode(text: "🚪")
        frontDoor.fontSize = configService.doorSize
        frontDoor.fontName = "Arial"
        frontDoor.horizontalAlignmentMode = .center
        frontDoor.verticalAlignmentMode = .center
        frontDoor.position = CGPoint(x: -worldWidth/2 + configService.doorOffsetFromWall, y: 0)
        frontDoor.zPosition = 20 // Very high above everything
        frontDoor.name = "front_door"
        addChild(frontDoor)
        
        print("🚪 EMOJI Front door added at \(frontDoor.position)")
        
        let wallRight = SKSpriteNode(color: wallColor, size: CGSize(width: wallThickness, height: worldHeight))
        wallRight.position = CGPoint(x: worldWidth/2 - wallInset, y: 0)
        wallRight.zPosition = -5
        addChild(wallRight)
    }
    
    private func setupShopFloorBounds() {
        // Main shop floor area - light blue rectangle under brewing stations
        let shopFloorBounds = SKSpriteNode(color: configService.shopFloorColor, 
                                          size: configService.shopFloorSize)
        shopFloorBounds.position = configService.shopFloorOffset
        shopFloorBounds.zPosition = -8
        addChild(shopFloorBounds)
        
        print("🏠 Light blue shop floor added under brewing stations")
    }
    
    private func setupCharacter() {
        character = Character(gridService: gridService, animationService: animationService)
        addChild(character)
        
        // Center camera on character
        gameCamera.position = character.position
        gameCamera.setScale(cameraState.scale)
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
            station.zPosition = 5
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
        // PRESERVED: Time system unchanged
        timeBreaker = PowerBreaker()
        timeBreaker.position = CGPoint(x: -600, y: 400) // Top-left corner of shop, but visible and accessible
        timeBreaker.zPosition = 10
        addChild(timeBreaker)
        
        timeWindow = Window()
        timeWindow.position = CGPoint(x: 400, y: 300) // Center-right of explorable area
        timeWindow.zPosition = 10
        addChild(timeWindow)
        
        // Add time phase label
        timeLabel = SKLabelNode(text: "DAY")
        timeLabel.fontSize = 24
        timeLabel.fontName = "Arial-Bold"
        timeLabel.fontColor = .black
        timeLabel.horizontalAlignmentMode = .center
        timeLabel.verticalAlignmentMode = .center
        timeLabel.position = CGPoint(x: 400, y: 300) // Same position as time window to center it
        timeLabel.zPosition = 11 // Above time window
        addChild(timeLabel)
        
        print("🌅 Time system: Game starts in Day, flows until Dawn completion trips breaker")
    }
    
    private func setupGestures() {
        guard let view = view else { return }
        
        // Use InputService for gesture setup with delegate pattern
        inputService.setupGestures(for: view, context: .gameScene, config: nil, delegate: self)
        print("🎮 Gestures setup using InputService with delegate pattern")
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

    
    // MARK: - Touch Handling (Using InputService)
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        // Don't handle touches during pinch
        guard !isHandlingPinch else { return }
        
        let result = inputService.handleTouchBegan(touches, with: event, in: self, gridService: gridService, context: .gameScene)
        
        switch result {
        case .handled:
            break // Already handled by service
            
        case .notHandled:
            break // Not handled, ignore
            
        case .longPress(let node, let location):
            let gameNodes = [
                "timeBreaker": timeBreaker as SKNode,
                "carriedItem": character.carriedItem as SKNode? ?? SKNode() // Fallback to avoid optionals
            ].compactMapValues { $0 != SKNode() ? $0 : nil }
            
            if let interactable = inputService.findInteractableNode(node, context: .gameScene, gameSpecificNodes: gameNodes) {
                inputService.startLongPress(for: interactable, at: location) { [weak self] node, location in
                    self?.handleLongPress(on: node, at: location)
                }
                print("🔍 Long press started on \(node) using InputService")
            }
            
        case .movement(let targetCell):
            character.moveToGridCell(targetCell)
            print("🎯 Character moving to available cell \(targetCell) using InputService")
            
        case .occupiedCell(let cell):
            inputService.showOccupiedCellFeedback(at: cell, in: self, gridService: gridService)
            print("❌ Cell \(cell) is occupied")
        }
    }
    
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        inputService.handleTouchEnded(touches, with: event)
    }
    
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        inputService.handleTouchCancelled(touches, with: event)
    }

    
    private func handleLongPress(on node: SKNode, at location: CGPoint) {
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
            print("🧋 Updated drink display with AnimationService feedback")
            
        // 4. Forest door - enter woods
        } else if node.name == "front_door" {
            // Haptic feedback for entering forest
            transitionService.triggerHapticFeedback(type: .success)
            print("🚪 Entering the mysterious forest...")
            enterForest()
            
        // 5. Pick up completed drink
        } else if node.name == "completed_drink_pickup" {
            print("🧋 Attempting to pick up completed drink")
            if character.carriedItem == nil {
                if let completedDrink = drinkCreator.createCompletedDrink(from: ingredientStations) {
                    character.pickupItem(completedDrink)
                    drinkCreator.resetStations(ingredientStations)
                    print("🧋 Picked up completed drink and reset stations")
                }
            } else {
                print("❌ Already carrying something")
            }
            
        // 6. Handle rotatable objects (including tables)
        } else if let rotatable = node as? RotatableObject {
            
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

    
    // MARK: - InputServiceDelegate Methods
    func inputService(_ service: InputService, didReceivePinch gesture: UIPinchGestureRecognizer) {
        isHandlingPinch = true
        
        switch gesture.state {
        case .began:
            cameraState.lastPinchScale = cameraState.scale
        case .changed:
            let newScale = cameraState.lastPinchScale / gesture.scale
            cameraState.scale = max(cameraState.minZoom, min(cameraState.maxZoom, newScale))
            gameCamera.setScale(cameraState.scale)
        case .ended, .cancelled:
            isHandlingPinch = false
        default:
            break
        }
        
        print("🎮 GameScene: Handled pinch gesture through delegate")
    }
    
    func inputService(_ service: InputService, didReceiveRotation gesture: UIRotationGestureRecognizer) {
        guard gesture.state == .ended else { return }
        
        // Rotate carried items if character is carrying something
        if character.isCarrying {
            character.rotateCarriedItem()
            print("🎮 GameScene: Rotated carried item through delegate")
        }
    }
    
    func inputService(_ service: InputService, didReceiveTwoFingerTap gesture: UITapGestureRecognizer) {
        // Reset camera zoom to default
        cameraState.scale = configService.cameraDefaultScale
        let zoomAction = SKAction.scale(to: cameraState.scale, duration: configService.cameraZoomResetDuration)
        gameCamera.run(zoomAction)
        
        print("🎮 GameScene: Camera zoom reset through delegate")
    }
    
    // MARK: - Camera Update
    private func updateCamera() {
        let targetPosition = character.position
        let currentPosition = gameCamera.position
        
        let deltaX = targetPosition.x - currentPosition.x
        let deltaY = targetPosition.y - currentPosition.y
        
        let newX = currentPosition.x + deltaX * cameraLerpSpeed * 0.016
        let newY = currentPosition.y + deltaY * cameraLerpSpeed * 0.016
        
        let effectiveViewWidth = size.width * cameraState.scale
        let effectiveViewHeight = size.height * cameraState.scale
        
        let halfViewWidth = effectiveViewWidth / 2
        let halfViewHeight = effectiveViewHeight / 2
        
        let restaurantLeft = -worldWidth/2 + 80
        let restaurantRight = worldWidth/2 - 80
        let restaurantBottom = -worldHeight/2 + 80
        let restaurantTop = worldHeight/2 - 80
        
        let clampedX = max(restaurantLeft + halfViewWidth, min(restaurantRight - halfViewWidth, newX))
        let clampedY = max(restaurantBottom + halfViewHeight, min(restaurantTop - halfViewHeight, newY))
        
        gameCamera.position = CGPoint(x: clampedX, y: clampedY)
    }
    
    // MARK: - Update Loop
    override func update(_ currentTime: TimeInterval) {
        // Update scene time consistently
        if sceneTime == 0 {
            sceneTime = currentTime // Initialize on first frame
        }
        let deltaTime = currentTime - sceneTime
        sceneTime = currentTime
        
        updateCamera()
        character.update()
        
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
        // Create a smaller version of the drink for table display
        let tableDrink = SKSpriteNode(color: originalDrink.color, size: configService.tableDrinkOnTableSize)
        
        // Copy drink visual elements if it's a completed drink
        if originalDrink.objectType == .completedDrink {
            // Add drink details (simplified)
            let lid = SKSpriteNode(color: configService.tableLidColor, size: configService.tableLidSize)
            lid.position = configService.tableLidOffset
            tableDrink.addChild(lid)
            
            let straw = SKSpriteNode(color: configService.tableStrawColor, size: configService.tableStrawSize)
            straw.position = configService.tableStrawOffset
            tableDrink.addChild(straw)
        }
        
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
}
