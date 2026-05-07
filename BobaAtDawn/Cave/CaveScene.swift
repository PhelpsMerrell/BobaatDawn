//
//  CaveScene.swift
//  BobaAtDawn
//
//  Interior of the Cave, entered from a forest room. Structure mirrors
//  BigOakTreeScene: one SKScene subclass, multiple "rooms" swapped via
//  room-setup re-runs with a black-overlay fade transition.
//
//  4 rooms:
//    1. Entrance  (top floor — workshop with mine machine + waste bin,
//                  exit door back to forest, stairs down)
//    2. Floor 1   (10 rocks/day, stairs up + down)
//    3. Floor 2   (10 rocks/day, stairs up + down)
//    4. Floor 3   (10 rocks/day, deepest — stairs up only)
//
//  Triggers:
//    - One down-stair tile per room (except deepest)
//    - One up-stair tile per room (except entrance)
//    - One exit door in the entrance → back to ForestScene Room 2
//    - Mine machine + waste bin in the entrance
//
//  Mushrooms (ForageNode) and rocks (ForageNode) spawn via
//  ForagingManager. Rocks live only in floors 1-3.
//

import SpriteKit

// MARK: - Cave Room Identifiers
enum CaveRoom: Int, CaseIterable {
    case entrance = 1
    case floor1   = 2
    case floor2   = 3
    case floor3   = 4

    var debugName: String {
        switch self {
        case .entrance: return "Entrance"
        case .floor1:   return "Floor 1"
        case .floor2:   return "Floor 2"
        case .floor3:   return "Floor 3"
        }
    }
}

// MARK: - Cave Scene
@objc(CaveScene)
class CaveScene: BaseGameScene {

    // MARK: - Node Names (trigger identifiers used in touch handling)
    static let stairsDownName = "cave_stairs_down"
    static let stairsUpName   = "cave_stairs_up"
    static let exitDoorName   = "cave_exit_door"

    // MARK: - State
    /// Current room the player is in. Default to entrance on scene creation.
    internal var currentCaveRoom: CaveRoom = .entrance

    // MARK: - Tracked nodes (replaced on each room setup)
    internal var roomLabel: SKLabelNode?
    /// Mine machine present only when the player is in the entrance.
    internal var mineMachine: MineMachine?
    /// Waste bin present only when the player is in the entrance.
    internal var wasteBin: WasteBin?

    // MARK: - Transition Control
    private var isTransitioning: Bool = false
    private var transitionCooldown: TimeInterval = 0
    private let transitionCooldownDuration: TimeInterval = 0.75

    // MARK: - BaseGameScene Template Methods

    override open func setupWorld() {
        super.setupWorld()
        // Dim, stony palette
        backgroundColor = SKColor(red: 0.12, green: 0.11, blue: 0.14, alpha: 1.0)

        guard worldWidth > 0 && worldHeight > 0 else {
            Log.error(.scene, "CaveScene: invalid world dimensions: \(worldWidth) x \(worldHeight)")
            return
        }

        requiredSceneNode(named: "cave_floor", as: SKSpriteNode.self).zPosition = ZLayers.floor
        requiredSceneNode(named: "cave_wall_top", as: SKSpriteNode.self).zPosition = ZLayers.walls
        requiredSceneNode(named: "cave_wall_bottom", as: SKSpriteNode.self).zPosition = ZLayers.walls
        requiredSceneNode(named: "cave_wall_left", as: SKSpriteNode.self).zPosition = ZLayers.walls
        requiredSceneNode(named: "cave_wall_right", as: SKSpriteNode.self).zPosition = ZLayers.walls

        Log.info(.scene, "CaveScene world setup complete")
    }

    override open func setupSpecificContent() {
        // Refresh foraged spawns for today if we've ticked over to a new day.
        let timeService = serviceContainer.resolve(TimeService.self)
        ForagingManager.shared.refreshIfNeeded(dayCount: timeService.dayCount)

        GnomeManager.shared.registerCaveScene(self)
        setupCurrentCaveRoom()
        setupCaveMultiplayer()  // → CaveScene+Multiplayer.swift
        Log.info(.scene, "CaveScene initialized — \(currentCaveRoom.debugName)")
    }

    // MARK: - Room Setup Entry Point
    internal func setupCurrentCaveRoom() {
        clearRoomContent()
        configureActiveRoom()      // → CaveScene+Rooms.swift

        // Clear previous room's foraged nodes, then spawn current room's.
        clearRoomForageNodes()
        spawnForageNodesForRoom(currentCaveRoom.rawValue)

        // Install machine + waste bin in the entrance only.
        if currentCaveRoom == .entrance {
            installMineMachineAndBin()
        } else {
            mineMachine = nil
            wasteBin = nil
        }

        // Spawn gnome visuals for whoever's currently logically in this floor.
        GnomeManager.shared.spawnVisibleGnomes(inCaveRoom: currentCaveRoom, scene: self)

        // Spawn the mine cart visual if the cart is logically in this
        // cave floor (typically only the entrance during the day, but
        // could be any room mid-procession).
        GnomeManager.shared.spawnVisibleCartIfPresent(
            inCaveRoom: currentCaveRoom, scene: self
        )

        Log.debug(.scene, "Cave room \(currentCaveRoom.debugName) setup complete")
    }

    internal func clearRoomContent() {
        for room in CaveRoom.allCases {
            roomContainer(for: room)?.isHidden = true
        }
        roomLabel = nil
        mineMachine = nil
        wasteBin = nil

        // Despawn gnome visuals from old room — manager will respawn for new room.
        GnomeManager.shared.despawnAllVisibleGnomes()
        // Same for the cart visual.
        GnomeManager.shared.despawnCartVisual()
    }

    // MARK: - Mine Machine + Waste Bin

    /// Resolve (or create) the mine machine and waste bin nodes inside
    /// the active entrance container. SKS-side authors place an empty
    /// SKNode at `mine_machine_anchor` and `waste_bin_anchor`; we look
    /// up the anchor and either reuse a child of the right type, or
    /// drop new instances at the anchor.
    private func installMineMachineAndBin() {
        guard let container = roomContainer(for: .entrance) else { return }

        // Machine
        if let existing = container.namedChild(MineMachine.nodeName, as: MineMachine.self) {
            mineMachine = existing
        } else {
            let anchor = container.sceneNode(named: "mine_machine_anchor", as: SKNode.self)
            let pos = anchor?.positionInSceneCoordinates() ?? CGPoint(x: -120, y: 0)
            let machine = MineMachine()
            machine.position = pos
            container.addChild(machine)
            mineMachine = machine
        }

        // Waste bin
        if let existing = container.namedChild(WasteBin.nodeName, as: WasteBin.self) {
            wasteBin = existing
        } else {
            let anchor = container.sceneNode(named: "waste_bin_anchor", as: SKNode.self)
            let pos = anchor?.positionInSceneCoordinates() ?? CGPoint(x: 120, y: 0)
            let bin = WasteBin()
            bin.position = pos
            container.addChild(bin)
            wasteBin = bin
        }
    }

    /// Hooks called by GnomeManager to flash the machine / bump the bin
    /// when a gnome interacts with them. Safe no-op if not present.
    func flashMineMachineIfPresent(green: Bool) {
        if green {
            mineMachine?.flashGreen()
        } else {
            mineMachine?.flashRed()
        }
    }
    func bumpWasteBinIfPresent() {
        wasteBin?.acceptRock()
    }

    // MARK: - Foraged Ingredient Management

    private func clearRoomForageNodes() {
        children.compactMap { $0 as? ForageNode }.forEach { $0.removeFromParent() }
    }

    private func spawnForageNodesForRoom(_ room: Int) {
        let spawns = ForagingManager.shared.spawnsFor(.caveRoom(room))
        for spawn in spawns {
            let node = ForageNode(spawn: spawn)
            addChild(node)
        }
        if !spawns.isEmpty {
            Log.debug(.scene, "Spawned \(spawns.count) foraged items in cave room \(room)")
        }
    }

    // MARK: - Touch Handling
    override open func handleSceneSpecificTouch(_ touches: Set<UITouch>, with event: UIEvent?) -> Bool {
        guard let touch = touches.first else { return false }
        let location = touch.location(in: self)
        let touchedNode = atPoint(location)

        // Stair / exit interactions (long-press to activate, matches oak pattern)
        if let triggerNode = touchedNode.firstNamedAncestor(matching: caveTriggerNames) {
            startLongPress(for: triggerNode, at: location)
            return true
        }

        // Mine machine / waste bin long-press
        if let node = touchedNode.firstNamedAncestor(matching: [MineMachine.nodeName, WasteBin.nodeName]) {
            startLongPress(for: node, at: location)
            return true
        }

        // Check for foraged-item interaction (mushrooms, rocks, future items)
        if touchedNode is ForageNode || touchedNode.parent is ForageNode {
            let forageNode = (touchedNode as? ForageNode) ?? (touchedNode.parent as! ForageNode)
            startLongPress(for: forageNode, at: location)
            return true
        }

        // Free movement within the cave interior (no grid restriction).
        if isWithinCaveBounds(location) {
            triggerMovementFeedback()
            character.handleTouchMovement(to: location)
            return true
        }

        return false
    }

    override open func handleSceneSpecificLongPress(on node: SKNode, at location: CGPoint) {
        // Mine machine — feed a carried rock, or get haptic-only otherwise.
        if node.name == MineMachine.nodeName {
            handleMineMachineLongPress()
            return
        }
        // Waste bin — drop a carried rock as junk.
        if node.name == WasteBin.nodeName {
            handleWasteBinLongPress()
            return
        }

        // Foraged item pickup (rocks, mushrooms, etc.)
        if let forage = node as? ForageNode {
            guard character.carriedItem == nil else {
                Log.debug(.scene, "Can't pick up \(forage.ingredient.displayName) — already carrying an item")
                return
            }

            let spawnID = forage.spawnID
            let ingredient = forage.ingredient
            let locationKey = forage.location.stringKey

            forage.pickUp {
                Log.info(.scene, "Picked up \(ingredient.displayName) (\(spawnID))")
            }

            ForagingManager.shared.collect(spawnID: spawnID)

            let carriable = ingredient.makeCarriable()
            // Tag rocks with their spawnID so the machine knows what
            // verdict to apply when fed.
            if ingredient == .rock {
                carriable.userData = NSMutableDictionary()
                carriable.userData?["rockSpawnID"] = spawnID
            }
            character.pickupItem(carriable)

            transitionService.triggerHapticFeedback(type: .light)

            MultiplayerService.shared.send(
                type: .itemForaged,
                payload: ItemForagedMessage(
                    spawnID: spawnID,
                    locationKey: locationKey
                )
            )
            return
        }

        // Stair / exit triggers
        guard let name = node.name else { return }

        switch name {
        case CaveScene.stairsDownName:
            triggerSuccessFeedback()
            if let next = CaveRoom(rawValue: currentCaveRoom.rawValue + 1) {
                transitionToCaveRoom(next)
            } else {
                Log.debug(.scene, "No deeper cave room — already at deepest floor")
            }

        case CaveScene.stairsUpName:
            triggerSuccessFeedback()
            if let prev = CaveRoom(rawValue: currentCaveRoom.rawValue - 1) {
                transitionToCaveRoom(prev)
            } else {
                Log.debug(.scene, "No room above — already at entrance")
            }

        case CaveScene.exitDoorName:
            triggerSuccessFeedback()
            returnToForest()

        default:
            Log.debug(.scene, "CaveScene: unhandled long-press on \(name)")
        }
    }

    // MARK: - Player → Mine Machine

    /// Player is feeding the machine. Only valid if carrying a rock.
    private func handleMineMachineLongPress() {
        guard let carried = character.carriedItem else {
            transitionService.triggerHapticFeedback(type: .light)
            return
        }
        guard let ingredient = ForageableIngredient.fromCarriedNodeName(carried.name),
              ingredient == .rock else {
            transitionService.triggerHapticFeedback(type: .light)
            return
        }
        guard let rockID = carried.userData?["rockSpawnID"] as? String else {
            // Rock with no associated spawn ID — rare, but bail safely.
            transitionService.triggerHapticFeedback(type: .light)
            return
        }
        // Drop the rock from hand visually
        character.dropItemSilently()
        // Compute verdict + flash machine; broadcast happens in the manager.
        let isGreen = GnomeManager.shared.playerFedRockToMachine(rockID: rockID)
        if isGreen {
            // Hand the player a gem
            let gem = ForageableIngredient.gem.makeCarriable()
            addChild(gem)
            gem.position = mineMachine?.position ?? character.position
            character.pickupItem(gem)
            transitionService.triggerHapticFeedback(type: .success)
            Log.info(.game, "Player got a GEM from rock \(rockID)")
        } else {
            // Red — auto-bumps the bin in the manager hook
            transitionService.triggerHapticFeedback(type: .light)
            Log.info(.game, "Player rock rejected (red) — \(rockID)")
        }
    }

    /// Player wants to dump a carried rock straight to the bin.
    private func handleWasteBinLongPress() {
        guard let carried = character.carriedItem else {
            transitionService.triggerHapticFeedback(type: .light)
            return
        }
        guard let ingredient = ForageableIngredient.fromCarriedNodeName(carried.name),
              ingredient == .rock else {
            transitionService.triggerHapticFeedback(type: .light)
            return
        }
        character.dropItemSilently()
        wasteBin?.acceptRock()
        transitionService.triggerHapticFeedback(type: .success)
    }

    // MARK: - Trigger Helpers
    private var caveTriggerNames: Set<String> {
        [
            CaveScene.stairsDownName,
            CaveScene.stairsUpName,
            CaveScene.exitDoorName,
        ]
    }

    // MARK: - Room Transitions
    private func transitionToCaveRoom(_ target: CaveRoom) {
        guard !isTransitioning else { return }
        guard target != currentCaveRoom else { return }

        isTransitioning = true
        transitionCooldown = transitionCooldownDuration

        DialogueService.shared.dismissDialogue()

        let from = currentCaveRoom
        currentCaveRoom = target

        let spawnWorld = spawnPosition(enteringRoom: target, from: from)  // → +Rooms

        transitionService.transitionInteriorRoom(
            in: self,
            character: character,
            camera: gameCamera,
            spawnPosition: spawnWorld,
            roomSetupAction: { [weak self] in
                self?.setupCurrentCaveRoom()
            },
            completion: { [weak self] in
                self?.isTransitioning = false
                Log.debug(.scene, "Cave room transition complete → \(target.debugName)")
            }
        )
    }

    // MARK: - Exit to Forest
    private func returnToForest() {
        Log.info(.scene, "Exiting Cave → Forest Room 2")
        DialogueService.shared.dismissDialogue()

        // Despawn gnome visuals — they'll come back in the forest.
        GnomeManager.shared.despawnAllVisibleGnomes()

        // Exit back to the forest room the cave entrance is in.
        transitionService.transitionToForestRoom(
            from: self,
            targetRoom: 2,
            completion: {
                Log.info(.scene, "Returned to Forest Room 2 from Cave")
            }
        )
    }

    // MARK: - Update Loop
    override open func updateSpecificContent(_ currentTime: TimeInterval) {
        if transitionCooldown > 0 {
            transitionCooldown -= 1.0 / 60.0
        }

        // Drive ambient gnome ↔ gnome chatter.
        let agents = GnomeManager.shared.agents.filter { $0.sceneNode != nil }
        GnomeConversationService.shared.tick(in: self, agents: agents)
    }

    // MARK: - Bounds
    private func isWithinCaveBounds(_ location: CGPoint) -> Bool {
        let margin: CGFloat = 60 // wall thickness
        let leftBound   = -worldWidth/2 + margin
        let rightBound  =  worldWidth/2 - margin
        let topBound    =  worldHeight/2 - margin
        let bottomBound = -worldHeight/2 + margin

        return location.x > leftBound &&
               location.x < rightBound &&
               location.y > bottomBound &&
               location.y < topBound
    }
}
