//
//  CaveScene+Rooms.swift
//  BobaAtDawn
//
//  Editor-first cave room layout. Static cave-room nodes live in
//  CaveScene.sks and this file only toggles room containers and
//  resolves spawn anchors between floor transitions.
//

import SpriteKit

// MARK: - Cave Editor Layout
enum CaveLayout {
    static var entranceDefaultSpawnFallback: CGPoint { CGPoint(x: 0, y: -300) }
    static var floorDefaultSpawnFallback: CGPoint    { CGPoint(x: 0, y: -300) }

    static var entranceStairDownSpawnFallback: CGPoint { CGPoint(x: 0, y: 380) }
    static var floorStairUpSpawnFallback: CGPoint      { CGPoint(x: 0, y: 380) }
    static var floorStairDownSpawnFallback: CGPoint    { CGPoint(x: 0, y: -380) }
}

private extension CaveRoom {
    var containerName: String {
        switch self {
        case .entrance: return "cave_room_entrance"
        case .floor1:   return "cave_room_floor_1"
        case .floor2:   return "cave_room_floor_2"
        case .floor3:   return "cave_room_floor_3"
        }
    }
}

// MARK: - Cave Room Setup
extension CaveScene {

    internal func configureActiveRoom() {
        for room in CaveRoom.allCases {
            roomContainer(for: room)?.isHidden = room != currentCaveRoom
        }

        guard let container = roomContainer(for: currentCaveRoom) else {
            Log.error(.scene, "Missing \(currentCaveRoom.containerName) in CaveScene.sks")
            return
        }

        roomLabel = container.namedChild("cave_room_label", as: SKLabelNode.self)
    }

    internal func roomContainer(for room: CaveRoom) -> SKNode? {
        sceneNode(named: room.containerName, as: SKNode.self)
    }

    /// Compute the world-space position where the character should appear
    /// when entering `target` from `from`. Reads named anchor nodes inside
    /// the target room's container if present; otherwise falls back to the
    /// editor-first layout defaults used by CaveScene.sks.
    internal func spawnPosition(enteringRoom target: CaveRoom, from: CaveRoom) -> CGPoint {
        let container = roomContainer(for: target)

        // Determine if we're moving DOWN (from a shallower room) or UP
        // (from a deeper room). Down means we came down stairs — spawn at
        // the up-stairs landing in the new room. Up means we came up
        // stairs — spawn at the down-stairs landing.
        let movingDown = target.rawValue > from.rawValue

        if movingDown {
            // Came down — spawn next to the stairs-up in the destination.
            return positionOfAnchor(
                named: "spawn_from_above",
                in: container,
                fallback: CaveLayout.floorStairUpSpawnFallback
            )
        } else {
            // Came up — spawn next to the stairs-down in the destination.
            // If target is entrance, that's the main "stairs down" spot.
            let fallback = (target == .entrance)
                ? CaveLayout.entranceStairDownSpawnFallback
                : CaveLayout.floorStairDownSpawnFallback
            return positionOfAnchor(
                named: "spawn_from_below",
                in: container,
                fallback: fallback
            )
        }
    }

    private func positionOfAnchor(named anchorName: String, in container: SKNode?, fallback: CGPoint) -> CGPoint {
        guard let anchor = container?.sceneNode(named: anchorName, as: SKNode.self) else {
            return fallback
        }
        return anchor.positionInSceneCoordinates()
    }
}
