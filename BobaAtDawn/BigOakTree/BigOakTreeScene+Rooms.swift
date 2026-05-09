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

        configureDiningTableSprites()

        // Dining tables are permanent lobby props now, so always
        // surface the authored art when the room configures.
        setDiningTablesVisible(true)

        // If the player enters the oak during dawn phase 1, recover
        // breakfast seating now that the seat anchors are available.
        GnomeManager.shared.ensureOakBreakfastIfNeeded()

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

// MARK: - Dining Tables (lobby anchors)
//
// Tables and seats are authored in BigOakTreeScene.sks under the
// `oak_room_lobby` container with the following naming convention:
//
//   gnome_table_<n>           where n in 1...5  (the table sprite)
//   gnome_seat_<n>_<s>        where s in 1...4  (chair anchor for table n)
//   gnome_cook_station        (where Cook stands while plating up)
//
// All anchors are optional. If a seat is missing, GnomeSeating skips
// that slot and falls back to a free-mingle position for whichever
// gnome would have sat there. If `gnome_cook_station` is missing,
// Cook falls back to her existing dinnerMinglePosition. None of these
// missing anchors trip an assert — the simulation degrades gracefully
// to today's free-mingle behavior.

extension BigOakTreeScene {

    /// Maximum number of dining tables expected by the simulation.
    /// Anchors with indices beyond this are ignored.
    static let diningTableCount = 5
    /// Seats per table.
    static let seatsPerTable = 4
    /// Runtime visual size for the authored dining table sprites.
    static let diningTableSpriteSize = CGSize(width: 128, height: 128)

    /// Lobby container, or nil if the SKS hasn't been loaded yet.
    private var lobbyContainer: SKNode? {
        roomContainer(for: .lobby)
    }

    /// Ensure authored dining table sprites resolve to the intended
    /// art and size at runtime. The editor archive can preserve the
    /// named sprite nodes while still drifting in texture/size data
    /// across repairs, so we stamp the known-good asset here.
    ///
    /// Handles both layouts: a top-level SKSpriteNode named
    /// `gnome_table_<n>`, OR an SKNode parent with that name and a
    /// child SKSpriteNode (which is what the editor produces when you
    /// drag a Color Sprite and rename it). Without the second case,
    /// tables stay textureless because the cast-to-SKSpriteNode lookup
    /// silently misses the parent SKNode.
    private func configureDiningTableSprites() {
        guard let lobby = lobbyContainer else { return }
        let tableTexture = Self.resolveBoxTexture()
        tableTexture.filteringMode = .nearest

        for tableIndex in 1...Self.diningTableCount {
            guard let node = lobby.sceneNode(named: "gnome_table_\(tableIndex)", as: SKNode.self) else {
                Log.warn(.scene, "[Tables] gnome_table_\(tableIndex) not found in lobby")
                continue
            }
            // Find the textured sprite: either the node itself, or its
            // first SKSpriteNode child.
            let sprite: SKSpriteNode?
            if let asSprite = node as? SKSpriteNode {
                sprite = asSprite
            } else {
                sprite = node.children.compactMap { $0 as? SKSpriteNode }.first
            }
            guard let s = sprite else {
                Log.warn(.scene, "[Tables] gnome_table_\(tableIndex) has no SKSpriteNode to texture")
                continue
            }
            s.texture = tableTexture
            s.size = Self.diningTableSpriteSize
            s.centerRect = CGRect(x: 0, y: 0, width: 1, height: 1)
            s.colorBlendFactor = 0   // ensure base color tint doesn't
                                     // multiply the texture into a dark
                                     // brown blob (the .sks ships with a
                                     // dark-brown _baseColor on these).
            s.color = .white         // identity tint when blend is 0,
                                     // safe to set anyway.
            // Reset any non-1 scale set in the editor; otherwise the
            // 0.5x scale baked into the .sks shrinks our 128x128 size
            // back down to ~64x60.
            s.xScale = 1.0
            s.yScale = 1.0
            s.isHidden = s.isHidden  // no-op, but explicit; actual
                                     // visibility toggled by
                                     // setDiningTablesVisible.
            Log.debug(.scene, "[Tables] textured gnome_table_\(tableIndex) (size=\(s.size), tex=\(tableTexture))")
        }
    }

    /// Look up the box.png asset from the catalog, trying a couple of
    /// likely paths in case the user's catalog has the image inside a
    /// namespaced folder. SKTexture(imageNamed:) returns a placeholder
    /// 1x1 white texture if the name doesn't resolve, so we sniff the
    /// returned texture's pixel size and fall through.
    private static func resolveBoxTexture() -> SKTexture {
        let candidates = ["box", "Items/box", "box.png"]
        for name in candidates {
            let tex = SKTexture(imageNamed: name)
            // Real box.png is 512x512. Anything <= 1px is the placeholder.
            let size = tex.size()
            if size.width > 4 && size.height > 4 {
                return tex
            }
        }
        // Last resort: return whatever "box" yields (placeholder),
        // logging loudly so the issue is obvious.
        Log.error(.scene, "[Tables] Could not resolve 'box' texture from any known asset path. Check Assets.xcassets/Items/box.imageset.")
        return SKTexture(imageNamed: "box")
    }

    /// World-space position of the named seat anchor, or nil if the
    /// SKS doesn't carry it. `tableIndex` and `seatIndex` are 1-based.
    func diningSeatPosition(tableIndex: Int, seatIndex: Int) -> CGPoint? {
        guard let lobby = lobbyContainer else { return nil }
        let name = "gnome_seat_\(tableIndex)_\(seatIndex)"
        guard let anchor = lobby.sceneNode(named: name, as: SKNode.self) else {
            return nil
        }
        return anchor.positionInSceneCoordinates()
    }

    /// World-space position of a table's center sprite (used by the
    /// cook to walk up to the table). Falls back to the centroid of
    /// the table's seat anchors if the table sprite is missing.
    func diningTablePosition(tableIndex: Int) -> CGPoint? {
        guard let lobby = lobbyContainer else { return nil }
        if let table = lobby.sceneNode(named: "gnome_table_\(tableIndex)", as: SKNode.self) {
            return table.positionInSceneCoordinates()
        }
        // Fallback — average the seat anchors.
        var sum = CGPoint.zero
        var count = 0
        for s in 1...Self.seatsPerTable {
            if let p = diningSeatPosition(tableIndex: tableIndex, seatIndex: s) {
                sum.x += p.x
                sum.y += p.y
                count += 1
            }
        }
        guard count > 0 else { return nil }
        return CGPoint(x: sum.x / CGFloat(count), y: sum.y / CGFloat(count))
    }

    /// World-space position of the cook station anchor, or nil if it
    /// isn't authored.
    func cookStationPosition() -> CGPoint? {
        guard let lobby = lobbyContainer,
              let anchor = lobby.sceneNode(named: "gnome_cook_station", as: SKNode.self) else {
            return nil
        }
        return anchor.positionInSceneCoordinates()
    }

    /// World-space position of the broker desk anchor, or nil if not
    /// authored. Broker idles here and accepts NPC trades.
    func brokerDeskPosition() -> CGPoint? {
        guard let lobby = lobbyContainer,
              let anchor = lobby.sceneNode(named: "gnome_anchor_broker_desk", as: SKNode.self) else {
            return nil
        }
        return anchor.positionInSceneCoordinates()
    }

    /// World-space position of the treasurer desk anchor, or nil if not
    /// authored. Treasurer idles here and dispatches gem refills to
    /// the broker on request.
    func treasurerDeskPosition() -> CGPoint? {
        guard let lobby = lobbyContainer,
              let anchor = lobby.sceneNode(named: "gnome_anchor_treasurer_desk", as: SKNode.self) else {
            return nil
        }
        return anchor.positionInSceneCoordinates()
    }

    /// World-space position the broker dumps the daily wares box at —
    /// the kitchen pantry/fridge. Falls back to the cook station
    /// position if the dedicated anchor isn't authored, since the
    /// pantry will sit near the cook's workstation.
    func kitchenDumpPosition() -> CGPoint? {
        guard let lobby = lobbyContainer else { return nil }
        if let anchor = lobby.sceneNode(named: "gnome_anchor_kitchen_dump", as: SKNode.self) {
            return anchor.positionInSceneCoordinates()
        }
        // Fall back to the cook station — the pantry lives near it.
        return cookStationPosition()
    }

    /// All seat anchors that exist in the SKS, returned as
    /// (anchorName, worldPosition) tuples in (table, seat) order. Used
    /// by GnomeSeating to assign seats. Empty when the SKS has no
    /// dining anchors authored — the seating system then falls back
    /// to free-mingle behavior.
    func availableDiningSeats() -> [(anchor: String, position: CGPoint)] {
        var result: [(String, CGPoint)] = []
        for t in 1...Self.diningTableCount {
            for s in 1...Self.seatsPerTable {
                if let p = diningSeatPosition(tableIndex: t, seatIndex: s) {
                    result.append(("gnome_seat_\(t)_\(s)", p))
                }
            }
        }
        return result
    }

    /// Map a seat anchor name back to its (table, seat) index pair.
    /// Returns nil for malformed names.
    static func parseSeatAnchor(_ anchorName: String) -> (table: Int, seat: Int)? {
        // Format: "gnome_seat_<t>_<s>"
        let parts = anchorName.split(separator: "_")
        guard parts.count == 4,
              parts[0] == "gnome",
              parts[1] == "seat",
              let t = Int(parts[2]),
              let s = Int(parts[3]) else {
            return nil
        }
        return (t, s)
    }

    /// Keep every authored `gnome_table_*` sprite visible in the
    /// lobby. Seat anchors are invisible by nature so they're
    /// untouched. We keep this method so existing meal code can call
    /// it, but hide requests are intentionally ignored.
    func setDiningTablesVisible(_ visible: Bool) {
        guard let lobby = lobbyContainer else { return }
        for t in 1...Self.diningTableCount {
            if let table = lobby.sceneNode(named: "gnome_table_\(t)", as: SKNode.self) {
                table.isHidden = false
            }
        }
    }
}
