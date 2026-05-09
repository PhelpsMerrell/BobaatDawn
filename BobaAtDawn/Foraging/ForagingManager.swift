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
import QuartzCore

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

// MARK: - Pending Spawn

/// A spawn the manager has reserved but not yet released into the
/// world. Used by `.scatteredPerLocationOverDay` to stagger spawning
/// throughout the day. Each pending entry has a target time — once
/// `now >= scheduledTime` AND the location has room (under its
/// concurrent cap), it gets promoted into a real `ForageSpawn`.
struct PendingSpawn {
    let spawnID: String
    let ingredient: ForageableIngredient
    let location: SpawnLocation
    let position: CGPoint
    /// Absolute CACurrentMediaTime at which this should attempt to spawn.
    var scheduledTime: TimeInterval
    /// Per-room concurrent cap to respect when promoting.
    let maxConcurrent: Int
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
            // Matcha — staggered throughout the day, 3-7 per forest room,
            // capped at 8 concurrent uncollected per room. Per design,
            // the forest economy gates how many items NPCs can find
            // and trade with the broker.
            SpawnProfile(
                ingredient: .matchaLeaf,
                locations: SpawnLocation.allForestRooms,
                rule: .scatteredPerLocationOverDay(
                    minPerDay: 3,
                    maxPerDay: 7,
                    maxConcurrent: 8
                )
            ),

            // Strawberries — same staggered behavior as matcha. The
            // 8-concurrent cap is shared per ingredient, not across
            // ingredients, so a room can hold up to 8 matcha AND 8
            // strawberries simultaneously — plenty of supply.
            SpawnProfile(
                ingredient: .strawberry,
                locations: SpawnLocation.allForestRooms,
                rule: .scatteredPerLocationOverDay(
                    minPerDay: 3,
                    maxPerDay: 7,
                    maxConcurrent: 8
                )
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

    /// Spawns scheduled to appear later in the day. Drained by `tick`.
    /// Each entry has an absolute target time and a per-room concurrent
    /// cap. When promoted, the entry is removed and a corresponding
    /// `ForageSpawn` is appended to `spawns`.
    private(set) var pendingSpawns: [PendingSpawn] = []

    /// Fired after a regeneration. Lets subscribers (GnomeManager) react
    /// to a new day's rock layout.
    var onRegenerated: ((Int) -> Void)?

    /// Fired when a pending spawn is promoted mid-day. Lets the active
    /// scene render the new ForageNode without waiting for a room
    /// re-entry. Argument is the freshly-promoted spawn.
    var onSpawnPromoted: ((ForageSpawn) -> Void)?

    private init() {}

    // MARK: - Day Reset

    /// Call when entering the forest or cave. If the day has advanced,
    /// wipe all spawns and regenerate from profiles.
    ///
    /// Host-authoritative: on the guest, this is a no-op. The guest's
    /// spawn state is delivered via `applySnapshot` from the host's
    /// `worldSync` exchange, and stays in sync with the host as long
    /// as that exchange happens at least once per day. (Mid-day day
    /// rollovers without a fresh worldSync will leave the guest on
    /// the previous day's spawns until reconnect — documented gap,
    /// see WorldSyncMessage.forageSpawnsJSON.)
    func refreshIfNeeded(dayCount: Int) {
        guard !MultiplayerService.shared.isGuest else {
            if dayCount != spawnDay {
                Log.debug(.forest, "Guest skipping foraging refresh for day \(dayCount) (waiting for host sync)")
            }
            return
        }
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
        pendingSpawns.removeAll()
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

        case let .scatteredPerLocationOverDay(minPerDay, maxPerDay, maxConcurrent):
            // Staggered spawning. For each location, roll a per-day
            // count and queue that many pending spawns at random times
            // throughout the day. The first ~25% of the day's worth of
            // spawns lands at dawn so the world doesn't feel barren
            // when the player wakes up; the rest stagger through.
            let now = CACurrentMediaTime()
            let dayDuration = TimeInterval(GameConfig.Time.dayDuration)
            // Front-load ¼ of the count so dawn isn't empty. The other
            // ¾ space out evenly across the rest of the day.
            for (locIndex, location) in profile.locations.enumerated() {
                let perDay = Int.random(in: max(0, minPerDay)...max(minPerDay, maxPerDay))
                guard perDay > 0 else { continue }
                let frontLoaded = max(1, perDay / 4)
                for i in 0..<perDay {
                    let id = "\(profile.ingredient.rawValue)_d\(spawnDay)_p\(profileIndex)_\(locIndex)_\(i)"
                    let position = randomPosition(
                        in: location,
                        ingredient: profile.ingredient,
                        index: i
                    )
                    let scheduledTime: TimeInterval
                    if i < frontLoaded {
                        // Spawn within the first ~5 seconds of the
                        // day, with a small random jitter so multiple
                        // items don't pop simultaneously.
                        scheduledTime = now + TimeInterval.random(in: 0...5)
                    } else {
                        // Distribute the rest across the day. Add a
                        // small gap from "now" so the front-loaded
                        // batch finishes first, plus jitter.
                        let lateBudget = dayDuration * 0.85
                        let slot = Double(i - frontLoaded) / Double(max(1, perDay - frontLoaded))
                        let jitter = TimeInterval.random(in: -lateBudget * 0.05...lateBudget * 0.05)
                        scheduledTime = now + 6.0 + (slot * lateBudget) + jitter
                    }
                    pendingSpawns.append(PendingSpawn(
                        spawnID: id,
                        ingredient: profile.ingredient,
                        location: location,
                        position: position,
                        scheduledTime: scheduledTime,
                        maxConcurrent: maxConcurrent
                    ))
                }
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

    // MARK: - Tick (Pending → Live)

    /// Promote any pending spawns whose time has come, respecting the
    /// per-room concurrent caps. Call from the active scene's update
    /// loop. Cheap when there's nothing to do (early return on empty).
    ///
    /// Host-authoritative: only the host (or solo) drives the schedule.
    /// On the guest side, pending spawns sit dormant and the host's
    /// world sync delivers the realized spawn list directly. This
    /// avoids both clients independently rolling and broadcasting
    /// near-simultaneous duplicates.
    func tick() {
        guard !MultiplayerService.shared.isGuest else { return }
        guard !pendingSpawns.isEmpty else { return }

        let now = CACurrentMediaTime()
        var promotedAny = false
        var index = 0

        while index < pendingSpawns.count {
            let pending = pendingSpawns[index]
            if now < pending.scheduledTime {
                index += 1
                continue
            }

            // Time has come — check the room's concurrent cap.
            let live = spawns.filter {
                $0.location == pending.location
                    && $0.ingredient == pending.ingredient
                    && !$0.isCollected
            }.count

            if live >= pending.maxConcurrent {
                // Room is full. Push this spawn's scheduled time out
                // a bit so we re-check it later instead of spinning.
                pendingSpawns[index].scheduledTime = now + TimeInterval.random(in: 8...20)
                index += 1
                continue
            }

            // Promote.
            let spawn = ForageSpawn(
                spawnID: pending.spawnID,
                ingredient: pending.ingredient,
                location: pending.location,
                position: pending.position,
                isCollected: false
            )
            spawns.append(spawn)
            pendingSpawns.remove(at: index)
            promotedAny = true
            onSpawnPromoted?(spawn)
            Log.debug(.forest, "Promoted pending \(spawn.ingredient.displayName) at \(spawn.location.stringKey)")
            // Don't advance index — the array shrunk, the next pending
            // moved into this slot.
        }

        if promotedAny {
            Log.debug(.forest, "Tick: \(pendingSpawns.count) pending remain")
        }
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

    // MARK: - Snapshot Export / Apply (Multiplayer Join Sync)

    /// Export the full forage state as a JSON envelope. Used by
    /// SaveService.exportWorldSync at join time so the guest can
    /// adopt the host's exact spawn layout for the day. Returns
    /// `"{}"` if encoding fails so callers always get a writable
    /// string.
    ///
    /// Pending-spawn `scheduledTime` values are translated to
    /// host-relative offsets here — the guest rebases to its own
    /// clock when applying. This keeps stagger timing approximately
    /// preserved across the network without requiring synchronized
    /// machine clocks.
    func exportSnapshot() -> String {
        let now = CACurrentMediaTime()
        let realized = spawns.map { spawn in
            ForageSpawnEntry(
                spawnID: spawn.spawnID,
                ingredient: spawn.ingredient.rawValue,
                locationKey: spawn.location.stringKey,
                position: CodablePoint(spawn.position),
                isCollected: spawn.isCollected
            )
        }
        let pending = pendingSpawns.map { p in
            PendingSpawnEntry(
                spawnID: p.spawnID,
                ingredient: p.ingredient.rawValue,
                locationKey: p.location.stringKey,
                position: CodablePoint(p.position),
                scheduledOffsetSeconds: max(0, p.scheduledTime - now),
                maxConcurrent: p.maxConcurrent
            )
        }
        let snapshot = ForageSpawnsSnapshot(
            spawnDay: spawnDay,
            spawns: realized,
            pendingSpawns: pending
        )
        guard let data = try? JSONEncoder().encode(snapshot),
              let json = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return json
    }

    /// Apply a previously-exported snapshot, replacing local state.
    /// Called from worldSync apply on the guest. No-op on empty or
    /// unparseable input — we never wipe local spawns because of a
    /// corrupt sync.
    ///
    /// Pending-spawn `scheduledOffsetSeconds` values are rebased to
    /// the local clock at apply time so stagger timing carries over
    /// without machine-clock skew.
    func applySnapshot(_ json: String) {
        guard !json.isEmpty, json != "{}",
              let data = json.data(using: .utf8),
              let snapshot = try? JSONDecoder().decode(ForageSpawnsSnapshot.self, from: data) else {
            return
        }
        let now = CACurrentMediaTime()
        spawnDay = snapshot.spawnDay
        spawns = snapshot.spawns.compactMap { entry in
            guard let ingredient = ForageableIngredient(rawValue: entry.ingredient),
                  let location = SpawnLocation(stringKey: entry.locationKey) else {
                return nil
            }
            return ForageSpawn(
                spawnID: entry.spawnID,
                ingredient: ingredient,
                location: location,
                position: entry.position.cgPoint,
                isCollected: entry.isCollected
            )
        }
        pendingSpawns = snapshot.pendingSpawns.compactMap { entry in
            guard let ingredient = ForageableIngredient(rawValue: entry.ingredient),
                  let location = SpawnLocation(stringKey: entry.locationKey) else {
                return nil
            }
            return PendingSpawn(
                spawnID: entry.spawnID,
                ingredient: ingredient,
                location: location,
                position: entry.position.cgPoint,
                scheduledTime: now + entry.scheduledOffsetSeconds,
                maxConcurrent: entry.maxConcurrent
            )
        }
        Log.info(.forest, "Foraging snapshot applied: day \(spawnDay), \(spawns.count) live, \(pendingSpawns.count) pending")
    }
}
