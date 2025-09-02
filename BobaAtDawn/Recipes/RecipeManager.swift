//
//  RecipeManager.swift
//  BobaAtDawn
//
//  Recipe management service for handling recipe discovery, hints, and customer preferences
//

import Foundation

// MARK: - Recipe Manager Service
class RecipeManager {
    private static let shared = RecipeManager()
    
    // Track discovered recipes
    private var discoveredRecipes: Set<String> = []
    
    // Track recipe attempt history
    private var recipeHistory: [(recipe: String?, quality: RecipeQuality, timestamp: Date)] = []
    
    private init() {}
    
    static func getInstance() -> RecipeManager {
        return shared
    }
    
    // MARK: - Recipe Discovery
    
    /// Mark a recipe as discovered when player creates it
    func discoverRecipe(_ recipe: Recipe, quality: RecipeQuality) {
        discoveredRecipes.insert(recipe.name)
        
        // Add to history
        recipeHistory.append((recipe.name, quality, Date()))
        
        // Limit history to last 20 attempts
        if recipeHistory.count > 20 {
            recipeHistory.removeFirst(recipeHistory.count - 20)
        }
        
        print("📚 Recipe Discovered: \(recipe.name) at \(quality.displayName) quality!")
    }
    
    /// Get list of all discovered recipes
    func getDiscoveredRecipes() -> [Recipe] {
        return RecipeBook.allRecipes.filter { discoveredRecipes.contains($0.name) }
    }
    
    /// Check if a recipe has been discovered
    func isDiscovered(_ recipe: Recipe) -> Bool {
        return discoveredRecipes.contains(recipe.name)
    }
    
    // MARK: - Recipe Hints & Suggestions
    
    /// Get a hint for improving current drink
    func getImprovementHint(for ingredients: [Ingredient]) -> String? {
        let (bestRecipe, currentQuality) = RecipeBook.findBestRecipe(for: ingredients)
        
        guard let recipe = bestRecipe else {
            return "Try adding tea and a lid for a basic drink!"
        }
        
        // If perfect, no improvement needed
        if currentQuality == .perfect {
            return nil
        }
        
        // Check what's missing from perfect combinations
        for perfectCombo in recipe.perfectCombinations {
            var missingIngredients: [Ingredient] = []
            var wrongLevelIngredients: [Ingredient] = []
            
            for perfectIngredient in perfectCombo {
                if let currentIngredient = ingredients.first(where: { $0.type == perfectIngredient.type }) {
                    if currentIngredient.level != perfectIngredient.level {
                        wrongLevelIngredients.append(perfectIngredient)
                    }
                } else {
                    missingIngredients.append(perfectIngredient)
                }
            }
            
            // Give hint for first missing or wrong ingredient
            if !missingIngredients.isEmpty {
                let missing = missingIngredients.first!
                return "Try adding \(missing.level.displayName) \(missing.type.displayName)"
            }
            
            if !wrongLevelIngredients.isEmpty {
                let wrong = wrongLevelIngredients.first!
                return "Try \(wrong.level.displayName) \(wrong.type.displayName) instead"
            }
        }
        
        return recipe.nextIngredientHint
    }
    
    /// Get random recipe suggestion
    func getRandomRecipeSuggestion() -> Recipe {
        return RecipeBook.allRecipes.randomElement() ?? RecipeBook.allRecipes[0]
    }
    
    /// Get recipe suggestions based on available ingredients
    func getRecipeSuggestions(availableTypes: [IngredientType]) -> [Recipe] {
        return RecipeBook.getAvailableRecipes(with: availableTypes)
            .prefix(3) // Limit to top 3 suggestions
            .map { $0 }
    }
    
    // MARK: - Statistics & Analytics
    
    /// Get player's recipe mastery statistics
    func getRecipeStatistics() -> RecipeStatistics {
        let totalAttempts = recipeHistory.count
        let successfulRecipes = recipeHistory.compactMap { $0.recipe }.count
        let uniqueRecipes = Set(recipeHistory.compactMap { $0.recipe }).count
        
        let qualityDistribution = Dictionary(grouping: recipeHistory) { $0.quality }
            .mapValues { $0.count }
        
        let averageQuality = recipeHistory.isEmpty ? 0.0 : 
            Double(recipeHistory.map { $0.quality.rawValue }.reduce(0, +)) / Double(totalAttempts)
        
        return RecipeStatistics(
            totalAttempts: totalAttempts,
            successfulRecipes: successfulRecipes,
            uniqueRecipes: uniqueRecipes,
            discoveredRecipes: discoveredRecipes.count,
            qualityDistribution: qualityDistribution,
            averageQuality: averageQuality,
            recentTrend: getRecentQualityTrend()
        )
    }
    
    private func getRecentQualityTrend() -> QualityTrend {
        guard recipeHistory.count >= 6 else { return .stable }
        
        let recent = recipeHistory.suffix(3).map { $0.quality.rawValue }
        let previous = recipeHistory.dropLast(3).suffix(3).map { $0.quality.rawValue }
        
        let recentAvg = Double(recent.reduce(0, +)) / Double(recent.count)
        let previousAvg = Double(previous.reduce(0, +)) / Double(previous.count)
        
        if recentAvg > previousAvg + 0.5 {
            return .improving
        } else if recentAvg < previousAvg - 0.5 {
            return .declining
        } else {
            return .stable
        }
    }
    
    /// Get most successful recipe type
    func getFavoriteRecipe() -> String? {
        let recipeCounts = Dictionary(grouping: recipeHistory.compactMap { $0.recipe }) { $0 }
            .mapValues { $0.count }
        
        return recipeCounts.max(by: { $0.value < $1.value })?.key
    }
    
    // MARK: - Reset & Debug
    
    /// Reset all recipe progress (for testing)
    func resetProgress() {
        discoveredRecipes.removeAll()
        recipeHistory.removeAll()
        print("🧹 Recipe progress reset")
    }
    
    /// Debug print current state
    func debugPrint() {
        print("🧋 === Recipe Manager Debug ===")
        print("📚 Discovered Recipes: \(discoveredRecipes.count)/\(RecipeBook.allRecipes.count)")
        print("📈 Recent History: \(recipeHistory.suffix(5))")
        print("⭐ Statistics: \(getRecipeStatistics())")
        print("🧋 =============================")
    }
}

// MARK: - Recipe Statistics
struct RecipeStatistics {
    let totalAttempts: Int
    let successfulRecipes: Int
    let uniqueRecipes: Int
    let discoveredRecipes: Int
    let qualityDistribution: [RecipeQuality: Int]
    let averageQuality: Double
    let recentTrend: QualityTrend
    
    var successRate: Double {
        return totalAttempts > 0 ? Double(successfulRecipes) / Double(totalAttempts) : 0.0
    }
    
    var discoveryRate: Double {
        return Double(discoveredRecipes) / Double(RecipeBook.allRecipes.count)
    }
}

enum QualityTrend {
    case improving
    case stable
    case declining
    
    var emoji: String {
        switch self {
        case .improving: return "📈"
        case .stable: return "➡️"
        case .declining: return "📉"
        }
    }
    
    var description: String {
        switch self {
        case .improving: return "Improving"
        case .stable: return "Stable"
        case .declining: return "Needs Work"
        }
    }
}

// MARK: - Customer Preferences (Future Extension)
extension RecipeManager {
    
    /// Get customer preference for recipe types (placeholder for future NPC system)
    func getCustomerPreference(for customerType: String) -> Recipe? {
        // This could be expanded to return different recipes based on NPC types
        // For now, return a random recipe
        return getRandomRecipeSuggestion()
    }
    
    /// Calculate customer satisfaction based on recipe quality
    func getCustomerSatisfaction(recipe: Recipe?, quality: RecipeQuality, customerType: String = "generic") -> Double {
        // Base satisfaction from quality
        var satisfaction = quality.customerSatisfactionBonus
        
        // Future: Add customer-specific preferences
        // if customerType == "health_conscious" && recipe?.name.contains("Light") == true {
        //     satisfaction += 0.1
        // }
        
        return max(0.0, min(1.0, 0.5 + satisfaction)) // Clamp between 0 and 1
    }
}
