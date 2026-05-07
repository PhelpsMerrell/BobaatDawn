//
//  HouseScene.swift
//  BobaAtDawn
//
//  Interior of a forest NPC's house. Single SKScene subclass backed by one
//  generic HouseScene.sks layout, parameterized per-visit with
//  (currentForestRoom, currentHouseNumber).
//
//  Triggers:
//    - One exit door (`house_exit_door`) → back to ForestScene at
//      currentForestRoom via a long-press.
//
//  For now every house shares the same empty-room layout. The resident
//  NPC is shown inside only if they're currently `.atHome` and not
//  liberated — otherwise the house is empty (they're in the shop or
//  traveling).
//
//  Multiplayer model:
//    - Each house instance is its own scene (one per player).
//    - PlayerPositionMessage.sceneType = "house_{room}_{house}".
//    - If both players are in the same house they see each other;
//      otherwise the remote character is hidden.
//

import SpriteKit

@objc(HouseScene)
class HouseScene: BaseGameScene {

    // MARK: - Node Names
    static let exitDoorName = "house_exit_door"

    // MARK: - Scene State
    // Set by SceneTransitionService BEFORE presenting, so didMove(to:) /
    // setupSpecificContent have the correct context from the first frame.

    /// Forest room the house belongs to (1-5).
    internal var currentForestRoom: Int = 1

    /// House slot (1-4) within the forest room.
    internal var currentHouseNumber: Int = 1

    // MARK: - Tracked Nodes
    internal var roomLabel: SKLabelNode?
    internal var placedResident: SKNode?

    // MARK: - Transition Control
    private var isTransitioning: Bool = false
    private var transitionCooldown: TimeInterval = 0
    private let transitionCooldownDuration: TimeInterval = 0.75

    // MARK: - BaseGameScene Template Methods

    override open func setupWorld() {
        super.setupWorld()
        backgroundColor = SKColor(red: 0.18, green: 0.13, blue: 0.10, alpha: 1.0)

        guard worldWidth > 0 && worldHeight > 0 else {
            Log.error(.scene, "HouseScene: invalid world dimensions: \(worldWidth) x \(worldHeight)")
            return
        }

        requiredSceneNode(named: "house_floor", as: SKSpriteNode.self).zPosition = ZLayers.floor
        requiredSceneNode(named: "house_wall_top", as: SKSpriteNode.self).zPosition = ZLayers.walls
        requiredSceneNode(named: "house_wall_bottom", as: SKSpriteNode.self).zPosition = ZLayers.walls
        requiredSceneNode(named: "house_wall_left", as: SKSpriteNode.self).zPosition = ZLayers.walls
        requiredSceneNode(named: "house_wall_right", as: SKSpriteNode.self).zPosition = ZLayers.walls

        Log.info(.scene, "HouseScene world setup complete (room \(currentForestRoom), house \(currentHouseNumber))")
    }

    override open func setupSpecificContent() {
        configureRoomLabel()
        configureResident()
        setupHouseMultiplayer()  // → HouseScene+Multiplayer.swift
        Log.info(.scene, "HouseScene initialized — Room \(currentForestRoom) / House \(currentHouseNumber)")
    }

    // MARK: - Label + Occupant
    private func configureRoomLabel() {
        roomLabel = sceneNode(named: "house_room_label", as: SKLabelNode.self)

        if let resident = currentOccupant() {
            roomLabel?.text = "\(resident.npcData.name)'s House"
        } else {
            roomLabel?.text = "Empty House — Room \(currentForestRoom), #\(currentHouseNumber)"
        }
    }

    private func configureResident() {
        placedResident?.removeFromParent()
        placedResident = nil

        // Only show the resident if they're actually at home (not in the
        // shop / traveling) and not already liberated.
        guard let resident = currentOccupant(),
              case .atHome = resident.status,
              !SaveService.shared.isNPCLiberated(resident.npcData.id) else {
            return
        }

        // Placeholder visual — emoji label in the animal's raw form.
        let animalType = resident.npcData.animalType ?? .fox
        let placeholder = SKLabelNode(text: animalType.rawValue)
        placeholder.fontSize = 48
        placeholder.fontName = "Arial"
        placeholder.horizontalAlignmentMode = .center
        placeholder.verticalAlignmentMode = .center
        placeholder.zPosition = ZLayers.npcs
        placeholder.name = "house_resident_placeholder"

        let anchorPos = positionOfAnchor(named: "house_resident_anchor", fallback: .zero)
        placeholder.position = anchorPos

        addChild(placeholder)
        placedResident = placeholder
    }

    private func currentOccupant() -> NPCResident? {
        NPCResidentManager.shared.getAllResidents().first {
            $0.npcData.homeRoom == currentForestRoom && $0.homeHouse == currentHouseNumber
        }
    }

    private func positionOfAnchor(named anchorName: String, fallback: CGPoint) -> CGPoint {
        guard let anchor = sceneNode(named: anchorName, as: SKNode.self) else {
            return fallback
        }
        return anchor.positionInSceneCoordinates()
    }

    // MARK: - Touch Handling
    override open func handleSceneSpecificTouch(_ touches: Set<UITouch>, with event: UIEvent?) -> Bool {
        guard let touch = touches.first else { return false }
        let location = touch.location(in: self)
        let touchedNode = atPoint(location)

        // Exit door (long-press to leave)
        if let triggerNode = touchedNode.firstNamedAncestor(matching: [HouseScene.exitDoorName]) {
            startLongPress(for: triggerNode, at: location)
            return true
        }

        // Free movement inside the house (no grid restriction).
        if isWithinHouseBounds(location) {
            triggerMovementFeedback()
            character.handleTouchMovement(to: location)
            return true
        }

        return false
    }

    override open func handleSceneSpecificLongPress(on node: SKNode, at location: CGPoint) {
        guard let name = node.name else { return }

        switch name {
        case HouseScene.exitDoorName:
            triggerSuccessFeedback()
            returnToForest()
        default:
            Log.debug(.scene, "HouseScene: unhandled long-press on \(name)")
        }
    }

    // MARK: - Exit to Forest
    private func returnToForest() {
        guard !isTransitioning else { return }
        isTransitioning = true
        transitionCooldown = transitionCooldownDuration

        Log.info(.scene, "Exiting House \(currentHouseNumber) → Forest Room \(currentForestRoom)")
        DialogueService.shared.dismissDialogue()

        transitionService.transitionToForestRoom(
            from: self,
            targetRoom: currentForestRoom,
            completion: { [weak self] in
                self?.isTransitioning = false
                Log.info(.scene, "Returned to Forest Room \(self?.currentForestRoom ?? 0) from house")
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
    private func isWithinHouseBounds(_ location: CGPoint) -> Bool {
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
