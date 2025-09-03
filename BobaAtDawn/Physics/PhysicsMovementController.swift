import SpriteKit

// MARK: - Movement Controller Protocol
protocol MovementController {
    func moveToward(target: CGPoint, deltaTime: TimeInterval)
    func moveToGrid(_ gridPosition: GridCoordinate, completion: (() -> Void)?)
    func stop()
    func setMaxSpeed(_ speed: CGFloat)
    var isMoving: Bool { get }
    var currentTarget: CGPoint? { get }
}

// MARK: - Physics Movement Controller
class PhysicsMovementController: MovementController {
    
    // MARK: - Dependencies
    private let physicsBody: SKPhysicsBody
    internal let gridService: GridService
    
    // MARK: - Movement State
    internal(set) var isMoving: Bool = false
    internal(set) var currentTarget: CGPoint?
    private var gridTarget: GridCoordinate?
    private var completion: (() -> Void)?
    
    // MARK: - Movement Configuration
    private var maxSpeed: CGFloat
    private let acceleration: CGFloat
    private let snapDistance: CGFloat
    
    // MARK: - Grid Snapping
    private let enableGridSnapping: Bool
    private var lastGridPosition: GridCoordinate?
    
    // MARK: - Initialization
    init(physicsBody: SKPhysicsBody,
         gridService: GridService,
         maxSpeed: CGFloat = PhysicsConfig.Character.maxSpeed,
         acceleration: CGFloat = PhysicsConfig.Character.acceleration,
         enableGridSnapping: Bool = true) {
        
        self.physicsBody = physicsBody
        self.gridService = gridService
        self.maxSpeed = maxSpeed
        self.acceleration = acceleration
        self.snapDistance = PhysicsConfig.Character.snapToGridThreshold
        self.enableGridSnapping = enableGridSnapping
        
        print("🏃‍♂️ PhysicsMovementController initialized with max speed: \(maxSpeed)")
    }
    
    // MARK: - Movement Methods
    func moveToward(target: CGPoint, deltaTime: TimeInterval) {
        guard let node = physicsBody.node else { 
            print("⚠️ moveToward: node is nil, cannot move")
            stop()
            return 
        }
        
        currentTarget = target
        isMoving = true
        
        let currentPos = node.position
        let direction = CGPoint(
            x: target.x - currentPos.x,
            y: target.y - currentPos.y
        )
        let distance = sqrt(direction.x * direction.x + direction.y * direction.y)
        
        if distance < 2.0 {
            stop()
            return
        }
        
        let normalizedDirection = CGPoint(
            x: direction.x / distance,
            y: direction.y / distance
        )
        
        let desiredVelocity = CGVector(
            dx: normalizedDirection.x * maxSpeed,
            dy: normalizedDirection.y * maxSpeed
        )
        
        let currentVelocity = physicsBody.velocity
        let velocityChange = CGVector(
            dx: desiredVelocity.dx - currentVelocity.dx,
            dy: desiredVelocity.dy - currentVelocity.dy
        )
        
        let forceMultiplier = acceleration * physicsBody.mass
        let force = CGVector(
            dx: velocityChange.dx * forceMultiplier * CGFloat(deltaTime),
            dy: velocityChange.dy * forceMultiplier * CGFloat(deltaTime)
        )
        
        physicsBody.applyForce(force)
        limitMaximumSpeed()
        
        print("🏃‍♂️ Moving toward \(target), distance: \(String(format: "%.1f", distance))")
    }
    
    func moveToGrid(_ gridPosition: GridCoordinate, completion: (() -> Void)? = nil) {
        guard gridPosition.isValid() else {
            print("❌ Invalid grid position: \(gridPosition)")
            completion?()
            return
        }
        
        let worldTarget = gridService.gridToWorld(gridPosition)
        self.gridTarget = gridPosition
        self.completion = completion
        
        print("🎯 Moving to grid \(gridPosition) = world \(worldTarget)")
        
        currentTarget = worldTarget
        isMoving = true
    }
    
    func stop() {
        // Safety check before accessing physics body
        guard let node = physicsBody.node else {
            print("⚠️ stop: node is nil, using cleanup instead")
            cleanup()
            return
        }
        
        let currentVelocity = physicsBody.velocity
        let dampingForce = CGVector(
            dx: -currentVelocity.dx * physicsBody.linearDamping,
            dy: -currentVelocity.dy * physicsBody.linearDamping
        )
        
        physicsBody.applyForce(dampingForce)
        
        // Use stopInternal to avoid calling handleGridArrival again
        stopInternal()
        
        print("🛑 Movement stopped")
    }
    
    func setMaxSpeed(_ speed: CGFloat) {
        maxSpeed = speed
        print("🏃‍♂️ Max speed updated to \(speed)")
    }
    
    // MARK: - Physics Update
    func update(deltaTime: TimeInterval) {
        guard isMoving, let target = currentTarget else { return }
        guard let node = physicsBody.node else { 
            print("⚠️ PhysicsMovementController.update: node is nil, stopping movement")
            stop()
            return 
        }
        
        moveToward(target: target, deltaTime: deltaTime)
        
        if let gridTarget = gridTarget {
            let currentPos = node.position
            let targetWorldPos = gridService.gridToWorld(gridTarget)
            let distance = sqrt(pow(currentPos.x - targetWorldPos.x, 2) + pow(currentPos.y - targetWorldPos.y, 2))
            
            if distance < snapDistance {
                handleGridArrival(gridTarget)
                self.gridTarget = nil
            }
        }
        
        if enableGridSnapping {
            updateGridSnapping()
        }
        
        limitMaximumSpeed()
    }
    
    // MARK: - Grid Integration
    private func handleGridArrival(_ gridPosition: GridCoordinate) {
        guard let node = physicsBody.node else { 
            print("⚠️ handleGridArrival: node is nil, character may have been deallocated")
            cleanup()
            return 
        }
        
        // Use a safer approach - just try to access the position and catch any issues
        do {
            let exactWorldPosition = gridService.gridToWorld(gridPosition)
            
            // Safely update position within a do-catch equivalent check
            node.position = exactWorldPosition
            physicsBody.velocity = CGVector.zero
            
            print("✅ Arrived at grid \(gridPosition) = world \(exactWorldPosition)")
            
            // Call completion callback safely
            let completionCallback = completion
            completion = nil
            completionCallback?()
            
            lastGridPosition = gridPosition
            
        } catch {
            print("⚠️ Error updating character position: \(error)")
            cleanup()
        }
        
        // Always stop movement to prevent further issues
        stopInternal()
    }
    
    // Safe cleanup method
    private func cleanup() {
        isMoving = false
        currentTarget = nil
        gridTarget = nil
        completion = nil
    }
    
    // Internal stop method that doesn't try to call handleGridArrival
    private func stopInternal() {
        isMoving = false
        currentTarget = nil
        gridTarget = nil
    }
    
    private func updateGridSnapping() {
        guard let node = physicsBody.node else { return }
        
        let currentGridPos = gridService.worldToGrid(node.position)
        if currentGridPos != lastGridPosition {
            lastGridPosition = currentGridPos
            print("📍 Entered grid cell: \(currentGridPos)")
        }
    }
    
    private func limitMaximumSpeed() {
        let velocity = physicsBody.velocity
        let speed = sqrt(velocity.dx * velocity.dx + velocity.dy * velocity.dy)
        
        if speed > maxSpeed {
            let scale = maxSpeed / speed
            physicsBody.velocity = CGVector(
                dx: velocity.dx * scale,
                dy: velocity.dy * scale
            )
        }
    }
    
    // MARK: - Utility Methods
    func getDistanceToTarget() -> CGFloat? {
        guard let target = currentTarget, let node = physicsBody.node else { return nil }
        let currentPos = node.position
        return sqrt(pow(currentPos.x - target.x, 2) + pow(currentPos.y - target.y, 2))
    }
    
    func getCurrentGridPosition() -> GridCoordinate? {
        guard let node = physicsBody.node else { return nil }
        return gridService.worldToGrid(node.position)
    }
    
    func getCurrentSpeed() -> CGFloat {
        let velocity = physicsBody.velocity
        return sqrt(velocity.dx * velocity.dx + velocity.dy * velocity.dy)
    }
    
    // MARK: - Debug Information
    func getDebugInfo() -> String {
        let speed = getCurrentSpeed()
        let gridPos = getCurrentGridPosition() ?? GridCoordinate(x: -1, y: -1)
        let distanceToTarget = getDistanceToTarget() ?? 0
        
        return """
        Movement Debug:
        - Moving: \(isMoving)
        - Speed: \(String(format: "%.1f", speed))/\(String(format: "%.1f", maxSpeed))
        - Grid: \(gridPos)
        - Target Distance: \(String(format: "%.1f", distanceToTarget))
        - Physics Velocity: \(physicsBody.velocity)
        """
    }
    
    // MARK: - External Access Helpers
    @discardableResult
    internal func beginMovement(to target: CGPoint) -> Self {
        self.currentTarget = target
        self.isMoving = true
        return self
    }
    
    internal func setMoving(_ moving: Bool) {
        self.isMoving = moving
        if !moving { self.currentTarget = nil }
    }
    
    @inline(__always) internal func gridToWorld(_ grid: GridCoordinate) -> CGPoint {
        gridService.gridToWorld(grid)
    }
    
    @inline(__always) internal func worldToGrid(_ point: CGPoint) -> GridCoordinate {
        gridService.worldToGrid(point)
    }
}

// MARK: - NPC Movement Controller
class NPCMovementController: PhysicsMovementController {
    
    private let wanderRadius: CGFloat
    private var homePosition: GridCoordinate?
    
    init(physicsBody: SKPhysicsBody,
         gridService: GridService,
         homePosition: GridCoordinate? = nil) {
        
        self.wanderRadius = 120.0
        self.homePosition = homePosition
        
        super.init(
            physicsBody: physicsBody,
            gridService: gridService,
            maxSpeed: PhysicsConfig.NPC.maxSpeed,
            acceleration: PhysicsConfig.NPC.acceleration,
            enableGridSnapping: false
        )
    }
    
    func wanderRandomly() {
        guard let home = homePosition ?? getCurrentGridPosition() else { return }
        let homeWorldPos = gridService.gridToWorld(home)
        
        let angle = Float.random(in: 0...(2 * Float.pi))
        let distance = CGFloat.random(in: 30...wanderRadius)
        
        let randomTarget = CGPoint(
            x: homeWorldPos.x + cos(CGFloat(angle)) * distance,
            y: homeWorldPos.y + sin(CGFloat(angle)) * distance
        )
        
        currentTarget = randomTarget
        isMoving = true
        
        print("🦊 NPC wandering to \(randomTarget)")
    }
    
    func returnToHome() {
        guard let home = homePosition else { return }
        moveToGrid(home)
        print("🦊 NPC returning home to \(home)")
    }
    
    func setHomePosition(_ position: GridCoordinate) {
        homePosition = position
        print("🦊 NPC home position set to \(position)")
    }
}
