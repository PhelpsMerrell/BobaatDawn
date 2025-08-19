//
//  Character.swift
//  BobaAtDawn
//
//  Created by Phelps Merrell on 8/18/25.
//

import SpriteKit

class Character: SKSpriteNode {
    
    // MARK: - Properties
    private(set) var carriedItem: RotatableObject?
    private let carryOffset: CGFloat = 80
    
    // Grid properties
    private var gridPosition: GridCoordinate {
        return GridWorld.shared.currentCharacterPosition
    }
    
    var isCarrying: Bool {
        return carriedItem != nil
    }
    
    // MARK: - Initialization
    init() {
        super.init(texture: nil, color: SKColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1.0), size: CGSize(width: 40, height: 60))
        
        name = "character"
        zPosition = 10
        
        // Position character at grid center
        let startCell = GridCoordinate(x: 16, y: 12)  // Center of new 33x25 grid
        position = GridWorld.shared.gridToWorld(startCell)
        GridWorld.shared.moveCharacterTo(startCell)
        
        print("👤 Character initialized at grid \(startCell), world \(position)")
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Grid Movement (ENHANCED - More Fluid)
    func moveToGridCell(_ targetCell: GridCoordinate) {
        guard targetCell.isValid() else {
            print("❌ Invalid target cell: \(targetCell)")
            return
        }
        
        guard GridWorld.shared.isCellAvailable(targetCell) else {
            print("❌ Cell \(targetCell) is occupied")
            return
        }
        
        // Update grid state
        GridWorld.shared.moveCharacterTo(targetCell)
        
        // ENHANCED: More natural, fluid movement
        let worldPosition = GridWorld.shared.gridToWorld(targetCell)
        
        // Calculate distance for dynamic timing
        let distance = sqrt(pow(worldPosition.x - position.x, 2) + pow(worldPosition.y - position.y, 2))
        let baseSpeed: CGFloat = 300  // Points per second
        let duration = max(0.15, min(0.6, TimeInterval(distance / baseSpeed)))  // Dynamic timing
        
        // Create smooth, natural movement with easing
        let moveAction = SKAction.move(to: worldPosition, duration: duration)
        moveAction.timingMode = .easeInEaseOut  // Much more natural feeling
        run(moveAction, withKey: "gridMovement")
        
        // Move carried item with character (PRESERVED but enhanced)
        if let item = carriedItem {
            let itemTarget = CGPoint(x: worldPosition.x, y: worldPosition.y + carryOffset)
            let itemMove = SKAction.move(to: itemTarget, duration: duration)
            itemMove.timingMode = .easeInEaseOut  // Match character movement
            item.run(itemMove, withKey: "itemMovement")
        }
        
        print("👤 Character moving fluidly to grid \(targetCell) in \(String(format: "%.2f", duration))s")
    }
    
    // MARK: - Item Management (PRESERVED - NO CHANGES)
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
        
        // NEW: Grid-based dropping
        let currentCell = GridWorld.shared.currentCharacterPosition
        let adjacentCells = GridWorld.shared.getAvailableAdjacentCells(to: currentCell)
        
        if let targetCell = adjacentCells.first {
            // Create GameObject and occupy cell
            let gameObject = GameObject(skNode: item, gridPosition: targetCell, objectType: item.objectType)
            GridWorld.shared.occupyCell(targetCell, with: gameObject)
            
            // ENHANCED: More natural dropping animation
            let worldPos = GridWorld.shared.gridToWorld(targetCell)
            let distance = sqrt(pow(worldPos.x - item.position.x, 2) + pow(worldPos.y - item.position.y, 2))
            let dropDuration = max(0.2, min(0.5, TimeInterval(distance / 400)))  // Dynamic timing
            
            let dropAction = SKAction.move(to: worldPos, duration: dropDuration)
            dropAction.timingMode = .easeOut  // Natural settling motion
            item.run(dropAction)
            
            print("📦 Dropped \(item.objectType) fluidly at grid \(targetCell)")
        } else {
            // Fallback: Drop at character position if no adjacent cells available
            let dropPosition = CGPoint(x: position.x, y: position.y - 30)
            let dropAction = SKAction.move(to: dropPosition, duration: 0.3)
            dropAction.timingMode = .easeOut
            item.run(dropAction)
            
            print("📦 Dropped \(item.objectType) at character position (no grid cells available)")
        }
        
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
