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
@objc(GameScene)
class GameScene: BaseGameScene {

    private let editorStationNames = [
        "ingredient_station_ice",
        "ingredient_station_tea",
        "ingredient_station_boba",
        "ingredient_station_foam",
        "ingredient_station_lid",
        "ingredient_station_trash"
    ]

    private let editorFurnitureNames = [
        "furniture_arrow",
        "furniture_l_shape",
        "furniture_triangle",
        "furniture_rectangle"
    ]

    private let editorTableNames = [
        "table_1", "table_2", "table_3",
        "table_4", "table_5", "table_6",
        "table_7", "table_8", "table_9"
    ]

    // Node names here MUST match the `Name` field in GameScene.sks
    // (case-sensitive). StorageContainer's init(coder:) handles
    // case-insensitive storage-type derivation, so these strings only
    // need to match what's set in the editor.
    private let editorStorageNames = [
        "Pantry", "Fridge"
    ]

    /// Optional — if the JournalBook node has been added to GameScene.sks
    /// with this name, it'll be wired up at scene load. Until then this
    /// stays nil and the long-press handler simply won't see it.
    internal let editorJournalBookName = "journal_book"
    
    // MARK: - Services (internal for extension access)
    internal lazy var npcService: NPCService = serviceContainer.resolve(NPCService.self)
    internal lazy var timeService: TimeService = serviceContainer.resolve(TimeService.self)
    internal let residentManager = NPCResidentManager.shared
    
    // MARK: - Game Objects
    internal var ingredientStations: [IngredientStation] = []
    internal var drinkCreator: DrinkCreator!
    internal var storageContainers: [StorageContainer] = []
    internal var journalBook: JournalBook?
    
    // MARK: - Save System
    internal var saveJournal: SaveSystemButton!
    internal var clearDataButton: SaveSystemButton!
    internal var npcStatusTracker: SaveSystemButton!
    
    // MARK: - Time System

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
        setupStorageContainers()
        setupJournalBook()
        convertExistingObjectsToGrid()
        setupTimeSystem()
        setupSaveSystem()       // → GameScene+SaveSystem.swift
        setupLivingWorld()
        setupTimePhaseMonitoring()
        setupRitualArea()       // → GameScene+Ritual.swift
        
        // Restore persistent world items (trash + drinks on tables) that
        // were placed in previous sessions or before scene transitions.
        // Must run AFTER convertExistingObjectsToGrid so tables exist.
        restoreShopTrashFromRegistry()
        restoreDrinksOnTablesFromRegistry()

        // Apply rearrangement registry: re-position editor-placed
        // tables/furniture to wherever they were left in a prior
        // session or by the partner. Must run AFTER
        // convertExistingObjectsToGrid because that's where the .sks
        // furniture/table nodes get added to the grid; we re-occupy
        // their new cells here.
        applyMovableObjectRegistryToScene()
        
        if showGridOverlay { addGridOverlay() }
        
        setupMultiplayer()  // → GameScene+Multiplayer.swift
        
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

        backgroundColor = configService.backgroundColor
        shopFloor = requiredSceneNode(named: "shop_floor", as: SKSpriteNode.self)
        shopFloor.zPosition = ZLayers.floor

        let shopFloorBounds = requiredSceneNode(named: "shop_floor_bounds", as: SKSpriteNode.self)
        shopFloorBounds.zPosition = ZLayers.shopFloorBounds

        // Defensive cleanup: if `shop_floor_bounds` was accidentally given
        // a Custom Class of StorageContainer in the .sks editor, runtime
        // init(coder:) will have attached a "PANTRY" SKLabelNode to it.
        // Strip any such label so it doesn't float over the shop.
        // (The interactable-rejection for this node lives in
        // StandardInputService.checkCommonInteractables.)
        for child in shopFloorBounds.children where child.name == "storage_label" {
            child.removeFromParent()
        }

        if let barH = sceneNode(named: "bar_horizontal", as: SKSpriteNode.self) {
            barH.zPosition = ZLayers.walls
        }
        if let barV = sceneNode(named: "bar_vertical", as: SKSpriteNode.self) {
            barV.zPosition = ZLayers.walls
        }

        requiredSceneNode(named: "wall_top", as: SKSpriteNode.self).zPosition = ZLayers.walls
        requiredSceneNode(named: "wall_bottom", as: SKSpriteNode.self).zPosition = ZLayers.walls
        requiredSceneNode(named: "wall_left", as: SKSpriteNode.self).zPosition = ZLayers.walls
        requiredSceneNode(named: "wall_right", as: SKSpriteNode.self).zPosition = ZLayers.walls

        let door = requiredSceneNode(named: "front_door", as: SKLabelNode.self)
        door.zPosition = ZLayers.doors
        
        Log.info(.scene, "Shop world built (\(worldWidth)×\(worldHeight))")
    }
    
    // MARK: - Ingredient Stations
    
    private func setupIngredientStations() {
        // NOTE: `ingredient_station_trash` is required by the editor-scene
        // list. If it's not present yet in GameScene.sks, comment it out of
        // `editorStationNames` above until the node is added in Xcode.
        ingredientStations = editorStationNames.map { requiredSceneNode(named: $0, as: IngredientStation.self) }

        for station in ingredientStations {
            let cell = gridService.worldToGrid(station.positionInSceneCoordinates())
            station.zPosition = ZLayers.stations
            gridService.reserveCell(cell)
            let go = GameObject(skNode: station, gridPosition: cell, objectType: .station, gridService: gridService)
            gridService.occupyCell(cell, with: go)
            
            Log.debug(.drink, "Station \(station.stationType) at grid \(cell)")
        }

        drinkCreator = requiredSceneNode(named: "drink_creator", as: DrinkCreator.self)
        drinkCreator.zPosition = ZLayers.drinkCreator
        let displayCell = gridService.worldToGrid(drinkCreator.positionInSceneCoordinates())
        gridService.reserveCell(displayCell)
        
        // The counter display is always a static empty cup. It represents
        // the "stack of cups" the player grabs from; it does not reflect
        // any in-progress drink state (that lives on the drink in hand).
        drinkCreator.rebuildDisplayAsEmptyCup()
        
        Log.info(.drink, "\(ingredientStations.count) ingredient stations loaded from GameScene.sks")
    }
    
    // MARK: - World Item Restoration
    
    /// Rebuild shop-scoped trash nodes from the persistent registry so that
    /// trash left behind in prior sessions reappears on scene load.
    /// Called during setupSpecificContent after the grid is built.
    internal func restoreShopTrashFromRegistry() {
        let items = WorldItemRegistry.shared.items(of: .trash, at: .shop)
        guard !items.isEmpty else { return }
        
        for item in items {
            let trash = Trash(at: item.position.cgPoint, location: .shop)
            trash.userData = NSMutableDictionary()
            trash.userData?["worldItemID"] = item.id
            addChild(trash)
        }
        Log.info(.save, "Restored \(items.count) shop trash from registry")
    }
    
    /// Rebuild drinks-on-tables from the persistent registry so that drinks
    /// placed in prior sessions reappear on scene load. Matches each item
    /// to the nearest table by position and stacks them using the same
    /// slot-index offset logic as `placeDrinkOnTable`.
    internal func restoreDrinksOnTablesFromRegistry() {
        let items = WorldItemRegistry.shared.items(of: .drinkOnTable, at: .shop)
        guard !items.isEmpty else { return }
        
        // Gather live table nodes once, skipping the sacred table (ritual-only).
        let tables: [RotatableObject] = children.compactMap { $0 as? RotatableObject }
            .filter { isTableNode($0) && $0.name != "sacred_table" }
        guard !tables.isEmpty else {
            Log.warn(.save, "Cannot restore drinks on tables — no table nodes found")
            return
        }
        
        let offsets: [CGPoint] = [
            configService.tableDrinkOnTableOffset,
            CGPoint(x: configService.tableDrinkOnTableOffset.x - 15,
                    y: configService.tableDrinkOnTableOffset.y + 10),
            CGPoint(x: configService.tableDrinkOnTableOffset.x + 15,
                    y: configService.tableDrinkOnTableOffset.y + 10)
        ]
        
        var restored = 0
        for item in items {
            guard let table = tables.min(by: {
                hypot($0.position.x - item.position.x, $0.position.y - item.position.y)
                <
                hypot($1.position.x - item.position.x, $1.position.y - item.position.y)
            }) else { continue }
            
            let drinkNode = buildTableDrinkVisual(
                hasTea:  item.hasTea,
                hasIce:  item.hasIce,
                hasBoba: item.hasBoba,
                hasFoam: item.hasFoam,
                hasLid:  item.hasLid
            )
            let slot = max(0, min(item.slotIndex, offsets.count - 1))
            drinkNode.position = offsets[slot]
            drinkNode.zPosition = ZLayers.childLayer(for: ZLayers.tables)
            drinkNode.name = "drink_on_table"
            drinkNode.userData = NSMutableDictionary()
            drinkNode.userData?["worldItemID"] = item.id
            table.addChild(drinkNode)
            restored += 1
        }
        Log.info(.save, "Restored \(restored)/\(items.count) drinks on tables from registry")
    }
    
    /// Build a small on-table drink node from a set of ingredient flags.
    /// Mirrors the atlas/scale logic of `createTableDrink` so restored and
    /// freshly-placed drinks look identical.
    private func buildTableDrinkVisual(hasTea: Bool, hasIce: Bool, hasBoba: Bool, hasFoam: Bool, hasLid: Bool) -> SKNode {
        let tableDrink = SKNode()
        let atlas = SKTextureAtlas(named: "Boba")
        guard atlas.textureNames.count > 0 else {
            Log.warn(.drink, "Boba atlas empty — returning empty table drink node")
            return tableDrink
        }
        
        let cupTex = atlas.textureNamed("cup_empty")
        let tableScale = 15.0 / cupTex.size().width
        
        func addLayer(_ name: String, z: CGFloat) {
            guard atlas.textureNames.contains(name) else { return }
            let tex = atlas.textureNamed(name)
            tex.filteringMode = .nearest
            let node = SKSpriteNode(texture: tex)
            node.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            node.position = .zero
            node.setScale(tableScale)
            node.zPosition = z
            node.blendMode = .alpha
            node.name = name
            tableDrink.addChild(node)
        }
        
        addLayer("cup_empty", z: 0)
        if hasTea  { addLayer("tea_black",       z: 1) }
        if hasIce  { addLayer("ice_cubes",       z: 2) }
        if hasBoba { addLayer("topping_tapioca", z: 3) }
        if hasFoam { addLayer("foam_cheese",     z: 4) }
        if hasLid  { addLayer("lid_straw",       z: 5) }
        
        return tableDrink
    }
    
    /// Apply persisted rearrangements: for every entry in
    /// `MovableObjectRegistry`, find the matching editor-placed node
    /// (tables `table_*`, furniture `furniture_*`) and move it to the
    /// stored position + rotation, freeing the editor cell and
    /// occupying the new one. Untracked nodes are left at their .sks
    /// defaults. Sacred table is always skipped.
    internal func applyMovableObjectRegistryToScene() {
        let entries = MovableObjectRegistry.shared.allEntries()
        guard !entries.isEmpty else { return }

        // Build lookup once — every editor table + furniture by name.
        var byName: [String: RotatableObject] = [:]
        for child in children {
            guard let rot = child as? RotatableObject,
                  let name = rot.name else { continue }
            if name == "sacred_table" { continue }
            if name.hasPrefix("table_") || name.hasPrefix("furniture_") {
                byName[name] = rot
            }
        }

        var applied = 0
        for entry in entries {
            guard let node = byName[entry.editorName] else { continue }
            // Free the old grid cell first.
            let oldCell = gridService.worldToGrid(node.position)
            gridService.freeCell(oldCell)

            // Place the node at the persisted position.
            node.position = entry.position.cgPoint
            if let state = RotationState(rawValue: entry.rotationDegrees) {
                node.setRotationState(state)
            }

            if entry.isCarried {
                // Object was in someone's hands when the registry was
                // last persisted. Leave it floating where it was; if
                // the partner is still connected they'll send a fresh
                // pickup/drop, otherwise the next drop persists a real
                // floor position.
                node.zPosition = ZLayers.carriedItems
            } else {
                // Re-occupy the new grid cell.
                let newCell = gridService.worldToGrid(node.position)
                let go = GameObject(
                    skNode: node,
                    gridPosition: newCell,
                    objectType: node.objectType,
                    gridService: gridService
                )
                gridService.occupyCell(newCell, with: go)
            }
            applied += 1
        }
        if applied > 0 {
            Log.info(.save, "Restored \(applied) movable-object placements")
        }
    }

    // MARK: - Mid-Scene Registry Reconcile
    
    /// Reconcile the live scene against the current `WorldItemRegistry`
    /// contents for shop items. Called after `applyWorldSync` imports a
    /// fresh registry from the other player.
    ///
    /// Strategy:
    ///   1. Index existing scene nodes by their `worldItemID`.
    ///   2. For each registry item: leave it if already rendered, spawn
    ///      it if not.
    ///   3. Remove any scene node whose `worldItemID` is no longer in the
    ///      registry.
    ///
    /// Only touches shop-scoped items (trash at .shop, drinkOnTable at
    /// .shop). Forest trash is handled by ForestScene. Sacred-table drinks
    /// are skipped entirely — they aren't persistent.
    internal func reconcileSceneWithWorldItemRegistry() {
        reconcileShopTrashWithRegistry()
        reconcileDrinksOnTablesWithRegistry()
    }
    
    private func reconcileShopTrashWithRegistry() {
        // Index existing trash nodes by registry ID.
        var existingByID: [String: Trash] = [:]
        var untrackedNodes: [Trash] = []
        for trash in children.compactMap({ $0 as? Trash }) {
            if let id = trash.userData?["worldItemID"] as? String {
                existingByID[id] = trash
            } else {
                untrackedNodes.append(trash)
            }
        }
        
        // Registry contents for the shop.
        let registryItems = WorldItemRegistry.shared.items(of: .trash, at: .shop)
        let registryIDs = Set(registryItems.map { $0.id })
        
        // Spawn anything present in the registry but missing from the scene.
        var spawned = 0
        for item in registryItems where existingByID[item.id] == nil {
            let trash = Trash(at: item.position.cgPoint, location: .shop)
            trash.userData = NSMutableDictionary()
            trash.userData?["worldItemID"] = item.id
            addChild(trash)
            spawned += 1
        }
        
        // Remove tracked scene nodes whose ID is no longer in the registry.
        var removed = 0
        for (id, node) in existingByID where !registryIDs.contains(id) {
            node.removeFromParent()
            removed += 1
        }
        
        // Untracked trash (no worldItemID on userData) is legacy-placed;
        // leave it alone — we don't know what it corresponds to in the
        // registry and ripping it out could surprise the player.
        if spawned > 0 || removed > 0 || !untrackedNodes.isEmpty {
            Log.info(.network, "Reconciled shop trash: +\(spawned) / -\(removed) (\(untrackedNodes.count) untracked left alone)")
        }
    }
    
    private func reconcileDrinksOnTablesWithRegistry() {
        // Find every `drink_on_table` node in the scene, flattened across
        // all tables. Key them by registry ID.
        var existingByID: [String: SKNode] = [:]
        var untrackedNodes: [SKNode] = []
        
        let tables: [RotatableObject] = children.compactMap { $0 as? RotatableObject }
            .filter { isTableNode($0) && $0.name != "sacred_table" }
        
        for table in tables {
            for child in table.children where child.name == "drink_on_table" {
                if let id = child.userData?["worldItemID"] as? String {
                    existingByID[id] = child
                } else {
                    untrackedNodes.append(child)
                }
            }
        }
        
        let registryItems = WorldItemRegistry.shared.items(of: .drinkOnTable, at: .shop)
        let registryIDs = Set(registryItems.map { $0.id })
        
        let offsets: [CGPoint] = [
            configService.tableDrinkOnTableOffset,
            CGPoint(x: configService.tableDrinkOnTableOffset.x - 15,
                    y: configService.tableDrinkOnTableOffset.y + 10),
            CGPoint(x: configService.tableDrinkOnTableOffset.x + 15,
                    y: configService.tableDrinkOnTableOffset.y + 10)
        ]
        
        // Spawn missing drinks, matched to nearest table by position.
        var spawned = 0
        for item in registryItems where existingByID[item.id] == nil {
            guard !tables.isEmpty,
                  let table = tables.min(by: {
                      hypot($0.position.x - item.position.x, $0.position.y - item.position.y)
                      <
                      hypot($1.position.x - item.position.x, $1.position.y - item.position.y)
                  }) else { continue }
            
            let drinkNode = buildTableDrinkVisual(
                hasTea:  item.hasTea,
                hasIce:  item.hasIce,
                hasBoba: item.hasBoba,
                hasFoam: item.hasFoam,
                hasLid:  item.hasLid
            )
            let slot = max(0, min(item.slotIndex, offsets.count - 1))
            drinkNode.position = offsets[slot]
            drinkNode.zPosition = ZLayers.childLayer(for: ZLayers.tables)
            drinkNode.name = "drink_on_table"
            drinkNode.userData = NSMutableDictionary()
            drinkNode.userData?["worldItemID"] = item.id
            table.addChild(drinkNode)
            spawned += 1
        }
        
        // Remove tracked drinks whose ID vanished from the registry.
        var removed = 0
        for (id, node) in existingByID where !registryIDs.contains(id) {
            node.removeFromParent()
            removed += 1
        }
        
        if spawned > 0 || removed > 0 || !untrackedNodes.isEmpty {
            Log.info(.network, "Reconciled drinks on tables: +\(spawned) / -\(removed) (\(untrackedNodes.count) untracked left alone)")
        }
    }

    // MARK: - Storage Containers (Pantry & Fridge)

    private func setupStorageContainers() {
        storageContainers = editorStorageNames.compactMap { sceneNode(named: $0, as: StorageContainer.self) }

        for container in storageContainers {
            let cell = gridService.worldToGrid(container.positionInSceneCoordinates())
            container.zPosition = ZLayers.furniture
            gridService.reserveCell(cell)
            let go = GameObject(skNode: container, gridPosition: cell, objectType: .furniture, gridService: gridService)
            gridService.occupyCell(cell, with: go)
        }

        Log.info(.game, "\(storageContainers.count) storage containers loaded from GameScene.sks")
    }

    // MARK: - Journal Book

    /// Look up the JournalBook node by its editor name. Optional —
    /// if the node hasn't been added yet, this no-ops gracefully and
    /// the long-press handler will never see one.
    private func setupJournalBook() {
        guard let node = sceneNode(named: editorJournalBookName, as: JournalBook.self) else {
            Log.info(.scene, "JournalBook not found in GameScene.sks (yet) — skipping wiring")
            return
        }
        node.zPosition = ZLayers.furniture
        let cell = gridService.worldToGrid(node.positionInSceneCoordinates())
        gridService.reserveCell(cell)
        let go = GameObject(skNode: node, gridPosition: cell, objectType: .furniture, gridService: gridService)
        gridService.occupyCell(cell, with: go)
        journalBook = node
        Log.info(.game, "JournalBook wired at grid \(cell)")
    }
    
    // MARK: - Furniture & Tables
    
    private func convertExistingObjectsToGrid() {
        let placedObjects = editorFurnitureNames.map { requiredSceneNode(named: $0, as: RotatableObject.self) }

        for obj in placedObjects {
            let gridPos = gridService.worldToGrid(obj.positionInSceneCoordinates())
            obj.zPosition = ZLayers.groundObjects
            let go = GameObject(skNode: obj, gridPosition: gridPos, objectType: obj.objectType, gridService: gridService)
            gridService.occupyCell(gridPos, with: go)
        }

        let tables = editorTableNames.map { requiredSceneNode(named: $0, as: RotatableObject.self) }
        for table in tables {
            let gridPos = gridService.worldToGrid(table.positionInSceneCoordinates())
            table.zPosition = ZLayers.tables
            let go = GameObject(skNode: table, gridPosition: gridPos, objectType: .furniture, gridService: gridService)
            gridService.occupyCell(gridPos, with: go)
        }
        
        Log.debug(.grid, "Loaded \(placedObjects.count) placed objects and \(tables.count) tables from GameScene.sks")
    }
    
    // MARK: - Time System
    
    private func setupTimeSystem() {
       

       

       

        timeControlButton = TimeControlButton(timeService: timeService)
        if let timeControlAnchor = sceneNode(named: "time_control_anchor", as: SKNode.self) {
            timeControlButton?.position = timeControlAnchor.positionInSceneCoordinates()
        }
        if let timeControlButton {
            addChild(timeControlButton)
        }
        
        Log.info(.time, "Time system placed")
    }

    internal func isTableNode(_ node: SKNode) -> Bool {
        guard let name = node.name else { return false }
        return name.hasPrefix("table_") || name == "sacred_table"
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
        // Bring the gnome simulation in sync with the current phase too.
        // GameScene is the canonical owner of TimeService — every other
        // scene reads from it, so this is the right place to seed the
        // gnome manager's phase tracking.
        GnomeManager.shared.handleTimePhaseChange(lastTimePhase, dayCount: timeService.dayCount)
        Log.info(.time, "Phase monitoring initialized at \(lastTimePhase.displayName)")
    }
    
    // MARK: - Multiplayer Sync Counters
    private var npcSyncFrameCounter: Int = 0
    private var snailSyncFrameCounter: Int = 0
    private var timeSyncFrameCounter: Int = 0
    private var autoSaveFrameCounter: Int = 0
    
    // MARK: - Update Loop
    
    override open func updateSpecificContent(_ currentTime: TimeInterval) {
        timeService.update()
        
        // Drive the NPC ↔ NPC conversation scheduler. Cheap when no
        // conversation is active (just a throttled scan). Hosts/solo
        // schedule; guests render via remote messages.
        let convoTimeContext: TimeContext = (timeService.currentPhase == .night) ? .night : .day
        NPCConversationService.shared.tick(
            deltaTime: 1.0 / 60.0,
            in: self,
            npcs: npcs,
            timeContext: convoTimeContext
        )
        
        let currentPhase = timeService.currentPhase
        if currentPhase != lastTimePhase {
            // Guest receives phase changes from host's timePhaseChanged
            // broadcast — don't also react to local phase detection, which
            // can diverge slightly and cause double-firing.
            if !MultiplayerService.shared.isGuest {
                Log.info(.time, "Phase changed: \(lastTimePhase.displayName) → \(currentPhase.displayName)")
                lastTimePhase = currentPhase
                residentManager.handleTimePhaseChange(currentPhase)
                handleRitualTimePhaseChange(currentPhase)  // → GameScene+Ritual.swift
                
                // Drive the gnome simulation's daily cycle (dawn rollover,
                // recall at dusk/night, etc.) and persist the new state.
                GnomeManager.shared.handleTimePhaseChange(currentPhase, dayCount: timeService.dayCount)
                SaveService.shared.persistGnomeState()
                
                // Host broadcasts time phase to guest
                if MultiplayerService.shared.isHost {
                    MultiplayerService.shared.send(type: .timePhaseChanged, payload: TimePhaseChangedMessage(
                        newPhase: currentPhase.displayName, dayCount: timeService.dayCount
                    ))
                }
            } else {
                // Guest: just track the phase locally for display purposes.
                // Actual phase-change logic fires from the network handler.
                lastTimePhase = currentPhase
            }
        }
        
        
        timeControlButton?.update()
        residentManager.update(deltaTime: 1.0 / 60.0)
        
        updateShopNPCs()
        
        // Storage auto-close: if the player wanders away from an open
        // container it shuts itself. Cheap per-frame distance check.
        for container in storageContainers {
            container.checkAutoClose(playerPosition: character.position)
        }
        
        // HOST: When the player is in the shop there is no forest host
        // room/position, so let the snail world run its shop-wander path.
        // Guest receives snail state via snailSync, so skip local simulation.
        if !MultiplayerService.shared.isGuest {
            let snailWorld = SnailWorldState.shared
            if timeService.currentPhase == .night && !snailWorld.isActive {
                snailWorld.activate()
            } else if timeService.currentPhase != .night && snailWorld.isActive {
                snailWorld.deactivate()
            }
            snailWorld.tickHost(deltaTime: 1.0 / 60.0, hostRoom: nil, hostPosition: nil)
        }
        
        // HOST: Broadcast NPC + snail sync to guest periodically
        if MultiplayerService.shared.isHost && MultiplayerService.shared.isConnected {
            npcSyncFrameCounter += 1
            snailSyncFrameCounter += 1
            
            // NPC sync every ~0.5s (30 frames)
            if npcSyncFrameCounter >= 30 {
                npcSyncFrameCounter = 0
                broadcastNPCShopSync()
            }
            
            // Snail sync every ~0.25s (15 frames) for tight position accuracy
            if snailSyncFrameCounter >= 15 {
                snailSyncFrameCounter = 0
                broadcastSnailSync()
            }
            
            // Time sync every ~5s (300 frames)
            timeSyncFrameCounter += 1
            if timeSyncFrameCounter >= 300 {
                timeSyncFrameCounter = 0
                MultiplayerService.shared.send(type: .timeSync, payload: TimeSyncMessage(
                    phase: timeService.currentPhase.displayName,
                    progress: timeService.phaseProgress,
                    isFlowing: timeService.isTimeActive,
                    dayCount: timeService.dayCount
                ))
            }
        }
        
        // Periodic auto-save every ~2 minutes (7200 frames at 60fps)
        // Ensures the shared world persists even if the app is killed.
        autoSaveFrameCounter += 1
        if autoSaveFrameCounter >= 7200 {
            autoSaveFrameCounter = 0
            SaveService.shared.autoSave(timeService: timeService)
        }
    }
    
   
    
    // MARK: - Shop NPC Management
    
    private func updateShopNPCs() {
        // Guest: don't run NPC state machines — positions come from host sync.
        // Still do cleanup to remove NPCs that have left the scene.
        if !MultiplayerService.shared.isGuest {
            let dt = 1.0 / 60.0
            for npc in npcs { npc.update(deltaTime: dt) }
        }
        
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
    
    // MARK: - Host Broadcast Helpers
    
    /// Sends current shop NPC positions + states to guest.
    private func broadcastNPCShopSync() {
        let entries: [NPCShopSyncEntry] = npcs.compactMap { npc in
            guard let charId = npc.animalType.characterId else { return nil }
            return NPCShopSyncEntry(
                npcID: charId,
                animalType: npc.animalType.rawValue,
                position: CodablePoint(npc.position),
                state: npc.currentState.displayName
            )
        }
        guard !entries.isEmpty else { return }
        MultiplayerService.shared.send(type: .npcShopSync, payload: NPCShopSyncMessage(entries: entries))
    }
    
    /// Sends snail world state to guest.
    private func broadcastSnailSync() {
        let world = SnailWorldState.shared
        MultiplayerService.shared.send(type: .snailSync, payload: SnailSyncMessage(
            room: world.currentRoom,
            position: CodablePoint(world.roomPosition),
            isActive: world.isActive
        ))
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
        let slotIndex = existing.count
        drinkOnTable.position = offsets[slotIndex]
        drinkOnTable.zPosition = ZLayers.childLayer(for: ZLayers.tables)
        drinkOnTable.name = "drink_on_table"
        
        // Read ingredient layers directly off the drink in hand. This is
        // now the single source of truth for recipe state — stations don't
        // track it anymore.
        let ingredientFlags = drinkCreator.ingredientFlags(for: drink)
        
        if table.name != "sacred_table" {
            let item = WorldItemRegistry.makeDrinkOnTable(
                tablePosition: table.position,
                slotIndex: slotIndex,
                hasTea: ingredientFlags.hasTea,
                hasIce: ingredientFlags.hasIce,
                hasBoba: ingredientFlags.hasBoba,
                hasFoam: ingredientFlags.hasFoam,
                hasLid: ingredientFlags.hasLid
            )
            WorldItemRegistry.shared.add(item)
            drinkOnTable.userData = NSMutableDictionary()
            drinkOnTable.userData?["worldItemID"] = item.id
        }
        
        table.addChild(drinkOnTable)
        
        Log.info(.drink, "Placed drink on \(table.name ?? "table")")
        
        if table.name == "sacred_table" && isRitualActive {
            if ritualArea.areCandlesAllLit() {
                Log.info(.ritual, "Sacred table — triggering ritual sequence")
                triggerRitualSequence(drinkOnTable: drinkOnTable, sacredTable: table)
            } else {
                // Player placed the drink before finishing the candle round.
                // Leave the drink sitting; ritualArea.onCandlesAllLit will
                // pick it up and complete the ritual the moment the last
                // candle is lit.
                Log.info(.ritual, "Sacred table — drink placed; waiting for all candles to be lit")
            }
        }
        
        // Broadcast drink placement so the other player sees it
        if MultiplayerService.shared.isConnected {
            MultiplayerService.shared.send(type: .drinkPlacedOnTable, payload: DrinkPlacedOnTableMessage(
                tablePosition: CodablePoint(table.position),
                slotIndex: slotIndex,
                hasTea:  ingredientFlags.hasTea,
                hasIce:  ingredientFlags.hasIce,
                hasBoba: ingredientFlags.hasBoba,
                hasFoam: ingredientFlags.hasFoam,
                hasLid:  ingredientFlags.hasLid
            ))
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
        // Despawn gnome visuals so they show up cleanly in the forest scene.
        GnomeManager.shared.despawnAllVisibleGnomes()
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
    
    /// Intercept tap events when the chronicle book overlay is up so that
    /// prev/next/close buttons (and backdrop dismiss) work without the
    /// world reading those taps as movement targets.
    override open func handleSceneSpecificTouch(_ touches: Set<UITouch>, with event: UIEvent?) -> Bool {
        if let overlay = JournalBookOverlay.existing(in: self),
           let touch = touches.first {
            let location = touch.location(in: self)
            // Even if the user taps the parchment body (not a button),
            // swallow the touch so it doesn't move the character.
            _ = overlay.handleTap(at: location)
            return true
        }
        return false
    }
    
    override open func handleSceneSpecificLongPress(on node: SKNode, at location: CGPoint) {
        handleGameSceneLongPress(on: node, at: location)
    }
    
    private func handleGameSceneLongPress(on node: SKNode, at location: CGPoint) {
        Log.debug(.input, "Long press on: \(node.name ?? "unnamed") (\(type(of: node)))")
        
        // PRIORITY: carrying a drink + long-press near a table → place it.
        // This must run before the `node == character.carriedItem` branch
        // below, because when the player is right next to a table the
        // carried drink visually overlaps it and would otherwise win the
        // hit-test (causing a drop instead of a placement).
        if let carried = character.carriedItem,
           isCarriedDrink(carried),
           let table = tableNearLocation(location) {
            placeDrinkOnTable(drink: carried, table: table)
            return
        }
        
        if node == character.carriedItem {
            character.dropItem()
            
        } else if let station = node as? IngredientStation {
            handleStationInteraction(station)
            
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
            
        } else if let journal = node as? JournalBook {
            // Open the chronicle book overlay. If one is already open
            // (rare — the touch dispatcher dismisses on backdrop tap),
            // present() will replace it.
            transitionService.triggerHapticFeedback(type: .selection)
            JournalBookOverlay.present(in: self, camera: gameCamera)
            _ = journal // silence unused warning
            
        } else if let slotName = node.name, slotName.hasPrefix("storage_slot_") {
            // Long-press on an open-storage slot icon. Slot sprites are
            // plain SKSpriteNodes (not RotatableObjects), so this branch
            // must live outside the `as? RotatableObject` cast below.
            handleStorageSlotLongPress(node)
            
        } else if let trash = node as? Trash {
            // Unregister from the world registry if this trash was being tracked
            // (restored from disk, or registered by a remote placement).
            if let itemID = trash.userData?["worldItemID"] as? String {
                WorldItemRegistry.shared.remove(id: itemID)
            }
            trash.pickUp { Log.debug(.game, "Trash cleaned up") }
            transitionService.triggerHapticFeedback(type: .light)
            
            // Broadcast trash cleaned
            MultiplayerService.shared.send(type: .trashCleaned, payload: TrashCleanedMessage(
                position: CodablePoint(trash.position), location: "shop"
            ))
            // Chronicle hook
            DailyChronicleLedger.shared.recordTrashCleaned(location: "shop")
            
        } else if let rotatable = node as? RotatableObject {
            // Drink-creator pickup: tapping the empty cup on the counter
            // hands the player a fresh empty cup. They then carry it to
            // the stations to build the drink additively.
            if rotatable.name == "drink_display" && rotatable.parent == drinkCreator {
                if character.carriedItem == nil {
                    let cup = drinkCreator.spawnEmptyCup()
                    character.pickupItem(cup)
                    // Counter display stays a static empty cup — it's the
                    // "stack of cups," always visible, not recipe-aware.
                    drinkCreator.rebuildDisplayAsEmptyCup()
                    Log.info(.drink, "Picked up empty cup from creator")
                }
                return
            }
            
            // Storage container: deposit (carrying depositable) /
            // toggle-open (empty hands) / haptic (carrying non-depositable).
            if let storage = rotatable as? StorageContainer {
                handleStorageContainerLongPress(storage)
                return
            }
            
            // NOTE: storage-slot long-press is handled earlier in the
            // outer dispatch — slot sprites are plain SKSpriteNodes and
            // never reach this RotatableObject branch.
            
            // Table drink placement
            if isTableNode(rotatable), let carried = character.carriedItem {
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
    
    // MARK: - Long-Press Table Helpers
    
    /// True if the carried node is a player-built drink (empty cup or
    /// finished). Matches the convention used by `handleStationInteraction`.
    private func isCarriedDrink(_ item: SKNode) -> Bool {
        guard let name = item.name else { return false }
        return name == "picked_up_drink" || name == "completed_drink"
    }
    
    /// Walk every node hit-tested at `location` and return the first one
    /// whose ancestor chain contains a table (regular or sacred). Lets a
    /// long-press "see through" the carried drink overlapping a table.
    private func tableNearLocation(_ location: CGPoint) -> RotatableObject? {
        for hit in nodes(at: location) {
            var cursor: SKNode? = hit
            while let c = cursor {
                if let rot = c as? RotatableObject, isTableNode(rot) {
                    return rot
                }
                cursor = c.parent
            }
        }
        return nil
    }
    
    // MARK: - Storage Container Interaction (pantry / fridge)
    
    /// Route a long-press on the pantry/fridge body:
    ///   - Carrying a depositable ingredient → deposit it (priority).
    ///   - Carrying anything else → haptic only (drink in hand etc).
    ///   - Empty hands → toggle open/closed.
    private func handleStorageContainerLongPress(_ storage: StorageContainer) {
        // Deposit path. `depositableIngredient` filters out non-pantry
        // items (rocks, gems) so they don't get jammed into the pantry.
        if let carried = character.carriedItem,
           let ingredient = depositableIngredient(for: carried) {
            let containerName = storage.storageType.rawValue
            if StorageRegistry.shared.canStore(ingredient: ingredient, in: containerName) {
                _ = StorageRegistry.shared.store(ingredient: ingredient, in: containerName)
                storage.onInventoryChanged()
                character.dropItemSilently()
                transitionService.triggerHapticFeedback(type: .success)
                Log.info(.game, "Deposited \(ingredient) into \(storage.storageType.displayName)")
                
                // Broadcast deposit so the other player's registry + UI match.
                if MultiplayerService.shared.isConnected {
                    MultiplayerService.shared.send(
                        type: .storageDeposited,
                        payload: StorageDepositedMessage(
                            containerName: containerName,
                            ingredient: ingredient
                        )
                    )
                }
            } else {
                transitionService.triggerHapticFeedback(type: .light)
                Log.debug(.game, "\(storage.storageType.displayName) can't accept \(ingredient) (5 unique slots full)")
            }
            return
        }
        
        // Non-depositable in hand (e.g. a drink, a rock, a gem) → haptic only.
        if character.carriedItem != nil {
            transitionService.triggerHapticFeedback(type: .light)
            return
        }
        
        // Empty hands → toggle open/closed.
        storage.toggleOpen()
        transitionService.triggerHapticFeedback(type: .selection)
    }
    
    /// Route a long-press on an open-pantry slot sprite. Retrieves one unit
    /// of the slot's ingredient and hands it to the player. Does nothing if
    /// the player is already carrying something.
    private func handleStorageSlotLongPress(_ slotNode: SKNode) {
        guard character.carriedItem == nil else {
            // Can't retrieve with full hands — feel the tap but do nothing.
            transitionService.triggerHapticFeedback(type: .light)
            return
        }
        guard let containerName = slotNode.userData?["containerName"] as? String,
              let ingredient = slotNode.userData?["ingredient"] as? String else {
            Log.warn(.game, "Storage slot missing userData")
            return
        }
        
        // Find the matching live container so we can refresh its sprites.
        guard let storage = storageContainers.first(where: { $0.storageType.rawValue == containerName }) else {
            Log.warn(.game, "No live StorageContainer for '\(containerName)'")
            return
        }
        
        guard StorageRegistry.shared.retrieveOne(ingredient: ingredient, from: containerName) else {
            // Registry said no — usually means count already hit zero via
            // a concurrent network retrieval. Rebuild sprites so the UI matches.
            storage.onInventoryChanged()
            transitionService.triggerHapticFeedback(type: .light)
            return
        }
        
        // Build the carriable item for this ingredient.
        guard let carried = makeCarriableIngredient(named: ingredient) else {
            Log.error(.game, "No carriable factory for ingredient '\(ingredient)'")
            // Roll back the registry mutation so the player doesn't lose a unit.
            _ = StorageRegistry.shared.store(ingredient: ingredient, in: containerName)
            storage.onInventoryChanged()
            return
        }
        
        addChild(carried)
        carried.position = character.position
        character.pickupItem(carried)
        storage.onInventoryChanged()
        transitionService.triggerHapticFeedback(type: .success)
        Log.info(.game, "Retrieved \(ingredient) from \(storage.storageType.displayName)")
        
        // Broadcast to partner.
        if MultiplayerService.shared.isConnected {
            MultiplayerService.shared.send(
                type: .storageRetrieved,
                payload: StorageRetrievedMessage(
                    containerName: containerName,
                    ingredient: ingredient
                )
            )
        }
    }
    
    /// If the player's currently-carried item is a depositable ingredient,
    /// return its canonical ingredient-string. Rocks and gems are work
    /// items, not pantry food, so they're filtered out by
    /// `ForageableIngredient.isPantryDepositable`.
    private func depositableIngredient(for carried: RotatableObject) -> String? {
        guard let ingredient = ForageableIngredient.fromCarriedNodeName(carried.name),
              ingredient.isPantryDepositable else {
            return nil
        }
        return ingredient.rawValue
    }
    
    /// Factory for turning an ingredient string into a freshly-built
    /// carriable RotatableObject. Mirrors the deposit side above.
    private func makeCarriableIngredient(named ingredient: String) -> RotatableObject? {
        guard let forageable = ForageableIngredient(rawValue: ingredient) else {
            return nil
        }
        return forageable.makeCarriable()
    }
    
    // MARK: - Station Interaction (drink-in-hand model)
    
    /// Route a station tap through the drink-in-hand pipeline:
    ///   - Always play the station's visual pulse (local + broadcast so
    ///     the partner sees your activity).
    ///   - If you're carrying a drink AND the station is `.trash`, discard it.
    ///   - If you're carrying a drink AND the station is an ingredient,
    ///     apply it additively (no-op if already present or if lidded).
    ///   - If you're not carrying a drink, haptic only — no effect.
    private func handleStationInteraction(_ station: IngredientStation) {
        // Visual pulse (always)
        let pulse = animationService.stationInteractionPulse(station)
        animationService.run(pulse, on: station, withKey: AnimationKeys.stationInteraction, completion: nil)
        station.interact()
        
        // Cosmetic-only broadcast so the remote player sees our station pulse.
        // The remote handler MUST NOT mutate any drink state.
        if MultiplayerService.shared.isConnected {
            MultiplayerService.shared.send(type: .stationToggled, payload: StationToggledMessage(
                stationName: "\(station.stationType)", newState: "pulse"
            ))
        }
        
        // With no drink in hand, stations do nothing — just a light haptic.
        guard let carried = character.carriedItem else {
            transitionService.triggerHapticFeedback(type: .light)
            return
        }
        
        // Matcha leaves and furniture aren't drinks — stations don't touch them.
        let isDrinkInHand = (carried.name == "picked_up_drink" || carried.name == "completed_drink")
        guard isDrinkInHand else {
            transitionService.triggerHapticFeedback(type: .light)
            return
        }
        
        if station.stationType == .trash {
            // Discard the drink entirely.
            drinkCreator.discardCarriedDrink(carried)
            character.dropItemSilently()
            transitionService.triggerHapticFeedback(type: .success)
            Log.info(.drink, "Drink discarded via trash station")
            return
        }
        
        // Ingredient application (additive, lid locks it).
        let applied = drinkCreator.applyIngredient(to: carried, type: station.stationType)
        if applied {
            transitionService.triggerHapticFeedback(type: .light)
        } else {
            // Either already-applied, or drink is lidded/complete. Haptic
            // is still worth firing so the player feels the tap, but we
            // don't change the cup.
            transitionService.triggerHapticFeedback(type: .selection)
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
