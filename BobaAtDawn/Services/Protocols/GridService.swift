//
//  GridService.swift
//  BobaAtDawn
//
//  Service protocol for grid-based world management
//

import SpriteKit

protocol GridService {
    // Grid configuration
    var cellSize: CGFloat { get }
    var columns: Int { get }
    var rows: Int { get }
    var shopOrigin: CGPoint { get }
    
    // Coordinate conversion
    func worldToGrid(_ worldPos: CGPoint) -> GridCoordinate
    func gridToWorld(_ gridPos: GridCoordinate) -> CGPoint
    
    // Cell management
    func isCellAvailable(_ cell: GridCoordinate) -> Bool
    func occupyCell(_ cell: GridCoordinate, with gameObject: GameObject)
    func freeCell(_ cell: GridCoordinate)
    func reserveCell(_ cell: GridCoordinate)
    func objectAt(_ cell: GridCoordinate) -> GameObject?
    
    // Character management
    func moveCharacterTo(_ cell: GridCoordinate)
    var currentCharacterPosition: GridCoordinate { get }
    
    // Pathfinding helpers
    func findNearestAvailableCell(to center: GridCoordinate, maxRadius: Int) -> GridCoordinate?
    func getAvailableAdjacentCells(to center: GridCoordinate) -> [GridCoordinate]
    
    // Debug/utility
    func printGridState()
}
