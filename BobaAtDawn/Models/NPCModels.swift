//
//  NPCModels.swift
//  BobaAtDawn
//
//  Data models for NPC dialogue and character system
//

import Foundation

// MARK: - NPC Character Data
struct NPCData: Codable {
    let id: String
    let name: String
    let animal: String
    let causeOfDeath: String
    let dialogue: NPCDialogue
    
    enum CodingKeys: String, CodingKey {
        case id, name, animal, dialogue
        case causeOfDeath = "cause_of_death"
    }
}

struct NPCDialogue: Codable {
    let day: [String]
    let night: [String]
}

struct NPCDatabase: Codable {
    let npcs: [NPCData]
}

// MARK: - Animal Emoji Mapping
extension NPCData {
    /// Get emoji representation for this NPC's animal
    var emoji: String {
        switch animal.lowercased() {
        case "deer": return "🦌"
        case "rabbit": return "🐰" 
        case "wolf": return "🐺"
        case "mule": return "🐴" // Using horse for mule
        case "pufferfish": return "🐡"
        case "owl": return "🦉"
        case "fox": return "🦊"
        case "songbird": return "🐦"
        case "bear": return "🐻"
        case "mouse": return "🐭"
        default: return "🦔" // Default hedgehog for unknown animals
        }
    }
    
    /// Get random dialogue line for current time context
    func getRandomDialogue(isNight: Bool) -> String {
        let lines = isNight ? dialogue.night : dialogue.day
        return lines.randomElement() ?? "..."
    }
}

// MARK: - Time Context
enum TimeContext {
    case day
    case night
    
    var isNight: Bool {
        return self == .night
    }
}
