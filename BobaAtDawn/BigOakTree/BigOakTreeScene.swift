//
//  BigOakTreeScene.swift
//  BobaAtDawn
//
//  Interior of the Big Oak Tree structure.
//  Structure mirrors ForestScene:
//    - One SKScene subclass
//    - Multiple "rooms" swapped in/out via room-setup re-runs with a
//      black-overlay fade transition.
//
//  5 rooms:
//    1. Lobby         (cozy main hall with fireplace, kitchen, couches)
//    2. Left bedroom
//    3. Middle bedroom
//    4. Right bedroom
//    5. Treasury     (gem pile reachable from the lobby)
//
//  Triggers:
//    - Three stair tiles in the lobby → bedrooms
//    - One stair tile in the lobby → treasury
//    - One down-stair tile in each bedroom → lobby
//    - One stair tile in the treasury → lobby
//    - One exit door in the lobby → back to ForestScene Room 4
//
//  All visuals are placeholders (flat SKSpriteNodes + SKLabelNode emojis)
//  with distinct `name` values so they're easy to swap for Sprite2D art
//  later — see `BigOakTreeScene+Rooms.swift`.
//

import SpriteKit

// MARK: - Oak Room Identifiers
enum OakRoom: Int, CaseIterable {
    case lobby          = 1
    case leftBedroom    = 2
    case middleBedroom  = 3
    case rightBedroom   = 4
    case treasury       = 5

    var debugName: String {
        switch self {
        case .lobby:         return "Lobby"
        case .leftBedroom:   return "Left Bedroom"
        case .middleBedroom: return "Middle Bedroom"
        case .rightBedroom:  return "Right Bedroom"
        case .treasury:      return "Treasury"
        }
    }
}

// MARK: - Big Oak Tree Scene
@objc(BigOakTreeScene)
class BigOakTreeScene: BaseGameScene {

    // MARK: - Node Names (trigger identifiers used in touch handling)
    static let stairsLeftName    = "oak_stairs_left"
    static let stairsMiddleName  = "oak_stairs_middle"
    static let stairsRightName   = "oak_stairs_right"
    static let stairsTreasuryName = "oak_stairs_treasury"
    static let stairsDownName    = "oak_stairs_down"
    static let exitDoorName      = "oak_exit_door"

    // MARK: - State
    /// Current room the player is in. Default to lobby on scene creation.
    internal var currentOakRoom: OakRoom = .lobby

    // MARK: - Tracked nodes (replaced on each room setup)
    internal var roomLabel: SKLabelNode?
    internal var placedDecor: [SKNode] = []
    /// The treasury pile node when the player is currently in the
    /// treasury room. Nil otherwise. The GnomeManager updates this via
    /// `updateTreasuryPileIfPresent` so the count sticks even when
    /// gems are deposited from elsewhere.
    internal var treasuryPile: TreasuryPile?

    // MARK: - Transition Control
    private var isTransitioning: Bool = false
    private var transitionCooldown: TimeInterval = 0
    private let transitionCooldownDuration: TimeInterval = 0.75

    // MARK: - BaseGameScene Template Methods

    override open func setupWorld() {
        super.setupWorld()
        backgroundColor = SKColor(red: 0.28, green: 0.18, blue: 0.12, alpha: 1.0)

        guard worldWidth > 0 && worldHeight > 0 else {
            Log.error(.scene, "BigOakTreeScene: invalid world dimensions: \(worldWidth) x \(worldHeight)")
            return
        }

        requiredSceneNode(named: "oak_floor", as: SKSpriteNode.self).zPosition = ZLayers.floor
        requiredSceneNode(named: "oak_wall_top", as: SKSpriteNode.self).zPosition = ZLayers.walls
        requiredSceneNode(named: "oak_wall_bottom", as: SKSpriteNode.self).zPosition = ZLayers.walls
        requiredSceneNode(named: "oak_wall_left", as: SKSpriteNode.self).zPosition = ZLayers.walls
        requiredSceneNode(named: "oak_wall_right", as: SKSpriteNode.self).zPosition = ZLayers.walls

        Log.info(.scene, "BigOakTreeScene world setup complete")
    }

    override open func setupSpecificContent() {
        // Start in whatever room `currentOakRoom` was set to before presenting.
        GnomeManager.shared.registerOakScene(self)
        setupCurrentOakRoom()
        setupOakTreeMultiplayer()  // → BigOakTreeScene+Multiplayer.swift
        Log.info(.scene, "BigOakTreeScene initialized — \(currentOakRoom.debugName)")
    }

    // MARK: - Room Setup Entry Point
    internal func setupCurrentOakRoom() {
        clearRoomContent()
        configureActiveRoom()

        // Spawn the mine cart visual if the cart is logically in this
        // oak room (only relevant during the dusk procession arrival
        // and the resting state at oak_5).
        GnomeManager.shared.spawnVisibleCartIfPresent(
            inOakRoom: currentOakRoom, scene: self
        )

        Log.debug(.scene, "Oak room \(currentOakRoom.debugName) setup complete")
    }

    internal func clearRoomContent() {
        for room in OakRoom.allCases {
            roomContainer(for: room)?.isHidden = true
        }

        roomLabel = nil
        treasuryPile = nil
        placedDecor.removeAll()

        // Despawn all visible gnomes — manager will respawn correct
        // ones in the new room via configureActiveRoom().
        GnomeManager.shared.despawnAllVisibleGnomes()
        // Cart visual too.
        GnomeManager.shared.despawnCartVisual()
    }

    // MARK: - Treasury Pile Hook (called by GnomeManager)

    /// Update the in-room treasury pile visual when a deposit (local or
    /// remote) changes the count. Safely no-ops when the player isn't
    /// looking at the treasury room.
    func updateTreasuryPileIfPresent(count: Int, didReset: Bool) {
        guard let pile = treasuryPile else { return }
        let prevCount = pile.displayedCount
        pile.setCount(count)
        if didReset {
            pile.playResetCelebration()
        } else if count > prevCount {
            pile.playDepositAnimation()
        }
    }

    /// Used by GnomeManager.respawnVisualIfRoomVisible — returns the
    /// active oak room container so the manager can drop new gnome
    /// nodes into a sensible parent if it ever needs to.
    func roomContainerForGnomes() -> SKNode? {
        roomContainer(for: currentOakRoom)
    }

    // MARK: - Touch Handling
    override open func handleSceneSpecificTouch(_ touches: Set<UITouch>, with event: UIEvent?) -> Bool {
        guard let touch = touches.first else { return false }
        let location = touch.location(in: self)
        let touchedNode = atPoint(location)

        // Stair / exit interactions (long-press to activate, matches back_door pattern)
        if let triggerNode = touchedNode.firstNamedAncestor(matching: oakTriggerNames) {
            startLongPress(for: triggerNode, at: location)
            return true
        }

        // Treasury pile long-press — deposit a carried gem if any.
        if let node = touchedNode.firstNamedAncestor(matching: [TreasuryPile.nodeName]) {
            startLongPress(for: node, at: location)
            return true
        }

        // Free movement within the oak tree interior (no grid restriction).
        if isWithinOakBounds(location) {
            triggerMovementFeedback()
            character.handleTouchMovement(to: location)
            return true
        }

        return false
    }

    override open func handleSceneSpecificLongPress(on node: SKNode, at location: CGPoint) {
        guard let name = node.name else { return }

        switch name {
        case BigOakTreeScene.stairsLeftName:
            triggerSuccessFeedback()
            transitionToOakRoom(.leftBedroom)

        case BigOakTreeScene.stairsMiddleName:
            triggerSuccessFeedback()
            transitionToOakRoom(.middleBedroom)

        case BigOakTreeScene.stairsRightName:
            triggerSuccessFeedback()
            transitionToOakRoom(.rightBedroom)

        case BigOakTreeScene.stairsTreasuryName:
            triggerSuccessFeedback()
            transitionToOakRoom(.treasury)

        case BigOakTreeScene.stairsDownName:
            triggerSuccessFeedback()
            transitionToOakRoom(.lobby)

        case BigOakTreeScene.exitDoorName:
            triggerSuccessFeedback()
            returnToForest()

        case TreasuryPile.nodeName:
            // Player is depositing a gem — only valid if carrying a gem.
            handleTreasuryDeposit()

        default:
            Log.debug(.scene, "BigOakTreeScene: unhandled long-press on \(name)")
        }
    }

    private func handleTreasuryDeposit() {
        guard let carried = character.carriedItem else {
            transitionService.triggerHapticFeedback(type: .light)
            return
        }
        guard let ingredient = ForageableIngredient.fromCarriedNodeName(carried.name),
              ingredient == .gem else {
            transitionService.triggerHapticFeedback(type: .light)
            return
        }
        // Deposit it.
        character.dropItemSilently()
        GnomeManager.shared.playerDepositedGem()
        transitionService.triggerHapticFeedback(type: .success)
        Log.info(.game, "Player deposited gem in treasury (count = \(GnomeManager.shared.treasuryGemCount))")
    }

    // MARK: - Trigger Helpers
    private var oakTriggerNames: Set<String> {
        [
            BigOakTreeScene.stairsLeftName,
            BigOakTreeScene.stairsMiddleName,
            BigOakTreeScene.stairsRightName,
            BigOakTreeScene.stairsTreasuryName,
            BigOakTreeScene.stairsDownName,
            BigOakTreeScene.exitDoorName,
        ]
    }

    // MARK: - Room Transitions
    private func transitionToOakRoom(_ target: OakRoom) {
        guard !isTransitioning else { return }
        guard target != currentOakRoom else { return }

        isTransitioning = true
        transitionCooldown = transitionCooldownDuration

        // Dismiss any active dialogue before swapping layouts.
        DialogueService.shared.dismissDialogue()

        let from = currentOakRoom
        currentOakRoom = target

        // Compute the spawn position in the destination room.
        let spawnWorld = spawnPosition(enteringRoom: target, from: from)

        transitionService.transitionInteriorRoom(
            in: self,
            character: character,
            camera: gameCamera,
            spawnPosition: spawnWorld,
            roomSetupAction: { [weak self] in
                self?.setupCurrentOakRoom()
            },
            completion: { [weak self] in
                self?.isTransitioning = false
                Log.debug(.scene, "Oak room transition complete → \(target.debugName)")
            }
        )
    }

    // MARK: - Exit to Forest
    private func returnToForest() {
        Log.info(.scene, "Exiting Big Oak Tree → Forest Room 4")
        DialogueService.shared.dismissDialogue()

        // Despawn gnomes — they'll re-render on whichever scene we land in.
        GnomeManager.shared.despawnAllVisibleGnomes()
        GnomeManager.shared.despawnCartVisual()

        // Exit back to the forest room the player entered from.
        transitionService.transitionToForestRoom(
            from: self,
            targetRoom: 4,
            completion: {
                Log.info(.scene, "Returned to Forest Room 4 from Big Oak Tree")
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
    private func isWithinOakBounds(_ location: CGPoint) -> Bool {
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
