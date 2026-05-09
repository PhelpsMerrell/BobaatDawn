//
//  PersistenceModels.swift
//  BobaAtDawn
//
//  SwiftData models for minimal world state persistence
//

import SwiftData
import Foundation

// MARK: - World State (Single Source of Truth)
@Model
final class WorldState {
    var worldID: String = "save_slot_1"
    var slotIndex: Int = 1
    var slotName: String = WorldState.defaultSlotName(for: 1)
    var hasStartedGame: Bool = false
    var currentTimePhase: String = "day"
    var timeProgress: Float = 0.0
    var isTimeFlowing: Bool = true
    var cycleCount: Int = 0
    
    // NEW: Day counter — incremented each time night→dawn transition fires.
    // Ritual triggers when (dayCount % 3 == 0) and dayCount > 0.
    var dayCount: Int = 0
    
    // JSON string of current NPC positions/states
    var npcStatesJSON: String = "{}"
    
    // JSON array of persistent world items (trash + drinks on tables).
    // See WorldItemRegistry.
    var worldItemsJSON: String = "[]"
    
    // JSON blob of the player's currently-carried item.
    // See CharacterCarryState.
    var carryStateJSON: String = "{}"
    
    // JSON blob of ingredient station toggle states.
    // See StationPersistedState.
    var stationStatesJSON: String = "{}"
    
    // JSON blob of pantry/fridge contents, keyed by container name.
    // See StorageRegistry.
    var storageJSON: String = "{}"
    
    // JSON array of GnomeSnapshot — drives the persistent gnome simulation.
    // Defaults to empty array on fresh worlds. See GnomeManager.
    var gnomeStateJSON: String = "[]"

    // JSON blob of the broker economy state — box contents, broker gem
    // reserve, and transient flags (broker-away-from-desk,
    // treasurer-dispatched, treasurer-carrying-gems). See BrokerEconomyState
    // in GnomeManager. Defaults to "{}" which the apply path treats as
    // "keep current live state".
    var brokerEconomyJSON: String = "{}"
    
    // Treasury gem count (resets to 0 once it crosses TreasuryPile.resetThreshold).
    var treasuryGemCount: Int = 0

    // JSON array of MovableObjectEntry — editor-placed RotatableObjects
    // (tables / furniture) that have been rearranged from their .sks
    // default positions. See MovableObjectRegistry. Default "[]" means
    // everything at editor default.
    var movableObjectsJSON: String = "[]"
    
    // Simple key-value store for world flags
    var worldFlags: [String: Bool] = [:]
    
    // Last save timestamp
    var lastSaved: Date = Date()
    
    init(slotIndex: Int = 1, slotName: String? = nil) {
        self.slotIndex = max(1, slotIndex)
        self.worldID = Self.slotID(for: self.slotIndex)
        self.slotName = Self.sanitizedSlotName(slotName, slotIndex: self.slotIndex)
    }

    static func slotID(for index: Int) -> String {
        "save_slot_\(max(1, index))"
    }

    static func defaultSlotName(for index: Int) -> String {
        "Save Slot \(max(1, index))"
    }

    static func sanitizedSlotName(_ value: String?, slotIndex: Int) -> String {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? defaultSlotName(for: slotIndex) : trimmed
    }
}

// MARK: - NPC Memory (Tracks relationships with player)
@Model
final class NPCMemory {
    var saveSlotID: String = WorldState.slotID(for: 1)
    var npcID: String
    var name: String
    var animalType: String
    
    // Relationship with player (discovered through play)
    var hasMetPlayer: Bool = false
    var totalInteractions: Int = 0
    var lastInteractionDate: Date?
    
    // Satisfaction system (1-100)
    var satisfactionScore: Int = 50 // Starts neutral
    var totalDrinksReceived: Int = 0
    var niceTreatmentCount: Int = 0
    var meanTreatmentCount: Int = 0
    
    // Drink preferences (discovered through serving)
    var preferredFlavors: [String] = []
    var dislikedFlavors: [String] = []
    var favoriteBobaType: String = ""
    
    // Emotional state (affects dialogue selection)
    var currentMood: String = "neutral"
    
    // Liberation tracking
    var isLiberated: Bool = false
    var liberationDate: Date?
    
    // Satisfaction level helpers
    var satisfactionLevel: SatisfactionLevel {
        switch satisfactionScore {
        case 80...100: return .delighted
        case 60...79: return .happy
        case 40...59: return .neutral
        case 20...39: return .disappointed
        case 1...19: return .upset
        default: return .neutral
        }
    }
    
    init(npcID: String, name: String, animalType: String) {
        self.npcID = npcID
        self.name = name
        self.animalType = animalType
    }
    
    // MARK: - Satisfaction Modifiers
    func receivedDrink() {
        satisfactionScore = min(100, satisfactionScore + 5)
        totalDrinksReceived += 1
    }
    
    func receivedNiceTreatment() {
        satisfactionScore = min(100, satisfactionScore + 1)
        niceTreatmentCount += 1
    }
    
    func receivedMeanTreatment() {
        satisfactionScore = max(1, satisfactionScore - 1)
        meanTreatmentCount += 1
    }
    
    func recordInteraction() {
        totalInteractions += 1
        lastInteractionDate = Date()
        hasMetPlayer = true
    }
}

// MARK: - Satisfaction Levels
enum SatisfactionLevel: String, CaseIterable {
    case delighted = "delighted"
    case happy = "happy"
    case neutral = "neutral"
    case disappointed = "disappointed"
    case upset = "upset"
    
    var emoji: String {
        switch self {
        case .delighted: return "😍"
        case .happy: return "😊"
        case .neutral: return "😐"
        case .disappointed: return "😞"
        case .upset: return "😠"
        }
    }
    
    var dialogueModifier: String {
        switch self {
        case .delighted: return "[Absolutely loves you]"
        case .happy: return "[Enjoys your company]"
        case .neutral: return "[Feels neutral about you]"
        case .disappointed: return "[Seems disappointed]"
        case .upset: return "[Clearly upset with you]"
        }
    }
}

// MARK: - NPC Relationship Memory (NPC ↔ NPC opinion scores)

/// Persistent record of how one NPC feels about another. Created lazily
/// — `getOrCreateRelationship(of:toward:)` seeds the score from JSON
/// stance overlap on first access. Subsequent conversations and hostile
/// actions mutate the score in place.
///
/// One row per ordered pair (A → B). A's opinion of B and B's opinion
/// of A are tracked independently, since asymmetric grudges are part of
/// the design (Qari blames Rascal; Rascal barely notices).
@Model
final class NPCRelationshipMemory {
    var saveSlotID: String = WorldState.slotID(for: 1)
    /// Composite key: "\(ofNPCID)__\(towardNPCID)". Stored explicitly so
    /// SwiftData predicates can fetch by it without composite-key headaches.
    var pairKey: String

    /// Whose opinion this row records.
    var ofNPCID: String

    /// Of whom.
    var towardNPCID: String

    /// Clamped [-100, +100]. 0 = neutral, positive = friendly, negative = sour.
    var score: Int = 0

    /// Number of conversations these two have had since seeding.
    var conversationCount: Int = 0

    /// Last time anything moved this score. nil if never updated since seed.
    var lastUpdated: Date?

    /// Total tally of each interaction type that has been applied to this
    /// pair. Stored as a JSON-encoded `[String: Int]` so SwiftData doesn't
    /// need a separate child table. Use `interactionTallies` accessor.
    var interactionTalliesJSON: String = "{}"

    init(ofNPCID: String, towardNPCID: String, initialScore: Int = 0) {
        self.ofNPCID = ofNPCID
        self.towardNPCID = towardNPCID
        self.pairKey = "\(ofNPCID)__\(towardNPCID)"
        self.score = initialScore
    }

    /// Apply one interaction's `selfDelta` (when this row is the speaker)
    /// or `otherDelta` (when this row is the listener) to the score.
    func applyDelta(_ delta: Int, interaction: ConversationInteraction) {
        score = max(-100, min(100, score + delta))
        lastUpdated = Date()
        var tallies = interactionTallies
        tallies[interaction.rawValue, default: 0] += 1
        if let data = try? JSONEncoder().encode(tallies),
           let json = String(data: data, encoding: .utf8) {
            interactionTalliesJSON = json
        }
    }

    var interactionTallies: [String: Int] {
        guard let data = interactionTalliesJSON.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([String: Int].self, from: data) else {
            return [:]
        }
        return decoded
    }

    // Friendliness helpers — match thresholds in OpinionModels.swift.
    var isHostile:  Bool { score <= HostilityThreshold.hostile }
    var isAvoidant: Bool { score <= HostilityThreshold.avoidant }
    var isFriendly: Bool { score >= HostilityThreshold.friendly }
    var isClose:    Bool { score >= HostilityThreshold.close }
}

// MARK: - Shop Memory (Player's drink-making history)
@Model
final class ShopMemory {
    var saveSlotID: String = WorldState.slotID(for: 1)
    var totalDrinksMade: Int = 0
    var discoveredRecipes: [String] = []
    var averageCustomerSatisfaction: Float = 0.5
    var totalCustomersServed: Int = 0
    
    // Simple flags for discovered gameplay elements
    var hasUsedAllStations: Bool = false
    var hasServedNightCustomer: Bool = false
    var hasRotatedFurniture: Bool = false
    
    init() {}
}
