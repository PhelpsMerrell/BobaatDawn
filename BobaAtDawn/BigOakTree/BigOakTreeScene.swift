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
//  4 rooms:
//    1. Lobby         (cozy main hall with fireplace, kitchen, couches)
//    2. Left bedroom
//    3. Middle bedroom
//    4. Right bedroom
//
//  Triggers:
//    - Three stair tiles in the lobby → bedrooms
//    - One down-stair tile in each bedroom → lobby
//    - One exit door in the lobby → back to ForestScene Room 4
//
//  All visuals are placeholders (flat SKSpriteNodes + SKLabelNode emojis)
//  with distinct `name` values so they're easy to swap for Sprite2D art
//  later — see `BigOakTreeScene+Rooms.swift`.
//

import SpriteKit

// MARK: - Oak Room Identifiers
enum OakRoom: Int {
    case lobby          = 1
    case leftBedroom    = 2
    case middleBedroom  = 3
    case rightBedroom   = 4

    var debugName: String {
        switch self {
        case .lobby:         return "Lobby"
        case .leftBedroom:   return "Left Bedroom"
        case .middleBedroom: return "Middle Bedroom"
        case .rightBedroom:  return "Right Bedroom"
        }
    }
}

// MARK: - Big Oak Tree Scene
class BigOakTreeScene: BaseGameScene {

    // MARK: - Node Names (trigger identifiers used in touch handling)
    static let stairsLeftName    = "oak_stairs_left"
    static let stairsMiddleName  = "oak_stairs_middle"
    static let stairsRightName   = "oak_stairs_right"
    static let stairsDownName    = "oak_stairs_down"
    static let exitDoorName      = "oak_exit_door"

    // MARK: - State
    /// Current room the player is in. Default to lobby on scene creation.
    internal var currentOakRoom: OakRoom = .lobby

    // MARK: - Tracked nodes (replaced on each room setup)
    internal var roomLabel: SKLabelNode?
    internal var placedDecor: [SKNode] = []
    internal var placedGnomes: [GnomeNPC] = []

    // MARK: - Transition Control
    private var isTransitioning: Bool = false
    private var transitionCooldown: TimeInterval = 0
    private let transitionCooldownDuration: TimeInterval = 0.75

    // MARK: - BaseGameScene Template Methods

    override open func setupWorld() {
        // Warm wood-brown interior — distinct from forest's green.
        backgroundColor = SKColor(red: 0.28, green: 0.18, blue: 0.12, alpha: 1.0)

        super.setupWorld()

        guard worldWidth > 0 && worldHeight > 0 else {
            Log.error(.scene, "BigOakTreeScene: invalid world dimensions: \(worldWidth) x \(worldHeight)")
            return
        }

        let floorSize = CGSize(width: worldWidth, height: worldHeight)
        guard floorSize.width > 0 && floorSize.height > 0 else {
            Log.error(.scene, "BigOakTreeScene: invalid floor size: \(floorSize)")
            return
        }

        // Floor (lighter wood tone than background walls)
        let floor = SKSpriteNode(
            color: SKColor(red: 0.45, green: 0.30, blue: 0.20, alpha: 1.0),
            size: floorSize
        )
        floor.position = .zero
        floor.zPosition = ZLayers.floor
        floor.name = "oak_floor"
        addChild(floor)

        // Walls (dark wood borders on all 4 sides)
        setupOakBounds()

        Log.info(.scene, "BigOakTreeScene world setup complete")
    }

    private func setupOakBounds() {
        let wallColor = SKColor(red: 0.15, green: 0.09, blue: 0.06, alpha: 1.0)
        let wallThickness: CGFloat = 60

        // Top
        let wallTop = SKSpriteNode(color: wallColor, size: CGSize(width: worldWidth, height: wallThickness))
        wallTop.position = CGPoint(x: 0, y: worldHeight/2 - wallThickness/2)
        wallTop.zPosition = ZLayers.walls
        wallTop.name = "oak_wall_top"
        addChild(wallTop)

        // Bottom
        let wallBottom = SKSpriteNode(color: wallColor, size: CGSize(width: worldWidth, height: wallThickness))
        wallBottom.position = CGPoint(x: 0, y: -worldHeight/2 + wallThickness/2)
        wallBottom.zPosition = ZLayers.walls
        wallBottom.name = "oak_wall_bottom"
        addChild(wallBottom)

        // Left
        let wallLeft = SKSpriteNode(color: wallColor, size: CGSize(width: wallThickness, height: worldHeight))
        wallLeft.position = CGPoint(x: -worldWidth/2 + wallThickness/2, y: 0)
        wallLeft.zPosition = ZLayers.walls
        wallLeft.name = "oak_wall_left"
        addChild(wallLeft)

        // Right
        let wallRight = SKSpriteNode(color: wallColor, size: CGSize(width: wallThickness, height: worldHeight))
        wallRight.position = CGPoint(x: worldWidth/2 - wallThickness/2, y: 0)
        wallRight.zPosition = ZLayers.walls
        wallRight.name = "oak_wall_right"
        addChild(wallRight)
    }

    override open func setupSpecificContent() {
        // Start in whatever room `currentOakRoom` was set to before presenting.
        setupCurrentOakRoom()
        setupOakTreeMultiplayer()  // → BigOakTreeScene+Multiplayer.swift
        Log.info(.scene, "BigOakTreeScene initialized — \(currentOakRoom.debugName)")
    }

    // MARK: - Room Setup Entry Point
    internal func setupCurrentOakRoom() {
        // Clear placed content from previous room
        clearRoomContent()

        // Build the layout for the current room (lives in +Rooms extension)
        switch currentOakRoom {
        case .lobby:          setupLobby()
        case .leftBedroom:    setupLeftBedroom()
        case .middleBedroom:  setupMiddleBedroom()
        case .rightBedroom:   setupRightBedroom()
        }

        Log.debug(.scene, "Oak room \(currentOakRoom.debugName) setup complete")
    }

    internal func clearRoomContent() {
        roomLabel?.removeFromParent()
        roomLabel = nil

        for node in placedDecor { node.removeFromParent() }
        placedDecor.removeAll()

        for gnome in placedGnomes { gnome.removeFromParent() }
        placedGnomes.removeAll()
    }

    // MARK: - Touch Handling
    override open func handleSceneSpecificTouch(_ touches: Set<UITouch>, with event: UIEvent?) -> Bool {
        guard let touch = touches.first else { return false }
        let location = touch.location(in: self)
        let touchedNode = atPoint(location)

        // Stair / exit interactions (long-press to activate, matches back_door pattern)
        if let name = touchedNode.name, isOakTrigger(name: name) {
            startLongPress(for: touchedNode, at: location)
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

        case BigOakTreeScene.stairsDownName:
            triggerSuccessFeedback()
            transitionToOakRoom(.lobby)

        case BigOakTreeScene.exitDoorName:
            triggerSuccessFeedback()
            returnToForest()

        default:
            Log.debug(.scene, "BigOakTreeScene: unhandled long-press on \(name)")
        }
    }

    // MARK: - Trigger Helpers
    private func isOakTrigger(name: String) -> Bool {
        return name == BigOakTreeScene.stairsLeftName ||
               name == BigOakTreeScene.stairsMiddleName ||
               name == BigOakTreeScene.stairsRightName ||
               name == BigOakTreeScene.stairsDownName ||
               name == BigOakTreeScene.exitDoorName
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

    /// Where the character should spawn when entering `target` coming from `from`.
    /// Spawn positions are defined in world coordinates relative to the scene origin.
    private func spawnPosition(enteringRoom target: OakRoom, from: OakRoom) -> CGPoint {
        switch target {
        case .lobby:
            // Came down from a bedroom — spawn near the stair that matches the
            // bedroom we came from so the player "lands" in the right spot.
            switch from {
            case .leftBedroom:    return OakLayout.lobbyStairLeftSpawn
            case .middleBedroom:  return OakLayout.lobbyStairMiddleSpawn
            case .rightBedroom:   return OakLayout.lobbyStairRightSpawn
            default:              return OakLayout.lobbyDefaultSpawn
            }
        case .leftBedroom:    return OakLayout.bedroomDownStairSpawn
        case .middleBedroom:  return OakLayout.bedroomDownStairSpawn
        case .rightBedroom:   return OakLayout.bedroomDownStairSpawn
        }
    }

    // MARK: - Exit to Forest
    private func returnToForest() {
        Log.info(.scene, "Exiting Big Oak Tree → Forest Room 4")
        DialogueService.shared.dismissDialogue()

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
