//
//  ForagingManager.swift
//  BobaAtDawn
//
//  Single source of truth for every foraged spawn in the world.
//  Replaces the three-way split of MatchaLeafManager / StrawberryManager
//  / CaveMushroomManager with one config-driven system.
//
//  Behavior:
//    - `refreshIfNeeded(dayCount:)` regenerates spawns at dawn rollover.
//    - Spawns live in memory, keyed by a unique spawn ID that survives
//      room transitions and multiplayer sync.
//    - `spawnsFor(_:)` returns the uncollected spawns for a given
//      forest/cave room so the scene can render them.
//    - `collect(spawnID:)` marks one collected (returns false if unknown
//      or already taken).
//
//  Extending with a new ingredient or location:
//    1. Add the case to `ForageableIngredient`.
//    2. Add a `SpawnProfile` to `defaultProfiles` below.
//

import CoreGraphics
import Foundation

// MARK: - Spawn Record

/// One placed forage instance. Position is world-space relative to the
/// scene the location maps to.
struct ForageSpawn {
    let spawnID: String
    let ingredient: ForageableIngredient
    let location: SpawnLocation
    let position: CGPoint
    var isCollected: Bool
}

// MARK: - Manager

final class ForagingManager {
    static let shared = ForagingManager()

    // MARK: - Configuration
    //
    // Edit this list to change spawning. Each entry is independent — you
    // can have the same ingredient in multiple profiles if you want
    // different rules for different areas (e.g. mushrooms one-per-room
    // in the cave AND scattered in the forest).

    /// The default spawn configuration. Replaced at runtime via
    /// `setProfiles(_:)` only for tests.
    var profiles: [SpawnProfile] = ForagingManager.defaultProfiles

    /// Cave rooms that contain rocks. The cave entrance (room 1) is the
    /// workshop floor (machine + waste bin) and gets no rocks.
    static let rockBearingCaveRooms: [SpawnLocation] = [
        .caveRoom(2), .caveRoom(3), .caveRoom(4)
    ]

    static var defaultProfiles: [SpawnProfile] {
        [
            // Matcha — 5 leaves scattered across the 5 forest rooms each day.
            SpawnProfile(
                ingredient: .matchaLeaf,
                locations: SpawnLocation.allForestRooms,
                rule: .scatteredTotal(count: 5)
            ),

            // Strawberries — one in 3 of the 5 forest rooms each day.
            SpawnProfile(
                ingredient: .strawberry,
                locations: SpawnLocation.allForestRooms,
                rule: .oneInRandomSubset(count: 3)
            ),

            // Mushrooms — one in every cave room every day.
            SpawnProfile(
                ingredient: .mushroom,
                locations: SpawnLocation.allCaveRooms,
                rule: .oneInEach
            ),

            // Rocks — keep every mining floor visibly stocked all day.
            // The gnomes (and the player) feed these into the mine
            // machine on the entrance floor.
            SpawnProfile(
                ingredient: .rock,
                locations: rockBearingCaveRooms,
                rule: .manyInEach(count: 20)
            ),
        ]
    }

    // MARK: - State

    /// Day the current spawns belong to. When `refreshIfNeeded` is
    /// called with a larger number, all spawns regenerate.
    private(set) var spawnDay: Int = -1

    /// All spawns for the current day. Flat list so multiplayer sync
    /// and lookup-by-id are trivial.
    private(set) var spawns: [ForageSpawn] = []

    /// Fired after a regeneration. Lets subscribers (GnomeManager) react
    /// to a new day's rock layout.
    var onRegenerated: ((Int) -> Void)?

    private init() {}

    // MARK: - Day Reset

    /// Call when entering the forest or cave. If the day has advanced,
    /// wipe all spawns and regenerate from profiles.
    func refreshIfNeeded(dayCount: Int) {
        guard dayCount != spawnDay else { return }
        spawnDay = dayCount
        regenerate()

        let byIngredient = Dictionary(grouping: spawns, by: { $0.ingredient })
        let summary = byIngredient
            .map { "\($0.key.displayName): \($0.value.count)" }
            .sorted()
            .joined(separator: ", ")
        Log.info(.forest, "Foraging refreshed for day \(dayCount) — \(summary)")
        onRegenerated?(dayCount)
    }

    private func regenerate() {
        spawns.removeAll()
        for (profileIndex, profile) in profiles.enumerated() {
            generate(profile: profile, profileIndex: profileIndex)
        }
    }

    // MARK: - Spawn Generation

    private func generate(profile: SpawnProfile, profileIndex: Int) {
        guard !profile.locations.isEmpty else { return }

        switch profile.rule {
        case .oneInEach:
            for (i, location) in profile.locations.enumerated() {
                let spawn = makeSpawn(
                    profile: profile,
                    profileIndex: profileIndex,
                    index: i,
                    location: location
                )
                spawns.append(spawn)
            }

        case let .manyInEach(count):
            guard count > 0 else { return }
            var index = 0
            for location in profile.locations {
                for _ in 0..<count {
                    let spawn = makeSpawn(
                        profile: profile,
                        profileIndex: profileIndex,
                        index: index,
                        location: location
                    )
                    spawns.append(spawn)
                    index += 1
                }
            }

        case let .oneInRandomSubset(count):
            var shuffled = profile.locations
            shuffled.shuffle()
            let picked = shuffled.prefix(min(count, shuffled.count))
            for (i, location) in picked.enumerated() {
                let spawn = makeSpawn(
                    profile: profile,
                    profileIndex: profileIndex,
                    index: i,
                    location: location
                )
                spawns.append(spawn)
            }

        case let .scatteredTotal(count):
            guard count > 0 else { return }
            // Shuffle locations so the first pass guarantees each room
            // gets at least one if `count >= locations.count`.
            var bag = profile.locations
            bag.shuffle()
            for i in 0..<count {
                let location = bag[i % bag.count]
                let spawn = makeSpawn(
                    profile: profile,
                    profileIndex: profileIndex,
                    index: i,
                    location: location
                )
                spawns.append(spawn)
            }
        }
    }

    private func makeSpawn(
        profile: SpawnProfile,
        profileIndex: Int,
        index: Int,
        location: SpawnLocation
    ) -> ForageSpawn {
        let id = "\(profile.ingredient.rawValue)_d\(spawnDay)_p\(profileIndex)_\(index)"
        return ForageSpawn(
            spawnID: id,
            ingredient: profile.ingredient,
            location: location,
            position: randomPosition(in: location, ingredient: profile.ingredient, index: index),
            isCollected: false
        )
    }

    // MARK: - Position Generation

    /// Random world-space position inside a traversable area for the
    /// given location. Forest rooms are wider than cave rooms; both stay
    /// clear of walls and transition zones.
    ///
    /// Rocks are spread on a coarse grid so 10 in one cave room don't
    /// pile on top of each other — looks more like a real mining floor.
    private func randomPosition(
        in location: SpawnLocation,
        ingredient: ForageableIngredient = .mushroom,
        index: Int = 0
    ) -> CGPoint {
        switch location {
        case .forestRoom:
            let x = CGFloat.random(in: -400...400)
            let y = CGFloat.random(in: -250...250)
            return CGPoint(x: x, y: y)
        case .caveRoom:
            // For rocks, lay them out on a 5×2 jittered grid so a cave
            // room visually reads as "lots of scattered rocks".
            if ingredient == .rock {
                let col = index % 5
                let row = (index / 5) % 2
                let baseX = CGFloat(col - 2) * 130 // -260, -130, 0, 130, 260
                let baseY = CGFloat(row) * 140 - 70 // -70 or 70
                let jitterX = CGFloat.random(in: -25...25)
                let jitterY = CGFloat.random(in: -25...25)
                return CGPoint(x: baseX + jitterX, y: baseY + jitterY)
            }
            let x = CGFloat.random(in: -300...300)
            let y = CGFloat.random(in: -200...200)
            return CGPoint(x: x, y: y)
        }
    }

    // MARK: - Queries

    /// Uncollected spawns for a specific location.
    func spawnsFor(_ location: SpawnLocation) -> [ForageSpawn] {
        spawns.filter { $0.location == location && !$0.isCollected }
    }

    /// Find a spawn by ID, collected or not (used by network handlers).
    func spawn(withID spawnID: String) -> ForageSpawn? {
        spawns.first { $0.spawnID == spawnID }
    }

    /// Total uncollected spawns of a given ingredient today.
    func uncollectedCount(of ingredient: ForageableIngredient) -> Int {
        spawns.filter { $0.ingredient == ingredient && !$0.isCollected }.count
    }

    // MARK: - Collection

    /// Mark a spawn collected. Returns true if the spawn existed and
    /// was not already collected.
    @discardableResult
    func collect(spawnID: String) -> Bool {
        guard let index = spawns.firstIndex(where: { $0.spawnID == spawnID }) else {
            Log.warn(.forest, "Tried to collect unknown spawn: \(spawnID)")
            return false
        }
        guard !spawns[index].isCollected else {
            Log.debug(.forest, "Spawn \(spawnID) already collected")
            return false
        }
        spawns[index].isCollected = true
        Log.info(.forest, "Collected \(spawns[index].ingredient.displayName) (\(spawnID))")
        // Chronicle hook — ledger gates internally to host/solo only.
        // Skip rocks (they're work items, not flavorful forageables).
        if spawns[index].ingredient != .rock {
            DailyChronicleLedger.shared.recordIngredientForaged(
                name: spawns[index].ingredient.rawValue
            )
        }
        return true
    }

    // MARK: - Gnome Convenience

    /// Pick the nearest uncollected rock spawn in any rock-bearing cave
    /// room, biased to the gnome's `preferredRoom` if non-nil. Returns
    /// nil if no rocks remain anywhere today.
    func nearestRockSpawn(preferredRoom: Int? = nil) -> ForageSpawn? {
        let allRocks = spawns.filter { $0.ingredient == .rock && !$0.isCollected }
        if let preferred = preferredRoom {
            let inPreferred = allRocks.filter {
                if case let .caveRoom(n) = $0.location, n == preferred { return true }
                return false
            }
            if let pick = inPreferred.randomElement() { return pick }
        }
        return allRocks.randomElement()
    }
}
