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
    
    // MARK: - Simulated movement (called every frame from GameScene OR ForestScene)
    
    /// Call this when the player is in the SHOP so the snail wanders room-to-room off-screen.
    func simulateWandering(deltaTime: TimeInterval) {
        guard isActive else { return }
        
        roomChangeAccumulator += deltaTime
        if roomChangeAccumulator >= wanderRoomInterval {
            roomChangeAccumulator = 0
            let oldRoom = currentRoom
            currentRoom = Bool.random() ? nextRoom(from: currentRoom) : previousRoom(from: currentRoom)
            roomPosition = randomRoomPosition()
            Log.debug(.forest, "Snail wandered: room \(oldRoom) -> \(currentRoom)")
        }
    }
    
    /// Call this when the player is in the FOREST but the snail is in a DIFFERENT room.
    /// The snail moves toward the player's room. `playerPosition` is used to ensure
    /// the snail enters on the opposite side from the player if it reaches their room.
    func simulateHunting(towardRoom targetRoom: Int, playerPosition: CGPoint, deltaTime: TimeInterval) {
        guard isActive else { return }
        guard currentRoom != targetRoom else { return }
        
        roomChangeAccumulator += deltaTime
        if roomChangeAccumulator >= huntRoomInterval {
            roomChangeAccumulator = 0
            let oldRoom = currentRoom
            currentRoom = stepToward(target: targetRoom, from: currentRoom)
            if currentRoom == targetRoom {
                // Entering the player's room — spawn opposite the player
                roomPosition = entryPosition(playerPosition: playerPosition)
            } else {
                roomPosition = randomRoomPosition()
            }
            Log.debug(.forest, "Snail hunting: room \(oldRoom) -> \(currentRoom) (target: \(targetRoom))")
        }
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
    private let baseSpeed: CGFloat = 20.0
    private var targetPosition: CGPoint = .zero
    private var isMovingTowardsPlayer: Bool = false
    
    private weak var timeService: TimeService?
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
        
        alpha = 0.0
        isHidden = true
        
        Log.debug(.forest, "SnailNPC node created")
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Visual Setup
    private func setupVisuals() {
        let snailLabel = SKLabelNode(text: "\u{1F40C}")
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
    func syncWithWorldState(playerRoom: Int, playerPosition: CGPoint) {
        let world = SnailWorldState.shared
        
        checkTimeActivation()
        
        guard world.isActive else {
            if !isHidden { fadeOut() }
            return
        }
        
        if world.currentRoom == playerRoom {
            if isHidden {
                position = world.roomPosition
                fadeIn()
            }
            
            huntPlayerDirectly(playerPosition: playerPosition)
            isMovingTowardsPlayer = true
            world.roomPosition = position
            
        } else {
            if !isHidden {
                world.roomPosition = position
                fadeOut()
            }
            
            isMovingTowardsPlayer = false
            physicsBody?.velocity = .zero
            
            if !MultiplayerService.shared.isGuest {
                world.simulateHunting(towardRoom: playerRoom, playerPosition: playerPosition, deltaTime: 1.0/60.0)
            }
        }
        
        if isMovingTowardsPlayer && !isHidden {
            updateGlowIntensity()
        }
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
    
    // MARK: - Update (legacy)
    func update(deltaTime: TimeInterval) { }
    
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
}

// MARK: - Notification Extension
extension Notification.Name {
    static let snailCaughtPlayer = Notification.Name("snailCaughtPlayer")
}
