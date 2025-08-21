//
//  GridWorld.swift
//  BobaAtDawn
//
//  Grid service implementation using dependency injection
//

import SpriteKit

class GridWorld: GridService {
    
    // MARK: - Configuration
    let cellSize: CGFloat = GameConfig.Grid.cellSize
    let columns: Int = GameConfig.Grid.columns
    let rows: Int = GameConfig.Grid.rows
    let shopOrigin: CGPoint = GameConfig.Grid.shopOrigin
    
    // MARK: - State
    private var occupiedCells: [GridCoordinate: GameObject] = [:]
    private var reservedCells: Set<GridCoordinate> = []
    private var characterPosition = GameConfig.Grid.characterStartPosition
    
    init() {
        print("🎯 GridWorld initialized with DI: \(columns)x\(rows) grid with \(cellSize)pt cells")
    }
    
    // MARK: - Coordinate Conversion
    
    func worldToGrid(_ worldPos: CGPoint) -> GridCoordinate {
        let x = Int((worldPos.x - shopOrigin.x) / cellSize)
        let y = Int((worldPos.y - shopOrigin.y) / cellSize)
        return GridCoordinate(x: max(0, min(columns - 1, x)), 
                             y: max(0, min(rows - 1, y)))
    }
    
    func gridToWorld(_ gridPos: GridCoordinate) -> CGPoint {
        let x = shopOrigin.x + (CGFloat(gridPos.x) * cellSize) + (cellSize / 2)
        let y = shopOrigin.y + (CGFloat(gridPos.y) * cellSize) + (cellSize / 2)
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
    
    // MARK: - Pathfinding Helpers
    
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

// MARK: - GridCoordinate Extension for Validation
extension GridCoordinate {
    func isValid() -> Bool {
        return x >= 0 && x < GameConfig.Grid.columns && y >= 0 && y < GameConfig.Grid.rows
    }
}
