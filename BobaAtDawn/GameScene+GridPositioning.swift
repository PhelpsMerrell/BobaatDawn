//
//  GameScene+GridPositioning.swift
//  BobaAtDawn
//
//  Grid positioning helper extension for easy repositioning
//

import SpriteKit

extension GameScene {
    
    // MARK: - Easy Grid Positioning Helpers
    
    /// Reposition any object to a grid coordinate
    /// - Parameters:
    ///   - object: The SKNode to reposition
    ///   - gridPos: Target grid coordinate
    func repositionObject(_ object: SKNode, to gridPos: GridCoordinate) {
        object.position = gridService.gridToWorld(gridPos)
        print("🎯 \(object.name ?? "Object") moved to grid \(gridPos) = world \(object.position)")
    }
    
    /// Move time window to a new grid position
    /// - Parameter gridPos: New grid coordinate for time window
    func moveTimeWindow(to gridPos: GridCoordinate) {
        repositionObject(timeWindow, to: gridPos)
        repositionObject(timeLabel, to: gridPos) // Keep label with window
        print("⏰ Time window repositioned to grid \(gridPos)")
    }
    
    /// Move time breaker to a new grid position  
    /// - Parameter gridPos: New grid coordinate for time breaker
    func moveTimeBreaker(to gridPos: GridCoordinate) {
        repositionObject(timeBreaker, to: gridPos)
        print("🔌 Time breaker repositioned to grid \(gridPos)")
    }
    
    /// Move front door to a new grid position
    /// - Parameter gridPos: New grid coordinate for front door
    func moveFrontDoor(to gridPos: GridCoordinate) {
        if let door = childNode(withName: "front_door") {
            repositionObject(door, to: gridPos)
            print("🚪 Front door repositioned to grid \(gridPos)")
        }
    }
    
    /// Get current grid position of any object
    /// - Parameter object: Object to check position of
    /// - Returns: Current grid coordinate
    func getCurrentGridPosition(of object: SKNode) -> GridCoordinate {
        return gridService.worldToGrid(object.position)
    }
    
    // MARK: - Debug Methods (Optional - call manually if needed)
    
    /// Print current positions of all major elements
    func printCurrentPositions() {
        print("📍 CURRENT GRID POSITIONS:")
        print("   Character: \(getCurrentGridPosition(of: character))")
        print("   Time Window: \(getCurrentGridPosition(of: timeWindow))")
        print("   Time Breaker: \(getCurrentGridPosition(of: timeBreaker))")
        if let door = childNode(withName: "front_door") {
            print("   Front Door: \(getCurrentGridPosition(of: door))")
        }
        print("   Station positions:")
        for (index, station) in ingredientStations.enumerated() {
            print("     \(station.stationType): \(getCurrentGridPosition(of: station))")
        }
    }
    
    /// Show grid coordinate reference in console
    func printGridReference() {
        print("""
        📍 GRID REFERENCE (33x25):
        ┌─────────────────────────────────────────┐
        │ (0,24)      TOP ROW        (32,24)     │ ← Top edge
        │   3,20 = breaker area                   │
        │                                  28,18  │ ← Time window area
        │                                         │
        │ (0,12)      CENTER         (32,12)     │ ← Vertical center
        │  1,12 = door    (16,12) = World (0,0)  │ ← Character start
        │                                         │
        │           Station row at y=15           │ ← Brewing area
        │                                         │
        │ (0,0)      BOTTOM ROW       (32,0)     │ ← Bottom edge  
        └─────────────────────────────────────────┘
        
        COMMON POSITIONS:
        • Top-left corner: (3, 20)
        • Top-right corner: (28, 20) 
        • Center: (16, 12)
        • Left wall: (1, y) 
        • Right wall: (31, y)
        • Station row: (x, 15)
        """)
    }
    
    /// Enable/disable grid overlay for debugging
    /// - Parameter show: Whether to show grid lines
    func toggleGridOverlay(_ show: Bool = true) {
        // Remove existing grid lines
        enumerateChildNodes(withName: "//grid_line") { node, _ in
            node.removeFromParent()
        }
        
        guard show else { return }
        
        // Add grid lines
        for x in 0...gridService.columns {
            let line = SKSpriteNode(color: SKColor.black.withAlphaComponent(0.1), 
                                   size: CGSize(width: 1, height: CGFloat(gridService.rows) * gridService.cellSize))
            line.position = CGPoint(x: gridService.shopOrigin.x + CGFloat(x) * gridService.cellSize, 
                                   y: gridService.shopOrigin.y + CGFloat(gridService.rows) * gridService.cellSize / 2)
            line.zPosition = -5
            line.name = "grid_line"
            addChild(line)
        }
        
        for y in 0...gridService.rows {
            let line = SKSpriteNode(color: SKColor.black.withAlphaComponent(0.1), 
                                   size: CGSize(width: CGFloat(gridService.columns) * gridService.cellSize, height: 1))
            line.position = CGPoint(x: gridService.shopOrigin.x + CGFloat(gridService.columns) * gridService.cellSize / 2, 
                                   y: gridService.shopOrigin.y + CGFloat(y) * gridService.cellSize)
            line.zPosition = -5
            line.name = "grid_line"
            addChild(line)
        }
        
        print("🎯 Grid overlay \(show ? "enabled" : "disabled")")
    }
}
