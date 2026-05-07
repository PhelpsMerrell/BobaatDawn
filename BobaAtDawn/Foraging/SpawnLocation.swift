//
//  SpawnLocation.swift
//  BobaAtDawn
//
//  Abstraction for "where an ingredient can live in the world."
//  Currently covers forest rooms (1-5) and cave rooms (1-4). Extend
//  with new cases (e.g. .bigOakTree(OakRoom), .shop) as the world grows.
//
//  `stringKey` is what gets sent over the network so the remote player
//  can scope their visual cleanup to the right scene.
//

import Foundation

enum SpawnLocation: Hashable, Codable {
    case forestRoom(Int)   // 1...5
    case caveRoom(Int)     // 1...4

    // MARK: - Convenience

    static let allForestRooms: [SpawnLocation] = (1...5).map { .forestRoom($0) }
    static let allCaveRooms:   [SpawnLocation] = (1...4).map { .caveRoom($0) }

    // MARK: - String Encoding (network + logs)

    /// Stable string key used in network messages and debug logs.
    /// Round-trips through `init(stringKey:)`.
    var stringKey: String {
        switch self {
        case let .forestRoom(n): return "forest_\(n)"
        case let .caveRoom(n):   return "cave_\(n)"
        }
    }

    init?(stringKey: String) {
        let parts = stringKey.split(separator: "_")
        guard parts.count == 2, let n = Int(parts[1]) else { return nil }
        switch parts[0] {
        case "forest": self = .forestRoom(n)
        case "cave":   self = .caveRoom(n)
        default:       return nil
        }
    }
}
