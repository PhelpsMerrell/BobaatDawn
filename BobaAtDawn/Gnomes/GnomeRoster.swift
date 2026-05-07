//
//  GnomeRoster.swift
//  BobaAtDawn
//
//  Bridge between `Data/gnome_data.json` (loaded by GnomeDataLoader)
//  and the runtime `GnomeIdentity` consumed by GnomeManager, GnomeNPC,
//  and GnomeConversationService.
//
//  The 18 gnomes that used to be hand-authored here as `static let`
//  records are now built on first access from the JSON. The named
//  accessors (bossThork, apprenticePip, kitchenCook, …) are preserved
//  so callers that reference a specific gnome by name (e.g.
//  GnomeManager.dinnerMinglePosition uses `kitchenCook.id`) continue
//  to compile — each is now a computed lookup by stable id.
//
//  Counts the manager expects (must match what the JSON ships):
//    1 boss          — supervises the mines
//    12 miners       — work the mines daily
//    5 housekeepers  — never leave the oak; cooks, cleaners, treasurer
//
//  Authoring rule: any gnome referenced by id from Swift code (anchor
//  names, debug menu, etc.) MUST exist in `gnome_data.json`. Missing
//  ids will trip a `fatalError` from `findRequired(_:)` at startup —
//  loud failure on misconfigured builds is preferable to a silent
//  drift between code and data.
//

import Foundation

// MARK: - Gnome Identity Record
/// One row in the runtime roster. Built from a `GnomeData` JSON record
/// via `GnomeRoster.bridge(_:)`. The fields the manager reads directly
/// (`id`, `role`, `homeOakRoom`, `homeAnchorName`, `flavorTags`,
/// `initialRank`) are kept here for stability — anything richer
/// (personality archetype, opinion stances, voice lines, lore,
/// explicit relationships) is reachable through the optional `data`
/// reference and is intended for LLM RAG prompts.
struct GnomeIdentity {
    let id: String                  // stable, e.g. "gnome_boss_thork"
    let displayName: String         // base name shown in dialogue bubbles
    let role: GnomeRole
    let homeOakRoom: Int            // OakRoom raw value (1=lobby, 2=left, 3=middle, 4=right)
    let homeAnchorName: String      // anchor in the oak SKS where they hang/sleep
    let flavorTags: [String]        // descriptors used by the conversation prompts
    let initialRank: GnomeRank      // starting rank (only meaningful for miners)
    /// Backing JSON record this identity was built from. Carries the
    /// rich personality, opinions, voice lines, and lore the LLM uses
    /// as RAG context for generated dialogue. Optional so any code path
    /// that constructs a GnomeIdentity directly (tests, fallbacks) does
    /// not have to invent a fake `GnomeData`.
    let data: GnomeData?

    init(
        id: String,
        displayName: String,
        role: GnomeRole,
        homeOakRoom: Int,
        homeAnchorName: String,
        flavorTags: [String],
        initialRank: GnomeRank,
        data: GnomeData? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.role = role
        self.homeOakRoom = homeOakRoom
        self.homeAnchorName = homeAnchorName
        self.flavorTags = flavorTags
        self.initialRank = initialRank
        self.data = data
    }
}

// MARK: - Gnome Roster

enum GnomeRoster {

    // MARK: - All

    /// The full roster, in JSON order. Cached on first access.
    /// JSON order today is: boss → 12 miners → 5 housekeepers, which
    /// matches the previous hand-authored ordering one-for-one.
    static var all: [GnomeIdentity] { cachedAll }

    /// Lazy cache. `static let` semantics make this run exactly once on
    /// first access of any roster API, after `GnomeDataLoader.shared`
    /// has loaded its database.
    private static let cachedAll: [GnomeIdentity] =
        GnomeDataLoader.shared.all.compactMap(bridge)

    /// Find an identity by id. O(n) but n=18.
    static func find(_ id: String) -> GnomeIdentity? {
        all.first { $0.id == id }
    }

    /// Look up an id that is known to exist in the JSON. Used by the
    /// named static accessors below. A missing id here means the
    /// authoring contract has been broken (Swift code references a
    /// gnome the JSON does not contain), so we fail loudly.
    private static func findRequired(_ id: String) -> GnomeIdentity {
        guard let identity = find(id) else {
            fatalError("[GnomeRoster] '\(id)' not found in gnome_data.json — fix the JSON or the reference")
        }
        return identity
    }

    // MARK: - Role Slices

    /// All miners, in roster order. Boss is excluded.
    static var miners: [GnomeIdentity] {
        all.filter { $0.role == .miner }
    }

    /// All housekeepers, in roster order.
    static var housekeepers: [GnomeIdentity] {
        all.filter { $0.role == .housekeeper }
    }

    /// The (single) boss.
    static var boss: GnomeIdentity { bossThork }

    // MARK: - Named Accessors (lookups by stable id)
    //
    // These mirror the old `static let` properties one-for-one. They
    // exist purely so code like `GnomeRoster.kitchenCook.id` keeps
    // working without changes.

    // The boss
    static var bossThork: GnomeIdentity { findRequired("gnome_boss_thork") }

    // 12 miners
    static var apprenticePip: GnomeIdentity { findRequired("gnome_apprentice_pip") }
    static var minerDurn:     GnomeIdentity { findRequired("gnome_miner_durn") }
    static var minerBess:     GnomeIdentity { findRequired("gnome_miner_bess") }
    static var minerOck:      GnomeIdentity { findRequired("gnome_miner_ock") }
    static var minerThistle:  GnomeIdentity { findRequired("gnome_miner_thistle") }
    static var minerGrim:     GnomeIdentity { findRequired("gnome_miner_grim") }
    static var minerMoss:     GnomeIdentity { findRequired("gnome_miner_moss") }
    static var minerClod:     GnomeIdentity { findRequired("gnome_miner_clod") }
    static var minerFenn:     GnomeIdentity { findRequired("gnome_miner_fenn") }
    static var minerRill:     GnomeIdentity { findRequired("gnome_miner_rill") }
    static var minerSedge:    GnomeIdentity { findRequired("gnome_miner_sedge") }
    static var minerToma:     GnomeIdentity { findRequired("gnome_miner_toma") }

    // 5 housekeepers
    static var lobbyGreeter:       GnomeIdentity { findRequired("gnome_lobby_greeter") }
    static var fireplaceKeeper:    GnomeIdentity { findRequired("gnome_fireplace_keeper") }
    static var kitchenCook:        GnomeIdentity { findRequired("gnome_kitchen_cook") }
    static var leftBedroomElder:   GnomeIdentity { findRequired("gnome_left_bedroom_elder") }
    static var middleBedroomSeer:  GnomeIdentity { findRequired("gnome_middle_bedroom_seer") }

    // MARK: - JSON → Runtime Bridge

    /// Build a runtime `GnomeIdentity` from one JSON record. Returns
    /// nil (with a logged error) if the record's `role` string can't
    /// be parsed — the bad record is then dropped from the roster
    /// rather than crashing the whole simulation.
    private static func bridge(_ data: GnomeData) -> GnomeIdentity? {
        guard let role = parseRole(data.role) else {
            Log.error(.npc, "[GnomeRoster] Unknown role '\(data.role)' for gnome \(data.id) — skipping")
            return nil
        }
        let rank = parseRank(data.rank, role: role)
        return GnomeIdentity(
            id: data.id,
            displayName: data.name,
            role: role,
            homeOakRoom: data.homeOakRoom,
            homeAnchorName: anchorName(for: data.id),
            flavorTags: data.personality.traits,
            initialRank: rank,
            data: data
        )
    }

    /// Map the JSON `role` string to the runtime enum. Returns nil for
    /// unknown values so the bridge can drop the row.
    private static func parseRole(_ raw: String) -> GnomeRole? {
        switch raw {
        case "boss":        return .boss
        case "miner":       return .miner
        case "housekeeper": return .housekeeper
        default:            return nil
        }
    }

    /// Map the JSON `rank` string to the runtime enum. Housekeepers get
    /// `.standard` because the rank field is `null` in JSON for them
    /// and the manager expects a non-optional starting rank.
    private static func parseRank(_ raw: String?, role: GnomeRole) -> GnomeRank {
        switch raw {
        case "junior":   return .junior
        case "standard": return .standard
        case "senior":   return .senior
        case "foreman":  return .foreman
        default:
            // Boss without a "foreman" rank is a JSON authoring slip —
            // fall through to .foreman to preserve the manager's
            // expectations. Housekeepers / unknown → .standard.
            return role == .boss ? .foreman : .standard
        }
    }

    /// Resolve the home anchor name from the gnome id. The anchor
    /// names live in the oak `.sks` scene — they are scene-layout
    /// details rather than identity data, so they are derived here
    /// instead of being authored in JSON.
    ///
    /// Anchor map (matches the previous hand-authored values exactly):
    ///   gnome_lobby_greeter      → gnome_anchor_greeter
    ///   gnome_fireplace_keeper   → gnome_anchor_fireplace_keeper
    ///   gnome_kitchen_cook       → gnome_anchor_kitchen
    ///   gnome_boss_thork         → gnome_anchor_greeter (shares lobby)
    ///   everyone else            → gnome_anchor_bedroom
    private static func anchorName(for id: String) -> String {
        switch id {
        case "gnome_lobby_greeter":    return "gnome_anchor_greeter"
        case "gnome_fireplace_keeper": return "gnome_anchor_fireplace_keeper"
        case "gnome_kitchen_cook":     return "gnome_anchor_kitchen"
        case "gnome_boss_thork":       return "gnome_anchor_greeter"
        default:                       return "gnome_anchor_bedroom"
        }
    }
}
