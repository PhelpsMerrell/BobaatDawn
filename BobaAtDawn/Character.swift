//
//  Character.swift
//  BobaAtDawn
//
//  Created by Phelps Merrell on 8/18/25.
//

import SpriteKit
import GameplayKit

class Character: SKSpriteNode {
    
    // MARK: - Properties
    private(set) var carriedItem: RotatableObject?
    private let moveSpeed: CGFloat = 200
    private let carryOffset: CGFloat = 80
    
    // Pathfinding properties
    private var pathfindingGraph: GKObstacleGraph<GKGraphNode2D>?
    private var currentPath: [GKGraphNode2D] = []
    private var currentPathIndex: Int = 0
    private var isMoving: Bool = false
    
    var isCarrying: Bool {
        return carriedItem != nil
    }
    
    // MARK: - Initialization
    init() {
        super.init(texture: nil, color: SKColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1.0), size: CGSize(width: 40, height: 60))
        
        name = "character"
        zPosition = 10
        
        setupPhysics()
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupPhysics() {
        physicsBody = SKPhysicsBody(rectangleOf: size)
        physicsBody?.isDynamic = true
        physicsBody?.categoryBitMask = 2
        physicsBody?.collisionBitMask = 1
        physicsBody?.contactTestBitMask = 1
        physicsBody?.affectedByGravity = false
        physicsBody?.allowsRotation = false
    }
    
    // MARK: - Pathfinding Setup
    func setupPathfinding(with obstacles: [RotatableObject], worldBounds: CGRect) {
        // Convert SKSpriteNodes to GKPolygonObstacles
        var gkObstacles: [GKPolygonObstacle] = []
        
        // Add table obstacles
        for obstacle in obstacles {
            let obstacleSize = obstacle.size
            let obstaclePos = obstacle.position
            
            // Create slightly larger obstacle bounds for better pathfinding
            let padding: Float = 20.0
            let points = [
                vector_float2(Float(obstaclePos.x - obstacleSize.width/2 - CGFloat(padding)), 
                             Float(obstaclePos.y - obstacleSize.height/2 - CGFloat(padding))),
                vector_float2(Float(obstaclePos.x + obstacleSize.width/2 + CGFloat(padding)), 
                             Float(obstaclePos.y - obstacleSize.height/2 - CGFloat(padding))),
                vector_float2(Float(obstaclePos.x + obstacleSize.width/2 + CGFloat(padding)), 
                             Float(obstaclePos.y + obstacleSize.height/2 + CGFloat(padding))),
                vector_float2(Float(obstaclePos.x - obstacleSize.width/2 - CGFloat(padding)), 
                             Float(obstaclePos.y + obstacleSize.height/2 + CGFloat(padding)))
            ]
            
            let polygonObstacle = GKPolygonObstacle(points: points)
            gkObstacles.append(polygonObstacle)
        }
        
        // Add world boundary obstacles
        let boundaryPadding: Float = 50.0
        let worldLeft = Float(worldBounds.minX + CGFloat(boundaryPadding))
        let worldRight = Float(worldBounds.maxX - CGFloat(boundaryPadding))
        let worldBottom = Float(worldBounds.minY + CGFloat(boundaryPadding))
        let worldTop = Float(worldBounds.maxY - CGFloat(boundaryPadding))
        
        // Top wall
        let topWall = GKPolygonObstacle(points: [
            vector_float2(worldLeft, worldTop),
            vector_float2(worldRight, worldTop),
            vector_float2(worldRight, worldTop + 100),
            vector_float2(worldLeft, worldTop + 100)
        ])
        gkObstacles.append(topWall)
        
        // Bottom wall
        let bottomWall = GKPolygonObstacle(points: [
            vector_float2(worldLeft, worldBottom - 100),
            vector_float2(worldRight, worldBottom - 100),
            vector_float2(worldRight, worldBottom),
            vector_float2(worldLeft, worldBottom)
        ])
        gkObstacles.append(bottomWall)
        
        // Left wall
        let leftWall = GKPolygonObstacle(points: [
            vector_float2(worldLeft - 100, worldBottom),
            vector_float2(worldLeft, worldBottom),
            vector_float2(worldLeft, worldTop),
            vector_float2(worldLeft - 100, worldTop)
        ])
        gkObstacles.append(leftWall)
        
        // Right wall
        let rightWall = GKPolygonObstacle(points: [
            vector_float2(worldRight, worldBottom),
            vector_float2(worldRight + 100, worldBottom),
            vector_float2(worldRight + 100, worldTop),
            vector_float2(worldRight, worldTop)
        ])
        gkObstacles.append(rightWall)
        
        // Create the pathfinding graph
        pathfindingGraph = GKObstacleGraph(obstacles: gkObstacles, bufferRadius: 30.0)
    }
    // MARK: - Movement
    func moveTo(_ targetPosition: CGPoint, avoiding obstacles: [RotatableObject]) {
        // Stop any current movement
        removeAction(forKey: "movement")
        isMoving = false
        
        // Use pathfinding if available, otherwise fallback to direct movement
        if let graph = pathfindingGraph {
            moveWithPathfinding(to: targetPosition)
        } else {
            // Fallback to old collision avoidance system
            let validPosition = getValidPosition(targetPosition, avoiding: obstacles)
            moveDirectlyTo(validPosition)
        }
    }
    
    private func moveWithPathfinding(to targetPosition: CGPoint) {
        guard let graph = pathfindingGraph else {
            return
        }
        
        // Create start and end nodes
        let startNode = GKGraphNode2D(point: vector_float2(Float(position.x), Float(position.y)))
        let endNode = GKGraphNode2D(point: vector_float2(Float(targetPosition.x), Float(targetPosition.y)))
        
        // Connect nodes to the graph
        graph.connectUsingObstacles(node: startNode)
        graph.connectUsingObstacles(node: endNode)
        
        // Find path
        let path = graph.findPath(from: startNode, to: endNode) as? [GKGraphNode2D] ?? []
        
        // Remove temporary nodes
        graph.remove([startNode, endNode])
        
        if path.isEmpty {
            // No path found, try direct movement
            print("No path found, moving directly")
            moveDirectlyTo(targetPosition)
        } else {
            // Follow the path
            currentPath = path
            currentPathIndex = 0
            isMoving = true
            followPath()
        }
    }
    
    private func followPath() {
        guard currentPathIndex < currentPath.count, isMoving else {
            isMoving = false
            return
        }
        
        let nextNode = currentPath[currentPathIndex]
        let nextPosition = CGPoint(x: CGFloat(nextNode.position.x), y: CGFloat(nextNode.position.y))
        
        // Calculate distance and duration
        let distance = sqrt(pow(nextPosition.x - position.x, 2) + pow(nextPosition.y - position.y, 2))
        let duration = TimeInterval(distance / moveSpeed)
        
        // Move to next waypoint
        let moveAction = SKAction.move(to: nextPosition, duration: duration)
        moveAction.timingMode = .linear
        
        let completion = SKAction.run { [weak self] in
            self?.currentPathIndex += 1
            self?.followPath()
        }
        
        let sequence = SKAction.sequence([moveAction, completion])
        run(sequence, withKey: "movement")
        
        // Move carried item with character
        if let item = carriedItem {
            let itemTarget = CGPoint(x: nextPosition.x, y: nextPosition.y + carryOffset)
            let itemMoveAction = SKAction.move(to: itemTarget, duration: duration)
            itemMoveAction.timingMode = .linear
            item.run(itemMoveAction, withKey: "itemMovement")
        }
    }
    
    private func moveDirectlyTo(_ targetPosition: CGPoint) {
        let distance = sqrt(pow(targetPosition.x - position.x, 2) + pow(targetPosition.y - position.y, 2))
        let duration = TimeInterval(distance / moveSpeed)
        
        let moveAction = SKAction.move(to: targetPosition, duration: duration)
        moveAction.timingMode = .easeOut
        run(moveAction, withKey: "movement")
        
        // Move carried item with character
        if let item = carriedItem {
            let itemTarget = CGPoint(x: targetPosition.x, y: targetPosition.y + carryOffset)
            let itemMoveAction = SKAction.move(to: itemTarget, duration: duration)
            itemMoveAction.timingMode = .easeOut
            item.run(itemMoveAction, withKey: "itemMovement")
        }
    }
    
    private func getValidPosition(_ targetPosition: CGPoint, avoiding obstacles: [RotatableObject]) -> CGPoint {
        // World bounds
        let worldWidth: CGFloat = 2000
        let worldHeight: CGFloat = 1500
        
        let clampedX = max(-worldWidth/2 + 60, min(worldWidth/2 - 60, targetPosition.x))
        let clampedY = max(-worldHeight/2 + 60, min(worldHeight/2 - 60, targetPosition.y))
        let clampedPosition = CGPoint(x: clampedX, y: clampedY)
        
        // Simple collision avoidance
        for obstacle in obstacles {
            let distance = sqrt(pow(clampedPosition.x - obstacle.position.x, 2) + 
                              pow(clampedPosition.y - obstacle.position.y, 2))
            if distance < 80 {
                let angle = atan2(clampedPosition.y - obstacle.position.y, 
                                clampedPosition.x - obstacle.position.x)
                let safeX = obstacle.position.x + cos(angle) * 100
                let safeY = obstacle.position.y + sin(angle) * 100
                return CGPoint(x: safeX, y: safeY)
            }
        }
        
        return clampedPosition
    }
    
    // MARK: - Item Management
    func pickupItem(_ item: RotatableObject) {
        guard carriedItem == nil else { return }
        guard item.canBeCarried else { return } // Only pick up small items (drink or completedDrink)
        
        carriedItem = item
        item.removeFromParent()
        
        // Add to character's parent (the scene)
        parent?.addChild(item)
        
        // Position above head
        updateCarriedItemPosition()
        
        // Add floating animation
        let floatAction = SKAction.repeatForever(
            SKAction.sequence([
                SKAction.moveBy(x: 0, y: 5, duration: 1.0),
                SKAction.moveBy(x: 0, y: -5, duration: 1.0)
            ])
        )
        item.run(floatAction, withKey: "floating")
        item.zPosition = 15
    }
    
    func dropItem() {
        guard let item = carriedItem else { return }
        
        // Stop floating animation
        item.removeAction(forKey: "floating")
        
        // Drop at character position
        let dropPosition = CGPoint(x: position.x, y: position.y - 30)
        let dropAction = SKAction.move(to: dropPosition, duration: 0.3)
        dropAction.timingMode = .easeOut
        item.run(dropAction)
        
        item.zPosition = 3
        carriedItem = nil
    }
    
    func rotateCarriedItem() {
        // Only rotate if the carried item is rotatable
        if let item = carriedItem, item.isRotatable {
            item.rotateToNextState()
        }
    }
    
    private func updateCarriedItemPosition() {
        guard let item = carriedItem else { return }
        item.position = CGPoint(x: position.x, y: position.y + carryOffset)
    }
    
    // MARK: - Update
    func update() {
        // Keep carried item positioned correctly during any movement
        if isCarrying {
            updateCarriedItemPosition()
        }
    }
}
