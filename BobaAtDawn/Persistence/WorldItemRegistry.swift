//
//  WorldItemRegistry.swift
//  BobaAtDawn
//
//  Persistent registry of dynamic placed items in the world — trash and
//  drinks-on-tables. Tracks items by location, survives scene transitions,
//  and syncs to SwiftData via SaveService for cross-session continuity.
//
//  Design:
//    - SpriteKit nodes that represent a persistent item store their
//      registry UUID in `node.userData["worldItemID"]`.
//    - Scene setup queries the registry for its location and rebuilds
//      the visual nodes from the stored data.
//    - Mutations fire `onDidMutate`, which SaveService wires to
//      persist the registry to disk.
//

import CoreGraphics
import Foundation

// MARK: - World Location

/// Where an item lives. Used as the primary filter for registry queries
/// and scene-local restoration.
enum WorldLocation: Codable, Hashable {
    case shop
    case forestRoom(Int)
    case house(forestRoom: Int, house: Int)  // reserved
    case oak(Int)                              // reserved
}

// MARK: - World Item Kinds

enum WorldItemKind: String, Codable {
    case trash
    case drinkOnTable
}

// MARK: - World Item

/// A single persistent item. The `metadata` dictionary carries kind-specific
/// info (drink ingredients, slot index) to avoid proliferating concrete types.
struct WorldItem: Codable {
    let id: String
    let kind: WorldItemKind
    let location: WorldLocation
    var position: CodablePoint
    var metadata: [String: String]
}

// MARK: - Registry

final class WorldItemRegistry {
    static let shared = WorldItemRegistry()

    private var items: [String: WorldItem] = [:]

    /// Fired after any mutation. SaveService wires this to persist-to-disk.
    var onDidMutate: (() -> Void)?

    private init() {}

    // MARK: - Loading

    /// Bulk-load items from disk. Does not fire onDidMutate so the load
    /// path doesn't immediately re-save.
    func loadAll(_ newItems: [WorldItem]) {
        self.items.removeAll()
        for item in newItems { self.items[item.id] = item }
        Log.info(.save, "WorldItemRegistry loaded \(newItems.count) items")
    }

    // MARK: - Mutations

    @discardableResult
    func add(_ item: WorldItem) -> WorldItem {
        items[item.id] = item
        onDidMutate?()
        return item
    }

    func remove(id: String) {
        guard items[id] != nil else { return }
        items.removeValue(forKey: id)
        onDidMutate?()
    }

    // MARK: - Queries

    func itemsAt(_ location: WorldLocation) -> [WorldItem] {
        items.values.filter { $0.location == location }
    }

    func items(of kind: WorldItemKind, at location: WorldLocation) -> [WorldItem] {
        items.values.filter { $0.kind == kind && $0.location == location }
    }

    func item(withID id: String) -> WorldItem? {
        items[id]
    }

    func allItems() -> [WorldItem] {
        Array(items.values)
    }

    /// Find the item nearest to a world position at a location, optionally
    /// filtered by kind. Used to reconcile remote messages (which send
    /// positions, not IDs) against the local registry.
    func nearestItem(kind: WorldItemKind? = nil,
                     at location: WorldLocation,
                     near position: CGPoint) -> WorldItem? {
        let candidates = items.values.filter {
            $0.location == location && (kind == nil || $0.kind == kind)
        }
        return candidates.min {
            let d1 = hypot($0.position.x - position.x, $0.position.y - position.y)
            let d2 = hypot($1.position.x - position.x, $1.position.y - position.y)
            return d1 < d2
        }
    }

    // MARK: - Bulk Operations

    /// Remove all items of a given kind — used for dawn rollovers.
    func removeAll(kind: WorldItemKind) {
        let ids = items.values.filter { $0.kind == kind }.map { $0.id }
        guard !ids.isEmpty else { return }
        for id in ids { items.removeValue(forKey: id) }
        onDidMutate?()
    }

    /// Remove every item at a location.
    func removeAll(at location: WorldLocation) {
        let ids = items.values.filter { $0.location == location }.map { $0.id }
        guard !ids.isEmpty else { return }
        for id in ids { items.removeValue(forKey: id) }
        onDidMutate?()
    }

    /// Clear everything (used by clearSaveData).
    func clear() {
        guard !items.isEmpty else { return }
        items.removeAll()
        onDidMutate?()
    }

    // MARK: - Factory Helpers

    static func makeDrinkOnTable(
        tablePosition: CGPoint,
        slotIndex: Int,
        hasTea: Bool, hasIce: Bool, hasBoba: Bool, hasFoam: Bool, hasLid: Bool
    ) -> WorldItem {
        WorldItem(
            id: UUID().uuidString,
            kind: .drinkOnTable,
            location: .shop,
            position: CodablePoint(tablePosition),
            metadata: [
                "slotIndex": "\(slotIndex)",
                "hasTea": "\(hasTea)",
                "hasIce": "\(hasIce)",
                "hasBoba": "\(hasBoba)",
                "hasFoam": "\(hasFoam)",
                "hasLid": "\(hasLid)"
            ]
        )
    }

    static func makeTrash(location: WorldLocation, at position: CGPoint) -> WorldItem {
        WorldItem(
            id: UUID().uuidString,
            kind: .trash,
            location: location,
            position: CodablePoint(position),
            metadata: [:]
        )
    }
}

// MARK: - Metadata Accessors

extension WorldItem {
    var slotIndex: Int { Int(metadata["slotIndex"] ?? "0") ?? 0 }
    var hasTea: Bool   { metadata["hasTea"]  == "true" }
    var hasIce: Bool   { metadata["hasIce"]  == "true" }
    var hasBoba: Bool  { metadata["hasBoba"] == "true" }
    var hasFoam: Bool  { metadata["hasFoam"] == "true" }
    var hasLid: Bool   { metadata["hasLid"]  == "true" }
}

// MARK: - Movable Object Entry

/// One persistent rearrangement of an editor-placed `RotatableObject`
/// (table, furniture). Keyed by the node's editor `name` (e.g. `table_3`,
/// `furniture_arrow`) so identity is stable across sessions and across
/// the host↔guest divide. Position + rotation are the world-truth that
/// gets broadcast and saved.
struct MovableObjectEntry: Codable {
    /// Editor-assigned node name. Stable identity. e.g. "table_3".
    let editorName: String
    /// World-space position the object should sit at when on the floor.
    var position: CodablePoint
    /// 0 / 90 / 180 / 270. Maps to RotationState.rawValue.
    var rotationDegrees: Int
    /// True while one of the two players is carrying this object.
    /// While `true`, scene rendering should leave the object floating
    /// above the carrying RemoteCharacter (or the local Character) and
    /// not stamp it into the grid.
    var isCarried: Bool
    /// Which player is carrying it: true = host, false = guest, nil if
    /// not carried. Lets a guest disambiguate "my partner is holding
    /// this" from "I am holding this" without needing a player ID.
    var carriedByHost: Bool?
}

// MARK: - Movable Object Registry

/// Tracks position + rotation of editor-placed `RotatableObject`s in the
/// shop scene that the player can rearrange (tables, furniture). Kept
/// alongside `WorldItemRegistry` because they share the same persistence
/// + auto-save pipeline. Keyed by editor name.
///
/// Scope: shop only. Forest furniture isn't movable in the current design.
/// Sacred table is excluded by name in the call sites.
final class MovableObjectRegistry {
    static let shared = MovableObjectRegistry()

    private var entries: [String: MovableObjectEntry] = [:]

    /// Fired after any mutation. SaveService wires this to persist-to-disk.
    var onDidMutate: (() -> Void)?

    private init() {}

    // MARK: - Loading

    /// Bulk-load from disk or worldSync. Does NOT fire onDidMutate so
    /// the load path doesn't immediately re-save.
    func loadAll(_ list: [MovableObjectEntry]) {
        entries.removeAll()
        for entry in list { entries[entry.editorName] = entry }
        Log.info(.save, "MovableObjectRegistry loaded \(list.count) entries")
    }

    // MARK: - Mutations

    /// Record/update the on-floor position + rotation of an object.
    /// Clears any in-flight carry state.
    func recordPlacement(editorName: String, position: CGPoint, rotationDegrees: Int) {
        let entry = MovableObjectEntry(
            editorName: editorName,
            position: CodablePoint(position),
            rotationDegrees: rotationDegrees,
            isCarried: false,
            carriedByHost: nil
        )
        entries[editorName] = entry
        onDidMutate?()
    }

    /// Mark an object as currently carried by `byHost` (true=host, false=guest).
    /// Position is left at last-known-floor so a disconnect mid-carry
    /// drops the object back where it was when picked up.
    func recordPickup(editorName: String, byHost: Bool) {
        if var entry = entries[editorName] {
            entry.isCarried = true
            entry.carriedByHost = byHost
            entries[editorName] = entry
        } else {
            // First-ever pickup of an object that hadn't been moved yet.
            // Stamp a placeholder; position will be overwritten by the
            // matching drop message.
            entries[editorName] = MovableObjectEntry(
                editorName: editorName,
                position: CodablePoint(.zero),
                rotationDegrees: 0,
                isCarried: true,
                carriedByHost: byHost
            )
        }
        onDidMutate?()
    }

    /// Update rotation for a carried object (the player can rotate it
    /// while in hand). No-op if the object isn't tracked yet.
    func recordRotation(editorName: String, rotationDegrees: Int) {
        guard var entry = entries[editorName] else { return }
        entry.rotationDegrees = rotationDegrees
        entries[editorName] = entry
        onDidMutate?()
    }

    // MARK: - Queries

    func entry(for editorName: String) -> MovableObjectEntry? {
        entries[editorName]
    }

    func allEntries() -> [MovableObjectEntry] {
        Array(entries.values)
    }

    func clear() {
        guard !entries.isEmpty else { return }
        entries.removeAll()
        onDidMutate?()
    }
}
