//
//  NPCModels.swift
//  BobaAtDawn
//
//  Data models for NPC dialogue, character system, and shared enums
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
    
    enum CodingKeys: String, CodingKey {
        case id, name, animal, dialogue
        case causeOfDeath = "cause_of_death"
        case homeRoom = "home_room"
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
