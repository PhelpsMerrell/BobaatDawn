//
//  ForestScene.swift
//  BobaAtDawn
//
//  5-room looping forest exploration area
//

import SpriteKit
import UIKit // For haptic feedback
import Foundation // For snail system

@objc(ForestScene)
class ForestScene: BaseGameScene, SKPhysicsContactDelegate {
    
    // MARK: - Room System (Internal - accessible to extensions)
    internal var currentRoom: Int = 1 // Rooms 1-5
    internal let roomEmojis = ["", "🍄", "⛰️", "⭐", "💎", "🌳"] // Index 0 unused, rooms 1-5
    private let residentManager = NPCResidentManager.shared
    
    // MARK: - Room Elements (Internal - accessible to extensions)
    internal var roomIdentifier: SKLabelNode! // Big emoji in center
    internal var backDoor: SKLabelNode! // Return to shop (Room 1 only)
    internal var oakTreeEntrance: SKLabelNode? // Entrance to Big Oak Tree (Room 4 only)
    internal var caveEntrance: SKLabelNode? // Entrance to Cave (Room 2 only)
    
    // MARK: - Transition Control
    private var isTransitioning: Bool = false
    private var transitionCooldown: TimeInterval = 0
    private let transitionCooldownDuration: TimeInterval = 1.0 // 1 second cooldown
    private var lastTriggeredSide: String = "" // Track which side last triggered ("left" or "right")
    private var hasLeftTransitionZone: Bool = true // Must leave zone before triggering again
    
    // MARK: - Misty Visual Effects (Internal - accessible to extensions)
    internal var leftMist: SKSpriteNode!
    internal var rightMist: SKSpriteNode!
    internal var leftHintEmoji: SKLabelNode!
    internal var rightHintEmoji: SKLabelNode!
    
    // MARK: - NPC System (Internal - accessible to extensions)
    internal var roomNPCs: [ForestNPCEntity] = [] // NPCs in current room
    
    // MARK: - Snail System
    private var snail: SnailNPC?
    private var snailContactObserver: NSObjectProtocol?
    /// Grace period flag — when true, snail contact is suppressed to give
    /// the player a moment to orient after entering the forest.
    private var snailGracePeriodActive: Bool = true
    
    // Public access for extensions
    var currentSnail: SnailNPC? {
        return snail
    }
    
    // MARK: - BaseGameScene Template Method Implementation
    override open func setupWorld() {
        super.setupWorld()
        backgroundColor = SKColor(red: 0.2, green: 0.3, blue: 0.2, alpha: 1.0)
        
        guard worldWidth > 0 && worldHeight > 0 else {
            Log.error(.forest, "Invalid world dimensions: \(worldWidth) x \(worldHeight)")
            return
        }

        requiredSceneNode(named: "forest_floor", as: SKSpriteNode.self).zPosition = -10
        requiredSceneNode(named: "forest_wall_top", as: SKSpriteNode.self).zPosition = -5
        requiredSceneNode(named: "forest_wall_bottom", as: SKSpriteNode.self).zPosition = -5
        requiredSceneNode(named: "forest_wall_left", as: SKSpriteNode.self).zPosition = -5
        requiredSceneNode(named: "forest_wall_right", as: SKSpriteNode.self).zPosition = -5
        
        Log.info(.forest, "Forest world setup complete")
    }
    
    override open func setupSpecificContent() {
        // Register with resident manager
        residentManager.registerForestScene(self)
        
        // Ensure foraged spawns are generated for today
        let timeService = serviceContainer.resolve(TimeService.self)
        ForagingManager.shared.refreshIfNeeded(dayCount: timeService.dayCount)
        
        setupCurrentRoom()
        
        // Initialize the snail
        setupSnail()
        
        // Set up physics contact delegate for snail detection
        physicsWorld.contactDelegate = self
        
        setupForestMultiplayer()  // → ForestScene+Multiplayer.swift
        
        Log.info(.forest, "Forest scene initialized — Room \(currentRoom): \(roomEmojis[currentRoom])")
    }
    
    private func setupCurrentRoom() {
        // Clear existing NPCs
        clearRoomNPCs()
        
        // Clear existing foraged nodes from previous room
        clearRoomForageNodes()
        
        // Despawn any gnomes still attached from a prior room — manager
        // will respawn the right ones for the new room below.
        GnomeManager.shared.despawnAllVisibleGnomes()
        // Despawn the cart visual too — refreshForestGnomeSpawns will
        // respawn it if the cart is logically in this room now.
        GnomeManager.shared.despawnCartVisual()
        
        // Use the new grid positioning system
        setupRoomWithGrid(currentRoom)
        
        // Add misty transition effects
        setupMistyEffects()
        
        // Spawn foraged ingredients for this room
        spawnForageNodesForRoom(currentRoom)
        
        // Notify resident manager of room change
        residentManager.forestRoomChanged(to: currentRoom, scene: self)
        
        // Spawn any gnomes currently transiting through this forest room.
        refreshForestGnomeSpawns()  // → ForestScene+Gnomes.swift
        
        Log.debug(.forest, "Room \(currentRoom) setup complete")
    }
    
    // MARK: - NPC Management (Now handled by ResidentManager)
    // NPCs are now managed by NPCResidentManager for persistent world
    
    private func clearRoomNPCs() {
        // Remove existing NPCs
        for npc in roomNPCs {
            npc.removeFromParent()
        }
        roomNPCs.removeAll()
    }
    
    // MARK: - Foraged Ingredient System
    
    private func clearRoomForageNodes() {
        children.compactMap { $0 as? ForageNode }.forEach { $0.removeFromParent() }
    }
    
    private func spawnForageNodesForRoom(_ room: Int) {
        let spawns = ForagingManager.shared.spawnsFor(.forestRoom(room))
        for spawn in spawns {
            let node = ForageNode(spawn: spawn)
            addChild(node)
        }
        if !spawns.isEmpty {
            Log.debug(.forest, "Spawned \(spawns.count) foraged items in forest room \(room)")
        }
    }
    
    // MARK: - Misty Visual Effects
    private func setupMistyEffects() {
        leftMist = requiredSceneNode(named: "left_mist", as: SKSpriteNode.self)
        rightMist = requiredSceneNode(named: "right_mist", as: SKSpriteNode.self)
        leftMist.zPosition = -8
        rightMist.zPosition = -8
        leftMist.removeAllActions()
        rightMist.removeAllActions()
        startPulsingAnimation()
    }
    
    private func startPulsingAnimation() {
        // Use AnimationService for consistent pulsing effect
        let pulseConfig = AnimationConfig(
            duration: 2.0, // 2 second full cycle
            easing: .easeInOut,
            repeatCount: -1 // Repeat forever
        )
        
        let leftPulseAction = animationService.pulse(leftMist, scale: 1.2, config: pulseConfig)
        let rightPulseAction = animationService.pulse(rightMist, scale: 1.2, config: pulseConfig)
        
        animationService.run(leftPulseAction, on: leftMist, withKey: AnimationKeys.pulse, completion: nil)
        animationService.run(rightPulseAction, on: rightMist, withKey: AnimationKeys.pulse, completion: nil)
        
        print("✨ AnimationService pulsing started for forest transition areas")
    }
    
    // MARK: - BaseGameScene Template Method Implementation
    override open func handleSceneSpecificTouch(_ touches: Set<UITouch>, with event: UIEvent?) -> Bool {
        guard let touch = touches.first else { return false }
        let location = touch.location(in: self)
        let touchedNode = atPoint(location)
        
        // Check for door interaction (only in Room 1)
        if currentRoom == 1 && touchedNode.name == "back_door" {
            startLongPress(for: touchedNode, at: location)
            return true
        }
        
        // Check for Big Oak Tree entrance (only in Room 4)
        if currentRoom == 4 && touchedNode.name == "oak_tree_entrance" {
            startLongPress(for: touchedNode, at: location)
            return true
        }
        
        // Check for Cave entrance (only in Room 2)
        if currentRoom == 2 && touchedNode.name == "cave_entrance" {
            startLongPress(for: touchedNode, at: location)
            return true
        }
        
        // Check for forest house entry (house_1 … house_4 in any room).
        // Touch may land on the house label itself or on its `house_name_tag`
        // child — walk up to find the house node.
        if let houseNode = findHouseAncestor(touchedNode) {
            startLongPress(for: houseNode, at: location)
            return true
        }
        
        // Check for foraged-item interaction (matcha, strawberry, etc.)
        if touchedNode is ForageNode || touchedNode.parent is ForageNode {
            let forageNode = (touchedNode as? ForageNode) ?? (touchedNode.parent as! ForageNode)
            startLongPress(for: forageNode, at: location)
            return true
        }
        
        // Check for trash interaction
        if touchedNode is Trash || touchedNode.parent is Trash {
            let trashNode = (touchedNode as? Trash) ?? (touchedNode.parent as! Trash)
            startLongPress(for: trashNode, at: location)
            return true
        }
        
        // Forest movement - allow movement anywhere within bounds
        if isWithinForestBounds(location) {
            // Very light haptic for footsteps
            triggerMovementFeedback()
            
            // Move character directly to world position (no grid restrictions)
            character.handleTouchMovement(to: location)
            print("🌲 Character moving to \(location)")
            return true
        } else {
            print("❌ Movement blocked - outside forest bounds")
            return false
        }
    }
    
    override open func handleSceneSpecificLongPress(on node: SKNode, at location: CGPoint) {
        if node.name == "back_door" {
            // Haptic feedback for door interaction
            triggerSuccessFeedback()
            returnToShop()
        } else if node.name == "oak_tree_entrance" {
            // Haptic feedback for entering the oak tree
            triggerSuccessFeedback()
            enterBigOakTree()
        } else if node.name == "cave_entrance" {
            // Haptic feedback for entering the cave
            triggerSuccessFeedback()
            enterCave()
        } else if let houseNumber = houseNumber(from: node) {
            triggerSuccessFeedback()
            enterHouse(houseNumber: houseNumber)
        } else if let forage = node as? ForageNode {
            // Pick up a foraged ingredient — only if not already carrying something
            guard character.carriedItem == nil else {
                Log.debug(.forest, "Can't pick up \(forage.ingredient.displayName) — already carrying an item")
                return
            }
            
            let spawnID = forage.spawnID
            let ingredient = forage.ingredient
            let location = forage.location
            
            forage.pickUp {
                Log.info(.forest, "Picked up \(ingredient.displayName) (\(spawnID))")
            }
            
            // Mark as collected in the foraging registry
            ForagingManager.shared.collect(spawnID: spawnID)
            
            // Give the player the carriable form
            let carriable = ingredient.makeCarriable()
            character.pickupItem(carriable)
            
            transitionService.triggerHapticFeedback(type: .light)
            
            // Broadcast pickup to other player
            MultiplayerService.shared.send(
                type: .itemForaged,
                payload: ItemForagedMessage(
                    spawnID: spawnID,
                    locationKey: location.stringKey
                )
            )
        } else if let trash = node as? Trash {
            // Pick up trash in the forest
            print("🗑 Picking up forest trash")
            let trashPos = trash.position
            
            // Remove from the world registry so it doesn't ghost back
            // on re-entry / app restart.
            if let id = trash.userData?["worldItemID"] as? String {
                WorldItemRegistry.shared.remove(id: id)
            }
            
            trash.pickUp {
                print("🗑 ✅ Forest trash cleaned up!")
            }
            transitionService.triggerHapticFeedback(type: .light)
            
            // Broadcast trash cleaned
            MultiplayerService.shared.send(type: .trashCleaned, payload: TrashCleanedMessage(
                position: CodablePoint(trashPos), location: "forest_room_\(self.currentRoom)"
            ))
            // Chronicle hook
            DailyChronicleLedger.shared.recordTrashCleaned(
                location: "forest room \(self.currentRoom)"
            )
        }
    }
    
    // Long-press plumbing is inherited from BaseGameScene (startLongPress /
    // cancelLongPress / handleLongPress). Base's handleLongPress calls
    // handleSceneSpecificLongPress above, which handles ALL long-press
    // targets in the forest (back door, oak tree entrance, trash).
    
    // MARK: - Room Transition System (Internal - accessible to extensions)
    private func isNearLeftEdge(_ location: CGPoint) -> Bool {
        return location.x < -worldWidth/2 + 300 // Expanded transition zone (was 100)
    }
    
    private func isNearRightEdge(_ location: CGPoint) -> Bool {
        return location.x > worldWidth/2 - 300 // Expanded transition zone (was 100)
    }
    
    internal func getPreviousRoom() -> Int {
        return currentRoom == 1 ? 5 : currentRoom - 1 // Loop: Room 1 → Room 5
    }
    
    internal func getNextRoom() -> Int {
        return currentRoom == 5 ? 1 : currentRoom + 1 // Loop: Room 5 → Room 1
    }
    
    /// One-way portal destinations. Returns target room or nil if no portal.
    internal func getPortalDestination() -> Int? {
        switch currentRoom {
        case 4: return 2  // Room 4 → Room 2
        case 3: return 5  // Room 3 → Room 5
        default: return nil
        }
    }
    
    internal func transitionToRoom(_ newRoom: Int) {
        // Prevent multiple transitions
        guard !isTransitioning else { return }
        isTransitioning = true
        transitionCooldown = transitionCooldownDuration
        
        // Dismiss any active dialogue before transitioning
        DialogueService.shared.dismissDialogue()
        
        // Store previous room for character repositioning logic
        let previousRoom = currentRoom
        currentRoom = newRoom
        
        // Use transition service for room transitions
        transitionService.transitionForestRoom(
            in: self,
            from: previousRoom,
            to: newRoom,
            character: character,
            camera: gameCamera,
            gridService: gridService,
            lastTriggeredSide: lastTriggeredSide,
            roomSetupAction: { [weak self] in
                self?.setupCurrentRoom()
            },
            completion: { [weak self] in
                self?.isTransitioning = false
                self?.hasLeftTransitionZone = false
                print("🌲 Room transition complete")
            }
        )
    }

    
    private func returnToShop() {
        Log.info(.forest, "Returning to boba shop")
        
        // Dismiss any active dialogue before leaving
        DialogueService.shared.dismissDialogue()
        
        // Despawn gnomes — they'll show up wherever we land.
        GnomeManager.shared.despawnAllVisibleGnomes()
        
        // Use transition service for returning to game
        transitionService.transitionToGame(from: self) {
            print("🏠 Successfully returned to boba shop")
        }
    }
    
    private func enterBigOakTree() {
        Log.info(.forest, "Entering Big Oak Tree from Room \(currentRoom)")
        
        // Dismiss any active dialogue before leaving
        DialogueService.shared.dismissDialogue()
        
        // Despawn gnomes — they'll re-render in the oak.
        GnomeManager.shared.despawnAllVisibleGnomes()
        
        // Use transition service to enter the oak tree interior
        transitionService.transitionToBigOakTree(from: self) {
            print("🌳 Successfully entered the Big Oak Tree")
        }
    }
    
    private func enterCave() {
        Log.info(.forest, "Entering Cave from Room \(currentRoom)")
        
        // Dismiss any active dialogue before leaving
        DialogueService.shared.dismissDialogue()
        
        // Despawn gnomes — they'll re-render in the cave.
        GnomeManager.shared.despawnAllVisibleGnomes()
        
        // Use transition service to enter the cave interior
        transitionService.transitionToCave(from: self) {
            print("🕳️ Successfully entered the Cave")
        }
    }
    
    // MARK: - House Entry
    private func enterHouse(houseNumber: Int) {
        Log.info(.forest, "Entering House \(houseNumber) in Room \(currentRoom)")
        
        DialogueService.shared.dismissDialogue()
        
        transitionService.transitionToHouse(from: self, room: currentRoom, house: houseNumber) {
            print("🏡 Successfully entered house \(houseNumber)")
        }
    }
    
    /// Walk up the ancestor chain looking for a node named `house_1`…`house_4`.
    /// Returns that node (so callers can long-press it) or nil if none found.
    private func findHouseAncestor(_ node: SKNode) -> SKNode? {
        var current: SKNode? = node
        while let candidate = current {
            if houseNumber(from: candidate) != nil {
                return candidate
            }
            current = candidate.parent
        }
        return nil
    }
    
    /// Extract the house slot (1–4) from a node named `house_1`…`house_4`.
    /// Returns nil for anything else (including `house_name_tag`).
    private func houseNumber(from node: SKNode) -> Int? {
        guard let name = node.name,
              name.hasPrefix("house_"),
              name != "house_name_tag",
              let num = Int(name.dropFirst("house_".count)),
              (1...4).contains(num) else {
            return nil
        }
        return num
    }
    
    override open func updateSpecificContent(_ currentTime: TimeInterval) {
        // Update transition cooldown
        if transitionCooldown > 0 {
            transitionCooldown -= 1.0/60.0 // Approximate frame time
        }
        
        // Only check transitions if not in cooldown
        if !isTransitioning && transitionCooldown <= 0 {
            checkForRoomTransitions()
            checkPortalCollision()
        }
        
        // Update snail behavior
        updateSnailBehavior()
        
        // Drive ambient gnome ↔ gnome chatter for any gnomes transiting
        // through this forest room.
        tickForestGnomeConversation()  // → ForestScene+Gnomes.swift
        
        // HOST: Broadcast forest NPC positions to guest every ~0.5s
        if MultiplayerService.shared.isHost && MultiplayerService.shared.isConnected {
            forestNpcSyncFrameCounter += 1
            if forestNpcSyncFrameCounter >= 30 {
                forestNpcSyncFrameCounter = 0
                broadcastForestNpcSync()
            }
        }
    }
    
    // MARK: - Character Position Monitoring
    private func checkForRoomTransitions() {
        let characterPos = character.position
        
        // Check if character is in center (forest floor) to reset zone tracking
        if characterPos.x > -worldWidth/2 + 133 && characterPos.x < worldWidth/2 - 133 {
            if !hasLeftTransitionZone {
                hasLeftTransitionZone = true
                lastTriggeredSide = ""
                print("🌲 Character returned to forest center - transitions re-enabled")
            }
        }
        
        // Only allow transitions if character has left transition zones
        guard hasLeftTransitionZone else { return }
        
        // Transition zones match the entire pulsing area (133pt wide)
        // Check if character walked into left transition area (entire pulsing zone)
        if characterPos.x < -worldWidth/2 + 133 && lastTriggeredSide != "left" {
            // Haptic feedback for room transition
            transitionService.triggerHapticFeedback(type: .light)
            lastTriggeredSide = "left"
            transitionToRoom(getPreviousRoom())
        }
        // Check if character walked into right transition area (entire pulsing zone)
        else if characterPos.x > worldWidth/2 - 133 && lastTriggeredSide != "right" {
            // Haptic feedback for room transition
            transitionService.triggerHapticFeedback(type: .light)
            lastTriggeredSide = "right"
            transitionToRoom(getNextRoom())
        }
    }
    
    // MARK: - Snail System
    internal func setupSnail() {
        // Idempotent guard: remove any existing snail nodes (defensive
        // against stale visuals carried over from a previous scene
        // presentation or accidental double-init). There must be exactly
        // one SnailNPC in the scene tree at any time.
        children.compactMap { $0 as? SnailNPC }.forEach { $0.removeFromParent() }

        // Create the snail visual node with time service dependency
        let timeService = serviceContainer.resolve(TimeService.self)
        snail = SnailNPC(timeService: timeService)
        
        // Place at world state position (persists across scene loads)
        let world = SnailWorldState.shared
        
        // SAFE-SPAWN: If the snail is active and in the player's starting
        // room, check whether its persisted position is dangerously close
        // to the character's spawn point. If so, relocate it to the
        // opposite side of the room so the player doesn't get caught on
        // the first frame.
        let characterSpawn = gridService.gridToWorld(configService.characterStartPosition)
        if world.isActive && world.currentRoom == currentRoom {
            let dx = world.roomPosition.x - characterSpawn.x
            let dy = world.roomPosition.y - characterSpawn.y
            let distToSpawn = sqrt(dx * dx + dy * dy)
            let safeDistance: CGFloat = 300 // Minimum gap on scene load
            
            if distToSpawn < safeDistance {
                // Push snail to the far side of the room
                let relocatedX: CGFloat = world.roomPosition.x >= 0 ? -500 : 500
                let relocatedY = CGFloat.random(in: -300...300)
                world.roomPosition = CGPoint(x: relocatedX, y: relocatedY)
                Log.info(.forest, "Snail was too close to spawn (\(Int(distToSpawn))pt) — relocated to \(world.roomPosition)")
            }
        }
        
        snail?.position = world.roomPosition
        
        // Ensure contact starts DISABLED (SnailNPC init already does this,
        // but belt-and-suspenders for the grace period).
        snail?.setContactEnabled(false)
        
        // Add to scene (visibility is controlled by syncWithWorldState)
        if let snail = snail {
            addChild(snail)
        }
        
        // Listen for snail catch events
        snailContactObserver = NotificationCenter.default.addObserver(
            forName: .snailCaughtPlayer,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleSnailCatch()
        }
        
        // GRACE PERIOD: Keep snail contact disabled for 1.5 seconds after
        // the scene loads, regardless of night/active state. This covers
        // any edge case where the snail position happens to overlap the
        // player on the very first physics step.
        snailGracePeriodActive = true
        snail?.setContactEnabled(false)
        let graceAction = SKAction.sequence([
            SKAction.wait(forDuration: 1.5),
            SKAction.run { [weak self] in
                guard let self = self else { return }
                self.snailGracePeriodActive = false
                // Re-enable contact now if the snail is currently visible
                // and active. During grace, fadeIn() was allowed to show
                // the snail but its setContactEnabled(true) was overridden
                // every frame. Now that grace is over, restore it.
                if let snail = self.snail,
                   !snail.isHidden,
                   SnailWorldState.shared.isActive {
                    snail.setContactEnabled(true)
                }
                Log.debug(.forest, "Snail grace period ended")
            }
        ])
        run(graceAction, withKey: "snail_grace_period")
        
        Log.debug(.forest, "Snail node added (world room: \(world.currentRoom), active: \(world.isActive))")
    }
    
    private var snailSyncFrameCounter: Int = 0
    private var forestNpcSyncFrameCounter: Int = 0
    
    private func updateSnailBehavior() {
        guard let snail = snail else { return }

        // HOST drives ALL snail simulation — a single per-frame tick on
        // SnailWorldState that handles same-room hunting, different-room
        // drift, and shop-only wander. Guest never simulates.
        if !MultiplayerService.shared.isGuest {
            SnailWorldState.shared.tickHost(
                deltaTime: 1.0 / 60.0,
                hostRoom: currentRoom,
                hostPosition: character?.position ?? .zero
            )
        }

        // Both sides: visual mirrors world state.
        snail.syncWithWorldState(
            playerRoom: currentRoom,
            playerPosition: character?.position ?? .zero
        )

        // GRACE PERIOD OVERRIDE: syncWithWorldState may call fadeIn() which
        // enables contact. If the grace period is still active, force
        // contact back off so the player can't be caught during the first
        // 1.5 seconds after scene load.
        if snailGracePeriodActive {
            snail.setContactEnabled(false)
        }

        // HOST: Broadcast snail sync to guest.
        if MultiplayerService.shared.isHost && MultiplayerService.shared.isConnected {
            snailSyncFrameCounter += 1
            if snailSyncFrameCounter >= 15 {
                snailSyncFrameCounter = 0
                let world = SnailWorldState.shared
                MultiplayerService.shared.send(type: .snailSync, payload: SnailSyncMessage(
                    room: world.currentRoom,
                    position: CodablePoint(world.roomPosition),
                    isActive: world.isActive
                ))
            }
        }
    }
    
    // MARK: - Forest NPC Sync (Host Broadcast)
    
    /// Collect all ForestNPCEntity children in this scene and broadcast
    /// their positions to the guest so wandering is visually consistent.
    private func broadcastForestNpcSync() {
        let forestNPCs = children.compactMap { $0 as? ForestNPCEntity }
        guard !forestNPCs.isEmpty else { return }
        
        let entries: [ForestNpcSyncEntry] = forestNPCs.compactMap { npc in
            ForestNpcSyncEntry(
                npcID: npc.npcData.id,
                position: CodablePoint(npc.position)
            )
        }
        
        MultiplayerService.shared.send(
            type: .forestNpcSync,
            payload: ForestNpcSyncMessage(room: currentRoom, entries: entries)
        )
    }
    
    private func handleSnailCatch() {
        Log.info(.forest, "PLAYER CAUGHT BY SNAIL — teleporting to shop")
        
        // Create dramatic transition effect
        createSnailCatchTransition()
        
        // Teleport player back to shop after brief delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.teleportPlayerToShop()
        }
    }
    
    private func createSnailCatchTransition() {
        // Create ominous transition effect
        let overlay = SKSpriteNode(color: .black, size: CGSize(width: frame.width * 2, height: frame.height * 2))
        overlay.alpha = 0
        overlay.zPosition = 1000
        overlay.position = CGPoint(x: 0, y: 0)
        addChild(overlay)
        
        // Fade to black
        let fadeIn = SKAction.fadeIn(withDuration: 0.3)
        overlay.run(fadeIn)
        
        // Add eerie sound effect placeholder
        print("🔊 *Eerie snail catch sound*")
        
        // Haptic feedback for the catch
        let impactFeedback = UIImpactFeedbackGenerator(style: .heavy)
        impactFeedback.impactOccurred()
        
        // Remove overlay after teleport
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            overlay.removeFromParent()
        }
    }
    
    private func teleportPlayerToShop() {
        // Use the scene transition service to return to shop
        let transitionService = serviceContainer.resolve(SceneTransitionService.self)
        
        // Reset player to shop starting position
        transitionService.transitionToGame(from: self) {
            print("🏠 Player safely returned to shop after snail encounter")
            
            // Optional: Show a brief message about the snail encounter
            self.showSnailEscapeMessage()
        }
    }
    
    private func showSnailEscapeMessage() {
        // You could add a subtle message or effect here
        print("💭 You feel like you barely escaped something ominous...")
    }
    
    // MARK: - Physics Contact for Snail
    func didBegin(_ contact: SKPhysicsContact) {
        
        let bodyA = contact.bodyA
        let bodyB = contact.bodyB
        
        // FIXED: Ignore snail contacts while the grace period is active or
        // while the snail is hidden/inactive. This prevents the invisible
        // snail (stale persisted position overlapping the player's spawn)
        // from triggering an instant catch on scene load.
        if snailGracePeriodActive { return }
        if snail?.isHidden == true { return }
        if !SnailWorldState.shared.isActive { return }
        
        // Check if character contacted snail
        if (bodyA.categoryBitMask == PhysicsCategory.character && bodyB.categoryBitMask == PhysicsCategory.snail) ||
           (bodyA.categoryBitMask == PhysicsCategory.snail && bodyB.categoryBitMask == PhysicsCategory.character) {
            
            // Determine which is the snail
            let possibleSnail = (bodyA.node?.name == "snail_enemy") ? bodyA.node : 
                               (bodyB.node?.name == "snail_enemy") ? bodyB.node : nil
            
            if let snailNode = possibleSnail as? SnailNPC {
                // Player caught!
                snailNode.playerCaught()
            }
        }
    }
    
    // MARK: - Forest Bounds Check
    private func isWithinForestBounds(_ location: CGPoint) -> Bool {
        // Allow movement anywhere except in the boundaries (walls)
        let margin: CGFloat = 60 // Same as wall thickness
        
        let leftBound = -worldWidth/2 + margin
        let rightBound = worldWidth/2 - margin
        let topBound = worldHeight/2 - margin
        let bottomBound = -worldHeight/2 + margin
        
        return location.x > leftBound && location.x < rightBound &&
               location.y < topBound && location.y > bottomBound
    }
    
    // MARK: - Cleanup
    deinit {
        if let observer = snailContactObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }
}
