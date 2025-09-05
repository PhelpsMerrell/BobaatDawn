//
//  SnailNPC.swift
//  BobaAtDawn
//
//  The mysterious snail that hunts players in the forest at night
//

import SpriteKit

// MARK: - The Snail Enemy
class SnailNPC: SKSpriteNode {
    
    // MARK: - Properties
    private let baseSpeed: CGFloat = 20.0 // 1/5 of normal NPC speed (100)
    private var targetPosition: CGPoint = .zero
    private var isActive: Bool = false
    private var currentRoom: Int = 1
    
    // Movement state
    private var isMovingTowardsPlayer: Bool = false
    private var lastDirectionChange: TimeInterval = 0
    private let directionChangeInterval: TimeInterval = 3.0 // Change direction every 3 seconds when wandering
    
    // References
    private weak var timeService: TimeService?
    private weak var forestScene: ForestScene?
    
    // Visual state
    private var glowEffect: SKEffectNode?
    
    // MARK: - Initialization
    init(timeService: TimeService) {
        self.timeService = timeService
        
        // Create snail sprite - using emoji for now, you can replace with actual sprite
        let texture = SKTexture() // Will be replaced by visual setup
        super.init(texture: texture, color: .clear, size: CGSize(width: 40, height: 40))
        
        setupVisuals()
        setupPhysics()
        
        name = "snail_enemy"
        zPosition = ZLayers.enemies
        
        // Start invisible - only appears at night
        alpha = 0.0
        isHidden = true
        
        print("🐌 The Snail has awakened...")
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Visual Setup
    private func setupVisuals() {
        // Create snail emoji sprite (replace with actual art later)
        let snailLabel = SKLabelNode(text: "🐌")
        snailLabel.fontSize = 32
        snailLabel.verticalAlignmentMode = .center
        snailLabel.horizontalAlignmentMode = .center
        snailLabel.zPosition = 1
        addChild(snailLabel)
        
        // Add eerie glow effect
        setupGlowEffect()
        
        // Add subtle breathing animation
        let breathe = SKAction.sequence([
            SKAction.scale(to: 1.05, duration: 2.0),
            SKAction.scale(to: 0.95, duration: 2.0)
        ])
        let breatheForever = SKAction.repeatForever(breathe)
        run(breatheForever, withKey: "snail_breathe")
    }
    
    private func setupGlowEffect() {
        // Create an eerie glow around the snail
        glowEffect = SKEffectNode()
        glowEffect?.shouldRasterize = true
        
        let glowSprite = SKSpriteNode(color: SKColor.purple.withAlphaComponent(0.3), size: CGSize(width: 60, height: 60))
        glowSprite.blendMode = .add
        
        // Add pulsing glow animation
        let pulse = SKAction.sequence([
            SKAction.fadeAlpha(to: 0.1, duration: 1.5),
            SKAction.fadeAlpha(to: 0.5, duration: 1.5)
        ])
        let pulseForever = SKAction.repeatForever(pulse)
        glowSprite.run(pulseForever)
        
        glowEffect?.addChild(glowSprite)
        insertChild(glowEffect!, at: 0)
    }
    
    // MARK: - Physics Setup
    private func setupPhysics() {
        physicsBody = SKPhysicsBody(circleOfRadius: 20)
        physicsBody?.categoryBitMask = PhysicsCategory.snail
        physicsBody?.contactTestBitMask = PhysicsCategory.character
        physicsBody?.collisionBitMask = 0 // Ghost through everything except player detection
        physicsBody?.affectedByGravity = false
        physicsBody?.isDynamic = true
        physicsBody?.allowsRotation = false
        physicsBody?.linearDamping = 0.5
        
        print("🐌 Snail physics configured for player detection")
    }
    
    // MARK: - Scene Registration
    func registerWithForestScene(_ scene: ForestScene) {
        self.forestScene = scene
        print("🐌 Snail registered with forest scene")
    }
    
    // MARK: - Time-Based Activation
    func checkTimeActivation() {
        guard let timeService = timeService else { return }
        
        let shouldBeActive = timeService.currentPhase == .night
        
        if shouldBeActive && !isActive {
            activateSnail()
        } else if !shouldBeActive && isActive {
            deactivateSnail()
        }
    }
    
    private func activateSnail() {
        isActive = true
        isHidden = false
        
        // Spawn in a random forest room (1-5)
        currentRoom = Int.random(in: 1...5)
        
        // Fade in with eerie effect
        let fadeIn = SKAction.sequence([
            SKAction.fadeIn(withDuration: 2.0),
            SKAction.run { [weak self] in
                self?.startHunting()
            }
        ])
        
        run(fadeIn)
        
        print("🐌 The Snail emerges in the night... (Room \(currentRoom))")
    }
    
    private func deactivateSnail() {
        isActive = false
        
        // Fade out and hide
        let fadeOut = SKAction.sequence([
            SKAction.fadeOut(withDuration: 2.0),
            SKAction.run { [weak self] in
                self?.isHidden = true
                self?.stopHunting()
            }
        ])
        
        run(fadeOut)
        
        print("🐌 The Snail retreats with the dawn...")
    }
    
    // MARK: - Hunting Behavior
    private func startHunting() {
        guard isActive else { return }
        
        // Start the hunting pattern
        scheduleNextMovement()
        
        print("🐌 The Snail begins its relentless pursuit...")
    }
    
    private func stopHunting() {
        removeAction(forKey: "snail_movement")
        removeAction(forKey: "snail_hunt")
        isMovingTowardsPlayer = false
    }
    
    func updateHuntingBehavior(playerInForest: Bool, playerRoom: Int = 1, playerPosition: CGPoint = .zero) {
        guard isActive else { return }
        
        if playerInForest {
            // Player is in forest - hunt them!
            if playerRoom == currentRoom {
                // Same room - move directly towards player
                huntPlayerDirectly(playerPosition: playerPosition)
            } else {
                // Different room - move towards their room
                moveTowardsPlayerRoom(playerRoom)
            }
        } else {
            // Player is in shop - wander randomly
            wanderRandomly()
        }
    }
    
    private func huntPlayerDirectly(playerPosition: CGPoint) {
        isMovingTowardsPlayer = true
        targetPosition = playerPosition
        
        // Calculate direction to player
        let dx = targetPosition.x - position.x
        let dy = targetPosition.y - position.y
        let distance = sqrt(dx*dx + dy*dy)
        
        if distance > 10 { // Don't micro-adjust when very close
            // Move towards player at snail speed
            let normalizedDx = dx / distance
            let normalizedDy = dy / distance
            
            let velocity = CGVector(
                dx: normalizedDx * baseSpeed,
                dy: normalizedDy * baseSpeed
            )
            
            physicsBody?.velocity = velocity
            
            // Face the direction of movement
            if dx > 0 {
                xScale = 1
            } else if dx < 0 {
                xScale = -1
            }
        }
        
        // Schedule next hunt update
        let huntUpdate = SKAction.sequence([
            SKAction.wait(forDuration: 0.1), // Update 10 times per second
            SKAction.run { [weak self] in
                // This will be called again by the scene
            }
        ])
        
        run(huntUpdate, withKey: "snail_hunt")
    }
    
    private func moveTowardsPlayerRoom(_ playerRoom: Int) {
        // Move towards the exit to get to player's room
        // This is a simplified version - in a real game you'd pathfind through rooms
        
        if currentRoom != playerRoom {
            // For now, just move towards a direction that would take us to the player's room
            let roomDifference = playerRoom - currentRoom
            
            // Move in a direction based on room difference
            let moveDirection: CGPoint
            if roomDifference > 0 {
                // Move "forward" through rooms
                moveDirection = CGPoint(x: 1, y: 0)
            } else {
                // Move "backward" through rooms
                moveDirection = CGPoint(x: -1, y: 0)
            }
            
            let velocity = CGVector(
                dx: moveDirection.x * baseSpeed * 0.7, // Slower when changing rooms
                dy: moveDirection.y * baseSpeed * 0.7
            )
            
            physicsBody?.velocity = velocity
            
            // Chance to change rooms
            if Int.random(in: 1...100) <= 5 { // 5% chance per update
                currentRoom = playerRoom
                print("🐌 The Snail has moved to room \(currentRoom)")
            }
        }
    }
    
    private func wanderRandomly() {
        isMovingTowardsPlayer = false
        
        let currentTime = CACurrentMediaTime()
        
        // Change direction every few seconds
        if currentTime - lastDirectionChange > directionChangeInterval {
            lastDirectionChange = currentTime
            
            // Pick a random direction
            let angle = CGFloat.random(in: 0...(2 * .pi))
            let wanderSpeed = baseSpeed * 0.5 // Even slower when wandering
            
            targetPosition = CGPoint(
                x: position.x + cos(angle) * 100,
                y: position.y + sin(angle) * 100
            )
            
            let velocity = CGVector(
                dx: cos(angle) * wanderSpeed,
                dy: sin(angle) * wanderSpeed
            )
            
            physicsBody?.velocity = velocity
            
            // Face movement direction
            if cos(angle) > 0 {
                xScale = 1
            } else {
                xScale = -1
            }
        }
    }
    
    private func scheduleNextMovement() {
        let moveUpdate = SKAction.sequence([
            SKAction.wait(forDuration: 0.2), // Update 5 times per second
            SKAction.run { [weak self] in
                if self?.isActive == true {
                    self?.scheduleNextMovement()
                }
            }
        ])
        
        run(moveUpdate, withKey: "snail_movement")
    }
    
    // MARK: - Player Contact
    func playerCaught() {
        print("🐌 💀 THE SNAIL HAS CAUGHT YOU!")
        
        // Create dramatic catch effect
        createCatchEffect()
        
        // Notify the scene to teleport player
        NotificationCenter.default.post(
            name: .snailCaughtPlayer,
            object: self
        )
    }
    
    private func createCatchEffect() {
        // Screen flash effect
        let flashNode = SKSpriteNode(color: .red, size: CGSize(width: 2000, height: 2000))
        flashNode.alpha = 0
        flashNode.zPosition = 1000
        parent?.addChild(flashNode)
        
        let flash = SKAction.sequence([
            SKAction.fadeIn(withDuration: 0.1),
            SKAction.fadeOut(withDuration: 0.3),
            SKAction.removeFromParent()
        ])
        flashNode.run(flash)
        
        // Snail grows larger momentarily
        let grow = SKAction.sequence([
            SKAction.scale(to: 1.5, duration: 0.1),
            SKAction.scale(to: 1.0, duration: 0.3)
        ])
        run(grow)
        
        // Haptic feedback
        let impactFeedback = UIImpactFeedbackGenerator(style: .heavy)
        impactFeedback.impactOccurred()
    }
    
    // MARK: - Update
    func update(deltaTime: TimeInterval) {
        // Check if should be active based on time
        checkTimeActivation()
        
        // Update glow intensity based on proximity to player (if tracking)
        if isMovingTowardsPlayer {
            updateGlowIntensity()
        }
    }
    
    private func updateGlowIntensity() {
        // Make glow more intense when closer to player
        guard let glowEffect = glowEffect,
              let glowSprite = glowEffect.children.first as? SKSpriteNode else { return }
        
        let distanceToTarget = sqrt(
            pow(targetPosition.x - position.x, 2) +
            pow(targetPosition.y - position.y, 2)
        )
        
        // Closer = more intense glow
        let maxDistance: CGFloat = 300
        let intensity = max(0.1, 1.0 - (distanceToTarget / maxDistance))
        glowSprite.alpha = intensity
    }
    
    // MARK: - Debug
    func printStatus() {
        print("🐌 === SNAIL STATUS ===")
        print("🐌 Active: \(isActive)")
        print("🐌 Room: \(currentRoom)")
        print("🐌 Hunting Player: \(isMovingTowardsPlayer)")
        print("🐌 Position: \(position)")
        print("🐌 Target: \(targetPosition)")
        print("🐌 ===================")
    }
}

// MARK: - Notification Extension
extension Notification.Name {
    static let snailCaughtPlayer = Notification.Name("snailCaughtPlayer")
}
