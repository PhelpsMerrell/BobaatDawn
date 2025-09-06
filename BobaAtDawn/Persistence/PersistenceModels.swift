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
    var worldID: String = "main_world"
    var currentTimePhase: String = "day"
    var timeProgress: Float = 0.0
    var isTimeFlowing: Bool = true
    var cycleCount: Int = 0
    
    // JSON string of current NPC positions/states
    var npcStatesJSON: String = "{}"
    
    // Simple key-value store for world flags
    var worldFlags: [String: Bool] = [:]
    
    // Last save timestamp
    var lastSaved: Date = Date()
    
    init() {
        self.worldID = "main_world"
    }
}

// MARK: - NPC Memory (Tracks relationships with player)
@Model
final class NPCMemory {
    var npcID: String
    var name: String
    var animalType: String
    
    // Relationship with player (discovered through play)
    var hasMetPlayer: Bool = false
    var totalInteractions: Int = 0
    var lastInteractionDate: Date?
    
    // NEW: Satisfaction system (1-100)
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

// MARK: - Shop Memory (Player's drink-making history)
@Model
final class ShopMemory {
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
