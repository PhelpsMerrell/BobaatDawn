//
//  GnomeData.swift
//  BobaAtDawn
//
//  Codable models mirroring `Data/gnome_data.json`. The JSON is the
//  single source of truth for gnome identity, personality, opinions,
//  and voice — Swift code (GnomeRoster, GnomeManager, GnomeNPC,
//  GnomeConversationService) reads from `GnomeDataLoader.shared` rather
//  than carrying hardcoded duplicates.
//
//  Schema notes
//  ------------
//  - `role` and `rank` are stored as raw strings here; conversion to the
//    runtime `GnomeRole` / `GnomeRank` enums happens at the bridge in
//    `GnomeRoster`. Keeping them strings means an unknown value (e.g.
//    a typo while authoring) won't crash decode — it just fails to
//    resolve into a runtime identity.
//  - `opinion_stances` are stored as `[String: Int]` because the gnome
//    JSON uses an integer scale (intent: 0–5 with 3 = neutral) instead
//    of the named-stance enum the NPC schema uses. Nothing currently
//    consumes these values; they are preserved for future RAG usage.
//  - All "filler" fields the user populates later (`gender`, `age`,
//    `lore`, `voice_lines`, `explicit_relationships`) are tolerated as
//    empty strings / `0` / empty arrays. The decoder does not require
//    them to be filled in.
//

import Foundation

// MARK: - Opinion Topic

/// One of the global "things gnomes might have an opinion on" defined
/// at the top of `gnome_data.json`. Parallel in shape to the NPC
/// `OpinionTopic`, but kept as its own type so the gnome and NPC
/// schemas can evolve independently.
struct GnomeOpinionTopic: Codable, Equatable {
    let id: String        // stable key, e.g. "gems", "the_machine"
    let label: String     // human-readable, suitable for prompts
    let axis: String      // grouping hint: "fear" | "wonder" | "tastes" | "habit" | "social"
}

// MARK: - Personality

/// Voice/style hints fed to the LLM. Mirrors `personality` block in JSON.
/// `archetype` and the arrays are non-optional so the decoder can rely
/// on a concrete (possibly empty) shape downstream — saves the prompt
/// builder from null-checking.
struct GnomePersonalityData: Codable, Equatable {
    let archetype: String
    let traits: [String]
    let speechQuirks: [String]

    enum CodingKeys: String, CodingKey {
        case archetype, traits
        case speechQuirks = "speech_quirks"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        archetype    = try c.decodeIfPresent(String.self, forKey: .archetype) ?? ""
        traits       = try c.decodeIfPresent([String].self, forKey: .traits) ?? []
        speechQuirks = try c.decodeIfPresent([String].self, forKey: .speechQuirks) ?? []
    }

    init(archetype: String, traits: [String], speechQuirks: [String]) {
        self.archetype = archetype
        self.traits = traits
        self.speechQuirks = speechQuirks
    }
}

// MARK: - Explicit Relationship

/// Hand-authored relationship adjustment between two gnomes.
/// Currently unused by runtime — gnomes do not yet have a pairwise
/// opinion-score system the way NPCs do — but parsed and preserved
/// so it can be wired up later without re-loading the file.
struct GnomeExplicitRelationship: Codable, Equatable {
    let with: String      // other gnome's id
    let delta: Int        // signed adjustment
    let reason: String    // designer note + LLM hint
}

// MARK: - GnomeData

/// One row from the `gnomes` array. Direct mirror of the JSON record.
/// Maps to a runtime `GnomeIdentity` via the bridge in `GnomeRoster`.
struct GnomeData: Codable, Equatable {
    let id: String
    let name: String
    let gender: String                 // empty string allowed
    let age: Int                       // 0 allowed
    let role: String                   // "boss" | "miner" | "housekeeper"
    let rank: String?                  // "junior" | "standard" | "senior" | "foreman" | nil
    let homeOakRoom: Int               // 1...4
    let lore: String                   // empty string allowed
    let personality: GnomePersonalityData
    let opinionStances: [String: Int]
    let explicitRelationships: [GnomeExplicitRelationship]
    let voiceLines: [String]

    enum CodingKeys: String, CodingKey {
        case id, name, gender, age, role, rank, lore, personality
        case homeOakRoom = "home_oak_room"
        case opinionStances = "opinion_stances"
        case explicitRelationships = "explicit_relationships"
        case voiceLines = "voice_lines"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id                    = try c.decode(String.self, forKey: .id)
        name                  = try c.decode(String.self, forKey: .name)
        gender                = try c.decodeIfPresent(String.self, forKey: .gender) ?? ""
        age                   = try c.decodeIfPresent(Int.self, forKey: .age) ?? 0
        role                  = try c.decode(String.self, forKey: .role)
        rank                  = try c.decodeIfPresent(String.self, forKey: .rank)
        homeOakRoom           = try c.decode(Int.self, forKey: .homeOakRoom)
        lore                  = try c.decodeIfPresent(String.self, forKey: .lore) ?? ""
        personality           = try c.decodeIfPresent(GnomePersonalityData.self, forKey: .personality)
                                ?? GnomePersonalityData(archetype: "", traits: [], speechQuirks: [])
        opinionStances        = try c.decodeIfPresent([String: Int].self, forKey: .opinionStances) ?? [:]
        explicitRelationships = try c.decodeIfPresent([GnomeExplicitRelationship].self, forKey: .explicitRelationships) ?? []
        voiceLines            = try c.decodeIfPresent([String].self, forKey: .voiceLines) ?? []
    }
}

// MARK: - Pool Lines

/// Hardcoded NPC line pools relocated from the old private
/// `GnomePoolLines` enum in `GnomeConversationService.swift`. Putting
/// them in JSON lets the user edit voice without recompiling.
///
/// All buckets default to empty arrays so a missing `gnome_pool_lines`
/// block (older JSON, partial authoring) doesn't break decode — the
/// conversation service falls back to a generic line in that case.
struct GnomePoolLinesData: Codable, Equatable {
    let boss: [String]
    let minerCave: [String]
    let minerAtHome: [String]
    let minerInTransit: [String]
    let housekeeperDay: [String]
    let housekeeperNight: [String]
    let brokerDay: [String]
    let brokerNight: [String]
    let treasurerDay: [String]
    let treasurerNight: [String]

    enum CodingKeys: String, CodingKey {
        case boss
        case minerCave        = "miner_cave"
        case minerAtHome      = "miner_at_home"
        case minerInTransit   = "miner_in_transit"
        case housekeeperDay   = "housekeeper_day"
        case housekeeperNight = "housekeeper_night"
        case brokerDay        = "broker_day"
        case brokerNight      = "broker_night"
        case treasurerDay     = "treasurer_day"
        case treasurerNight   = "treasurer_night"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        boss              = try c.decodeIfPresent([String].self, forKey: .boss) ?? []
        minerCave         = try c.decodeIfPresent([String].self, forKey: .minerCave) ?? []
        minerAtHome       = try c.decodeIfPresent([String].self, forKey: .minerAtHome) ?? []
        minerInTransit    = try c.decodeIfPresent([String].self, forKey: .minerInTransit) ?? []
        housekeeperDay    = try c.decodeIfPresent([String].self, forKey: .housekeeperDay) ?? []
        housekeeperNight  = try c.decodeIfPresent([String].self, forKey: .housekeeperNight) ?? []
        brokerDay         = try c.decodeIfPresent([String].self, forKey: .brokerDay) ?? []
        brokerNight       = try c.decodeIfPresent([String].self, forKey: .brokerNight) ?? []
        treasurerDay      = try c.decodeIfPresent([String].self, forKey: .treasurerDay) ?? []
        treasurerNight    = try c.decodeIfPresent([String].self, forKey: .treasurerNight) ?? []
    }

    /// Hand-rolled empty initializer for the empty-database fallback path.
    init() {
        boss = []; minerCave = []; minerAtHome = []; minerInTransit = []
        housekeeperDay = []; housekeeperNight = []
        brokerDay = []; brokerNight = []
        treasurerDay = []; treasurerNight = []
    }
}

// MARK: - GnomeDatabase

/// Top-level wrapper for the JSON file. Parallels `NPCDatabase`.
struct GnomeDatabase: Codable {
    let schemaVersion: Int
    let opinionTopics: [GnomeOpinionTopic]
    let poolLines: GnomePoolLinesData
    let gnomes: [GnomeData]

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case opinionTopics = "gnome_opinion_topics"
        case poolLines     = "gnome_pool_lines"
        case gnomes
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        opinionTopics = try c.decodeIfPresent([GnomeOpinionTopic].self, forKey: .opinionTopics) ?? []
        poolLines     = try c.decodeIfPresent(GnomePoolLinesData.self, forKey: .poolLines) ?? GnomePoolLinesData()
        gnomes        = try c.decode([GnomeData].self, forKey: .gnomes)
    }
}
