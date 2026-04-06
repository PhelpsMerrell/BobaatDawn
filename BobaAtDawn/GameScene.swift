//
//  GameScene.swift
//  BobaAtDawn
//
//  Main game scene — shop interior, world building, input handling, update loop.
//  Ritual system:  GameScene+Ritual.swift
//  Save system:    GameScene+SaveSystem.swift
//  Grid helpers:   GameScene+GridPositioning.swift
//

import SpriteKit

// MARK: - Main Game Scene
class GameScene: BaseGameScene {
    
    // MARK: - Services (internal for extension access)
    internal lazy var npcService: NPCService = serviceContainer.resolve(NPCService.self)
    internal lazy var timeService: TimeService = serviceContainer.resolve(TimeService.self)
    internal let residentManager = NPCResidentManager.shared
    
    // MARK: - Game Objects
    internal var ingredientStations: [IngredientStation] = []
    internal var drinkCreator: DrinkCreator!
    
    // MARK: - Save System
    internal var saveJournal: SaveSystemButton!
    internal var clearDataButton: SaveSystemButton!
    internal var npcStatusTracker: SaveSystemButton!
    
    // MARK: - Time System
    internal var timeBreaker: PowerBreaker!
    internal var timeWindow: Window!
    internal var timeLabel: SKLabelNode!
    
    // MARK: - Ritual System
    internal var ritualArea: RitualArea!
    internal var isRitualActive: Bool = false
    
    // MARK: - Debug / Physics / World
    internal var timeControlButton: TimeControlButton?
    internal var physicsContactHandler: PhysicsContactHandler!
    internal var shopFloor: SKSpriteNode!
    internal var showGridOverlay = false
    
    // MARK: - NPC System
    internal var npcs: [ShopNPC] = []
    
    // MARK: - Time Phase Monitoring
    internal var lastTimePhase: TimePhase = .day
    
    // MARK: - Scene Lifecycle
    
    override open func setupSpecificContent() {
        Log.info(.scene, "GameScene setup starting...")
        
        setupPhysicsWorld()
        setupIngredientStations()
        convertExistingObjectsToGrid()
        setupTimeSystem()
        setupSaveSystem()       // → GameScene+SaveSystem.swift
        setupLivingWorld()
        setupTimePhaseMonitoring()
        setupRitualArea()       // → GameScene+Ritual.swift
        
        if showGridOverlay { addGridOverlay() }
        
        gridService.printGridState()
        Log.info(.scene, "GameScene setup complete")
    }
    
    // MARK: - Physics Setup
    
    private func setupPhysicsWorld() {
        physicsWorld.gravity = PhysicsConfig.World.gravity
        physicsWorld.speed = PhysicsConfig.World.speed
        physicsContactHandler = PhysicsContactHandler()
        physicsWorld.contactDelegate = physicsContactHandler
        physicsContactHandler.contactDelegate = self
        Log.info(.physics, "Physics world enabled")
    }
    
    // MARK: - World Building
    
    override open func setupWorld() {
        super.setupWorld()
        
        guard worldWidth > 0 && worldHeight > 0 else {
            Log.error(.scene, "Invalid world dimensions: \(worldWidth) x \(worldHeight)")
            return
        }
        
        // Floor
        shopFloor = SKSpriteNode(color: configService.floorColor,
                                  size: CGSize(width: worldWidth, height: worldHeight))
        shopFloor.position = .zero
        shopFloor.zPosition = ZLayers.floor
        addChild(shopFloor)
        
        setupShopFloorBounds()
        setupWalls()
        setupFrontDoor()
        
        Log.info(.scene, "Shop world built (\(worldWidth)×\(worldHeight))")
    }
    
    private func setupShopFloorBounds() {
        let rect = GameConfig.shopFloorRect()
        guard rect.size.width > 0, rect.size.height > 0, rect.size.width < 10000 else {
            Log.error(.grid, "Invalid shop floor rect: \(rect.size)")
            return
        }
        guard let bounds = createValidatedSprite(color: configService.shopFloorColor,
                                                  size: rect.size, name: "shop floor bounds") else {
            Log.error(.grid, "Failed to create shop floor bounds sprite")
            return
        }
        bounds.position = rect.position
        bounds.zPosition = ZLayers.shopFloorBounds
        addChild(bounds)
    }
    
    private func setupWalls() {
        let t = configService.wallThickness
        let inset = configService.wallInset
        let color = configService.wallColor
        let w = worldWidth, h = worldHeight
        
        func wall(_ size: CGSize, _ pos: CGPoint) {
            guard size.width > 0, size.height > 0 else { return }
            let node = SKSpriteNode(color: color, size: size)
            node.position = pos
            node.zPosition = ZLayers.walls
            addChild(node)
        }
        
        wall(CGSize(width: w, height: t), CGPoint(x: 0, y:  h/2 - inset))  // top
        wall(CGSize(width: w, height: t), CGPoint(x: 0, y: -h/2 + inset))  // bottom
        wall(CGSize(width: t, height: h), CGPoint(x: -w/2 + inset, y: 0))  // left
        wall(CGSize(width: t, height: h), CGPoint(x:  w/2 - inset, y: 0))  // right
    }
    
    private func setupFrontDoor() {
        let door = SKLabelNode(text: "🚪")
        door.fontSize = configService.doorSize
        door.fontName = "Arial"
        door.horizontalAlignmentMode = .center
        door.verticalAlignmentMode = .center
        door.position = GameConfig.doorWorldPosition()
        door.zPosition = ZLayers.doors
        door.name = "front_door"
        addChild(door)
        Log.debug(.scene, "Front door at grid \(GameConfig.World.doorGridPosition)")
    }
    
    // MARK: - Ingredient Stations
    
    private func setupIngredientStations() {
        let types: [IngredientStation.StationType] = [.ice, .tea, .boba, .foam, .lid]
        let cells = [
            GridCoordinate(x: 12, y: 17), GridCoordinate(x: 14, y: 17),
            GridCoordinate(x: 16, y: 17), GridCoordinate(x: 18, y: 17),
            GridCoordinate(x: 20, y: 17)
        ]
        
        for (i, type) in types.enumerated() {
            let station = IngredientStation(type: type)
            let cell = cells[i]
            station.position = gridService.gridToWorld(cell)
            station.zPosition = ZLayers.stations
            addChild(station)
            ingredientStations.append(station)
            
            gridService.reserveCell(cell)
            let go = GameObject(skNode: station, gridPosition: cell, objectType: .station, gridService: gridService)
            gridService.occupyCell(cell, with: go)
            
            Log.debug(.drink, "Station \(type) at grid \(cell)")
        }
        
        drinkCreator = DrinkCreator()
        let displayCell = GridCoordinate(x: 16, y: 14)
        drinkCreator.position = gridService.gridToWorld(displayCell)
        drinkCreator.zPosition = ZLayers.drinkCreator
        addChild(drinkCreator)
        gridService.reserveCell(displayCell)
        drinkCreator.updateDrink(from: ingredientStations)
        
        Log.info(.drink, "5 ingredient stations placed")
    }
    
    // MARK: - Furniture & Tables
    
    private func convertExistingObjectsToGrid() {
        let objectConfigs: [(GridCoordinate, ObjectType, SKColor, String)] = [
            (GridCoordinate(x: 25, y: 10), .furniture, .red,    "arrow"),
            (GridCoordinate(x: 25, y: 12), .furniture, .blue,   "L"),
            (GridCoordinate(x: 25, y: 14), .drink,    .green,  "triangle"),
            (GridCoordinate(x: 25, y: 16), .furniture, .orange, "rectangle")
        ]
        
        for (gridPos, type, color, shape) in objectConfigs {
            let obj = RotatableObject(type: type, color: color, shape: shape)
            obj.position = gridService.gridToWorld(gridPos)
            obj.zPosition = ZLayers.groundObjects
            addChild(obj)
            let go = GameObject(skNode: obj, gridPosition: gridPos, objectType: type, gridService: gridService)
            gridService.occupyCell(gridPos, with: go)
        }
        
        let tablePositions = [
            GridCoordinate(x: 12, y: 8), GridCoordinate(x: 14, y: 8),
            GridCoordinate(x: 16, y: 8), GridCoordinate(x: 18, y: 8),
            GridCoordinate(x: 12, y: 6), GridCoordinate(x: 14, y: 6),
            GridCoordinate(x: 16, y: 6), GridCoordinate(x: 18, y: 6),
            GridCoordinate(x: 20, y: 6)
        ]
        
        let tableColor = SKColor(red: 0.4, green: 0.2, blue: 0.1, alpha: 1.0)
        for gridPos in tablePositions {
            let table = RotatableObject(type: .furniture, color: tableColor, shape: "table")
            table.position = gridService.gridToWorld(gridPos)
            table.zPosition = ZLayers.tables
            table.name = "table"
            addChild(table)
            let go = GameObject(skNode: table, gridPosition: gridPos, objectType: .furniture, gridService: gridService)
            gridService.occupyCell(gridPos, with: go)
        }
        
        Log.debug(.grid, "Objects and tables placed on grid")
    }
    
    // MARK: - Time System
    
    private func setupTimeSystem() {
        let positions = GameConfig.timeSystemPositions()
        
        timeBreaker = PowerBreaker()
        timeBreaker.position = positions.breaker
        timeBreaker.zPosition = ZLayers.timeSystem
        addChild(timeBreaker)
        
        timeWindow = Window()
        timeWindow.position = positions.window
        timeWindow.zPosition = ZLayers.timeSystem
        addChild(timeWindow)
        
        timeLabel = SKLabelNode(text: "DAY")
        timeLabel.fontSize = 24
        timeLabel.fontName = "Arial-Bold"
        timeLabel.fontColor = .black
        timeLabel.horizontalAlignmentMode = .center
        timeLabel.verticalAlignmentMode = .center
        timeLabel.position = positions.label
        timeLabel.zPosition = ZLayers.timeSystemLabels
        addChild(timeLabel)
        
        timeControlButton = TimeControlButton(timeService: timeService)
        timeControlButton?.position = CGPoint(x: positions.window.x + 80, y: positions.window.y)
        addChild(timeControlButton!)
        
        Log.info(.time, "Time system placed")
    }
    
    // MARK: - Living World
    
    private func setupLivingWorld() {
        residentManager.registerGameScene(self)
        residentManager.initializeWorld()
        Log.info(.resident, "Living world initialized")
    }
    
    private func setupTimePhaseMonitoring() {
        lastTimePhase = timeService.currentPhase
        residentManager.handleTimePhaseChange(lastTimePhase)
        Log.info(.time, "Phase monitoring initialized at \(lastTimePhase.displayName)")
    }
    
    // MARK: - Update Loop
    
    override open func updateSpecificContent(_ currentTime: TimeInterval) {
        timeService.update()
        
        let currentPhase = timeService.currentPhase
        if currentPhase != lastTimePhase {
            Log.info(.time, "Phase changed: \(lastTimePhase.displayName) → \(currentPhase.displayName)")
            lastTimePhase = currentPhase
            residentManager.handleTimePhaseChange(currentPhase)
            handleRitualTimePhaseChange(currentPhase)  // → GameScene+Ritual.swift
        }
        
        updateTimeDisplay()
        timeControlButton?.update()
        residentManager.update(deltaTime: 1.0 / 60.0)
        updateShopNPCs()
        
        // Simulate snail wandering while player is in the shop
        // Also check time activation so the snail wakes/sleeps even from the shop
        let snailWorld = SnailWorldState.shared
        if timeService.currentPhase == .night && !snailWorld.isActive {
            snailWorld.activate()
        } else if timeService.currentPhase != .night && snailWorld.isActive {
            snailWorld.deactivate()
        }
        snailWorld.simulateWandering(deltaTime: 1.0 / 60.0)
    }
    
    private func updateTimeDisplay() {
        let phase = timeService.currentPhase
        let pct = Int(timeService.phaseProgress * 100)
        let ritual = timeService.isRitualDay ? " 🕯️" : ""
        timeLabel.text = "D\(timeService.dayCount) \(phase.displayName.uppercased()) \(pct)%\(ritual)"
        
        switch phase {
        case .dawn:  timeLabel.fontColor = .systemPink
        case .day:   timeLabel.fontColor = .blue
        case .dusk:  timeLabel.fontColor = .orange
        case .night: timeLabel.fontColor = .purple
        }
    }
    
    // MARK: - Shop NPC Management
    
    private func updateShopNPCs() {
        let dt = 1.0 / 60.0
        for npc in npcs { npc.update(deltaTime: dt) }
        
        let before = npcs.count
        npcs.removeAll { npc in
            guard npc.parent == nil else { return false }
            if npc.isCurrentlyInRitual() {
                Log.warn(.npc, "Ritual NPC \(npc.animalType.rawValue) removed from parent — keeping in memory")
                return false
            }
            let satisfied = npc.state.isExiting && npc.state.displayName.contains("Happy")
            residentManager.npcLeftShop(npc, satisfied: satisfied)
            Log.debug(.npc, "Cleaned up \(npc.animalType.rawValue)")
            return true
        }
        if npcs.count < before {
            Log.debug(.npc, "NPC cleanup: \(before - npcs.count) removed, \(npcs.count) remain")
        }
    }
    
    // MARK: - Table / Drink Placement
    
    func placeDrinkOnTable(drink: RotatableObject, table: RotatableObject) {
        let existing = table.children.filter { $0.name == "drink_on_table" }
        guard existing.count < 3 else {
            Log.debug(.drink, "Table full (\(existing.count)/3)")
            return
        }
        
        character.dropItemSilently()
        
        let drinkOnTable = createTableDrink(from: drink)
        let offsets: [CGPoint] = [
            configService.tableDrinkOnTableOffset,
            CGPoint(x: configService.tableDrinkOnTableOffset.x - 15, y: configService.tableDrinkOnTableOffset.y + 10),
            CGPoint(x: configService.tableDrinkOnTableOffset.x + 15, y: configService.tableDrinkOnTableOffset.y + 10)
        ]
        drinkOnTable.position = offsets[existing.count]
        drinkOnTable.zPosition = ZLayers.childLayer(for: ZLayers.tables)
        drinkOnTable.name = "drink_on_table"
        table.addChild(drinkOnTable)
        
        Log.info(.drink, "Placed drink on \(table.name ?? "table")")
        
        if table.name == "sacred_table" && isRitualActive {
            Log.info(.ritual, "Sacred table — triggering ritual sequence")
            triggerRitualSequence(drinkOnTable: drinkOnTable, sacredTable: table)
        }
    }
    
    func createTableDrink(from originalDrink: RotatableObject) -> SKNode {
        let tableDrink = SKNode()
        let atlas = SKTextureAtlas(named: "Boba")
        guard atlas.textureNames.count > 0 else {
            Log.error(.drink, "Boba atlas not found or empty")
            return tableDrink
        }
        
        let cupTex = atlas.textureNamed("cup_empty")
        let tableScale = 15.0 / cupTex.size().width
        
        for child in originalDrink.children {
            guard let sprite = child as? SKSpriteNode, let name = sprite.name else { continue }
            guard atlas.textureNames.contains(name) else { continue }
            
            let tex = atlas.textureNamed(name)
            tex.filteringMode = .nearest
            let node = SKSpriteNode(texture: tex)
            node.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            node.position = .zero
            node.setScale(tableScale)
            node.zPosition = sprite.zPosition
            node.isHidden = sprite.isHidden
            node.alpha = sprite.alpha
            node.blendMode = .alpha
            node.name = name
            tableDrink.addChild(node)
        }
        
        Log.debug(.drink, "Table drink created with \(tableDrink.children.count) layers")
        return tableDrink
    }
    
    // MARK: - Forest Transition
    
    func enterForest() {
        Log.info(.forest, "Entering the mysterious forest...")
        transitionService.transitionToForest(from: self) {
            Log.info(.forest, "Transitioned to forest")
        }
    }
    
    // MARK: - Grid Overlay (Debug)
    
    private func addGridOverlay() {
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
    }
    
    // MARK: - Input Handling
    
    override open func handleSceneSpecificLongPress(on node: SKNode, at location: CGPoint) {
        handleGameSceneLongPress(on: node, at: location)
    }
    
    private func handleGameSceneLongPress(on node: SKNode, at location: CGPoint) {
        Log.debug(.input, "Long press on: \(node.name ?? "unnamed") (\(type(of: node)))")
        
        if node == character.carriedItem {
            character.dropItem()
            
        } else if node == timeBreaker {
            timeBreaker.toggle()
            
        } else if let station = node as? IngredientStation {
            let pulse = animationService.stationInteractionPulse(station)
            animationService.run(pulse, on: station, withKey: AnimationKeys.stationInteraction, completion: nil)
            station.interact()
            drinkCreator.updateDrink(from: ingredientStations)
            Log.debug(.drink, "Station \(station.stationType) toggled")
            
        } else if let saveButton = node as? SaveSystemButton {
            switch saveButton.buttonType {
            case .saveJournal: saveGameState()
            case .clearData:   clearSaveData()
            case .npcStatus:   showNPCStatusReport()
            }
            
        } else if node.name == "save_journal"      { saveGameState()
        } else if node.name == "clear_data_button"  { clearSaveData()
        } else if node.name == "npc_status_tracker" { showNPCStatusReport()
            
        } else if node.name == "front_door" {
            transitionService.triggerHapticFeedback(type: .success)
            enterForest()
            
        } else if let trash = node as? Trash {
            trash.pickUp { Log.debug(.game, "Trash cleaned up") }
            transitionService.triggerHapticFeedback(type: .light)
            
        } else if node.name == "completed_drink_pickup" {
            if character.carriedItem == nil,
               let drink = drinkCreator.createCompletedDrink(from: ingredientStations) {
                character.pickupItem(drink)
                drinkCreator.resetStations(ingredientStations)
                Log.info(.drink, "Picked up completed drink, stations reset")
            }
            
        } else if let rotatable = node as? RotatableObject {
            // Drink creator pickup
            if rotatable.name == "drink_display" && rotatable.parent == drinkCreator {
                if character.carriedItem == nil {
                    let creation = drinkCreator.createPickupDrink(from: ingredientStations)
                    character.pickupItem(creation)
                    drinkCreator.resetStations(ingredientStations)
                    Log.info(.drink, "Picked up creation from creator, stations reset")
                }
                return
            }
            
            // Table drink placement
            if (rotatable.name == "table" || rotatable.name == "sacred_table"),
               let carried = character.carriedItem {
                placeDrinkOnTable(drink: carried, table: rotatable)
                return
            }
            
            // Object pickup
            if rotatable.canBeCarried && character.carriedItem == nil {
                if let go = gridService.objectAt(gridService.worldToGrid(rotatable.position)) {
                    gridService.freeCell(go.gridPosition)
                }
                character.pickupItem(rotatable)
                Log.debug(.game, "Picked up \(rotatable.objectType)")
            }
        }
    }
}

// MARK: - Physics Contact Delegate

extension GameScene: PhysicsContactDelegate {
    
    func characterContactedStation(_ station: SKNode) {
        // proximity hint hook
    }
    
    func characterContactedDoor(_ door: SKNode) {
        // "enter forest" hint hook
    }
    
    func characterContactedItem(_ item: SKNode) {
        // "pick up" hint hook
    }
    
    func characterContactedNPC(_ npc: SKNode) {
        if let shopNPC = npc as? ShopNPC {
            Log.debug(.npc, "Character contacted \(shopNPC.animalType.rawValue)")
        }
    }
    
    func npcContactedDoor(_ npc: SKNode, door: SKNode) {
        if let shopNPC = npc as? ShopNPC, door.name == "front_door" {
            shopNPC.startLeaving(satisfied: true)
        }
    }
    
    func itemContactedFurniture(_ item: SKNode, furniture: SKNode) {
        // auto-placement hook
    }
}
