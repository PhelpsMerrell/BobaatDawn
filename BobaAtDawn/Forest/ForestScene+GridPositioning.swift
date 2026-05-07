//
//  ForestScene+GridPositioning.swift
//  BobaAtDawn
//
//  Editor-first forest room layout. Static room contents now live in
//  ForestScene.sks and code only toggles the active room plus dynamic labels.
//

import SpriteKit

private enum ForestLayout {
    static let roomNumbers = [1, 2, 3, 4, 5]
}

// MARK: - ForestScene Editor Layout Extension
extension ForestScene {

    func setupRoomWithGrid(_ roomNumber: Int) {
        for room in ForestLayout.roomNumbers {
            roomContainer(for: room)?.isHidden = room != roomNumber
        }

        guard let activeRoom = roomContainer(for: roomNumber) else {
            Log.error(.forest, "Missing forest_room_\(roomNumber) container in ForestScene.sks")
            return
        }

        roomIdentifier = activeRoom.namedChild("room_identifier", as: SKLabelNode.self)
        backDoor = activeRoom.namedChild("back_door", as: SKLabelNode.self)
        oakTreeEntrance = activeRoom.namedChild("oak_tree_entrance", as: SKLabelNode.self)
        caveEntrance = activeRoom.namedChild("cave_entrance", as: SKLabelNode.self)
        leftHintEmoji = activeRoom.namedChild("left_hint", as: SKLabelNode.self)
        rightHintEmoji = activeRoom.namedChild("right_hint", as: SKLabelNode.self)

        leftHintEmoji?.text = roomEmojis[getPreviousRoom()]
        rightHintEmoji?.text = roomEmojis[getNextRoom()]

        configurePortal(in: activeRoom)
        configureHouseMarkers(in: activeRoom, roomNumber: roomNumber)

        Log.info(.forest, "Room \(roomNumber) loaded from ForestScene.sks")
    }

    func checkPortalCollision() {
        guard let activeRoom = activeRoomContainer(),
              let portal = activeRoom.namedChild("portal", as: SKNode.self),
              portal.isHidden == false,
              let destination = getPortalDestination() else { return }

        let portalPosition = portal.positionInSceneCoordinates()
        let distance = hypot(character.position.x - portalPosition.x, character.position.y - portalPosition.y)

        if distance < 40 {
            print("🌀 Portal activated! Warping to room \(destination)")
            transitionService.triggerHapticFeedback(type: .success)
            transitionToRoom(destination)
        }
    }

    private func roomContainer(for roomNumber: Int) -> SKNode? {
        sceneNode(named: "forest_room_\(roomNumber)", as: SKNode.self)
    }

    private func activeRoomContainer() -> SKNode? {
        roomContainer(for: currentRoom)
    }

    private func configurePortal(in room: SKNode) {
        guard let portal = room.namedChild("portal", as: SKNode.self) else { return }
        guard let destination = getPortalDestination() else {
            portal.isHidden = true
            portal.removeAllActions()
            return
        }

        portal.isHidden = false

        if portal.action(forKey: "portal_spin") == nil {
            let spin = SKAction.repeatForever(
                SKAction.rotate(byAngle: .pi * 2, duration: 4.0)
            )
            portal.run(spin, withKey: "portal_spin")
        }

        if portal.action(forKey: "portal_pulse") == nil {
            let pulse = SKAction.repeatForever(
                SKAction.sequence([
                    SKAction.scale(to: 1.15, duration: 1.5),
                    SKAction.scale(to: 0.9, duration: 1.5)
                ])
            )
            portal.run(pulse, withKey: "portal_pulse")
        }

        if let hintLabel = portal.namedChild("portal_hint", as: SKLabelNode.self) {
            hintLabel.text = "→\(roomEmojis[destination])"
        }
    }

    private func configureHouseMarkers(in room: SKNode, roomNumber: Int) {
        let residentManager = NPCResidentManager.shared

        for houseNumber in 1...4 {
            guard let house = room.namedChild("house_\(houseNumber)", as: SKLabelNode.self) else { continue }

            house.children
                .filter { $0.name == "house_name_tag" }
                .forEach { $0.removeFromParent() }

            let occupant = residentManager.getAllResidents().first {
                $0.npcData.homeRoom == roomNumber && $0.homeHouse == houseNumber
            }

            guard let occupant else { continue }

            let nameTag = SKLabelNode(text: occupant.npcData.name)
            nameTag.fontSize = 10
            nameTag.fontName = "Arial"
            nameTag.fontColor = .white
            nameTag.alpha = 0.6
            nameTag.horizontalAlignmentMode = .center
            nameTag.verticalAlignmentMode = .top
            nameTag.position = CGPoint(x: 0, y: -25)
            nameTag.name = "house_name_tag"
            house.addChild(nameTag)
        }
    }
}
