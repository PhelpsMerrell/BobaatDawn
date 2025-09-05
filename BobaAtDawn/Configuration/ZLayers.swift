//
//  ZLayers.swift
//  BobaAtDawn
//
//  Centralized z-position layer management system
//  All z-positions in the game should reference these constants
//

import CoreGraphics

/// Z-position layering system with clear semantic grouping
/// Lower values appear behind higher values
struct ZLayers {
    
    // MARK: - Background Layers (Negative values)
    /// Floor and ground elements
    static let floor: CGFloat = -100
    static let floorDecoration: CGFloat = -90
    static let shopFloorBounds: CGFloat = -80
    
    /// Walls and boundaries
    static let walls: CGFloat = -50
    static let wallDecoration: CGFloat = -45
    
    // MARK: - Ground Level Objects (0-19)
    /// Default layer for most world objects
    static let groundObjects: CGFloat = 0
    
    /// Furniture and environment
    static let furniture: CGFloat = 5
    static let tables: CGFloat = 5
    static let decorations: CGFloat = 8
    
    /// Interactive displays
    static let drinkCreator: CGFloat = 10
    static let drinkDisplay: CGFloat = 11
    
    // MARK: - Interactive Layer (20-39)
    /// Ingredient stations
    static let stations: CGFloat = 20
    static let stationEffects: CGFloat = 21
    
    /// NPCs below character for proper layering
    static let npcs: CGFloat = 25
    static let npcEffects: CGFloat = 26
    
    /// Special enemies (snail)
    static let enemies: CGFloat = 27
    static let enemyEffects: CGFloat = 28
    
    /// Player character - always visible above NPCs
    static let character: CGFloat = 30
    static let characterEffects: CGFloat = 31
    
    // MARK: - Floating/Carried Items (40-49)
    /// Items being carried or floating
    static let carriedItems: CGFloat = 40
    static let itemEffects: CGFloat = 41
    
    // MARK: - Environment Systems (50-69)
    /// Time and weather systems
    static let timeSystem: CGFloat = 50
    static let timeSystemLabels: CGFloat = 51
    
    /// Doors and transitions
    static let doors: CGFloat = 60
    static let doorEffects: CGFloat = 61
    
    // MARK: - UI and Overlay Elements (70+)
    /// Feedback and indicators
    static let touchFeedback: CGFloat = 70
    static let gridOverlay: CGFloat = 75
    
    /// Dialogue and menus
    static let dialogueBackground: CGFloat = 90
    static let dialogueText: CGFloat = 91
    static let dialogueUI: CGFloat = 100
    
    // MARK: - Debug Layers (Optional, very high)
    static let debugOverlay: CGFloat = 999
    
    // MARK: - Helper Methods
    
    /// Get appropriate z-position for an object type
    static func layerFor(objectType: ObjectType) -> CGFloat {
        switch objectType {
        case .furniture:
            return furniture
        case .station:
            return stations
        case .drink, .completedDrink:
            return groundObjects
        }
    }
    
    /// Check if one layer should appear above another
    static func isAbove(_ layer1: CGFloat, _ layer2: CGFloat) -> Bool {
        return layer1 > layer2
    }
    
    /// Get a slightly offset z-position to prevent exact overlaps
    static func offset(_ baseLayer: CGFloat, by amount: CGFloat = 0.1) -> CGFloat {
        return baseLayer + amount
    }
    
    /// Ensure child nodes appear above their parent
    static func childLayer(for parentLayer: CGFloat) -> CGFloat {
        return parentLayer + 1
    }
}

// MARK: - Z-Layer Groups for Organization
extension ZLayers {
    
    /// All background layers
    static var backgroundLayers: [CGFloat] {
        [floor, floorDecoration, shopFloorBounds, walls, wallDecoration]
    }
    
    /// All interactive object layers
    static var interactiveLayers: [CGFloat] {
        [groundObjects, furniture, drinkCreator, stations, npcs, character]
    }
    
    /// All UI/overlay layers
    static var uiLayers: [CGFloat] {
        [touchFeedback, dialogueBackground, dialogueText, dialogueUI]
    }
    
    /// Validate that a z-position is within expected ranges
    static func validate(_ zPosition: CGFloat, for category: String) -> Bool {
        switch category {
        case "background":
            return zPosition < 0
        case "interactive":
            return zPosition >= 0 && zPosition < 50
        case "ui":
            return zPosition >= 70
        default:
            return true
        }
    }
}

// MARK: - Migration Helper
extension ZLayers {
    
    /// Maps old z-positions to new system for easier migration
    static func migrate(oldZPosition: CGFloat) -> CGFloat {
        switch oldZPosition {
        case -10: return floor
        case -8: return shopFloorBounds
        case -5: return walls
        case 1: return tables
        case 3: return groundObjects
        case 6: return drinkCreator
        case 10: return character
        case 11: return timeSystemLabels
        case 12: return npcs
        case 15: return stations
        case 20: return doors
        default: return groundObjects
        }
    }
}
