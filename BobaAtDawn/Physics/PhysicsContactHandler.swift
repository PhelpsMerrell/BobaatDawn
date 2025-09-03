//
//  PhysicsContactHandler.swift
//  BobaAtDawn
//
//  Handles physics contact events for character interactions, NPC behavior, and game logic
//  Integrates with existing game systems while providing physics-based collision detection
//

import SpriteKit

// MARK: - Contact Handler Protocol
protocol PhysicsContactDelegate: AnyObject {
    func characterContactedStation(_ station: SKNode)
    func characterContactedDoor(_ door: SKNode)
    func characterContactedItem(_ item: SKNode)
    func characterContactedNPC(_ npc: SKNode)
    func npcContactedDoor(_ npc: SKNode, door: SKNode)
    func itemContactedFurniture(_ item: SKNode, furniture: SKNode)
}

// MARK: - Physics Contact Handler
class PhysicsContactHandler: NSObject, SKPhysicsContactDelegate {
    
    // MARK: - Delegate
    weak var contactDelegate: PhysicsContactDelegate?
    
    // MARK: - Contact Detection State
    private var activeContacts: Set<String> = []
    
    // MARK: - Initialization
    override init() {
        super.init()
        print("⚡ PhysicsContactHandler initialized")
    }
    
    // MARK: - SKPhysicsContactDelegate
    
    func didBegin(_ contact: SKPhysicsContact) {
        let contactKey = createContactKey(contact)
        
        // Prevent duplicate contact events
        guard !activeContacts.contains(contactKey) else { return }
        activeContacts.insert(contactKey)
        
        // Determine which bodies are involved
        let (bodyA, bodyB) = sortContactBodies(contact.bodyA, contact.bodyB)
        
        // Handle specific contact combinations
        handleContact(bodyA: bodyA, bodyB: bodyB, contact: contact)
    }
    
    func didEnd(_ contact: SKPhysicsContact) {
        let contactKey = createContactKey(contact)
        activeContacts.remove(contactKey)
        
        // Handle contact end if needed (for hover effects, etc.)
        handleContactEnd(contact)
    }
    
    // MARK: - Contact Handling
    
    private func handleContact(bodyA: SKPhysicsBody, bodyB: SKPhysicsBody, contact: SKPhysicsContact) {
        let categoryA = bodyA.categoryBitMask
        let categoryB = bodyB.categoryBitMask
        
        // Character contacts
        if categoryA == PhysicsCategory.character {
            handleCharacterContact(character: bodyA, other: bodyB, contact: contact)
        } else if categoryB == PhysicsCategory.character {
            handleCharacterContact(character: bodyB, other: bodyA, contact: contact)
        }
        
        // NPC contacts
        else if categoryA == PhysicsCategory.npc {
            handleNPCContact(npc: bodyA, other: bodyB, contact: contact)
        } else if categoryB == PhysicsCategory.npc {
            handleNPCContact(npc: bodyB, other: bodyA, contact: contact)
        }
        
        // Item contacts (for physics interactions)
        else if categoryA == PhysicsCategory.item || categoryB == PhysicsCategory.item {
            handleItemContact(bodyA: bodyA, bodyB: bodyB, contact: contact)
        }
    }
    
    private func handleCharacterContact(character: SKPhysicsBody, other: SKPhysicsBody, contact: SKPhysicsContact) {
        guard let characterNode = character.node else { return }
        guard let otherNode = other.node else { return }
        
        let otherCategory = other.categoryBitMask
        
        switch otherCategory {
        case PhysicsCategory.station:
            contactDelegate?.characterContactedStation(otherNode)
            print("⚡ Character contacted station: \(otherNode.name ?? "unnamed")")
            
        case PhysicsCategory.door:
            contactDelegate?.characterContactedDoor(otherNode)
            print("⚡ Character contacted door: \(otherNode.name ?? "unnamed")")
            
        case PhysicsCategory.item:
            contactDelegate?.characterContactedItem(otherNode)
            print("⚡ Character contacted item: \(otherNode.name ?? "unnamed")")
            
        case PhysicsCategory.npc:
            contactDelegate?.characterContactedNPC(otherNode)
            print("⚡ Character contacted NPC: \(otherNode.name ?? "unnamed")")
            
        case PhysicsCategory.furniture:
            // Handle furniture contact (could be used for interaction hints)
            print("⚡ Character contacted furniture: \(otherNode.name ?? "unnamed")")
            
        case PhysicsCategory.wall:
            // Wall contact (could be used for sound effects)
            print("⚡ Character contacted wall")
            
        default:
            break
        }
    }
    
    private func handleNPCContact(npc: SKPhysicsBody, other: SKPhysicsBody, contact: SKPhysicsContact) {
        guard let npcNode = npc.node else { return }
        guard let otherNode = other.node else { return }
        
        let otherCategory = other.categoryBitMask
        
        switch otherCategory {
        case PhysicsCategory.door:
            contactDelegate?.npcContactedDoor(npcNode, door: otherNode)
            print("⚡ NPC contacted door: \(npcNode.name ?? "unnamed")")
            
        case PhysicsCategory.character:
            // Already handled in character contact
            break
            
        case PhysicsCategory.furniture:
            // NPC reached furniture (table, chair, etc.)
            print("⚡ NPC \(npcNode.name ?? "unnamed") contacted furniture: \(otherNode.name ?? "unnamed")")
            
        default:
            break
        }
    }
    
    private func handleItemContact(bodyA: SKPhysicsBody, bodyB: SKPhysicsBody, contact: SKPhysicsContact) {
        // Determine which is the item and which is the other object
        let itemBody = bodyA.categoryBitMask == PhysicsCategory.item ? bodyA : bodyB
        let otherBody = bodyA.categoryBitMask == PhysicsCategory.item ? bodyB : bodyA
        
        guard let itemNode = itemBody.node else { return }
        guard let otherNode = otherBody.node else { return }
        
        let otherCategory = otherBody.categoryBitMask
        
        switch otherCategory {
        case PhysicsCategory.furniture:
            contactDelegate?.itemContactedFurniture(itemNode, furniture: otherNode)
            print("⚡ Item contacted furniture: \(itemNode.name ?? "unnamed") -> \(otherNode.name ?? "unnamed")")
            
        case PhysicsCategory.character:
            // Already handled in character contact
            break
            
        default:
            break
        }
    }
    
    private func handleContactEnd(_ contact: SKPhysicsContact) {
        // Handle contact end events (for hover effects, proximity detection, etc.)
        // This could be used for interaction hints that appear/disappear
        
        let (bodyA, bodyB) = sortContactBodies(contact.bodyA, contact.bodyB)
        
        // Example: Character moving away from station
        if bodyA.categoryBitMask == PhysicsCategory.character && bodyB.categoryBitMask == PhysicsCategory.station {
            print("⚡ Character moved away from station")
        }
    }
    
    // MARK: - Utility Methods
    
    private func createContactKey(_ contact: SKPhysicsContact) -> String {
        let idA = contact.bodyA.node?.name ?? "\(ObjectIdentifier(contact.bodyA))"
        let idB = contact.bodyB.node?.name ?? "\(ObjectIdentifier(contact.bodyB))"
        
        // Create consistent key regardless of body order
        return idA < idB ? "\(idA)-\(idB)" : "\(idB)-\(idA)"
    }
    
    private func sortContactBodies(_ bodyA: SKPhysicsBody, _ bodyB: SKPhysicsBody) -> (SKPhysicsBody, SKPhysicsBody) {
        // Sort by category for consistent handling
        return bodyA.categoryBitMask <= bodyB.categoryBitMask ? (bodyA, bodyB) : (bodyB, bodyA)
    }
    
    // MARK: - Debug Information
    
    func getActiveContactsCount() -> Int {
        return activeContacts.count
    }
    
    func getActiveContacts() -> [String] {
        return Array(activeContacts)
    }
    
    func printActiveContacts() {
        print("⚡ Active Contacts (\(activeContacts.count)):")
        for contact in activeContacts {
            print("   - \(contact)")
        }
    }
}

// MARK: - Physics World Setup Helper
class PhysicsWorldSetup {
    
    static func setupPhysicsWorld(_ scene: SKScene) {
        // Configure physics world
        scene.physicsWorld.gravity = PhysicsConfig.World.gravity
        scene.physicsWorld.speed = PhysicsConfig.World.speed
        
        // Set up contact delegate
        let contactHandler = PhysicsContactHandler()
        scene.physicsWorld.contactDelegate = contactHandler
        
        // Store reference to contact handler in scene for cleanup
        scene.userData = scene.userData ?? [:]
        scene.userData?["contactHandler"] = contactHandler
        
        print("⚡ Physics world configured:")
        print("   - Gravity: \(PhysicsConfig.World.gravity)")
        print("   - Speed: \(PhysicsConfig.World.speed)")
        print("   - Contact delegate: enabled")
    }
    
    static func setupWorldBoundaries(_ scene: SKScene, worldSize: CGSize) {
        let boundaryThickness: CGFloat = 20.0
        let halfWidth = worldSize.width / 2
        let halfHeight = worldSize.height / 2
        
        // Top boundary
        let topBoundary = SKNode()
        topBoundary.position = CGPoint(x: 0, y: halfHeight + boundaryThickness/2)
        topBoundary.physicsBody = PhysicsBodyFactory.createBoundaryBody(
            size: CGSize(width: worldSize.width, height: boundaryThickness)
        )
        topBoundary.name = "boundary_top"
        scene.addChild(topBoundary)
        
        // Bottom boundary
        let bottomBoundary = SKNode()
        bottomBoundary.position = CGPoint(x: 0, y: -halfHeight - boundaryThickness/2)
        bottomBoundary.physicsBody = PhysicsBodyFactory.createBoundaryBody(
            size: CGSize(width: worldSize.width, height: boundaryThickness)
        )
        bottomBoundary.name = "boundary_bottom"
        scene.addChild(bottomBoundary)
        
        // Left boundary
        let leftBoundary = SKNode()
        leftBoundary.position = CGPoint(x: -halfWidth - boundaryThickness/2, y: 0)
        leftBoundary.physicsBody = PhysicsBodyFactory.createBoundaryBody(
            size: CGSize(width: boundaryThickness, height: worldSize.height)
        )
        leftBoundary.name = "boundary_left"
        scene.addChild(leftBoundary)
        
        // Right boundary
        let rightBoundary = SKNode()
        rightBoundary.position = CGPoint(x: halfWidth + boundaryThickness/2, y: 0)
        rightBoundary.physicsBody = PhysicsBodyFactory.createBoundaryBody(
            size: CGSize(width: boundaryThickness, height: worldSize.height)
        )
        rightBoundary.name = "boundary_right"
        scene.addChild(rightBoundary)
        
        print("⚡ World boundaries created: \(worldSize)")
    }
    
    static func getContactHandler(from scene: SKScene) -> PhysicsContactHandler? {
        return scene.userData?["contactHandler"] as? PhysicsContactHandler
    }
}

// MARK: - Physics Debug Visualizer (Development Only)
class PhysicsDebugVisualizer {
    
    private var debugNodes: [SKNode] = []
    private let scene: SKScene
    
    init(scene: SKScene) {
        self.scene = scene
    }
    
    func showPhysicsBodies(_ show: Bool) {
        if show {
            scene.view?.showsPhysics = true
            print("⚡ Physics debug visualization enabled")
        } else {
            scene.view?.showsPhysics = false
            clearDebugNodes()
            print("⚡ Physics debug visualization disabled")
        }
    }
    
    func visualizeContactPoints(_ contacts: [SKPhysicsContact]) {
        clearDebugNodes()
        
        for contact in contacts {
            let contactPoint = contact.contactPoint
            
            let debugNode = SKShapeNode(circleOfRadius: 5)
            debugNode.fillColor = .red
            debugNode.strokeColor = .white
            debugNode.lineWidth = 2
            debugNode.position = contactPoint
            debugNode.zPosition = 1000 // Very high to be visible
            
            scene.addChild(debugNode)
            debugNodes.append(debugNode)
            
            // Remove after short duration
            let removeAction = SKAction.sequence([
                SKAction.wait(forDuration: 1.0),
                SKAction.removeFromParent()
            ])
            debugNode.run(removeAction)
        }
    }
    
    private func clearDebugNodes() {
        for node in debugNodes {
            node.removeFromParent()
        }
        debugNodes.removeAll()
    }
    
    deinit {
        clearDebugNodes()
    }
}
