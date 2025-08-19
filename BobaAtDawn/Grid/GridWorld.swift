//
//  GridWorld.swift
//  BobaAtDawn
//
//  Central grid management system for tile-based gameplay
//

import SpriteKit

class GridWorld {
    static let shared = GridWorld()
    
    // Grid configuration
    static let cellSize: CGFloat = 60  // Increased from 40pt for better touch targets
    static let columns = 33  // 2000pt world width ÷ 60 ≈ 33
    static let rows = 25     // 1500pt world height ÷ 60 = 25
    static let shopOrigin = CGPoint(x: -1000, y: -750)  // Bottom-left of world
    
    // Grid state
    private var occupiedCells: [GridCoordinate: GameObject] = [:]
    private var reservedCells: Set<GridCoordinate> = []
    private var characterPosition = GridCoordinate(x: 16, y: 12)  // Center of world (adjusted for new grid)
    
    private init() {
        print("🎯 GridWorld initialized: \(GridWorld.columns)x\(GridWorld.rows) grid with \(GridWorld.cellSize)pt cells")
    }
    
    // MARK: - Coordinate Conversion
    
    func worldToGrid(_ worldPos: CGPoint) -> GridCoordinate {
        let x = Int((worldPos.x - GridWorld.shopOrigin.x) / GridWorld.cellSize)
        let y = Int((worldPos.y - GridWorld.shopOrigin.y) / GridWorld.cellSize)
        return GridCoordinate(x: max(0, min(GridWorld.columns - 1, x)), 
                             y: max(0, min(GridWorld.rows - 1, y)))
    }
    
    func gridToWorld(_ gridPos: GridCoordinate) -> CGPoint {
        let x = GridWorld.shopOrigin.x + (CGFloat(gridPos.x) * GridWorld.cellSize) + (GridWorld.cellSize / 2)
        let y = GridWorld.shopOrigin.y + (CGFloat(gridPos.y) * GridWorld.cellSize) + (GridWorld.cellSize / 2)
        return CGPoint(x: x, y: y)
    }
    
    // MARK: - Cell Management
    
    func isCellAvailable(_ cell: GridCoordinate) -> Bool {
        guard cell.isValid() else { return false }
        return !occupiedCells.keys.contains(cell) && !reservedCells.contains(cell)
    }
    
    func occupyCell(_ cell: GridCoordinate, with gameObject: GameObject) {
        guard cell.isValid() else { return }
        occupiedCells[cell] = gameObject
        print("🎯 Cell \(cell) occupied by \(gameObject.objectType)")
    }
    
    func freeCell(_ cell: GridCoordinate) {
        if let gameObject = occupiedCells.removeValue(forKey: cell) {
            print("🎯 Cell \(cell) freed from \(gameObject.objectType)")
        }
    }
    
    func reserveCell(_ cell: GridCoordinate) {
        guard cell.isValid() else { return }
        reservedCells.insert(cell)
        print("🎯 Cell \(cell) reserved")
    }
    
    func objectAt(_ cell: GridCoordinate) -> GameObject? {
        return occupiedCells[cell]
    }
    
    // MARK: - Character Management
    
    func moveCharacterTo(_ cell: GridCoordinate) {
        guard cell.isValid() else { return }
        let oldPosition = characterPosition
        characterPosition = cell
        print("🎯 Character moved from \(oldPosition) to \(cell)")
    }
    
    var currentCharacterPosition: GridCoordinate {
        return characterPosition
    }
    
    // MARK: - Utility Methods
    
    func findNearestAvailableCell(to center: GridCoordinate, maxRadius: Int = 5) -> GridCoordinate? {
        // Spiral search outward from center
        for radius in 1...maxRadius {
            for x in (center.x - radius)...(center.x + radius) {
                for y in (center.y - radius)...(center.y + radius) {
                    // Only check cells on the border of current radius
                    if abs(x - center.x) == radius || abs(y - center.y) == radius {
                        let candidate = GridCoordinate(x: x, y: y)
                        if isCellAvailable(candidate) {
                            return candidate
                        }
                    }
                }
            }
        }
        return nil
    }
    
    func getAvailableAdjacentCells(to center: GridCoordinate) -> [GridCoordinate] {
        return center.adjacentCells.filter { isCellAvailable($0) }
    }
    
    // MARK: - Debug
    
    func printGridState() {
        print("🎯 Grid State:")
        print("   Character at: \(characterPosition)")
        print("   Occupied cells: \(occupiedCells.count)")
        print("   Reserved cells: \(reservedCells.count)")
        for (cell, gameObject) in occupiedCells {
            print("   \(cell): \(gameObject.objectType)")
        }
    }
}
