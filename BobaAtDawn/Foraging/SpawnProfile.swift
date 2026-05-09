//
//  SpawnProfile.swift
//  BobaAtDawn
//
//  Config-as-data description of how one ingredient is sprinkled across
//  a set of locations each day.
//

import Foundation

// MARK: - Spawn Rules

/// How many instances to place and where they go.
enum SpawnRule {
    /// One spawn in every listed location. Used for dense ingredients
    /// (e.g. mushrooms in every cave room).
    case oneInEach

    /// `count` spawns in EVERY listed location. Used for high-volume
    /// ingredients like rocks (10 per cave floor).
    case manyInEach(count: Int)

    /// Pick `count` locations from the list at random, one spawn each.
    /// If `count` exceeds the list, every location gets one.
    case oneInRandomSubset(count: Int)

    /// Scatter `count` total spawns across the listed locations. Rooms
    /// can repeat (multiple spawns in one room possible). Every listed
    /// room is guaranteed at least one as long as `count >=` list size.
    case scatteredTotal(count: Int)

    /// Per-day total per location, distributed randomly throughout the
    /// day instead of all at dawn. The room never holds more than
    /// `maxConcurrent` uncollected spawns of this ingredient at once —
    /// pending spawns wait their turn if the room is full. Each room
    /// in `locations` gets an independent count rolled in [`minPerDay`,
    /// `maxPerDay`]. Used for the forest economy (matcha + strawberry).
    case scatteredPerLocationOverDay(
        minPerDay: Int,
        maxPerDay: Int,
        maxConcurrent: Int
    )
}

// MARK: - Profile

struct SpawnProfile {
    let ingredient: ForageableIngredient
    let locations: [SpawnLocation]
    let rule: SpawnRule
}
