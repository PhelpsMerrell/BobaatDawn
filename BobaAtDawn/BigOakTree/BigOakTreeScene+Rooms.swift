//
//  BigOakTreeScene+Rooms.swift
//  BobaAtDawn
//
//  Editor-first oak room layout. Static lobby/bedroom/treasury nodes
//  live in BigOakTreeScene.sks and this file only toggles room
//  containers, gnome visuals (delegated to GnomeManager), the treasury
//  pile, and spawn anchors.
//

import SpriteKit

// MARK: - Oak Editor Layout
enum OakLayout {
    static var lobbyStairLeftSpawnFallback: CGPoint { GameConfig.gridToWorld(GridCoordinate(x: 10, y: 17)) }
    static var lobbyStairMiddleSpawnFallback: CGPoint { GameConfig.gridToWorld(GridCoordinate(x: 16, y: 17)) }
    static var lobbyStairRightSpawnFallback: CGPoint { GameConfig.gridToWorld(GridCoordinate(x: 22, y: 17)) }
    static var lobbyStairTreasurySpawnFallback: CGPoint { GameConfig.gridToWorld(GridCoordinate(x: 6, y: 12)) }
    static var lobbyDefaultSpawnFallback: CGPoint { GameConfig.gridToWorld(GridCoordinate(x: 16, y: 7)) }
    static var bedroomSpawnFallback: CGPoint { GameConfig.gridToWorld(GridCoordinate(x: 16, y: 7)) }
    static var treasurySpawnFallback: CGPoint { GameConfig.gridToWorld(GridCoordinate(x: 16, y: 7)) }
    static var treasuryPileFallback: CGPoint { GameConfig.gridToWorld(GridCoordinate(x: 16, y: 12)) }
}

extension OakRoom {
    var containerName: String {
        switch self {
        case .lobby:
            return "oak_room_lobby"
        case .leftBedroom:
            return "oak_room_left_bedroom"
        case .middleBedroom:
            return "oak_room_middle_bedroom"
        case .rightBedroom:
            return "oak_room_right_bedroom"
        case .treasury:
            return "oak_room_treasury"
        }
    }
}

// MARK: - Oak Room Setup
extension BigOakTreeScene {

    internal func configureActiveRoom() {
        for room in OakRoom.allCases {
            roomContainer(for: room)?.isHidden = room != currentOakRoom
        }

        guard let container = roomContainer(for: currentOakRoom) else {
            Log.error(.scene, "Missing \(currentOakRoom.containerName) in BigOakTreeScene.sks")
            return
        }

        roomLabel = container.namedChild("oak_room_label", as: SKLabelNode.self)

        // Treasury room — install the treasury pile if we have an SKS
        // node for it; otherwise spawn one programmatically at the
        // anchor.
        if currentOakRoom == .treasury {
            installTreasuryPile(in: container)
        }

        // Hand off gnome visual spawning to the GnomeManager.
        GnomeManager.shared.spawnVisibleGnomes(
            inOakRoom: currentOakRoom,
            container: container,
            scene: self
        )
    }

    private func installTreasuryPile(in container: SKNode) {
        // Look for a TreasuryPile already in the .sks. If found, use it.
        if let pile = container.namedChild(TreasuryPile.nodeName, as: TreasuryPile.self) {
            treasuryPile = pile
            pile.setCount(GnomeManager.shared.treasuryGemCount)
            return
        }
        // Otherwise build one at the named anchor (or fallback) and add
        // it to the container.
        let anchor = positionOfAnchor(named: "treasury_pile_anchor",
                                       in: container,
                                       fallback: OakLayout.treasuryPileFallback)
        let pile = TreasuryPile()
        pile.position = anchor
        container.addChild(pile)
        treasuryPile = pile
        pile.setCount(GnomeManager.shared.treasuryGemCount)
    }

    internal func roomContainer(for room: OakRoom) -> SKNode? {
        sceneNode(named: room.containerName, as: SKNode.self)
    }

    internal func spawnPosition(enteringRoom target: OakRoom, from: OakRoom) -> CGPoint {
        switch target {
        case .lobby:
            let lobbyContainer = roomContainer(for: .lobby)
            switch from {
            case .leftBedroom:
                return positionOfAnchor(named: "spawn_from_left_bedroom", in: lobbyContainer, fallback: OakLayout.lobbyStairLeftSpawnFallback)
            case .middleBedroom:
                return positionOfAnchor(named: "spawn_from_middle_bedroom", in: lobbyContainer, fallback: OakLayout.lobbyStairMiddleSpawnFallback)
            case .rightBedroom:
                return positionOfAnchor(named: "spawn_from_right_bedroom", in: lobbyContainer, fallback: OakLayout.lobbyStairRightSpawnFallback)
            case .treasury:
                return positionOfAnchor(named: "spawn_from_treasury", in: lobbyContainer, fallback: OakLayout.lobbyStairTreasurySpawnFallback)
            default:
                return positionOfAnchor(named: "spawn_from_forest", in: lobbyContainer, fallback: OakLayout.lobbyDefaultSpawnFallback)
            }

        case .leftBedroom:
            return positionOfAnchor(named: "spawn_from_lobby", in: roomContainer(for: .leftBedroom), fallback: OakLayout.bedroomSpawnFallback)
        case .middleBedroom:
            return positionOfAnchor(named: "spawn_from_lobby", in: roomContainer(for: .middleBedroom), fallback: OakLayout.bedroomSpawnFallback)
        case .rightBedroom:
            return positionOfAnchor(named: "spawn_from_lobby", in: roomContainer(for: .rightBedroom), fallback: OakLayout.bedroomSpawnFallback)
        case .treasury:
            return positionOfAnchor(named: "spawn_from_lobby", in: roomContainer(for: .treasury), fallback: OakLayout.treasurySpawnFallback)
        }
    }

    private func positionOfAnchor(named anchorName: String, in container: SKNode?, fallback: CGPoint) -> CGPoint {
        guard let anchor = container?.sceneNode(named: anchorName, as: SKNode.self) else {
            return fallback
        }
        return anchor.positionInSceneCoordinates()
    }
}
