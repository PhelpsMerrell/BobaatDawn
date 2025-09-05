//
//  IngredientType.swift
//  BobaAtDawn
//
//  Simple ingredient types for station mapping
//

import Foundation

// MARK: - Simple Ingredient Types
enum IngredientType: String, CaseIterable {
    case tea = "tea"
    case ice = "ice"
    case boba = "boba"
    case foam = "foam"
    case lid = "lid"
    
    var displayName: String {
        switch self {
        case .tea: return "Tea"
        case .ice: return "Ice"
        case .boba: return "Boba Pearls"
        case .foam: return "Cheese Foam"
        case .lid: return "Lid & Straw"
        }
    }
}
