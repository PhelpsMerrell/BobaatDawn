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
        print("🐌 [WorldState] Snail ACTIVATED in room \(currentRoom)")
    }
    
    func deactivate() {
        isActive = false
        roomChangeAccumulator = 0
        print("🐌 [WorldState] Snail DEACTIVATED")
    }
    
    // MARK: - Simulated movement (called every frame from GameScene OR ForestScene)
    
    /// Call this when the player is in the SHOP so the snail wanders room-to-room off-screen.
    func simulateWandering(deltaTime: TimeInterval) {
        guard isActive else { return }
        
        roomChangeAccumulator += deltaTime
        if roomChangeAccumulator >= wanderRoomInterval {
            roomChangeAccumulator = 0
            let oldRoom = currentRoom
            // Random adjacent room (wrapping)
            currentRoom = Bool.random() ? nextRoom(from: currentRoom) : previousRoom(from: currentRoom)
            roomPosition = randomRoomPosition()
            print("🐌 [WorldState] Snail wandered: room \(oldRoom) → \(currentRoom)")
        }
    }
    
    /// Call this when the player is in the FOREST but the snail is in a DIFFERENT room.
    /// The snail moves toward the player's room.
    func simulateHunting(towardRoom targetRoom: Int, deltaTime: TimeInterval) {
        guard isActive else { return }
        guard currentRoom != targetRoom else { return } // Already there
        
        roomChangeAccumulator += deltaTime
        if roomChangeAccumulator >= huntRoomInterval {
            roomChangeAccumulator = 0
            let oldRoom = currentRoom
            currentRoom = stepToward(target: targetRoom, from: currentRoom)
            // When entering the player's room, appear from the edge they'd expect
            if currentRoom == targetRoom {
                roomPosition = entryPosition(comingFrom: oldRoom)
            } else {
                roomPosition = randomRoomPosition()
            }
            print("🐌 [WorldState] Snail hunting: room \(oldRoom) → \(currentRoom) (target: \(targetRoom))")
        }
    }
    
    // MARK: - Room navigation helpers
    
    /// One step toward target on the circular 1-2-3-4-5-1 loop, shortest path.
    private func stepToward(target: Int, from current: Int) -> Int {
        guard current != target else { return current }
        
        // Forward distance (1→2→3→4→5→1)
        let forwardDist = (target - current + 5) % 5
        // Backward distance
        let backwardDist = (current - target + 5) % 5
        
        if forwardDist <= backwardDist {
            return nextRoom(from: current)
        } else {
            return previousRoom(from: current)
        }
    }
    
    private func nextRoom(from room: Int) -> Int {
        return room == 5 ? 1 : room + 1
    }
    
    private func previousRoom(from room: Int) -> Int {
        return room == 1 ? 5 : room - 1
    }
    
    /// Random position within a room's playable area
    private func randomRoomPosition() -> CGPoint {
        // Use conservative bounds (forest rooms are ~2000x1500, playable area smaller)
        let x = CGFloat.random(in: -500...500)
        let y = CGFloat.random(in: -400...400)
        return CGPoint(x: x, y: y)
    }
    
    /// When the snail enters the player's room, pick an edge position
    /// based on which room it came from so it appears consistently.
    private func entryPosition(comingFrom previousRoom: Int) -> CGPoint {
        // If it came from a "lower" room number, appear on the left edge.
        // If from a "higher" room number, appear on the right edge.
        // This matches the left=previous, right=next room navigation.
        let fromDirection = stepDirection(from: previousRoom, to: currentRoom)
        
        let edgeX: CGFloat
        switch fromDirection {
        case .fromLeft:
            edgeX = -600  // Left edge of room
        case .fromRight:
            edgeX = 600   // Right edge of room
        }
        
        let randomY = CGFloat.random(in: -300...300)
        return CGPoint(x: edgeX, y: randomY)
    }
    
    private enum EntryDirection { case fromLeft, fromRight }
    
    private func stepDirection(from: Int, to: Int) -> EntryDirection {
        // If "from" is the previous room of "to", snail came from the left
        if nextRoom(from: from) == to {
            return .fromLeft
        } else {
            return .fromRight
        }
    }
}


// MARK: - The Snail Enemy (Visual / Scene Node)
class SnailNPC: SKSpriteNode {
    
    // MARK: - Properties
    private let baseSpeed: CGFloat = 20.0
    private var targetPosition: CGPoint = .zero
    private var isMovingTowardsPlayer: Bool = false
    private var lastDirectionChange: TimeInterval = 0
    private let directionChangeInterval: TimeInterval = 3.0
    
    // References
    private weak var timeService: TimeService?
    
    // Visual state
    private var glowEffect: SKEffectNode?
    
    // MARK: - Initialization
    init(timeService: TimeService) {
        self.timeService = timeService
        
        let texture = SKTexture()
        super.init(texture: texture, color: .clear, size: CGSize(width: 40, height: 40))
        
        setupVisuals()
        setupPhysics()
        
        name = "snail_enemy"
        zPosition = ZLayers.enemies
        
        // Start hidden — visibility controlled by syncWithWorldState
        alpha = 0.0
        isHidden = true
        
        print("🐌 SnailNPC node created")
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Visual Setup
    private func setupVisuals() {
        let snailLabel = SKLabelNode(text: "🐌")
        snailLabel.fontSize = 32
        snailLabel.verticalAlignmentMode = .center
        snailLabel.horizontalAlignmentMode = .center
        snailLabel.zPosition = 1
        addChild(snailLabel)
        
        setupGlowEffect()
        
        let breathe = SKAction.repeatForever(SKAction.sequence([
            SKAction.scale(to: 1.05, duration: 2.0),
            SKAction.scale(to: 0.95, duration: 2.0)
        ]))
        run(breathe, withKey: "snail_breathe")
    }
    
    private func setupGlowEffect() {
        glowEffect = SKEffectNode()
        glowEffect?.shouldRasterize = true
        
        let glowSprite = SKSpriteNode(color: SKColor.purple.withAlphaComponent(0.3), size: CGSize(width: 60, height: 60))
        glowSprite.blendMode = .add
        
        let pulse = SKAction.repeatForever(SKAction.sequence([
            SKAction.fadeAlpha(to: 0.1, duration: 1.5),
            SKAction.fadeAlpha(to: 0.5, duration: 1.5)
        ]))
        glowSprite.run(pulse)
        
        glowEffect?.addChild(glowSprite)
        insertChild(glowEffect!, at: 0)
    }
    
    // MARK: - Physics Setup
    private func setupPhysics() {
        physicsBody = SKPhysicsBody(circleOfRadius: 20)
        physicsBody?.categoryBitMask = PhysicsCategory.snail
        physicsBody?.contactTestBitMask = PhysicsCategory.character
        physicsBody?.collisionBitMask = 0
        physicsBody?.affectedByGravity = false
        physicsBody?.isDynamic = true
        physicsBody?.allowsRotation = false
        physicsBody?.linearDamping = 0.5
    }
    
    // MARK: - Sync with persistent world state
    /// Called every frame by ForestScene. Handles visibility, position, and time activation.
    func syncWithWorldState(playerRoom: Int, playerPosition: CGPoint) {
        let world = SnailWorldState.shared
        
        // Check time activation
        checkTimeActivation()
        
        guard world.isActive else {
            // Not active — stay hidden
            if !isHidden {
                fadeOut()
            }
            return
        }
        
        if world.currentRoom == playerRoom {
            // Snail is in the SAME room as the player — show it and hunt
            if isHidden {
                // Just arrived or just became visible — place at world state position
                position = world.roomPosition
                fadeIn()
            }
            
            // Hunt the player directly
            huntPlayerDirectly(playerPosition: playerPosition)
            isMovingTowardsPlayer = true
            
            // Write position back to world state so it persists if we leave
            world.roomPosition = position
            
        } else {
            // Snail is in a DIFFERENT room — hide it, simulate hunting toward player
            if !isHidden {
                // Was visible, now leaving — save position
                world.roomPosition = position
                fadeOut()
            }
            
            isMovingTowardsPlayer = false
            physicsBody?.velocity = .zero
            
            // Simulate room-to-room hunting
            world.simulateHunting(towardRoom: playerRoom, deltaTime: 1.0/60.0)
        }
        
        // Update glow intensity
        if isMovingTowardsPlayer && !isHidden {
            updateGlowIntensity()
        }
    }
    
    // MARK: - Time Activation
    private func checkTimeActivation() {
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
        let action = SKAction.fadeIn(withDuration: 1.5)
        run(action, withKey: "snail_fade")
        print("🐌 Snail fades into view...")
    }
    
    private func fadeOut() {
        let action = SKAction.sequence([
            SKAction.fadeOut(withDuration: 1.0),
            SKAction.run { [weak self] in
                self?.isHidden = true
            }
        ])
        run(action, withKey: "snail_fade")
    }
    
    // MARK: - Hunting
    private func huntPlayerDirectly(playerPosition: CGPoint) {
        targetPosition = playerPosition
        
        let dx = targetPosition.x - position.x
        let dy = targetPosition.y - position.y
        let distance = sqrt(dx*dx + dy*dy)
        
        guard distance > 10 else { return }
        
        let normalizedDx = dx / distance
        let normalizedDy = dy / distance
        
        physicsBody?.velocity = CGVector(
            dx: normalizedDx * baseSpeed,
            dy: normalizedDy * baseSpeed
        )
        
        if dx > 0 { xScale = 1 }
        else if dx < 0 { xScale = -1 }
    }
    
    // MARK: - Player Contact
    func playerCaught() {
        print("🐌 💀 THE SNAIL HAS CAUGHT YOU!")
        createCatchEffect()
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
    
    // MARK: - Update (legacy — kept for compatibility but real work is in syncWithWorldState)
    func update(deltaTime: TimeInterval) {
        // Time check is handled inside syncWithWorldState now
    }
    
    // MARK: - Glow
    private func updateGlowIntensity() {
        guard let glowEffect = glowEffect,
              let glowSprite = glowEffect.children.first as? SKSpriteNode else { return }
        
        let distanceToTarget = sqrt(
            pow(targetPosition.x - position.x, 2) +
            pow(targetPosition.y - position.y, 2)
        )
        
        let maxDistance: CGFloat = 300
        let intensity = max(0.1, 1.0 - (distanceToTarget / maxDistance))
        glowSprite.alpha = intensity
    }
    
    // MARK: - Debug
    func printStatus() {
        let world = SnailWorldState.shared
        print("🐌 === SNAIL STATUS ===")
        print("🐌 Active: \(world.isActive)")
        print("🐌 World Room: \(world.currentRoom)")
        print("🐌 World Position: \(world.roomPosition)")
        print("🐌 Node Position: \(position)")
        print("🐌 Hidden: \(isHidden)")
        print("🐌 Hunting: \(isMovingTowardsPlayer)")
        print("🐌 ===================")
    }
}

// MARK: - Notification Extension
extension Notification.Name {
    static let snailCaughtPlayer = Notification.Name("snailCaughtPlayer")
}
