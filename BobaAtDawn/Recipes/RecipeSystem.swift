//
//  RecipeSystem.swift
//  BobaAtDawn
//
//  Comprehensive recipe system for boba drinks with quality levels and ingredients
//

import Foundation

// MARK: - Ingredient Types
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

// MARK: - Ingredient Levels
enum IngredientLevel: Int, CaseIterable {
    case none = 0
    case light = 1
    case regular = 2
    case extra = 3
    
    var displayName: String {
        switch self {
        case .none: return "None"
        case .light: return "Light"
        case .regular: return "Regular"
        case .extra: return "Extra"
        }
    }
}

// MARK: - Ingredient State
struct Ingredient: Equatable {
    let type: IngredientType
    let level: IngredientLevel
    
    init(type: IngredientType, level: IngredientLevel = .regular) {
        self.type = type
        self.level = level
    }
    
    var isPresent: Bool {
        return level != .none
    }
}

// MARK: - Recipe Quality
enum RecipeQuality: Int, CaseIterable {
    case poor = 1
    case fair = 2
    case good = 3
    case excellent = 4
    case perfect = 5
    
    var displayName: String {
        switch self {
        case .poor: return "Poor"
        case .fair: return "Fair"
        case .good: return "Good"
        case .excellent: return "Excellent"
        case .perfect: return "Perfect"
        }
    }
    
    var emoji: String {
        switch self {
        case .poor: return "😞"
        case .fair: return "😐"
        case .good: return "🙂"
        case .excellent: return "😊"
        case .perfect: return "🤩"
        }
    }
    
  
}

// MARK: - Recipe Definition
struct Recipe {
    let name: String
    let requiredIngredients: [Ingredient]
    let optionalIngredients: [Ingredient]
    let forbiddenIngredients: [IngredientType]
    let perfectCombinations: [[Ingredient]] // Multiple perfect combinations possible
    let description: String
    
    init(name: String,
         required: [Ingredient] = [],
         optional: [Ingredient] = [],
         forbidden: [IngredientType] = [],
         perfectCombinations: [[Ingredient]] = [],
         description: String = "") {
        self.name = name
        self.requiredIngredients = required
        self.optionalIngredients = optional
        self.forbiddenIngredients = forbidden
        self.perfectCombinations = perfectCombinations.isEmpty ? [required + optional] : perfectCombinations
        self.description = description
    }
    
    /// Check if the given ingredients can create a valid drink
    func isValidDrink(with ingredients: [Ingredient]) -> Bool {
        // Must have all required ingredients
        for required in requiredIngredients {
            if !ingredients.contains(where: { $0.type == required.type && $0.isPresent }) {
                return false
            }
        }
        
        // Must not have forbidden ingredients
        for ingredient in ingredients {
            if ingredient.isPresent && forbiddenIngredients.contains(ingredient.type) {
                return false
            }
        }
        
        return true
    }
    
    /// Evaluate the quality of the drink based on recipe matching
    func evaluateQuality(with ingredients: [Ingredient]) -> RecipeQuality {
        guard isValidDrink(with: ingredients) else {
            return .poor
        }
        
        // Check for perfect combinations
        for perfectCombo in perfectCombinations {
            if matchesPerfectCombination(ingredients, perfectCombo) {
                return .perfect
            }
        }
        
        // Score based on how well ingredients match expectations
        var score = 0
        var maxScore = 0
        
        // Score required ingredients (exact level match)
        for required in requiredIngredients {
            maxScore += 3
            if let ingredient = ingredients.first(where: { $0.type == required.type }) {
                if ingredient.level == required.level {
                    score += 3 // Perfect match
                } else if ingredient.isPresent {
                    score += 1 // Present but wrong level
                }
            }
        }
        
        // Score optional ingredients (bonus points)
        for optional in optionalIngredients {
            maxScore += 2
            if let ingredient = ingredients.first(where: { $0.type == optional.type }) {
                if ingredient.level == optional.level {
                    score += 2 // Perfect match
                } else if ingredient.isPresent {
                    score += 1 // Present but wrong level
                }
            }
        }
        
        // Penalty for forbidden ingredients
        for ingredient in ingredients {
            if ingredient.isPresent && forbiddenIngredients.contains(ingredient.type) {
                score -= 2
            }
        }
        
        // Convert score to quality
        let percentage = maxScore > 0 ? Double(score) / Double(maxScore) : 0.0
        
        switch percentage {
        case 0.9...: return .excellent
        case 0.7..<0.9: return .good
        case 0.4..<0.7: return .fair
        default: return .poor
        }
    }
    
    private func matchesPerfectCombination(_ ingredients: [Ingredient], _ perfectCombo: [Ingredient]) -> Bool {
        // Must match all ingredients in the perfect combination exactly
        for perfectIngredient in perfectCombo {
            guard let ingredient = ingredients.first(where: { $0.type == perfectIngredient.type }) else {
                return false
            }
            
            if ingredient.level != perfectIngredient.level {
                return false
            }
        }
        
        // Must not have any extra ingredients not in the perfect combination
        for ingredient in ingredients {
            if ingredient.isPresent && !perfectCombo.contains(where: { $0.type == ingredient.type }) {
                return false
            }
        }
        
        return true
    }
}

// MARK: - Recipe Book (All Available Recipes)
struct RecipeBook {
    static let allRecipes: [Recipe] = [
        // Classic Milk Tea (Basic recipe)
        Recipe(
            name: "Classic Milk Tea",
            required: [
                Ingredient(type: .tea, level: .regular),
                Ingredient(type: .lid, level: .regular)
            ],
            optional: [
                Ingredient(type: .ice, level: .regular),
                Ingredient(type: .boba, level: .regular)
            ],
            forbidden: [.foam],
            perfectCombinations: [
                [
                    Ingredient(type: .tea, level: .regular),
                    Ingredient(type: .ice, level: .regular),
                    Ingredient(type: .boba, level: .regular),
                    Ingredient(type: .lid, level: .regular)
                ]
            ],
            description: "A traditional boba tea with black tea, tapioca pearls, and ice."
        ),
        
        // Cheese Foam Tea (Premium recipe)
        Recipe(
            name: "Cheese Foam Tea",
            required: [
                Ingredient(type: .tea, level: .regular),
                Ingredient(type: .foam, level: .regular),
                Ingredient(type: .lid, level: .regular)
            ],
            optional: [
                Ingredient(type: .ice, level: .light) // Light ice to not dilute foam
            ],
            forbidden: [.boba], // Boba pearls interfere with foam experience
            perfectCombinations: [
                [
                    Ingredient(type: .tea, level: .regular),
                    Ingredient(type: .foam, level: .regular),
                    Ingredient(type: .ice, level: .light),
                    Ingredient(type: .lid, level: .regular)
                ]
            ],
            description: "Smooth tea topped with creamy cheese foam. Best served with light ice."
        ),
        
        // Iced Tea (Simple & Refreshing)
        Recipe(
            name: "Iced Tea",
            required: [
                Ingredient(type: .tea, level: .regular),
                Ingredient(type: .ice, level: .regular),
                Ingredient(type: .lid, level: .regular)
            ],
            optional: [],
            forbidden: [.boba, .foam], // Pure tea experience
            perfectCombinations: [
                [
                    Ingredient(type: .tea, level: .regular),
                    Ingredient(type: .ice, level: .regular),
                    Ingredient(type: .lid, level: .regular)
                ]
            ],
            description: "Pure tea served ice cold. Simple and refreshing."
        ),
        
        // Hot Tea (No ice allowed)
        Recipe(
            name: "Hot Tea",
            required: [
                Ingredient(type: .tea, level: .regular),
                Ingredient(type: .lid, level: .regular)
            ],
            optional: [
                Ingredient(type: .foam, level: .regular)
            ],
            forbidden: [.ice, .boba], // Hot tea can't have ice or cold boba
            perfectCombinations: [
                [
                    Ingredient(type: .tea, level: .regular),
                    Ingredient(type: .lid, level: .regular)
                ],
                [
                    Ingredient(type: .tea, level: .regular),
                    Ingredient(type: .foam, level: .regular),
                    Ingredient(type: .lid, level: .regular)
                ]
            ],
            description: "Warming tea served hot. Perfect for cold days."
        ),
        
        // Double Boba Special (Extra boba)
        Recipe(
            name: "Double Boba Special",
            required: [
                Ingredient(type: .tea, level: .regular),
                Ingredient(type: .boba, level: .extra),
                Ingredient(type: .lid, level: .regular)
            ],
            optional: [
                Ingredient(type: .ice, level: .regular)
            ],
            forbidden: [.foam], // Foam interferes with boba texture
            perfectCombinations: [
                [
                    Ingredient(type: .tea, level: .regular),
                    Ingredient(type: .boba, level: .extra),
                    Ingredient(type: .ice, level: .regular),
                    Ingredient(type: .lid, level: .regular)
                ]
            ],
            description: "For boba lovers! Extra tapioca pearls in every sip."
        )
    ]
    
    /// Find the best recipe match for given ingredients
    static func findBestRecipe(for ingredients: [Ingredient]) -> (recipe: Recipe?, quality: RecipeQuality) {
        var bestRecipe: Recipe? = nil
        var bestQuality: RecipeQuality = .poor
        
        for recipe in allRecipes {
            if recipe.isValidDrink(with: ingredients) {
                let quality = recipe.evaluateQuality(with: ingredients)
                if quality.rawValue > bestQuality.rawValue {
                    bestRecipe = recipe
                    bestQuality = quality
                }
            }
        }
        
        return (bestRecipe, bestQuality)
    }
    
    /// Get all recipes that can be made with current available ingredients
    static func getAvailableRecipes(with availableIngredients: [IngredientType]) -> [Recipe] {
        return allRecipes.filter { recipe in
            // Check if all required ingredients are available
            for required in recipe.requiredIngredients {
                if !availableIngredients.contains(required.type) {
                    return false
                }
            }
            return true
        }
    }
}

// MARK: - Recipe Evaluation Result
struct RecipeEvaluationResult {
    let recipe: Recipe?
    let quality: RecipeQuality
    let ingredients: [Ingredient]
    let isValidDrink: Bool
    let feedback: String
    
    init(ingredients: [Ingredient]) {
        self.ingredients = ingredients
        
        let result = RecipeBook.findBestRecipe(for: ingredients)
        self.recipe = result.recipe
        self.quality = result.quality
        self.isValidDrink = result.recipe != nil
        
        // Generate feedback
        if let recipe = result.recipe {
            self.feedback = "Made \\(recipe.name) - Quality: \\(result.quality.displayName) \\(result.quality.emoji)"
        } else {
            self.feedback = "Unknown recipe - needs tea and lid at minimum"
        }
    }
}
