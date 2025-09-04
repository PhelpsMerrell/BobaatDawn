// MARK: - Movement Configuration
struct MovementConfig {
    static let usePhysicsMovement = false  // DISABLE PHYSICS - use simple SKAction movement
    static let debugMovement = false      // Disabled for immersion
    static let simplifiedMovement = true  // NEW: Bypass complex pathfinding for responsiveness
    static let directMovement = true      // NEW: Move directly to tapped location when possible
}//
//  Character.swift
//  BobaAtDawn
//
//  Created by Phelps Merrell on 8/18/25.
//

import SpriteKit

class Character: SKSpriteNode {
    
    // MARK: - Properties
    private(set) var carriedItem: RotatableObject?
    private let carryOffset: CGFloat = GameConfig.Character.carryOffset
    
    // MARK: - Dependencies
    private let gridService: GridService
    private var animationService: AnimationService?
    
    // MARK: - Physics Movement Controller
    // Lazy so it can safely use self.physicsBody AFTER setupPhysicsBody() runs.
    private lazy var movementController: PhysicsMovementController = { [unowned self] in
        guard let body = self.physicsBody else {
            fatalError("Character physics body is nil; call setupPhysicsBody() before accessing movementController.")
        }
        return PhysicsMovementController(
            physicsBody: body,
            gridService: gridService
        )
    }()
    
    private var lastGridPosition: GridCoordinate
    private var targetWorldPosition: CGPoint?
    
    // Grid properties
    private var gridPosition: GridCoordinate {
        return gridService.currentCharacterPosition
    }
    
    var isCarrying: Bool {
        return carriedItem != nil
    }
    
    // MARK: - Physics Properties
    var isMoving: Bool {
        return movementController.isMoving
    }
    
    var currentSpeed: CGFloat {
        return movementController.getCurrentSpeed()
    }
    
    // MARK: - Initialization
    init(gridService: GridService, animationService: AnimationService? = nil) {
        self.gridService = gridService
        self.animationService = animationService
        
        // Initialize grid tracking before super.init
        let startCell = GameConfig.Grid.characterStartPosition
        self.lastGridPosition = startCell
        
        super.init(texture: nil, color: GameConfig.Character.color, size: GameConfig.Character.size)
        
        name = "character"
        zPosition = ZLayers.character
        
        // Set up physics body BEFORE any movementController access
        setupPhysicsBody()
        
        // Position character at grid center
        position = gridService.gridToWorld(startCell)
        gridService.moveCharacterTo(startCell)
        
        print("👤 Character initialized with physics at grid \(startCell), world \(position)")
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Physics Setup
    private func setupPhysicsBody() {
        let body = PhysicsBodyFactory.createCharacterBody()
        self.physicsBody = body // SpriteKit sets body.node automatically
        
        // Verify the physics body was set correctly
        if physicsBody != nil {
            print("⚡ Character physics body created successfully")
        } else {
            print("❌ ERROR: Failed to create character physics body")
        }
        
        // Verify the node reference is correct
        if physicsBody?.node === self {
            print("⚡ Physics body node reference correct")
        } else {
            print("❌ WARNING: Physics body node reference may be incorrect")
        }
    }
    
    // MARK: - Touch/Input Handling
    func handleTouchMovement(to worldPosition: CGPoint) {
        if MovementConfig.directMovement {
            // DIRECT MOVEMENT: Move immediately to tapped location without grid constraints
            moveDirectlyTo(worldPosition)
        } else if MovementConfig.usePhysicsMovement {
            // Physics-based movement - smooth, no grid constraints
            moveToward(worldPosition)
        } else {
            // SIMPLIFIED: Basic grid movement without complex pathfinding
            let gridPosition = gridService.worldToGrid(worldPosition)
            if gridPosition.isValid() {
                if gridService.isCellAvailable(gridPosition) {
                    moveToGridWithAction(gridPosition)
                } else if MovementConfig.simplifiedMovement {
                    // Just try to move to the nearest available cell, no complex pathfinding
                    if let nearestCell = gridService.findNearestAvailableCell(to: gridPosition, maxRadius: 2) {
                        moveToGridWithAction(nearestCell)
                    }
                }
            }
        }
    }
    
    // MARK: - Direct Movement (NEW - Most Responsive)
    private func moveDirectlyTo(_ worldPosition: CGPoint) {
        // Stop any current movement
        removeAction(forKey: "character_movement")
        
        // Calculate movement duration based on distance
        let distance = sqrt(pow(worldPosition.x - position.x, 2) + pow(worldPosition.y - position.y, 2))
        let duration = max(0.1, min(0.4, TimeInterval(distance / 400))) // Very fast movement
        
        // Create smooth movement action
        let moveAction = SKAction.move(to: worldPosition, duration: duration)
        moveAction.timingMode = .easeOut
        
        // Add completion action for feedback
        let completionAction = SKAction.run {
            // Update carried item position after movement
            self.updateCarriedItemPosition()
            
            // Update grid service with new position
            let finalGridPos = self.gridService.worldToGrid(self.position)
            if finalGridPos.isValid() {
                self.gridService.moveCharacterTo(finalGridPos)
            }
            
            // Very subtle haptic feedback
            self.triggerArrivalFeedback()
        }
        
        let sequenceAction = SKAction.sequence([moveAction, completionAction])
        run(sequenceAction, withKey: "character_movement")
        
        print("🏃‍♂️ Character moving directly to \(worldPosition) in \(String(format: "%.2f", duration))s")
    }
    
    // MARK: - Haptic Feedback (Immersive)
    private func triggerPathfindingFeedback() {
        // Light selection haptic for successful smart pathfinding
        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
        impactFeedback.impactOccurred()
    }
    
    private func triggerFallbackFeedback() {
        // Medium selection haptic for fallback pathfinding
        let selectionFeedback = UISelectionFeedbackGenerator()
        selectionFeedback.selectionChanged()
    }
    
    private func triggerBlockedFeedback() {
        // Error haptic for completely blocked path
        let notificationFeedback = UINotificationFeedbackGenerator()
        notificationFeedback.notificationOccurred(.error)
    }
    
    private func triggerCollisionFeedback() {
        // Very light haptic for minor collision
        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
        impactFeedback.impactOccurred(intensity: 0.5)  // 50% intensity
    }
    
    private func triggerArrivalFeedback() {
        // Very subtle haptic for successful movement arrival
        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
        impactFeedback.impactOccurred(intensity: 0.3)  // 30% intensity - barely noticeable
    }
    private func findAndMoveToNearestAvailable(target: GridCoordinate) {
        let currentPos = gridService.worldToGrid(position)
        
        // Try to find a path around the obstacle
        if let nearestCell = findPathAroundObstacle(from: currentPos, to: target) {
            moveToGridWithAction(nearestCell)
            if MovementConfig.debugMovement {
                print("🧮 Smart pathfinding: Moving to \(nearestCell) to get closer to \(target)")
            }
            // Subtle haptic for successful pathfinding
            triggerPathfindingFeedback()
            
        } else {
            // Fallback: just find any nearby available cell
            if let fallbackCell = gridService.findNearestAvailableCell(to: target, maxRadius: 5) {
                moveToGridWithAction(fallbackCell)
                if MovementConfig.debugMovement {
                    print("🧮 Fallback pathfinding: Moving to \(fallbackCell) near \(target)")
                }
                // Light haptic for fallback pathfinding
                triggerFallbackFeedback()
                
            } else {
                // Show subtle "can't reach" feedback - gentle shake + haptic
                let gentleShake = SKAction.sequence([
                    SKAction.moveBy(x: 2, y: 0, duration: 0.04),
                    SKAction.moveBy(x: -4, y: 0, duration: 0.08),
                    SKAction.moveBy(x: 2, y: 0, duration: 0.04)
                ])
                run(gentleShake)
                
                // Error haptic for blocked path
                triggerBlockedFeedback()
                
                if MovementConfig.debugMovement {
                    print("🧮 ❌ Cannot reach target \(target) - no path available")
                }
            }
        }
    }
    
    private func findPathAroundObstacle(from start: GridCoordinate, to target: GridCoordinate) -> GridCoordinate? {
        // Simple pathfinding: try adjacent cells that get us closer to target
        let adjacentCells = start.adjacentCells
        
        // Filter available cells and sort by distance to target
        let availableCells = adjacentCells
            .filter { gridService.isCellAvailable($0) && $0.isValid() }
            .sorted { cell1, cell2 in
                let dist1 = cell1.distance(to: target)
                let dist2 = cell2.distance(to: target)
                return dist1 < dist2
            }
        
        // Return the best available cell (closest to target)
        return availableCells.first
    }
    
    // MARK: - Fallback Movement (SKAction-based)
    private func moveToGridWithAction(_ targetCell: GridCoordinate) {
        guard targetCell.isValid() else {
            print("❌ Invalid target cell: \(targetCell)")
            return
        }
        
        guard gridService.isCellAvailable(targetCell) else {
            if MovementConfig.debugMovement {
                print("❌ Cell \(targetCell) is occupied - collision detected!")
            }
            // Subtle collision feedback - tiny shake + light haptic
            let subtleShake = SKAction.sequence([
                SKAction.moveBy(x: 1, y: 0, duration: 0.03),
                SKAction.moveBy(x: -2, y: 0, duration: 0.06),
                SKAction.moveBy(x: 1, y: 0, duration: 0.03)
            ])
            run(subtleShake)
            
            // Light haptic for collision
            triggerCollisionFeedback()
            
            return
        }
        
        // Update grid state
        gridService.moveCharacterTo(targetCell)
        
        // Use SKAction for movement (the old reliable way)
        let targetWorldPos = gridService.gridToWorld(targetCell)
        let distance = sqrt(pow(targetWorldPos.x - position.x, 2) + pow(targetWorldPos.y - position.y, 2))
        let duration = max(0.15, min(0.6, TimeInterval(distance / 300)))
        
        let moveAction = SKAction.move(to: targetWorldPos, duration: duration)
        moveAction.timingMode = .easeOut
        
        // Add completion action
        let completionAction = SKAction.run {
            if MovementConfig.debugMovement {
                print("✅ Character arrived at grid \(targetCell) via SKAction")
            }
            // Very subtle haptic on successful arrival
            self.triggerArrivalFeedback()
        }
        
        let sequenceAction = SKAction.sequence([moveAction, completionAction])
        
        removeAction(forKey: "character_movement")
        run(sequenceAction, withKey: "character_movement")
        
        print("👤 Character moving to grid \(targetCell) via SKAction")
    }
    
    // MARK: - Physics Movement Methods
    func moveToward(_ worldPosition: CGPoint) {
        targetWorldPosition = worldPosition
        movementController.setMoving(true)  // FIXED: Ensure movement state is set
        print("🏃‍♂️ Character moving toward world position \(worldPosition)")
    }
    
    func stop() {
        targetWorldPosition = nil
        movementController.stop()
        print("🛑 Character stopped")
    }
    
    func setMaxSpeed(_ speed: CGFloat) {
        movementController.setMaxSpeed(speed)
    }
    
    // MARK: - Grid Movement (Physics-Based)
    func moveToGridCell(_ targetCell: GridCoordinate) {
        guard targetCell.isValid() else {
            print("❌ Invalid target cell: \(targetCell)")
            return
        }
        
        guard gridService.isCellAvailable(targetCell) else {
            print("❌ Cell \(targetCell) is occupied")
            return
        }
        
        // Update grid state
        gridService.moveCharacterTo(targetCell)
        
        // Use physics-based movement instead of SKAction
        movementController.moveToGrid(targetCell) { [weak self] in
            self?.handleGridArrival(targetCell)
        }
        
        print("👤 Character moving with physics to grid \(targetCell)")
    }
    
    // Convenience method for backward compatibility
    func moveToGrid(_ targetCell: GridCoordinate) {
        moveToGridCell(targetCell)
    }
    
    private func handleGridArrival(_ gridPosition: GridCoordinate) {
        print("✅ Character arrived at grid \(gridPosition)")
        updateCarriedItemPosition()
    }
    
    // MARK: - Item Management
    func pickupItem(_ item: RotatableObject) {
        guard carriedItem == nil else { return }
        guard item.canBeCarried else { return } // Only pick up small items
        
        carriedItem = item
        item.removeFromParent()
        
        // Add to character's parent (the scene)
        parent?.addChild(item)
        
        // Position above head
        updateCarriedItemPosition()
        
        // Floating animation
        if let animationService = animationService {
            let floatAction = animationService.carriedItemFloat(item)
            animationService.run(floatAction, on: item, withKey: AnimationKeys.carriedFloat, completion: nil)
        } else {
            let floatAction = SKAction.repeatForever(
                SKAction.sequence([
                    SKAction.moveBy(x: 0, y: GameConfig.Character.floatDistance, duration: GameConfig.Character.floatDuration),
                    SKAction.moveBy(x: 0, y: -GameConfig.Character.floatDistance, duration: GameConfig.Character.floatDuration)
                ])
            )
            item.run(floatAction, withKey: "floating")
        }
        item.zPosition = ZLayers.carriedItems
    }
    
    func dropItem() {
        guard let item = carriedItem else { return }
        
        // Stop floating animation
        if let animationService = animationService {
            animationService.stopAnimation(item, withKey: AnimationKeys.carriedFloat)
        } else {
            item.removeAction(forKey: "floating")
        }
        
        // Grid-based dropping
        let currentCell = gridService.currentCharacterPosition
        let adjacentCells = gridService.getAvailableAdjacentCells(to: currentCell)
        
        if let targetCell = adjacentCells.first {
            // Create GameObject and occupy cell
            let gameObject = GameObject(skNode: item, gridPosition: targetCell, objectType: item.objectType, gridService: gridService)
            gridService.occupyCell(targetCell, with: gameObject)
            
            // Smooth drop
            let worldPos = gridService.gridToWorld(targetCell)
            let distance = sqrt(pow(worldPos.x - item.position.x, 2) + pow(worldPos.y - item.position.y, 2))
            let dropDuration = max(0.2, min(0.5, TimeInterval(distance / 400)))
            
            let dropAction = SKAction.move(to: worldPos, duration: dropDuration)
            dropAction.timingMode = .easeOut
            item.run(dropAction)
            
            print("📦 Dropped \(item.objectType) fluidly at grid \(targetCell)")
        } else {
            // Fallback: drop at character position
            let dropPosition = CGPoint(x: position.x, y: position.y - 30)
            let dropAction = SKAction.move(to: dropPosition, duration: 0.3)
            dropAction.timingMode = .easeOut
            item.run(dropAction)
            
            print("📦 Dropped \(item.objectType) at character position (no grid cells available)")
        }
        
        item.zPosition = ZLayers.groundObjects
        carriedItem = nil
    }
    
    func dropItemSilently() {
        guard let item = carriedItem else { return }
        
        if let animationService = animationService {
            animationService.stopAnimation(item, withKey: AnimationKeys.carriedFloat)
        } else {
            item.removeAction(forKey: "floating")
        }
        
        item.removeFromParent()
        carriedItem = nil
        print("📦 Silently removed carried item")
    }
    
    func rotateCarriedItem() {
        if let item = carriedItem, item.isRotatable {
            item.rotateToNextState()
        }
    }
    
    private func updateCarriedItemPosition() {
        guard let item = carriedItem else { return }
        item.position = CGPoint(x: position.x, y: position.y + carryOffset)
    }
    
    // MARK: - Update
    func update(deltaTime: TimeInterval) {
        if MovementConfig.usePhysicsMovement {
            // Physics-based update
            updatePhysicsMovement(deltaTime: deltaTime)
        } else {
            // Simple update for SKAction-based movement
            updateCarriedItemPosition()
        }
    }
    
    private func updatePhysicsMovement(deltaTime: TimeInterval) {
        // Safety check: ensure physics body still exists
        guard physicsBody != nil else {
            print("⚠️ Character.update: physics body is nil, skipping physics update")
            // Still update carried items
            if isCarrying {
                updateCarriedItemPosition()
            }
            return
        }
        
        // Free movement toward world position (touch input)
        if let target = targetWorldPosition {
            movementController.moveToward(target: target, deltaTime: deltaTime)
        }
        
        // Update physics controller
        movementController.update(deltaTime: deltaTime)
        
        // Keep carried item positioned
        if isCarrying {
            updateCarriedItemPosition()
        }
        
        // Update grid position tracking
        updateGridPositionTracking()
    }
    
    private func updateGridPositionTracking() {
        // Only update grid position when character stops moving (for physics mode)
        if !isMoving {
            let currentWorldPos = position
            let newGridPos = gridService.worldToGrid(currentWorldPos)
            if newGridPos != lastGridPosition && newGridPos.isValid() {
                // Only update if significantly different to avoid jitter
                let distance = sqrt(pow(Float(newGridPos.x - lastGridPosition.x), 2) + pow(Float(newGridPos.y - lastGridPosition.y), 2))
                if distance >= 1.0 {
                    lastGridPosition = newGridPos
                    // Don't constantly update gridService in physics mode - let physics handle position
                    if !MovementConfig.usePhysicsMovement {
                        gridService.moveCharacterTo(newGridPos)
                    }
                }
            }
        }
    }
    
    // MARK: - Physics Integration
    func applyImpulse(_ impulse: CGVector) {
        physicsBody?.applyImpulse(impulse)
        print("💥 Applied impulse to character: \(impulse)")
    }
    
    func getPhysicsVelocity() -> CGVector {
        return physicsBody?.velocity ?? .zero
    }
    
    func getCurrentGridPosition() -> GridCoordinate {
        return movementController.getCurrentGridPosition() ?? lastGridPosition
    }
}
