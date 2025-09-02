//
//  RecipeConverter.swift
//  BobaAtDawn
//
//  Converts between old IngredientStation system and new Recipe system
//

import Foundation

// MARK: - Recipe Converter
struct RecipeConverter {
    
    /// Convert IngredientStation states to Recipe ingredients
    static func convertToIngredients(from stations: [IngredientStation]) -> [Ingredient] {
        var ingredients: [Ingredient] = []
        
        for station in stations {
            switch station.stationType {
            case .ice:
                let iceLevel = station.iceLevel
                let ingredientLevel: IngredientLevel = {
                    switch iceLevel {
                    case 0: return .regular  // Full ice
                    case 1: return .light    // Light ice
                    case 2: return .none     // No ice
                    default: return .none
                    }
                }()
                ingredients.append(Ingredient(type: .ice, level: ingredientLevel))
                
            case .boba:
                if station.hasBoba {
                    ingredients.append(Ingredient(type: .boba, level: .regular))
                } else {
                    ingredients.append(Ingredient(type: .boba, level: .none))
                }
                
            case .foam:
                if station.hasFoam {
                    ingredients.append(Ingredient(type: .foam, level: .regular))
                } else {
                    ingredients.append(Ingredient(type: .foam, level: .none))
                }
                
            case .tea:
                if station.hasTea {
                    ingredients.append(Ingredient(type: .tea, level: .regular))
                } else {
                    ingredients.append(Ingredient(type: .tea, level: .none))
                }
                
            case .lid:
                if station.hasLid {
                    ingredients.append(Ingredient(type: .lid, level: .regular))
                } else {
                    ingredients.append(Ingredient(type: .lid, level: .none))
                }
            }
        }
        
        return ingredients
    }
    
    /// Check if the current station configuration creates a valid drink
    static func isValidDrink(from stations: [IngredientStation]) -> Bool {
        let ingredients = convertToIngredients(from: stations)
        let (recipe, _) = RecipeBook.findBestRecipe(for: ingredients)
        return recipe != nil
    }
    
    /// Evaluate the recipe quality for current station configuration
    static func evaluateRecipe(from stations: [IngredientStation]) -> RecipeEvaluationResult {
        let ingredients = convertToIngredients(from: stations)
        return RecipeEvaluationResult(ingredients: ingredients)
    }
    
    /// Get feedback text for the current drink configuration
    static func getFeedback(from stations: [IngredientStation]) -> String {
        let evaluation = evaluateRecipe(from: stations)
        return evaluation.feedback
    }
    
    /// Check if drink is complete (has minimum required ingredients)
    static func isComplete(from stations: [IngredientStation]) -> Bool {
        let ingredients = convertToIngredients(from: stations)
        
        // Minimum requirements: tea + lid
        let hasTea = ingredients.first(where: { $0.type == .tea })?.isPresent ?? false
        let hasLid = ingredients.first(where: { $0.type == .lid })?.isPresent ?? false
        
        return hasTea && hasLid
    }
    
    /// Get recipe suggestions based on current ingredients
    static func getRecipeSuggestions(from stations: [IngredientStation]) -> [Recipe] {
        let ingredients = convertToIngredients(from: stations)
        let currentIngredientTypes = ingredients.compactMap { $0.isPresent ? $0.type : nil }
        
        // Add missing ingredient types as available
        var allAvailable = Set(currentIngredientTypes)
        allAvailable.insert(.tea)   // Always available
        allAvailable.insert(.lid)   // Always available
        allAvailable.insert(.ice)   // Always available
        allAvailable.insert(.boba)  // Always available
        allAvailable.insert(.foam)  // Always available
        
        return RecipeBook.getAvailableRecipes(with: Array(allAvailable))
    }
    
    /// Debug description of current drink state
    static func debugDescription(from stations: [IngredientStation]) -> String {
        let ingredients = convertToIngredients(from: stations)
        let evaluation = RecipeEvaluationResult(ingredients: ingredients)
        
        var description = "🧋 Current Drink State:\\n"
        
        for ingredient in ingredients {
            if ingredient.isPresent {
                description += "   ✅ \\(ingredient.type.displayName): \\(ingredient.level.displayName)\\n"
            } else {
                description += "   ❌ \\(ingredient.type.displayName): None\\n"
            }
        }
        
        description += "\\n"
        
        if let recipe = evaluation.recipe {
            description += "📖 Recipe: \\(recipe.name)\\n"
            description += "⭐ Quality: \\(evaluation.quality.displayName) \\(evaluation.quality.emoji)\\n"
            description += "💬 \\(recipe.description)\\n"
        } else {
            description += "❓ No matching recipe\\n"
            description += "💡 Tip: Add tea and lid for basic drink\\n"
        }
        
        return description
    }
}

// MARK: - Recipe Extensions for Game Integration
extension RecipeQuality {
    /// Get the satisfaction bonus for NPCs (for future use)
    var customerSatisfactionBonus: Double {
        switch self {
        case .poor: return -0.3
        case .fair: return -0.1
        case .good: return 0.0
        case .excellent: return 0.2
        case .perfect: return 0.5
        }
    }
}

extension Recipe {
    /// Get a hint for what ingredients are still needed
    var nextIngredientHint: String? {
        if !requiredIngredients.isEmpty {
            let needed = requiredIngredients.first!
            return "Try adding \\(needed.type.displayName)"
        }
        
        if !optionalIngredients.isEmpty {
            let optional = optionalIngredients.first!
            return "Consider adding \\(optional.type.displayName)"
        }
        
        return nil
    }
}
