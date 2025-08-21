//
//  GameObject.swift
//  BobaAtDawn
//
//  Wrapper for SKNode objects in the grid system
//

import SpriteKit

class GameObject {
    let gridPosition: GridCoordinate
    let skNode: SKNode
    let objectType: ObjectType
    private let gridService: GridService
    
    var worldPosition: CGPoint {
        return gridService.gridToWorld(gridPosition)
    }
    
    init(skNode: SKNode, gridPosition: GridCoordinate, objectType: ObjectType, gridService: GridService) {
        self.skNode = skNode
        self.gridPosition = gridPosition
        self.objectType = objectType
        self.gridService = gridService
    }
    
    // Update the SKNode position to match grid position
    func updateWorldPosition() {
        skNode.position = worldPosition
    }
    
    // Check if this object can be picked up
    var canBeCarried: Bool {
        if let rotatable = skNode as? RotatableObject {
            return rotatable.canBeCarried
        }
        return false
    }
    
    // Check if this object can be rotated
    var isRotatable: Bool {
        if let rotatable = skNode as? RotatableObject {
            return rotatable.isRotatable
        }
        return false
    }
}

extension GameObject: CustomStringConvertible {
    var description: String {
        return "GameObject(\(objectType) at \(gridPosition))"
    }
}
