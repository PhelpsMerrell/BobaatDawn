//
//  SnailNPC.swift
//  BobaAtDawn
//
//  The mysterious snail that hunts players in the forest at night.
//  Persists its room/position across scene loads via SnailWorldState.
//

import SpriteKit
import UIKit

// MARK: - Persistent Snail State (lives across scene loads)
/// Singleton that tracks where the snail is in the world regardless of
/// whether the ForestScene is loaded.
final class SnailWorldState {
    static let shared = SnailWorldState()
    
    /// Which forest room the snail is currently in (1-5)
    var currentRoom: Int = 1
    
    /// The snail's position within its current room (world coords, relative to room center 0,0)
    var roomPosition: CGPoint = .zero
    
    /// Whether the snail is currently active (night time)
    var isActive: Bool = false
    
    /// Timer for simulated room-to-room movement while player is in the shop
    private var roomChangeAccumulator: TimeInterval = 0
    
    /// How many seconds between the snail changing rooms while wandering (player in shop)
    private let wanderRoomInterval: TimeInterval = 30.0
    
    /// How many seconds between the snail changing rooms while hunting (player in forest, different room)
    private let huntRoomInterval: TimeInterval = 12.0
    
    private init() {}
    
    // MARK: - Activation (called by time system)
    func activate() {
        guard !isActive else { return }
        isActive = true
        currentRoom = Int.random(in: 1...5)
        roomPosition = randomRoomPosition()
        roomChangeAccumulator = 0
        Log.info(.forest, "Snail ACTIVATED in room \(currentRoom)")
    }
    
    func deactivate() {
        isActive = false
        roomChangeAccumulator = 0
        Log.info(.forest, "Snail DEACTIVATED")
    }
    
    // MARK: - Continuous Simulation (host only)

    /// Per-frame wander-target inside the current room. Host picks a
    /// new one when reached or after a room transition.
    private var wanderTarget: CGPoint?

    /// Speed (points/sec) when actively chasing the player.
    private let huntSpeed: CGFloat = 60.0

    /// Drift speed when wandering inside a room.
    private let wanderSpeed: CGFloat = 25.0

    /// Per-frame host simulation. Drives ALL snail motion — same-room
    /// hunting, different-room drift, and shop-only wander — in a single
    /// continuous loop. Replaces the old `simulateWandering` /
    /// `simulateHunting` pair which only mutated position on coarse room
    /// transitions and left the snail visually frozen between them.
    ///
    /// Only the host should call this; the guest mirrors the broadcast
    /// `roomPosition`. Pass `hostRoom == nil` when the host is in the
    /// shop (no forest player), in which case the snail wanders
    /// aimlessly through forest rooms.
    func tickHost(deltaTime: TimeInterval, hostRoom: Int?, hostPosition: CGPoint?) {
        guard isActive else { return }

        if let hRoom = hostRoom, let hPos = hostPosition, hRoom == currentRoom {
            // Same room as player — hunt continuously.
            roomChangeAccumulator = 0
            wanderTarget = nil
            moveRoomPosition(toward: hPos, speed: huntSpeed, deltaTime: deltaTime)
            return
        }

        // Different room (or host in shop): drift toward a wander
        // target, and tick the room-change timer.
        if wanderTarget == nil
            || hypot(roomPosition.x - wanderTarget!.x, roomPosition.y - wanderTarget!.y) < 30 {
            wanderTarget = randomRoomPosition()
        }
        if let t = wanderTarget {
            moveRoomPosition(toward: t, speed: wanderSpeed, deltaTime: deltaTime)
        }

        roomChangeAccumulator += deltaTime
        let interval = (hostRoom == nil) ? wanderRoomInterval : huntRoomInterval
        if roomChangeAccumulator >= interval {
            roomChangeAccumulator = 0
            let oldRoom = currentRoom
            if let hRoom = hostRoom {
                currentRoom = stepToward(target: hRoom, from: currentRoom)
            } else {
                currentRoom = Bool.random() ? nextRoom(from: currentRoom) : previousRoom(from: currentRoom)
            }
            if let hRoom = hostRoom, currentRoom == hRoom, let hPos = hostPosition {
                roomPosition = entryPosition(playerPosition: hPos)
            } else {
                roomPosition = randomRoomPosition()
            }
            wanderTarget = nil
            Log.debug(.forest, "Snail room \(oldRoom) -> \(currentRoom)")
        }
    }

    /// Step `roomPosition` toward `target` at `speed` points/sec without
    /// overshooting.
    private func moveRoomPosition(toward target: CGPoint, speed: CGFloat, deltaTime: TimeInterval) {
        let dx = target.x - roomPosition.x
        let dy = target.y - roomPosition.y
        let dist = sqrt(dx * dx + dy * dy)
        guard dist > 0.5 else { return }
        let step = min(speed * CGFloat(deltaTime), dist)
        let nx = dx / dist
        let ny = dy / dist
        roomPosition.x += nx * step
        roomPosition.y += ny * step
    }

    // MARK: - Room navigation helpers
    
    private func stepToward(target: Int, from current: Int) -> Int {
        guard current != target else { return current }
        let forwardDist = (target - current + 5) % 5
        let backwardDist = (current - target + 5) % 5
        return forwardDist <= backwardDist ? nextRoom(from: current) : previousRoom(from: current)
    }
    
    private func nextRoom(from room: Int) -> Int {
        return room == 5 ? 1 : room + 1
    }
    
    private func previousRoom(from room: Int) -> Int {
        return room == 1 ? 5 : room - 1
    }
    
    private func randomRoomPosition() -> CGPoint {
        let x = CGFloat.random(in: -500...500)
        let y = CGFloat.random(in: -400...400)
        return CGPoint(x: x, y: y)
    }
    
    /// Spawn the snail on the OPPOSITE side of the room from the player.
    /// Prevents the "impossible teleport" bug where the snail appeared
    /// right in front of the player when entering a new room.
    func entryPosition(playerPosition: CGPoint) -> CGPoint {
        let edgeX: CGFloat = playerPosition.x >= 0 ? -600 : 600
        
        var randomY = CGFloat.random(in: -300...300)
        if abs(randomY - playerPosition.y) < 100 {
            randomY = playerPosition.y >= 0 ? -250 : 250
        }
        
        return CGPoint(x: edgeX, y: randomY)
    }
}


// MARK: - The Snail Enemy (Visual / Scene Node)
class SnailNPC: SKSpriteNode {

    // MARK: - Properties
    private weak var timeService: TimeService?

    /// Last frame's visual position. Used to compute zRotation from
    /// movement delta so the sprite faces its direction of travel.
    private var lastVisualPosition: CGPoint = .zero
    
    // MARK: - Initialization
    init(timeService: TimeService) {
        self.timeService = timeService
        
        let texture = SKTexture()
        super.init(texture: texture, color: .clear, size: CGSize(width: 40, height: 40))
        
        setupVisuals()
        setupPhysics()
        
        name = "snail_enemy"
        zPosition = ZLayers.enemies
        
        alpha = 0.0
        isHidden = true
        
        Log.debug(.forest, "SnailNPC node created")
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Position Validation Bounds
    /// Safe operating rectangle for the snail inside any forest room —
    /// kept tight so the snail never spawns inside walls or beyond the
    /// visible play area. Tuned slightly smaller than the editor floor.
    static let safeRoomBounds = CGRect(x: -650, y: -450, width: 1300, height: 900)

    /// How close the snail can approach a `house_*` node before being
    /// pushed back out. Slightly larger than the visual house radius so
    /// the snail never overlaps a building.
    static let houseSafeRadius: CGFloat = 110

    // MARK: - Visual Setup
    private func setupVisuals() {
        if !applySnailTextureIfAvailable() {
            let snailLabel = SKLabelNode(text: "\u{1F40C}")
            snailLabel.fontSize = 32
            snailLabel.verticalAlignmentMode = .center
            snailLabel.horizontalAlignmentMode = .center
            snailLabel.zPosition = 1
            addChild(snailLabel)
        }

        let breathe = SKAction.repeatForever(SKAction.sequence([
            SKAction.scale(to: 1.05, duration: 2.0),
            SKAction.scale(to: 0.95, duration: 2.0)
        ]))
        run(breathe, withKey: "snail_breathe")
    }

    @discardableResult
    private func applySnailTextureIfAvailable() -> Bool {
        let directAssetNames = ["snail", "snail_idle", "snail_sprite", "snail_0"]
        for assetName in directAssetNames {
            if let image = UIImage(named: assetName) {
                let texture = SKTexture(image: image)
                texture.filteringMode = .nearest
                applySnailTexture(texture)
                return true
            }
        }

        let atlasCandidates = ["Snail", "Enemies", "Forest", "Creatures"]
        let textureCandidates = ["snail", "snail_idle", "snail_sprite", "snail_0"]
        for atlasName in atlasCandidates {
            let atlas = SKTextureAtlas(named: atlasName)
            guard let textureName = textureCandidates.first(where: { atlas.textureNames.contains($0) }) else {
                continue
            }
            let texture = atlas.textureNamed(textureName)
            texture.filteringMode = .nearest
            applySnailTexture(texture)
            return true
        }

        return false
    }

    private func applySnailTexture(_ texture: SKTexture) {
        self.texture = texture
        self.color = .white
        self.colorBlendFactor = 0.0

        let sourceSize = texture.size()
        guard sourceSize.width > 0, sourceSize.height > 0 else {
            size = CGSize(width: 56, height: 56)
            return
        }

        let maxDimension: CGFloat = 64
        let scale = min(maxDimension / sourceSize.width, maxDimension / sourceSize.height)
        size = CGSize(width: sourceSize.width * scale, height: sourceSize.height * scale)
    }
    
    // MARK: - Physics Setup
    private func setupPhysics() {
        physicsBody = SKPhysicsBody(circleOfRadius: 20)
        physicsBody?.categoryBitMask = PhysicsCategory.snail
        physicsBody?.contactTestBitMask = 0 // Starts disabled; enabled in fadeIn()
        physicsBody?.collisionBitMask = 0
        physicsBody?.affectedByGravity = false
        physicsBody?.isDynamic = true
        physicsBody?.allowsRotation = false
        physicsBody?.linearDamping = 0.5
    }
    
    func setContactEnabled(_ enabled: Bool) {
        physicsBody?.contactTestBitMask = enabled ? PhysicsCategory.character : 0
    }
    
    // MARK: - Sync with persistent world state

    /// Mirror the visual snail to `SnailWorldState`. Both host and guest
    /// run this exactly the same way — the snail visual is a pure
    /// readout of `SnailWorldState.roomPosition`. The host is the only
    /// side that mutates `roomPosition` (via `tickHost`), so both
    /// screens converge to the same position automatically.
    func syncWithWorldState(playerRoom: Int, playerPosition: CGPoint) {
        let world = SnailWorldState.shared

        checkTimeActivation()

        guard world.isActive else {
            if !isHidden { fadeOut() }
            physicsBody?.velocity = .zero
            return
        }

        guard world.currentRoom == playerRoom else {
            if !isHidden { fadeOut() }
            physicsBody?.velocity = .zero
            return
        }

        let target = validatedPosition(world.roomPosition)

        if isHidden {
            // First frame visible — snap to target, no rotation step yet.
            position = target
            lastVisualPosition = target
            fadeIn()
            return
        }

        // Smooth lerp toward authoritative position.
        let lerp: CGFloat = 0.25
        let nextPos = CGPoint(
            x: position.x + (target.x - position.x) * lerp,
            y: position.y + (target.y - position.y) * lerp
        )

        // Rotate to face direction of travel. Snail PNG is in side
        // profile facing +x by default (the original code flipped
        // xScale to face left), so atan2(dy, dx) gives the correct
        // facing angle directly.
        let dx = nextPos.x - lastVisualPosition.x
        let dy = nextPos.y - lastVisualPosition.y
        if dx * dx + dy * dy > 0.04 {
            zRotation = atan2(dy, dx)
        }

        position = nextPos
        lastVisualPosition = nextPos

        // We drive position directly; physics body just rides along
        // for contact detection.
        physicsBody?.velocity = .zero
    }

    // MARK: - Position Validation

    /// Clamp `candidate` into the safe room rectangle and push it out of
    /// any visible `house_*` node. Idempotent and cheap enough to call
    /// every frame the snail is moving.
    private func validatedPosition(_ candidate: CGPoint) -> CGPoint {
        var p = candidate
        let bounds = SnailNPC.safeRoomBounds

        // 1. Clamp to room rectangle.
        p.x = max(bounds.minX, min(bounds.maxX, p.x))
        p.y = max(bounds.minY, min(bounds.maxY, p.y))

        // 2. Push out of houses in the visible forest room. Iterate a
        //    few times in case pushing out of one house puts the snail
        //    inside another — should converge fast (rooms have ≤4 houses).
        guard let scene = self.scene else { return p }
        let safeRadius = SnailNPC.houseSafeRadius

        for _ in 0..<4 {
            var didAdjust = false
            scene.enumerateChildNodes(withName: "//house_*") { node, _ in
                // Skip houses inside hidden forest_room_X containers.
                var ancestor: SKNode? = node.parent
                var inHiddenRoom = false
                while let a = ancestor {
                    if let aname = a.name, aname.hasPrefix("forest_room_"), a.isHidden {
                        inHiddenRoom = true
                        break
                    }
                    ancestor = a.parent
                }
                if inHiddenRoom { return }

                // Convert house position into scene coordinates.
                let housePos: CGPoint
                if let parent = node.parent {
                    housePos = parent.convert(node.position, to: scene)
                } else {
                    housePos = node.position
                }

                let dx = p.x - housePos.x
                let dy = p.y - housePos.y
                let dist = sqrt(dx * dx + dy * dy)
                if dist < safeRadius {
                    if dist < 0.001 {
                        // Exactly coincident — nudge in a deterministic direction.
                        p.x = housePos.x + safeRadius
                    } else {
                        let scaleFactor = safeRadius / dist
                        p.x = housePos.x + dx * scaleFactor
                        p.y = housePos.y + dy * scaleFactor
                    }
                    didAdjust = true
                }
            }
            if !didAdjust { break }
            // Re-clamp to bounds after each round of pushes.
            p.x = max(bounds.minX, min(bounds.maxX, p.x))
            p.y = max(bounds.minY, min(bounds.maxY, p.y))
        }

        return p
    }
    
    // MARK: - Time Activation
    private func checkTimeActivation() {
        guard !MultiplayerService.shared.isGuest else { return }
        guard let timeService = timeService else { return }
        let world = SnailWorldState.shared
        
        let shouldBeActive = timeService.currentPhase == .night
        
        if shouldBeActive && !world.isActive {
            world.activate()
        } else if !shouldBeActive && world.isActive {
            world.deactivate()
        }
    }
    
    // MARK: - Visibility
    private func fadeIn() {
        isHidden = false
        setContactEnabled(true)
        let action = SKAction.fadeIn(withDuration: 1.5)
        run(action, withKey: "snail_fade")
        Log.debug(.forest, "Snail fades into view")
    }
    
    private func fadeOut() {
        setContactEnabled(false)
        let action = SKAction.sequence([
            SKAction.fadeOut(withDuration: 1.0),
            SKAction.run { [weak self] in
                self?.isHidden = true
            }
        ])
        run(action, withKey: "snail_fade")
    }
    
    // MARK: - Update (legacy)
    func update(deltaTime: TimeInterval) { }

    // MARK: - Player Contact
    func playerCaught() {
        Log.info(.forest, "THE SNAIL HAS CAUGHT YOU!")
        createCatchEffect()
        
        // Broadcast catch event so both screens see it
        if MultiplayerService.shared.isConnected {
            MultiplayerService.shared.send(type: .snailSync, payload: SnailSyncMessage(
                room: SnailWorldState.shared.currentRoom,
                position: CodablePoint(position),
                isActive: SnailWorldState.shared.isActive
            ))
        }
        
        NotificationCenter.default.post(name: .snailCaughtPlayer, object: self)
    }
    
    private func createCatchEffect() {
        let flashNode = SKSpriteNode(color: .red, size: CGSize(width: 2000, height: 2000))
        flashNode.alpha = 0
        flashNode.zPosition = 1000
        parent?.addChild(flashNode)
        
        flashNode.run(SKAction.sequence([
            SKAction.fadeIn(withDuration: 0.1),
            SKAction.fadeOut(withDuration: 0.3),
            SKAction.removeFromParent()
        ]))
        
        run(SKAction.sequence([
            SKAction.scale(to: 1.5, duration: 0.1),
            SKAction.scale(to: 1.0, duration: 0.3)
        ]))
        
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
    }
}

// MARK: - Notification Extension
extension Notification.Name {
    static let snailCaughtPlayer = Notification.Name("snailCaughtPlayer")
}
