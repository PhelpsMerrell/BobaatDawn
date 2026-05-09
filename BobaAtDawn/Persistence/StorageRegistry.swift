//
//  StorageRegistry.swift
//  BobaAtDawn
//
//  Persistent registry of storage container contents (pantry + fridge).
//  Tracks which ingredients each container holds, how many of each, and
//  keeps both clients in sync via the WorldSync path.
//
//  Design rules (confirmed with Phelps, session 2026-04-18):
//    - 5 UNIQUE ingredient slots per container.
//    - Each slot stacks unlimited (int count).
//    - `store(containerName:ingredient:)` succeeds if the ingredient is
//      already present OR there's an unused slot. Fails if 5 unique
//      ingredients are already stored and the incoming one is new.
//    - `retrieveOne(containerName:ingredient:)` decrements count. If
//      count hits zero, the slot is removed entirely (so a later
//      different ingredient can take its place).
//
//  Networking:
//    - Local mutations fire `onDidMutate`, wired by SaveService to
//      persist to SwiftData (same pattern as WorldItemRegistry).
//    - Export/import via `snapshot()` / `loadAll(_:)` for WorldSync.
//

import Foundation

// MARK: - Storage Contents

/// A single container's inventory: ordered list of ingredient names and
/// their stack counts. Order is stable (insertion order) so slot sprite
/// positions don't jump around as the player deposits/retrieves.
struct StorageContents: Codable, Equatable {
    /// Ingredient name → stack count. The key order is preserved
    /// via `slotOrder` because Swift dictionaries don't guarantee it.
    var counts: [String: Int]
    
    /// Insertion-order list of ingredient names. Always the same set
    /// as `counts.keys`. Used to render slots in a stable order.
    var slotOrder: [String]
    
    static let empty = StorageContents(counts: [:], slotOrder: [])
    
    var isEmpty: Bool { slotOrder.isEmpty }
    var uniqueCount: Int { slotOrder.count }
    var totalCount: Int { counts.values.reduce(0, +) }
    
    func count(of ingredient: String) -> Int {
        counts[ingredient] ?? 0
    }
}

// MARK: - Storage Registry

final class StorageRegistry {
    static let shared = StorageRegistry()
    
    /// Hard cap on unique ingredients per container.
    static let uniqueSlotsPerContainer = 5
    
    /// Container name ("pantry" / "fridge") → contents.
    private var containers: [String: StorageContents] = [:]
    
    /// Fired after any mutation. SaveService wires this to persist-to-disk.
    var onDidMutate: (() -> Void)?
    
    private init() {}
    
    // MARK: - Queries
    
    func contents(of containerName: String) -> StorageContents {
        containers[containerName] ?? .empty
    }
    
    func allContainers() -> [String: StorageContents] {
        containers
    }
    
    /// Whether an ingredient can be stored in this container right now.
    /// True if the ingredient is already present, or there's an unused
    /// slot among the 5.
    func canStore(ingredient: String, in containerName: String) -> Bool {
        let contents = contents(of: containerName)
        if contents.counts[ingredient] != nil { return true }
        return contents.uniqueCount < Self.uniqueSlotsPerContainer
    }
    
    // MARK: - Mutations
    
    /// Store one unit of an ingredient in the named container. Returns
    /// true on success, false if the container has 5 unique ingredients
    /// already and this one isn't among them.
    @discardableResult
    func store(ingredient: String, in containerName: String) -> Bool {
        var contents = contents(of: containerName)
        
        if contents.counts[ingredient] != nil {
            contents.counts[ingredient, default: 0] += 1
        } else {
            guard contents.uniqueCount < Self.uniqueSlotsPerContainer else {
                Log.debug(.game, "StorageRegistry: \(containerName) full (5 unique ingredients)")
                return false
            }
            contents.counts[ingredient] = 1
            contents.slotOrder.append(ingredient)
        }
        
        containers[containerName] = contents
        onDidMutate?()
        DailyChronicleLedger.shared.recordIngredientDeposited(
            name: ingredient, container: containerName
        )
        return true
    }

    /// Remove one unit of an ingredient. Returns true on success. If the
    /// count hits zero, the slot is removed entirely (so a different
    /// ingredient can take its place later).
    @discardableResult
    func retrieveOne(ingredient: String, from containerName: String) -> Bool {
        var contents = contents(of: containerName)
        guard let current = contents.counts[ingredient], current > 0 else {
            return false
        }
        
        if current == 1 {
            contents.counts.removeValue(forKey: ingredient)
            contents.slotOrder.removeAll { $0 == ingredient }
        } else {
            contents.counts[ingredient] = current - 1
        }
        
        containers[containerName] = contents
        onDidMutate?()
        DailyChronicleLedger.shared.recordIngredientRetrieved(
            name: ingredient, container: containerName
        )
        return true
    }
    
    /// Clear a single container (used for debug/testing; not wired to any
    /// gameplay path).
    func clear(_ containerName: String) {
        guard containers[containerName] != nil else { return }
        containers.removeValue(forKey: containerName)
        onDidMutate?()
    }
    
    /// Wipe every container. Used by SaveService.clearAllSaveData.
    func clearAll() {
        guard !containers.isEmpty else { return }
        containers.removeAll()
        onDidMutate?()
    }

    /// Consume up to `count` units from a container, picking the
    /// ingredient with the highest current stack first. Returns the
    /// list of (ingredient, amount) tuples actually consumed. Used by
    /// the cook at breakfast/dinner to drain the pantry.
    ///
    /// Greedy by highest count to keep the pantry balanced — the
    /// alternative (round-robin or oldest-first) tends to leave one
    /// ingredient stuck at a single unit forever, blocking that slot.
    /// Greedy drains down the tall stack until something else is
    /// taller.
    @discardableResult
    func consume(
        upTo count: Int,
        from containerName: String
    ) -> [(ingredient: String, amount: Int)] {
        guard count > 0 else { return [] }
        var contents = contents(of: containerName)
        guard !contents.isEmpty else { return [] }

        var consumed: [String: Int] = [:]
        var remaining = count
        while remaining > 0 {
            // Pick the ingredient with the highest current count.
            // Ties broken by slotOrder (insertion order) for stability.
            let candidate = contents.slotOrder.max { lhs, rhs in
                let lc = contents.counts[lhs] ?? 0
                let rc = contents.counts[rhs] ?? 0
                if lc != rc { return lc < rc }
                let li = contents.slotOrder.firstIndex(of: lhs) ?? 0
                let ri = contents.slotOrder.firstIndex(of: rhs) ?? 0
                return li > ri
            }
            guard let pick = candidate, let stack = contents.counts[pick], stack > 0 else { break }
            // Consume one unit from the picked ingredient.
            if stack == 1 {
                contents.counts.removeValue(forKey: pick)
                contents.slotOrder.removeAll { $0 == pick }
            } else {
                contents.counts[pick] = stack - 1
            }
            consumed[pick, default: 0] += 1
            remaining -= 1
            if contents.isEmpty { break }
        }

        if !consumed.isEmpty {
            containers[containerName] = contents
            onDidMutate?()
            for (ingredient, amount) in consumed {
                for _ in 0..<amount {
                    DailyChronicleLedger.shared.recordIngredientRetrieved(
                        name: ingredient, container: containerName
                    )
                }
            }
        }
        return consumed.map { (ingredient: $0.key, amount: $0.value) }
    }
    
    // MARK: - Loading / Snapshot (for WorldSync + disk persistence)
    
    /// Bulk replace from a snapshot. Does NOT fire onDidMutate — used by
    /// the load-from-disk and incoming-worldSync paths that persist
    /// separately.
    func loadAll(_ snapshot: [String: StorageContents]) {
        self.containers = snapshot
        Log.info(.save, "StorageRegistry loaded \(snapshot.count) containers")
    }
    
    func snapshot() -> [String: StorageContents] {
        containers
    }
}
