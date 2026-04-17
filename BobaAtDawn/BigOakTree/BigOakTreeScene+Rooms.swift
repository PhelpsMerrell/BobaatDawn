//
//  BigOakTreeScene+Rooms.swift
//  BobaAtDawn
//
//  Per-room layouts for the Big Oak Tree interior.
//  All grid positions live in `OakLayout` so they're easy to edit in one place.
//
//  Every placed node uses a distinct `name` and is a simple colored
//  SKSpriteNode or SKLabelNode placeholder — swap in Sprite2D art by
//  replacing the `SKSpriteNode(color:size:)` or `SKLabelNode(text:)` call
//  with your own texture-backed sprite of matching size and position.
//

import SpriteKit

// MARK: - OakLayout (all grid positions in one place)
/// Central registry of grid coordinates + spawn positions for the oak tree.
/// Edit these to reshape rooms.
enum OakLayout {

    // MARK: Lobby
    static let lobbyRoomLabel    = GridCoordinate(x: 16, y: 22)
    static let lobbyFireplace    = GridCoordinate(x:  7, y: 12)
    static let lobbyKitchen      = GridCoordinate(x: 25, y: 12)
    static let lobbyCouchLeft    = GridCoordinate(x: 13, y:  9)
    static let lobbyCouchRight   = GridCoordinate(x: 19, y:  9)
    static let lobbyStairsLeft   = GridCoordinate(x: 10, y: 19)
    static let lobbyStairsMiddle = GridCoordinate(x: 16, y: 19)
    static let lobbyStairsRight  = GridCoordinate(x: 22, y: 19)
    static let lobbyExitDoor     = GridCoordinate(x: 16, y:  5)

    // Lobby gnome placeholders
    static let lobbyGnomeGreeter   = GridCoordinate(x: 16, y: 13)
    static let lobbyGnomeFireplace = GridCoordinate(x:  9, y: 11)
    
    /// World-space rectangle confining lobby gnome wandering. Chosen to
    /// keep gnomes clear of the three stair tiles (grid y=19) above and
    /// the exit door (grid y=5) below, as well as the side walls.
    static let lobbyGnomeWanderBounds = CGRect(x: -600, y: -250,
                                                width: 1200, height: 550)

    // MARK: Bedrooms (same layout for all 3 for now — easy to customize later)
    static let bedroomRoomLabel   = GridCoordinate(x: 16, y: 22)
    static let bedroomBed         = GridCoordinate(x: 14, y: 15)
    static let bedroomNightstand  = GridCoordinate(x: 18, y: 15)
    static let bedroomWindow      = GridCoordinate(x: 16, y: 21)
    static let bedroomDownStair   = GridCoordinate(x: 16, y:  5)

    // Bedroom gnome placeholders (one per bedroom)
    static let bedroomGnomeSpot   = GridCoordinate(x: 16, y: 10)
    
    /// World-space rectangle confining bedroom gnome wandering. Chosen to
    /// keep gnomes clear of the window (grid y=21) above and the
    /// down-stair (grid y=5) below, plus the side walls.
    static let bedroomGnomeWanderBounds = CGRect(x: -400, y: -250,
                                                  width: 800, height: 500)

    // MARK: Spawn Positions (world coordinates, derived from grid)
    static var lobbyStairLeftSpawn:   CGPoint { GameConfig.gridToWorld(GridCoordinate(x: 10, y: 17)) }
    static var lobbyStairMiddleSpawn: CGPoint { GameConfig.gridToWorld(GridCoordinate(x: 16, y: 17)) }
    static var lobbyStairRightSpawn:  CGPoint { GameConfig.gridToWorld(GridCoordinate(x: 22, y: 17)) }
    /// Fallback spawn (e.g. first entry from forest) — near the exit door.
    static var lobbyDefaultSpawn:     CGPoint { GameConfig.gridToWorld(GridCoordinate(x: 16, y:  7)) }
    /// Where the player spawns inside a bedroom when arriving from the lobby —
    /// just above the down-stair so they can see the stair below them.
    static var bedroomDownStairSpawn: CGPoint { GameConfig.gridToWorld(GridCoordinate(x: 16, y:  7)) }

    // MARK: Placeholder Sizes (swap to real sprite sizes later)
    static let furnitureLarge  = CGSize(width: 120, height: 90)
    static let furnitureMedium = CGSize(width:  80, height: 80)
    static let furnitureSmall  = CGSize(width:  60, height: 60)
    static let stairTileSize   = CGSize(width:  80, height: 80)
    static let doorSize        = CGSize(width:  80, height: 100)

    // MARK: Placeholder Colors (swap to textures later)
    static let fireplaceColor = SKColor(red: 0.35, green: 0.10, blue: 0.05, alpha: 1.0)
    static let kitchenColor   = SKColor(red: 0.70, green: 0.55, blue: 0.35, alpha: 1.0)
    static let couchColor     = SKColor(red: 0.45, green: 0.25, blue: 0.15, alpha: 1.0)
    static let stairColor     = SKColor(red: 0.55, green: 0.35, blue: 0.20, alpha: 1.0)
    static let doorColor      = SKColor(red: 0.30, green: 0.18, blue: 0.10, alpha: 1.0)
    static let bedColor       = SKColor(red: 0.85, green: 0.75, blue: 0.60, alpha: 1.0)
    static let nightstandColor = SKColor(red: 0.40, green: 0.25, blue: 0.15, alpha: 1.0)
    static let windowColor    = SKColor(red: 0.55, green: 0.75, blue: 0.95, alpha: 1.0)
}

// MARK: - Room Layouts
extension BigOakTreeScene {

    // MARK: Lobby
    internal func setupLobby() {
        // Room label (top-center, big emoji identifier — mirrors ForestScene pattern)
        addRoomLabel("🏡", at: OakLayout.lobbyRoomLabel)

        // Fireplace — dark brick rectangle + emoji overlay
        addDecor(named: "oak_lobby_fireplace",
                 at: OakLayout.lobbyFireplace,
                 size: OakLayout.furnitureLarge,
                 color: OakLayout.fireplaceColor,
                 emoji: "🔥",
                 emojiFontSize: 40)

        // Kitchen counter — lighter wood rectangle + emoji
        addDecor(named: "oak_lobby_kitchen",
                 at: OakLayout.lobbyKitchen,
                 size: OakLayout.furnitureLarge,
                 color: OakLayout.kitchenColor,
                 emoji: "🍳",
                 emojiFontSize: 36)

        // Two couches flanking center
        addDecor(named: "oak_lobby_couch_left",
                 at: OakLayout.lobbyCouchLeft,
                 size: OakLayout.furnitureMedium,
                 color: OakLayout.couchColor,
                 emoji: "🛋️",
                 emojiFontSize: 32)

        addDecor(named: "oak_lobby_couch_right",
                 at: OakLayout.lobbyCouchRight,
                 size: OakLayout.furnitureMedium,
                 color: OakLayout.couchColor,
                 emoji: "🛋️",
                 emojiFontSize: 32)

        // Three stair tiles leading up to bedrooms
        addStairTile(name: BigOakTreeScene.stairsLeftName,
                     at: OakLayout.lobbyStairsLeft,
                     emoji: "⬆️")
        addStairTile(name: BigOakTreeScene.stairsMiddleName,
                     at: OakLayout.lobbyStairsMiddle,
                     emoji: "⬆️")
        addStairTile(name: BigOakTreeScene.stairsRightName,
                     at: OakLayout.lobbyStairsRight,
                     emoji: "⬆️")

        // Exit door (back to forest)
        addDoor(name: BigOakTreeScene.exitDoorName,
                at: OakLayout.lobbyExitDoor,
                emoji: "🚪")

        // Gnome placeholders (2 in the lobby)
        addGnome(ofType: .lobbyGreeter,
                 at: OakLayout.lobbyGnomeGreeter,
                 wanderBounds: OakLayout.lobbyGnomeWanderBounds)
        addGnome(ofType: .fireplaceKeeper,
                 at: OakLayout.lobbyGnomeFireplace,
                 wanderBounds: OakLayout.lobbyGnomeWanderBounds)
    }

    // MARK: Left Bedroom
    internal func setupLeftBedroom() {
        addRoomLabel("🛏️", at: OakLayout.bedroomRoomLabel)
        setupGenericBedroomFurniture()
        addGnome(ofType: .leftBedroomElder,
                 at: OakLayout.bedroomGnomeSpot,
                 wanderBounds: OakLayout.bedroomGnomeWanderBounds)
    }

    // MARK: Middle Bedroom
    internal func setupMiddleBedroom() {
        addRoomLabel("🛏️", at: OakLayout.bedroomRoomLabel)
        setupGenericBedroomFurniture()
        addGnome(ofType: .middleBedroomSeer,
                 at: OakLayout.bedroomGnomeSpot,
                 wanderBounds: OakLayout.bedroomGnomeWanderBounds)
    }

    // MARK: Right Bedroom
    internal func setupRightBedroom() {
        addRoomLabel("🛏️", at: OakLayout.bedroomRoomLabel)
        setupGenericBedroomFurniture()
        addGnome(ofType: .rightBedroomChild,
                 at: OakLayout.bedroomGnomeSpot,
                 wanderBounds: OakLayout.bedroomGnomeWanderBounds)
    }

    // MARK: Shared Bedroom Furniture
    /// Bedroom furniture is identical across all three for now. Customize
    /// each bedroom by splitting this into per-room methods and editing
    /// the relevant OakLayout constants or adding new ones.
    private func setupGenericBedroomFurniture() {
        addDecor(named: "oak_bedroom_bed",
                 at: OakLayout.bedroomBed,
                 size: OakLayout.furnitureLarge,
                 color: OakLayout.bedColor,
                 emoji: "🛏️",
                 emojiFontSize: 40)

        addDecor(named: "oak_bedroom_nightstand",
                 at: OakLayout.bedroomNightstand,
                 size: OakLayout.furnitureSmall,
                 color: OakLayout.nightstandColor,
                 emoji: "🕯️",
                 emojiFontSize: 28)

        addDecor(named: "oak_bedroom_window",
                 at: OakLayout.bedroomWindow,
                 size: OakLayout.furnitureMedium,
                 color: OakLayout.windowColor,
                 emoji: "🪟",
                 emojiFontSize: 32)

        // Down-stair back to the lobby
        addStairTile(name: BigOakTreeScene.stairsDownName,
                     at: OakLayout.bedroomDownStair,
                     emoji: "⬇️")
    }

    // MARK: - Placement Helpers
    /// Central room label (e.g. 🏡 or 🛏️) — big, visible, non-interactive.
    private func addRoomLabel(_ emoji: String, at gridPos: GridCoordinate) {
        let label = SKLabelNode(text: emoji)
        label.fontSize = 80
        label.fontName = "Arial"
        label.horizontalAlignmentMode = .center
        label.verticalAlignmentMode = .center
        label.position = GameConfig.gridToWorld(gridPos)
        label.zPosition = ZLayers.decorations
        label.alpha = 0.45
        label.name = "oak_room_label"
        label.isUserInteractionEnabled = false
        addChild(label)
        self.roomLabel = label
    }

    /// Decorative piece of furniture (non-interactive). A colored rectangle
    /// with an emoji overlay. Swap the rectangle for a textured
    /// SKSpriteNode to install real art later.
    ///
    /// - Parameters:
    ///   - name: SKNode `name` — must be distinct so it's easy to find/replace.
    ///   - gridPos: grid coordinate of the center of the piece.
    ///   - size: placeholder size; match your real art's size when swapping.
    ///   - color: placeholder fill color.
    ///   - emoji: overlay emoji to clarify what the object is.
    ///   - emojiFontSize: overlay size.
    private func addDecor(
        named name: String,
        at gridPos: GridCoordinate,
        size: CGSize,
        color: SKColor,
        emoji: String,
        emojiFontSize: CGFloat
    ) {
        let base = SKSpriteNode(color: color, size: size)
        base.position = GameConfig.gridToWorld(gridPos)
        base.zPosition = ZLayers.furniture
        base.name = name
        base.isUserInteractionEnabled = false
        addChild(base)
        placedDecor.append(base)

        let overlay = SKLabelNode(text: emoji)
        overlay.fontSize = emojiFontSize
        overlay.fontName = "Arial"
        overlay.horizontalAlignmentMode = .center
        overlay.verticalAlignmentMode = .center
        overlay.position = .zero
        overlay.zPosition = 1
        overlay.name = "\(name)_emoji"
        base.addChild(overlay)
    }

    /// Stair tile — interactive. Tapping it starts a long-press that
    /// triggers a room transition.
    private func addStairTile(
        name: String,
        at gridPos: GridCoordinate,
        emoji: String
    ) {
        let tile = SKSpriteNode(color: OakLayout.stairColor, size: OakLayout.stairTileSize)
        tile.position = GameConfig.gridToWorld(gridPos)
        tile.zPosition = ZLayers.doors
        tile.name = name
        tile.isUserInteractionEnabled = false // scene-level touch handling
        addChild(tile)
        placedDecor.append(tile)

        let overlay = SKLabelNode(text: emoji)
        overlay.fontSize = 36
        overlay.fontName = "Arial"
        overlay.horizontalAlignmentMode = .center
        overlay.verticalAlignmentMode = .center
        overlay.position = .zero
        overlay.zPosition = 1
        overlay.name = "\(name)_emoji"
        tile.addChild(overlay)
    }

    /// Door — interactive, same pattern as a stair tile but taller/door-shaped.
    private func addDoor(
        name: String,
        at gridPos: GridCoordinate,
        emoji: String
    ) {
        let door = SKSpriteNode(color: OakLayout.doorColor, size: OakLayout.doorSize)
        door.position = GameConfig.gridToWorld(gridPos)
        door.zPosition = ZLayers.doors
        door.name = name
        door.isUserInteractionEnabled = false
        addChild(door)
        placedDecor.append(door)

        let overlay = SKLabelNode(text: emoji)
        overlay.fontSize = 48
        overlay.fontName = "Arial"
        overlay.horizontalAlignmentMode = .center
        overlay.verticalAlignmentMode = .center
        overlay.position = .zero
        overlay.zPosition = 1
        overlay.name = "\(name)_emoji"
        door.addChild(overlay)
    }

    /// Spawn a gnome at a grid position. Tracked in `placedGnomes` so they
    /// get cleaned up on room changes.
    ///
    /// - Parameters:
    ///   - type: which hardcoded gnome identity this is.
    ///   - gridPos: spawn grid coordinate inside the current room.
    ///   - wanderBounds: optional world-space rectangle constraining where
    ///     this gnome can wander. Defaults to nil (unbounded within radius).
    ///     Pass a value like `OakLayout.lobbyGnomeWanderBounds` to keep
    ///     the gnome clear of stairs/doors.
    private func addGnome(
        ofType type: GnomeType,
        at gridPos: GridCoordinate,
        wanderBounds: CGRect? = nil
    ) {
        let gnome = GnomeNPC(
            gnomeType: type,
            at: GameConfig.gridToWorld(gridPos),
            wanderBounds: wanderBounds
        )
        addChild(gnome)
        placedGnomes.append(gnome)
    }
}
