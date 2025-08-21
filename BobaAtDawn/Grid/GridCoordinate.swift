//
//  GridCoordinate.swift
//  BobaAtDawn
//
//  Grid coordinate system for tile-based gameplay
//

import Foundation

struct GridCoordinate: Hashable, Codable {
    let x: Int
    let y: Int
    
    static let invalid = GridCoordinate(x: -1, y: -1)
    
    // Grid coordinate arithmetic
    func offset(dx: Int, dy: Int) -> GridCoordinate {
        return GridCoordinate(x: x + dx, y: y + dy)
    }
    
    // Get adjacent cells (4-directional)
    var adjacentCells: [GridCoordinate] {
        return [
            GridCoordinate(x: x + 1, y: y),     // Right
            GridCoordinate(x: x - 1, y: y),     // Left
            GridCoordinate(x: x, y: y + 1),     // Up
            GridCoordinate(x: x, y: y - 1)      // Down
        ]
    }
    
    // Manhattan distance between two grid coordinates
    func distance(to other: GridCoordinate) -> Int {
        return abs(x - other.x) + abs(y - other.y)
    }
    
    // Check if coordinate is within grid bounds
    func isValid(columns: Int = GameConfig.Grid.columns, rows: Int = GameConfig.Grid.rows) -> Bool {
        return x >= 0 && x < columns && y >= 0 && y < rows
    }
}

extension GridCoordinate: CustomStringConvertible {
    var description: String {
        return "(\(x), \(y))"
    }
}
