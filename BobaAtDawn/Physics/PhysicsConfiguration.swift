//
//  PhysicsConfiguration.swift
//  BobaAtDawn
//
//  Physics system configuration for SpriteKit physics bodies
//  Defines collision categories, contact handling, and physics properties
//

import SpriteKit

// MARK: - Physics Categories (Bit Masks)
struct PhysicsCategory {
    static let none: UInt32 = 0
    static let character: UInt32 = 0b1      // 1
    static let npc: UInt32 = 0b10           // 2
    static let furniture: UInt32 = 0b100     // 4
    static let wall: UInt32 = 0b1000        // 8
    static let station: UInt32 = 0b10000    // 16
    static let item: UInt32 = 0b100000      // 32
    static let door: UInt32 = 0b1000000     // 64
    static let shopFloor: UInt32 = 0b10000000 // 128
    static let boundary: UInt32 = 0b100000000 // 256
}

// MARK: - Physics Configuration
struct PhysicsConfig {
    
    // MARK: - Character Physics
    struct Character {
        static let mass: CGFloat = 1.0
        static let friction: CGFloat = 0.2
        static let restitution: CGFloat = 0.0  // No bouncing
        static let linearDamping: CGFloat = 2.0 // Quick stop when not moving
        static let angularDamping: CGFloat = 5.0 // Prevent spinning
        static let allowsRotation = false
        
        // Movement
        static let maxSpeed: CGFloat = 200.0 // Points per second
        static let acceleration: CGFloat = 800.0 // Points per second²
        static let snapToGridThreshold: CGFloat = 30.0 // Distance to snap to nearest grid
        
        // Physics body shape (slightly smaller than visual for better feel)
        static let bodySize = CGSize(width: 35, height: 55)
        static let bodyOffset = CGPoint(x: 0, y: -2.5) // Slightly down from center
    }
    
    // MARK: - NPC Physics
    struct NPC {
        static let mass: CGFloat = 0.8
        static let friction: CGFloat = 0.3
        static let restitution: CGFloat = 0.0
        static let linearDamping: CGFloat = 3.0
        static let angularDamping: CGFloat = 8.0
        static let allowsRotation = false
        
        // Movement
        static let maxSpeed: CGFloat = 120.0
        static let acceleration: CGFloat = 400.0
        
        // Physics body (circular for smooth movement)
        static let bodyRadius: CGFloat = 18.0
    }
    
    // MARK: - Furniture Physics
    struct Furniture {
        static let mass: CGFloat = 5.0 // Heavy, hard to push
        static let friction: CGFloat = 0.8 // High friction
        static let restitution: CGFloat = 0.1
        static let linearDamping: CGFloat = 5.0
        static let angularDamping: CGFloat = 10.0
        static let allowsRotation = true
        
        // Tables and objects (rectangular)
        static let bodySize = CGSize(width: 55, height: 55)
        static let bodyOffset = CGPoint.zero
    }
    
    // MARK: - Station Physics
    struct Station {
        static let mass: CGFloat = 10.0 // Very heavy, immovable
        static let friction: CGFloat = 1.0
        static let restitution: CGFloat = 0.0
        static let allowsRotation = false
        
        // Ingredient stations (rectangular)
        static let bodySize = CGSize(width: 75, height: 75)
    }
    
    // MARK: - Wall Physics
    struct Wall {
        static let mass: CGFloat = 1000.0 // Essentially immovable
        static let friction: CGFloat = 0.5
        static let restitution: CGFloat = 0.2 // Slight bounce off walls
        static let allowsRotation = false
        
        // Dynamic sizing based on wall type
    }
    
    // MARK: - Item Physics (Carried items, drinks, etc.)
    struct Item {
        static let mass: CGFloat = 0.1 // Very light
        static let friction: CGFloat = 0.1
        static let restitution: CGFloat = 0.3
        static let linearDamping: CGFloat = 1.0
        static let angularDamping: CGFloat = 2.0
        static let allowsRotation = true
        
        // Small items (circular for smooth handling)
        static let bodyRadius: CGFloat = 12.0
    }
    
    // MARK: - World Physics
    struct World {
        static let gravity = CGVector(dx: 0, dy: 0) // No gravity (top-down view)
        static let speed: CGFloat = 1.0 // Normal physics simulation speed
        
        // Contact detection thresholds
        static let contactThreshold: CGFloat = 2.0 // Minimum overlap for contact
    }
}

// MARK: - Physics Body Factory
class PhysicsBodyFactory {
    
    // MARK: - Character Physics Body
    static func createCharacterBody() -> SKPhysicsBody {
        let body = SKPhysicsBody(rectangleOf: PhysicsConfig.Character.bodySize,
                                center: PhysicsConfig.Character.bodyOffset)
        
        // Category and collision setup
        body.categoryBitMask = PhysicsCategory.character
        body.collisionBitMask = PhysicsCategory.wall | 
                               PhysicsCategory.furniture | 
                               PhysicsCategory.station |
                               PhysicsCategory.boundary
        body.contactTestBitMask = PhysicsCategory.npc | 
                                 PhysicsCategory.door | 
                                 PhysicsCategory.item |
                                 PhysicsCategory.station
        
        // Physics properties
        body.mass = PhysicsConfig.Character.mass
        body.friction = PhysicsConfig.Character.friction
        body.restitution = PhysicsConfig.Character.restitution
        body.linearDamping = PhysicsConfig.Character.linearDamping
        body.angularDamping = PhysicsConfig.Character.angularDamping
        body.allowsRotation = PhysicsConfig.Character.allowsRotation
        
        body.isDynamic = true
        body.affectedByGravity = false
        
        return body
    }
    
    // MARK: - NPC Physics Body
    static func createNPCBody() -> SKPhysicsBody {
        let body = SKPhysicsBody(circleOfRadius: PhysicsConfig.NPC.bodyRadius)
        
        // Category and collision setup
        body.categoryBitMask = PhysicsCategory.npc
        body.collisionBitMask = PhysicsCategory.wall | 
                               PhysicsCategory.furniture | 
                               PhysicsCategory.station |
                               PhysicsCategory.npc |
                               PhysicsCategory.boundary
        body.contactTestBitMask = PhysicsCategory.character |
                                 PhysicsCategory.door
        
        // Physics properties
        body.mass = PhysicsConfig.NPC.mass
        body.friction = PhysicsConfig.NPC.friction
        body.restitution = PhysicsConfig.NPC.restitution
        body.linearDamping = PhysicsConfig.NPC.linearDamping
        body.angularDamping = PhysicsConfig.NPC.angularDamping
        body.allowsRotation = PhysicsConfig.NPC.allowsRotation
        
        body.isDynamic = true
        body.affectedByGravity = false
        
        return body
    }
    
    // MARK: - Furniture Physics Body
    static func createFurnitureBody(size: CGSize = PhysicsConfig.Furniture.bodySize) -> SKPhysicsBody {
        let body = SKPhysicsBody(rectangleOf: size, center: PhysicsConfig.Furniture.bodyOffset)
        
        // Category and collision setup
        body.categoryBitMask = PhysicsCategory.furniture
        body.collisionBitMask = PhysicsCategory.character | 
                               PhysicsCategory.npc |
                               PhysicsCategory.furniture |
                               PhysicsCategory.item
        body.contactTestBitMask = PhysicsCategory.character |
                                 PhysicsCategory.item
        
        // Physics properties
        body.mass = PhysicsConfig.Furniture.mass
        body.friction = PhysicsConfig.Furniture.friction
        body.restitution = PhysicsConfig.Furniture.restitution
        body.linearDamping = PhysicsConfig.Furniture.linearDamping
        body.angularDamping = PhysicsConfig.Furniture.angularDamping
        body.allowsRotation = PhysicsConfig.Furniture.allowsRotation
        
        body.isDynamic = true
        body.affectedByGravity = false
        
        return body
    }
    
    // MARK: - Station Physics Body
    static func createStationBody(size: CGSize = PhysicsConfig.Station.bodySize) -> SKPhysicsBody {
        let body = SKPhysicsBody(rectangleOf: size)
        
        // Category and collision setup
        body.categoryBitMask = PhysicsCategory.station
        body.collisionBitMask = PhysicsCategory.character | 
                               PhysicsCategory.npc |
                               PhysicsCategory.furniture |
                               PhysicsCategory.item
        body.contactTestBitMask = PhysicsCategory.character |
                                 PhysicsCategory.item
        
        // Physics properties - stations are immovable
        body.mass = PhysicsConfig.Station.mass
        body.friction = PhysicsConfig.Station.friction
        body.restitution = PhysicsConfig.Station.restitution
        body.allowsRotation = PhysicsConfig.Station.allowsRotation
        
        body.isDynamic = false // Immovable
        body.affectedByGravity = false
        
        return body
    }
    
    // MARK: - Wall Physics Body
    static func createWallBody(size: CGSize) -> SKPhysicsBody {
        let body = SKPhysicsBody(rectangleOf: size)
        
        // Category and collision setup
        body.categoryBitMask = PhysicsCategory.wall
        body.collisionBitMask = PhysicsCategory.character | 
                               PhysicsCategory.npc |
                               PhysicsCategory.furniture |
                               PhysicsCategory.item
        body.contactTestBitMask = PhysicsCategory.none // Walls don't need contact events
        
        // Physics properties - walls are completely immovable
        body.mass = PhysicsConfig.Wall.mass
        body.friction = PhysicsConfig.Wall.friction
        body.restitution = PhysicsConfig.Wall.restitution
        body.allowsRotation = PhysicsConfig.Wall.allowsRotation
        
        body.isDynamic = false // Completely immovable
        body.affectedByGravity = false
        
        return body
    }
    
    // MARK: - Boundary Physics Body (Invisible world boundaries)
    static func createBoundaryBody(size: CGSize) -> SKPhysicsBody {
        let body = SKPhysicsBody(rectangleOf: size)
        
        // Category and collision setup
        body.categoryBitMask = PhysicsCategory.boundary
        body.collisionBitMask = PhysicsCategory.character | 
                               PhysicsCategory.npc |
                               PhysicsCategory.furniture |
                               PhysicsCategory.item
        body.contactTestBitMask = PhysicsCategory.none
        
        // Boundary properties - invisible, immovable barriers
        body.isDynamic = false
        body.affectedByGravity = false
        body.friction = 0.0
        body.restitution = 0.0
        
        return body
    }
    
    // MARK: - Item Physics Body
    static func createItemBody(radius: CGFloat = PhysicsConfig.Item.bodyRadius) -> SKPhysicsBody {
        let body = SKPhysicsBody(circleOfRadius: radius)
        
        // Category and collision setup
        body.categoryBitMask = PhysicsCategory.item
        body.collisionBitMask = PhysicsCategory.character | 
                               PhysicsCategory.npc |
                               PhysicsCategory.furniture |
                               PhysicsCategory.station |
                               PhysicsCategory.wall |
                               PhysicsCategory.item
        body.contactTestBitMask = PhysicsCategory.character
        
        // Physics properties - items are light and can be pushed around
        body.mass = PhysicsConfig.Item.mass
        body.friction = PhysicsConfig.Item.friction
        body.restitution = PhysicsConfig.Item.restitution
        body.linearDamping = PhysicsConfig.Item.linearDamping
        body.angularDamping = PhysicsConfig.Item.angularDamping
        body.allowsRotation = PhysicsConfig.Item.allowsRotation
        
        body.isDynamic = true
        body.affectedByGravity = false
        
        return body
    }
    
    // MARK: - Door Physics Body (For collision detection only)
    static func createDoorBody(size: CGSize) -> SKPhysicsBody {
        let body = SKPhysicsBody(rectangleOf: size)
        
        // Category and collision setup - doors are sensors, not solid
        body.categoryBitMask = PhysicsCategory.door
        body.collisionBitMask = PhysicsCategory.none // Pass-through
        body.contactTestBitMask = PhysicsCategory.character | PhysicsCategory.npc
        
        body.isDynamic = false
        body.affectedByGravity = false
        
        return body
    }
}

// MARK: - Physics Extensions
extension GameConfig {
    struct Physics {
        // Integration with existing config
        static let enabled = true
        static let debugDraw = false // Set to true during development
        
        // Grid integration
        static let enableGridSnapping = true
        static let snapDistance = PhysicsConfig.Character.snapToGridThreshold
        
        // Performance
        static let physicsSubsteps = 1 // Can increase for more accuracy if needed
        static let contactDelegate = true // Enable contact detection
    }
}
