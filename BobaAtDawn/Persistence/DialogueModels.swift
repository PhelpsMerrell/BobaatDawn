//
//  DialogueModels.swift
//  BobaAtDawn
//
//  SwiftData models for dynamic LLM-managed dialogue
//

import SwiftData
import Foundation

// MARK: - NPC Character (Core Data)
@Model
final class NPCCharacter {
    var npcID: String
    var name: String
    var animalType: String
    var causeOfDeath: String
    var homeRoom: Int
    
    // Relationship to dialogue lines
    @Relationship(deleteRule: .cascade) var dialogueLines: [DialogueLine] = []
    
    init(npcID: String, name: String, animalType: String, causeOfDeath: String, homeRoom: Int) {
        self.npcID = npcID
        self.name = name
        self.animalType = animalType
        self.causeOfDeath = causeOfDeath
        self.homeRoom = homeRoom
    }
}

// MARK: - Dialogue Line (LLM Generated)
@Model
final class DialogueLine {
    var lineID: String
    var text: String
    var timeContext: String // "day" or "night"
    
    // LLM can generate satisfaction-specific dialogue
    var minSatisfaction: Int = 0   // 0-100
    var maxSatisfaction: Int = 100 // 0-100
    
    // Metadata for LLM management
    var createdBy: String = "llm"  // "llm", "base", "player_choice"
    var createdAt: Date = Date()
    var isActive: Bool = true      // Can disable lines without deleting
    
    // Back-reference to character
    var character: NPCCharacter?
    
    init(lineID: String, text: String, timeContext: String, minSatisfaction: Int = 0, maxSatisfaction: Int = 100) {
        self.lineID = lineID
        self.text = text
        self.timeContext = timeContext
        self.minSatisfaction = minSatisfaction
        self.maxSatisfaction = maxSatisfaction
    }
}

// MARK: - Dialogue Extensions
extension NPCCharacter {
    
    /// Get appropriate dialogue for current context and satisfaction
    func getDialogue(timeContext: String, satisfactionScore: Int) -> DialogueLine? {
        let validLines = dialogueLines.filter { line in
            line.timeContext == timeContext &&
            line.isActive &&
            satisfactionScore >= line.minSatisfaction &&
            satisfactionScore <= line.maxSatisfaction
        }
        
        return validLines.randomElement()
    }
    
    /// Get all dialogue for a time context (for LLM analysis)
    func getAllDialogue(timeContext: String) -> [DialogueLine] {
        return dialogueLines.filter { $0.timeContext == timeContext && $0.isActive }
    }
}
