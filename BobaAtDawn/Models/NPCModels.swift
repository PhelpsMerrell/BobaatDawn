//
//  NPCModels.swift
//  BobaAtDawn
//
//  Data models for NPC dialogue, character system, and shared enums.
//
//  Schema v2 (introduced for the relationship/opinion system) extends
//  the original NPCData with:
//    - talkativeness         : Float (0...1, fixed at design time)
//    - personality           : NPCPersonality (optional)
//    - opinion_stances       : [topicID: OpinionStance]
//    - explicit_relationships: [ExplicitRelationship]
//    - past_life_echoes      : [PastLifeEcho]
//
//  All new fields are decoded as optional with sensible defaults so the
//  decoder doesn't fall over on partial data while the JSON is being
//  filled in.
//

import Foundation

// MARK: - NPC Character Data
struct NPCData: Codable {
    let id: String
    let name: String
    let animal: String
    let causeOfDeath: String
    let homeRoom: Int
    let dialogue: NPCDialogue

    // Schema v2 additions (optional — defaulted on decode for resilience)
    let talkativeness: Float
    let personality: NPCPersonality?
    let opinionStances: [String: OpinionStance]
    let explicitRelationships: [ExplicitRelationship]
    let pastLifeEchoes: [PastLifeEcho]

    // Schema v2.1 additions (optional — powers JSON-only fallback paths
    // when LLM dialogue is unavailable). Both decode-if-present so older
    // saves and partial JSONs still load cleanly.
    let tapFollowups: NPCTapFollowups?
    let chatter: NPCChatter?

    enum CodingKeys: String, CodingKey {
        case id, name, animal, dialogue
        case causeOfDeath = "cause_of_death"
        case homeRoom = "home_room"
        case talkativeness
        case personality
        case opinionStances = "opinion_stances"
        case explicitRelationships = "explicit_relationships"
        case pastLifeEchoes = "past_life_echoes"
        case tapFollowups = "tap_followups"
        case chatter
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id              = try c.decode(String.self, forKey: .id)
        name            = try c.decode(String.self, forKey: .name)
        animal          = try c.decode(String.self, forKey: .animal)
        causeOfDeath    = try c.decode(String.self, forKey: .causeOfDeath)
        homeRoom        = try c.decode(Int.self,    forKey: .homeRoom)
        dialogue        = try c.decode(NPCDialogue.self, forKey: .dialogue)

        talkativeness          = try c.decodeIfPresent(Float.self, forKey: .talkativeness) ?? 0.5
        personality            = try c.decodeIfPresent(NPCPersonality.self, forKey: .personality)
        opinionStances         = try c.decodeIfPresent([String: OpinionStance].self, forKey: .opinionStances) ?? [:]
        explicitRelationships  = try c.decodeIfPresent([ExplicitRelationship].self, forKey: .explicitRelationships) ?? []
        pastLifeEchoes         = try c.decodeIfPresent([PastLifeEcho].self, forKey: .pastLifeEchoes) ?? []

        tapFollowups           = try c.decodeIfPresent(NPCTapFollowups.self, forKey: .tapFollowups)
        chatter                = try c.decodeIfPresent(NPCChatter.self, forKey: .chatter)
    }

    /// Convenience initializer used by tests + fallback paths in BaseNPC.
    init(
        id: String, name: String, animal: String,
        causeOfDeath: String, homeRoom: Int, dialogue: NPCDialogue,
        talkativeness: Float = 0.5,
        personality: NPCPersonality? = nil,
        opinionStances: [String: OpinionStance] = [:],
        explicitRelationships: [ExplicitRelationship] = [],
        pastLifeEchoes: [PastLifeEcho] = [],
        tapFollowups: NPCTapFollowups? = nil,
        chatter: NPCChatter? = nil
    ) {
        self.id = id
        self.name = name
        self.animal = animal
        self.causeOfDeath = causeOfDeath
        self.homeRoom = homeRoom
        self.dialogue = dialogue
        self.talkativeness = talkativeness
        self.personality = personality
        self.opinionStances = opinionStances
        self.explicitRelationships = explicitRelationships
        self.pastLifeEchoes = pastLifeEchoes
        self.tapFollowups = tapFollowups
        self.chatter = chatter
    }
}

struct NPCDialogue: Codable {
    let day: [String]
    let night: [String]
}

// MARK: - Player Tap Followups

/// Per-NPC "player response" pools used when the LLM is unavailable
/// (iPad without Apple Intelligence, cold-start, error fallback). Each
/// pool is voice-matched to the NPC archetype so the satisfaction loop
/// still feels personal in JSON-only mode. Mirrors the kind/blunt pill
/// pair the LLM path generates.
struct NPCTapFollowups: Codable {
    let kind: [String]
    let blunt: [String]
}

// MARK: - NPC Ambient Chatter

/// Per-NPC ambient conversation pool used for NPC↔NPC chatter when the
/// LLM is unavailable. Keeps the same day/night split as `dialogue` so
/// the existential-tone shift still lands. Lines are written as full
/// conversation moves (questions, observations, redirects) so a 3–line
/// fallback conversation reads naturally without LLM stitching.
struct NPCChatter: Codable {
    let day: [String]
    let night: [String]
}

// MARK: - NPC Database (top-level JSON)

/// Schema v2 wraps the legacy `npcs` array with `schema_version` and a
/// global `opinion_topics` list. Both new fields decode as optional so a
/// pre-v2 JSON file still loads.
struct NPCDatabase: Codable {
    let schemaVersion: Int
    let opinionTopics: [OpinionTopic]
    let npcs: [NPCData]

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case opinionTopics = "opinion_topics"
        case npcs
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion  = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        opinionTopics  = try c.decodeIfPresent([OpinionTopic].self, forKey: .opinionTopics) ?? []
        npcs           = try c.decode([NPCData].self, forKey: .npcs)
    }
}

// MARK: - Animal Emoji Mapping
extension NPCData {
    /// Get emoji representation for this NPC's animal
    var emoji: String {
        switch animal.lowercased() {
        case "deer":      return "🦌"
        case "rabbit":    return "🐰"
        case "wolf":      return "🐺"
        case "mule":      return "🐴"
        case "pufferfish": return "🐡"
        case "owl":       return "🦉"
        case "fox":       return "🦊"
        case "songbird":  return "🐦"
        case "bear":      return "🐻"
        case "mouse":     return "🐭"
        case "hedgehog":  return "🦔"
        case "frog":      return "🐸"
        case "duck":      return "🦆"
        case "raccoon":   return "🦝"
        case "squirrel":  return "🐿️"
        case "bat":       return "🦇"
        default:          return "🦔"
        }
    }
    
    /// Get random dialogue line for current time context
    func getRandomDialogue(isNight: Bool) -> String {
        let lines = isNight ? dialogue.night : dialogue.day
        return lines.randomElement() ?? "..."
    }

    // MARK: - JSON Fallback Helpers

    /// Get a random kind player-response line. Used by the player-tap
    /// fallback when LLM dialogue is unavailable (iPad without Apple
    /// Intelligence, cold-start, error). Returns a generic warm reply
    /// when the JSON pool is missing or empty so the satisfaction loop
    /// still works on data older than schema v2.1.
    func getRandomKindFollowup() -> String {
        if let pool = tapFollowups?.kind, let line = pool.randomElement() {
            return line
        }
        return "That's nice to hear."
    }

    /// Get a random blunt player-response line. Mirrors `getRandomKindFollowup`
    /// but for the dismissive register — still safe to call on partial JSON.
    func getRandomBluntFollowup() -> String {
        if let pool = tapFollowups?.blunt, let line = pool.randomElement() {
            return line
        }
        return "Mm. Sure."
    }

    /// Get a random chatter line for the given time context. Used by the
    /// NPC↔NPC ambient conversation fallback when the LLM stream is nil.
    /// Falls back to the regular `dialogue` pool when chatter is missing,
    /// so behaviour degrades gracefully rather than silently going empty.
    func getRandomChatter(isNight: Bool) -> String {
        if let chatter = chatter {
            let pool = isNight ? chatter.night : chatter.day
            if let line = pool.randomElement() {
                return line
            }
        }
        return getRandomDialogue(isNight: isNight)
    }
    
    /// Resolve the AnimalType enum for this NPC data
    var animalType: AnimalType? {
        AnimalType.allCases.first { $0.characterId == id }
    }
}

// MARK: - NPC Database Extensions
extension NPCDatabase {
    func npcsInRoom(_ room: Int) -> [NPCData] {
        npcs.filter { $0.homeRoom == room }
    }
    
    var allResidents: [NPCData] { npcs }
    
    var roomDistribution: [Int: [NPCData]] {
        var distribution: [Int: [NPCData]] = [:]
        for room in 1...5 {
            distribution[room] = npcsInRoom(room)
        }
        return distribution
    }

    /// Look up a topic by its stable id.
    func topic(_ id: String) -> OpinionTopic? {
        opinionTopics.first { $0.id == id }
    }
}

// MARK: - Time Context
enum TimeContext {
    case day
    case night
    
    var isNight: Bool { self == .night }
}

// MARK: - Forest Animals with Character Mapping
enum AnimalType: String, CaseIterable {
    case fox = "🦊"
    case rabbit = "🐰"
    case hedgehog = "🦔"
    case frog = "🐸"
    case duck = "🦆"
    case bear = "🐻"
    case raccoon = "🦝"
    case squirrel = "🐿️"
    case deer = "🦌"
    case wolf = "🐺"
    case mule = "🐴"
    case pufferfish = "🐡"
    case owl = "🦉"
    case songbird = "🐦"
    case mouse = "🐭"
    case bat = "🦇"

    static var dayAnimals: [AnimalType] {
        [.fox, .rabbit, .hedgehog, .frog, .duck, .bear, .raccoon, .squirrel, .deer, .mule, .pufferfish, .songbird, .mouse]
    }

    static var nightAnimals: [AnimalType] {
        [.owl, .bat, .wolf]
    }

    static func random(isNight: Bool = false) -> AnimalType {
        let pool = isNight ? nightAnimals : dayAnimals
        return pool.randomElement() ?? .fox
    }
    
    /// Maps animal types to character IDs from JSON dialogue data
    var characterId: String? {
        switch self {
        case .deer:       return "qari_deer"
        case .rabbit:     return "timothy_rabbit"
        case .wolf:       return "gertrude_wolf"
        case .mule:       return "stanuel_mule"
        case .pufferfish: return "bb_james_pufferfish"
        case .owl:        return "luna_owl"
        case .fox:        return "finn_fox"
        case .songbird:   return "ivy_songbird"
        case .bear:       return "oscar_bear"
        case .mouse:      return "mira_mouse"
        case .hedgehog:   return "hazel_hedgehog"
        case .frog:       return "rivet_frog"
        case .duck:       return "della_duck"
        case .raccoon:    return "rascal_raccoon"
        case .squirrel:   return "nixie_squirrel"
        case .bat:        return "echo_bat"
        }
    }
}

// MARK: - NPC Response Types (for dialogue interactions)
enum NPCResponseType: String {
    case dismiss = "dismiss"
    case nice = "nice"
    case mean = "mean"
}
