//
//  GameScene.swift
//  BobaAtDawn
//
//  Created by Phelps Merrell on 8/18/25.
//

import SpriteKit

// MARK: - Main Game Scene
class GameScene: SKScene {
    
    // MARK: - Camera System
    private var gameCamera: SKCameraNode!
    private let cameraLerpSpeed: CGFloat = 2.0
    private var cameraScale: CGFloat = 1.0
    private let minZoom: CGFloat = 0.3
    private let maxZoom: CGFloat = 1.5
    private var lastPinchScale: CGFloat = 1.0
    
    // MARK: - World Settings
    private let worldWidth: CGFloat = 2000
    private let worldHeight: CGFloat = 1500
    
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
    
    // MARK: - Touch Handling (PRESERVED Long Press System)
    private var longPressTimer: Timer?
    private var longPressTarget: SKNode?
    private let longPressDuration: TimeInterval = 0.8
    private var isHandlingPinch = false
    
    // MARK: - Grid Visual Debug (Optional)
    private var showGridOverlay = false
    
    // MARK: - NPC System
    private var npcs: [NPC] = []
    private var lastNPCSpawnTime: TimeInterval = 0
    private let maxNPCs = 3
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
        
        print("🎯 Grid-based game initialized!")
        GridWorld.shared.printGridState()
        
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
        backgroundColor = SKColor(red: 0.9, green: 0.8, blue: 0.7, alpha: 1.0)
        
        shopFloor = SKSpriteNode(color: SKColor(red: 0.8, green: 0.7, blue: 0.6, alpha: 1.0), size: CGSize(width: worldWidth, height: worldHeight))
        shopFloor.position = CGPoint(x: 0, y: 0)
        shopFloor.zPosition = -10
        addChild(shopFloor)
        
        // Add shop floor boundary (visual only)
        setupShopFloorBounds()
        
        // Add shop walls
        let wallTop = SKSpriteNode(color: SKColor(red: 0.5, green: 0.3, blue: 0.2, alpha: 1.0), size: CGSize(width: worldWidth, height: 40))
        wallTop.position = CGPoint(x: 0, y: worldHeight/2 - 20)
        wallTop.zPosition = -5
        addChild(wallTop)
        
        let wallBottom = SKSpriteNode(color: SKColor(red: 0.5, green: 0.3, blue: 0.2, alpha: 1.0), size: CGSize(width: worldWidth, height: 40))
        wallBottom.position = CGPoint(x: 0, y: -worldHeight/2 + 20)
        wallBottom.zPosition = -5
        addChild(wallBottom)
        
        let wallLeft = SKSpriteNode(color: SKColor(red: 0.5, green: 0.3, blue: 0.2, alpha: 1.0), size: CGSize(width: 40, height: worldHeight))
        wallLeft.position = CGPoint(x: -worldWidth/2 + 20, y: 0)
        wallLeft.zPosition = -5
        addChild(wallLeft)
        
        // Add front door EMOJI in left wall
        let frontDoor = SKLabelNode(text: "🚪")
        frontDoor.fontSize = 80 // Make it bigger
        frontDoor.fontName = "Arial"
        frontDoor.horizontalAlignmentMode = .center
        frontDoor.verticalAlignmentMode = .center
        frontDoor.position = CGPoint(x: -worldWidth/2 + 120, y: 0) // Move closer to center
        frontDoor.zPosition = 20 // Very high above everything
        frontDoor.name = "front_door"
        addChild(frontDoor)
        
        print("🚪 EMOJI Front door added at \(frontDoor.position)")
        
        let wallRight = SKSpriteNode(color: SKColor(red: 0.5, green: 0.3, blue: 0.2, alpha: 1.0), size: CGSize(width: 40, height: worldHeight))
        wallRight.position = CGPoint(x: worldWidth/2 - 20, y: 0)
        wallRight.zPosition = -5
        addChild(wallRight)
    }
    
    private func setupShopFloorBounds() {
        // Main shop floor area - light blue rectangle under brewing stations
        let shopFloorBounds = SKSpriteNode(color: SKColor(red: 0.7, green: 0.85, blue: 1.0, alpha: 0.6), 
                                          size: CGSize(width: 800, height: 400))
        shopFloorBounds.position = CGPoint(x: 0, y: 150)  // Centered under stations
        shopFloorBounds.zPosition = -8
        addChild(shopFloorBounds)
        
        print("🏠 Light blue shop floor added under brewing stations")
    }
    
    private func setupCharacter() {
        character = Character()
        addChild(character)
        
        // Center camera on character
        gameCamera.position = character.position
        gameCamera.setScale(cameraScale)
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
            let worldPos = GridWorld.shared.gridToWorld(cell)
            
            station.position = worldPos
            station.zPosition = 5
            addChild(station)
            ingredientStations.append(station)
            
            // Reserve cell and register with grid
            GridWorld.shared.reserveCell(cell)
            let gameObject = GameObject(skNode: station, gridPosition: cell, objectType: .station)
            GridWorld.shared.occupyCell(cell, with: gameObject)
        }
        
        // DrinkCreator position - also grid-aligned (adjusted for new grid)
        drinkCreator = DrinkCreator()
        let displayCell = GridCoordinate(x: 16, y: 13)  // Below tea station center
        drinkCreator.position = GridWorld.shared.gridToWorld(displayCell)
        drinkCreator.zPosition = 6
        addChild(drinkCreator)
        GridWorld.shared.reserveCell(displayCell)
        
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
            let worldPos = GridWorld.shared.gridToWorld(config.gridPos)
            obj.position = worldPos
            obj.zPosition = 3
            addChild(obj)
            
            // Register with grid
            let gameObject = GameObject(skNode: obj, gridPosition: config.gridPos, objectType: config.type)
            GridWorld.shared.occupyCell(config.gridPos, with: gameObject)
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
            let worldPos = GridWorld.shared.gridToWorld(gridPos)
            table.position = worldPos
            table.zPosition = 1
            table.name = "table"
            addChild(table)
            
            // Register with grid
            let gameObject = GameObject(skNode: table, gridPosition: gridPos, objectType: .furniture)
            GridWorld.shared.occupyCell(gridPos, with: gameObject)
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
        
        // PRESERVED: Gesture system for pinch/rotation unchanged
        let pinchGesture = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        let rotationGesture = UIRotationGestureRecognizer(target: self, action: #selector(handleRotation(_:)))
        let twoFingerTap = UITapGestureRecognizer(target: self, action: #selector(handleTwoFingerTap(_:)))
        twoFingerTap.numberOfTouchesRequired = 2
        
        view.addGestureRecognizer(pinchGesture)
        view.addGestureRecognizer(rotationGesture)
        view.addGestureRecognizer(twoFingerTap)
    }
    
    // MARK: - Grid Visual Debug (Optional)
    private func addGridOverlay() {
        // Subtle grid lines for development
        for x in 0...GridWorld.columns {
            let line = SKSpriteNode(color: SKColor.black.withAlphaComponent(0.1), 
                                   size: CGSize(width: 1, height: CGFloat(GridWorld.rows) * GridWorld.cellSize))
            line.position = CGPoint(x: GridWorld.shopOrigin.x + CGFloat(x) * GridWorld.cellSize, 
                                   y: GridWorld.shopOrigin.y + CGFloat(GridWorld.rows) * GridWorld.cellSize / 2)
            line.zPosition = -5
            addChild(line)
        }
        
        for y in 0...GridWorld.rows {
            let line = SKSpriteNode(color: SKColor.black.withAlphaComponent(0.1), 
                                   size: CGSize(width: CGFloat(GridWorld.columns) * GridWorld.cellSize, height: 1))
            line.position = CGPoint(x: GridWorld.shopOrigin.x + CGFloat(GridWorld.columns) * GridWorld.cellSize / 2, 
                                   y: GridWorld.shopOrigin.y + CGFloat(y) * GridWorld.cellSize)
            line.zPosition = -5
            addChild(line)
        }
        
        print("🎯 Grid overlay added for debugging")
    }
    
    private func showGridCellOccupiedFeedback(at cell: GridCoordinate) {
        // ENHANCED: Subtle, natural feedback instead of harsh red squares
        let worldPos = GridWorld.shared.gridToWorld(cell)
        
        // Create a gentle pulsing circle instead of a red square
        let feedback = SKShapeNode(circleOfRadius: GridWorld.cellSize * 0.3)
        feedback.fillColor = SKColor.clear
        feedback.strokeColor = SKColor.orange.withAlphaComponent(0.4)
        feedback.lineWidth = 2
        feedback.position = worldPos
        feedback.zPosition = 5  // Lower z-position, less intrusive
        addChild(feedback)
        
        // Gentle pulse animation instead of harsh fade
        let pulseAction = SKAction.sequence([
            SKAction.scale(to: 1.2, duration: 0.15),
            SKAction.scale(to: 1.0, duration: 0.15),
            SKAction.wait(forDuration: 0.2),
            SKAction.fadeOut(withDuration: 0.4),
            SKAction.removeFromParent()
        ])
        feedback.run(pulseAction)
    }
    
    // MARK: - Touch Handling (NEW Grid System + PRESERVED Long Press)
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard !isHandlingPinch else { return }
        guard let touch = touches.first else { return }
        let location = touch.location(in: self)
        let targetCell = GridWorld.shared.worldToGrid(location)
        let touchedNode = atPoint(location)
        
        // Check what's in the tapped cell first
        if let gameObject = GridWorld.shared.objectAt(targetCell) {
            // PRESERVED: Use existing long press system for objects
            if let interactable = findInteractableNode(gameObject.skNode) {
                startLongPress(for: interactable, at: location)
                print("🔍 Long press started on \(gameObject.objectType) at grid \(targetCell)")
                return
            }
        }
        
        // Check for direct node touches (ingredient stations, drink display, etc.)
        if let interactable = findInteractableNode(touchedNode) {
            startLongPress(for: interactable, at: location)
            return
        }
        
        // NEW: Grid-based movement
        if GridWorld.shared.isCellAvailable(targetCell) {
            character.moveToGridCell(targetCell)
            print("🎯 Character moving to available cell \(targetCell)")
        } else {
            // Show feedback for occupied cell
            showGridCellOccupiedFeedback(at: targetCell)
            print("❌ Cell \(targetCell) is occupied")
        }
    }
    
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        cancelLongPress()
    }
    
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        cancelLongPress()
    }
    
    // MARK: - Long Press System (PRESERVED - NO CHANGES)
    private func startLongPress(for node: SKNode, at location: CGPoint) {
        longPressTarget = node
        longPressTimer = Timer.scheduledTimer(withTimeInterval: longPressDuration, repeats: false) { [weak self] _ in
            self?.handleLongPress(on: node, at: location)
        }
        
        // Visual feedback for long press start
        if let rotatable = node as? RotatableObject {
            let pulseAction = SKAction.sequence([
                SKAction.scale(to: 1.05, duration: 0.1),
                SKAction.scale(to: 1.0, duration: 0.1)
            ])
            rotatable.run(pulseAction)
        }
    }
    
    private func cancelLongPress() {
        longPressTimer?.invalidate()
        longPressTimer = nil
        longPressTarget = nil
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
            station.interact()
            drinkCreator.updateDrink(from: ingredientStations)
            print("🧋 Updated drink display")
            
        // 4. Forest door - enter woods
        } else if node.name == "front_door" {
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
                    if let gameObject = GridWorld.shared.objectAt(GridWorld.shared.worldToGrid(rotatable.position)) {
                        GridWorld.shared.freeCell(gameObject.gridPosition)
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
        
        longPressTimer = nil
        longPressTarget = nil
    }
    
    // MARK: - Helper Methods (PRESERVED)
    private func findInteractableNode(_ node: SKNode) -> SKNode? {
        print("🔎 Checking node: \(node.name ?? "unnamed") - \(type(of: node))")
        
        // Start with the touched node and search up the hierarchy
        var current: SKNode? = node
        var depth = 0
        
        while current != nil && depth < 5 {
            print("🔎 Level \(depth): \(current?.name ?? "unnamed") - \(type(of: current!))")
            
            // 1. Check for power breaker
            if current == timeBreaker {
                print("✅ Found power breaker")
                return timeBreaker
            }
            
            // 2. Check for ingredient stations
            if let station = current as? IngredientStation {
                print("✅ Found ingredient station: \(station.stationType)")
                return station
            }
            
            // 3. Check for completed drink pickup
            if current?.name == "completed_drink_pickup" {
                print("✅ Found completed drink ready for pickup")
                return current
            }
            
            // 4. Check for front door (forest entrance)
            if current?.name == "front_door" {
                print("✅ Found front door to forest")
                return current
            }
            
            // 5. Check for carried item (to drop)
            if current == character.carriedItem {
                print("✅ Found carried item")
                return character.carriedItem
            }
            
            // 6. Check for table interactions FIRST (before checking if it can be carried)
            if let rotatable = current as? RotatableObject {
                if rotatable.name == "table" {
                    print("✅ Found table for drink placement")
                    return rotatable
                }
                
                print("🔎 Found rotatable: \(rotatable.objectType), canBeCarried: \(rotatable.canBeCarried)")
                if rotatable.canBeCarried {
                    print("✅ Object can be carried")
                    return rotatable
                } else {
                    print("🔎 Object cannot be carried, checking parents...")
                }
            }
            
            current = current?.parent
            depth += 1
        }
        
        print("❌ No interactable found after checking \(depth) levels")
        return nil
    }
    
    // MARK: - Gesture Handlers (PRESERVED)
    @objc private func handlePinch(_ gesture: UIPinchGestureRecognizer) {
        isHandlingPinch = true
        
        switch gesture.state {
        case .began:
            lastPinchScale = cameraScale
        case .changed:
            let newScale = lastPinchScale / gesture.scale
            cameraScale = max(minZoom, min(maxZoom, newScale))
            gameCamera.setScale(cameraScale)
        case .ended, .cancelled:
            isHandlingPinch = false
        default:
            break
        }
    }
    
    @objc private func handleRotation(_ gesture: UIRotationGestureRecognizer) {
        guard gesture.state == .ended else { return }
        
        // PRESERVED: Rotate carried items
        if character.isCarrying {
            character.rotateCarriedItem()
        }
    }
    
    @objc private func handleTwoFingerTap(_ gesture: UITapGestureRecognizer) {
        // Reset camera zoom
        cameraScale = 1.0
        let zoomAction = SKAction.scale(to: cameraScale, duration: 0.3)
        gameCamera.run(zoomAction)
    }
    
    // MARK: - Camera Update
    private func updateCamera() {
        let targetPosition = character.position
        let currentPosition = gameCamera.position
        
        let deltaX = targetPosition.x - currentPosition.x
        let deltaY = targetPosition.y - currentPosition.y
        
        let newX = currentPosition.x + deltaX * cameraLerpSpeed * 0.016
        let newY = currentPosition.y + deltaY * cameraLerpSpeed * 0.016
        
        let effectiveViewWidth = size.width * cameraScale
        let effectiveViewHeight = size.height * cameraScale
        
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
        TimeManager.shared.update()
        
        // Update time display
        updateTimeDisplay()
        
        // Update NPC system using scene time
        updateNPCs(sceneTime)
    }
    
    private func updateTimeDisplay() {
        let phase = TimeManager.shared.currentPhase
        let progress = TimeManager.shared.phaseProgress
        
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
            print("🦊 TIME: \(TimeManager.shared.currentPhase), active: \(TimeManager.shared.isTimeActive)")
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
        
        // Spawn new NPC
        let isNight = TimeManager.shared.currentPhase == .night
        let animal = selectAnimalForSpawn(isNight: isNight) // PHASE 6: Enhanced selection
        let npc = NPC(animal: animal)
        
        addChild(npc)
        npcs.append(npc)
        lastNPCSpawnTime = currentTime
        
        print("🦊 ✨ SPAWNED \(animal.rawValue) at \(npc.position) (\(npcs.count)/\(maxNPCs) NPCs)")
        
        // PHASE 6: Add entrance animation
        addEntranceAnimation(for: npc)
    }
    
    private func getSpawnInterval() -> TimeInterval {
        // PHASE 5: Enhanced spawn rates based on time of day and shop state
        let baseInterval: TimeInterval
        
        switch TimeManager.shared.currentPhase {
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
    
    // MARK: - Phase 6: Enhanced Spawn Selection & Polish
    private func selectAnimalForSpawn(isNight: Bool) -> AnimalType {
        if isNight {
            // Night: 70% normal animals, 30% mysterious night visitors
            if Int.random(in: 1...10) <= 3 {
                return AnimalType.nightAnimals.randomElement() ?? .owl
            } else {
                return AnimalType.dayAnimals.randomElement() ?? .fox
            }
        } else {
            // Day/Dusk: mostly normal animals with some variety
            let allDayAnimals = AnimalType.dayAnimals
            return allDayAnimals.randomElement() ?? .fox
        }
    }
    
    private func addEntranceAnimation(for npc: NPC) {
        // PHASE 6: Subtle entrance effect
        npc.alpha = 0.0
        npc.setScale(0.8)
        
        let entranceAnimation = SKAction.group([
            SKAction.fadeIn(withDuration: 0.5),
            SKAction.scale(to: 1.0, duration: 0.5)
        ])
        entranceAnimation.timingMode = .easeOut
        
        npc.run(entranceAnimation)
        
        print("🎭 Added entrance animation for \(npc.animalType.rawValue)")
    }
    
    // MARK: - Debug Methods
    private func forceSpawnDebugNPC() {
        print("🦊 🚨 FORCE SPAWNING DEBUG NPC NOW!")
        
        let animal = AnimalType.fox
        let npc = NPC(animal: animal)
        
        print("🦊 Created NPC at position: \(npc.position)")
        
        addChild(npc)
        npcs.append(npc)
        lastNPCSpawnTime = sceneTime // Update spawn time to current scene time
        
        print("🦊 ✨ FORCE SPAWNED \(animal.rawValue) - Total NPCs: \(npcs.count)")
        print("🦊 NPC added to scene with zPosition: \(npc.zPosition)")
    }
    
    // MARK: - Table Service System (Phase 2)
    private func placeDrinkOnTable(drink: RotatableObject, table: RotatableObject) {
        // Remove drink from character
        character.dropItemSilently() // We'll add this method
        
        // Create drink sprite as child of table
        let drinkOnTable = createTableDrink(from: drink)
        drinkOnTable.position = CGPoint(x: 0, y: 25) // Offset on table surface
        drinkOnTable.zPosition = 1
        drinkOnTable.name = "drink_on_table"
        table.addChild(drinkOnTable)
        
        print("🧋 ✨ Successfully placed \(drink.objectType) on table!")
        print("🧋 Table now has \(table.children.count) child objects")
    }
    
    private func createTableDrink(from originalDrink: RotatableObject) -> SKNode {
        // Create a smaller version of the drink for table display
        let tableDrink = SKSpriteNode(color: originalDrink.color, size: CGSize(width: 20, height: 30))
        
        // Copy drink visual elements if it's a completed drink
        if originalDrink.objectType == .completedDrink {
            // Add drink details (simplified)
            let lid = SKSpriteNode(color: .lightGray, size: CGSize(width: 16, height: 4))
            lid.position = CGPoint(x: 0, y: 12)
            tableDrink.addChild(lid)
            
            let straw = SKSpriteNode(color: .white, size: CGSize(width: 2, height: 20))
            straw.position = CGPoint(x: 6, y: 8)
            tableDrink.addChild(straw)
        }
        
        return tableDrink
    }
    
    // MARK: - Forest Transition
    private func enterForest() {
        print("🌲 Transitioning to forest scene...")
        
        let fadeOut = SKAction.fadeOut(withDuration: 0.5)
        
        run(fadeOut) { [weak self] in
            guard let self = self else { return }
            
            let forestScene = ForestScene(size: self.size)
            forestScene.scaleMode = .aspectFill
            self.view?.presentScene(forestScene, transition: SKTransition.fade(withDuration: 0.5))
        }
    }
}
