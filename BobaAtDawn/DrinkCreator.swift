//
//  DrinkCreator.swift
//  BobaAtDawn
//
//  Fixed sprite loading and reset logic
//

import SpriteKit

// MARK: - Drink Creator
class DrinkCreator: SKNode {
    
    private var drinkDisplay: RotatableObject!
    private var isComplete: Bool = false
    
    override init() {
        super.init()
        setupDrinkDisplay()
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupDrinkDisplay() {
        // Central drink display shows current recipe
        drinkDisplay = RotatableObject(type: .completedDrink, color: .clear, shape: "drink")
        drinkDisplay.size = CGSize(width: 40, height: 60)
        drinkDisplay.name = "drink_display"
        addChild(drinkDisplay)
    }
    
    func updateDrink(from stations: [IngredientStation]) {
        // NEW: Use Recipe system to evaluate drink
        let evaluation = RecipeConverter.evaluateRecipe(from: stations)
        isComplete = RecipeConverter.isComplete(from: stations)
        
        // Get ingredient states for visual display
        let ingredients = RecipeConverter.convertToIngredients(from: stations)
        
        // Extract visual states for backward compatibility
        var iceLevel = 0
        var hasBoba = false
        var hasFoam = false
        var hasTea = false
        var hasLid = false
        
        for ingredient in ingredients {
            switch ingredient.type {
            case .ice:
                iceLevel = ingredient.level == .regular ? 0 : (ingredient.level == .light ? 1 : 2)
            case .boba:
                hasBoba = ingredient.isPresent
            case .foam:
                hasFoam = ingredient.isPresent
            case .tea:
                hasTea = ingredient.isPresent
            case .lid:
                hasLid = ingredient.isPresent
            }
        }
        
        // Update visual display
        updateDrinkVisuals(iceLevel: iceLevel, hasBoba: hasBoba, hasFoam: hasFoam, hasTea: hasTea, hasLid: hasLid, quality: evaluation.quality)
        
        // Add shaking if complete
        updateShaking()
        
        print("🧋 Recipe Evaluation: \(evaluation.feedback)")
        if let recipe = evaluation.recipe {
            print("📖 Recipe: \(recipe.name) - \(recipe.description)")
            
            // NEW: Track recipe discovery
            RecipeManager.getInstance().discoverRecipe(recipe, quality: evaluation.quality)
        }
    }
    
    private func updateDrinkVisuals(iceLevel: Int, hasBoba: Bool, hasFoam: Bool, hasTea: Bool, hasLid: Bool, quality: RecipeQuality) {
        // Clear existing children
        drinkDisplay.removeAllChildren()
        
        // ALWAYS show base cup
        print("🧋 Loading cup...")
        let cupTexture = SKTexture(imageNamed: "cup_empty")
        if cupTexture.size().width > 0 {
            let cup = SKSpriteNode(texture: cupTexture)
            // Try smaller scale first
            cup.setScale(0.07) // Scale down 512px to ~35px
            cup.position = CGPoint.zero
            cup.zPosition = 0
            drinkDisplay.addChild(cup)
            print("🧋 ✅ Cup: \(cupTexture.size()) scaled to \(cup.size)")
        } else {
            let cup = SKSpriteNode(color: .white, size: CGSize(width: 35, height: 50))
            cup.position = CGPoint.zero
            cup.zPosition = 0
            drinkDisplay.addChild(cup)
            print("🧋 ❌ Cup fallback used")
        }
        
        // Tea layer (if present)
        if hasTea {
            print("🧋 Loading tea...")
            let teaTexture = SKTexture(imageNamed: "tea_black")
            if teaTexture.size().width > 0 {
                let tea = SKSpriteNode(texture: teaTexture)
                tea.setScale(0.06) // Slightly smaller than cup
                tea.position = CGPoint(x: 0, y: -2)
                tea.zPosition = 1
                drinkDisplay.addChild(tea)
                print("🧋 ✅ Tea: \(teaTexture.size()) scaled to \(tea.size)")
            } else {
                let tea = SKSpriteNode(color: .brown, size: CGSize(width: 30, height: 35))
                tea.position = CGPoint(x: 0, y: -2)
                tea.zPosition = 1
                drinkDisplay.addChild(tea)
                print("🧋 ❌ Tea fallback used")
            }
        }
        
        // Ice (if present and ice level < 2)
        if hasTea && iceLevel < 2 {
            print("🧋 Loading ice...")
            let iceTexture = SKTexture(imageNamed: "ice_cubes")
            if iceTexture.size().width > 0 {
                let ice = SKSpriteNode(texture: iceTexture)
                ice.setScale(0.05) // Smaller for ice
                ice.position = CGPoint(x: 0, y: 5)
                ice.zPosition = 2
                ice.alpha = iceLevel == 0 ? 1.0 : 0.6
                drinkDisplay.addChild(ice)
                print("🧋 ✅ Ice: \(iceTexture.size()) scaled to \(ice.size)")
            } else {
                let ice = SKSpriteNode(color: .cyan, size: CGSize(width: 28, height: 15))
                ice.position = CGPoint(x: 0, y: 5)
                ice.zPosition = 2
                ice.alpha = iceLevel == 0 ? 1.0 : 0.6
                drinkDisplay.addChild(ice)
                print("🧋 ❌ Ice fallback used")
            }
        }
        
        // Boba pearls (if present)
        if hasBoba {
            print("🧋 Loading boba...")
            let bobaTexture = SKTexture(imageNamed: "topping_tapioca")
            if bobaTexture.size().width > 0 {
                let boba = SKSpriteNode(texture: bobaTexture)
                boba.setScale(0.05)
                boba.position = CGPoint(x: 0, y: -15)
                boba.zPosition = 3
                drinkDisplay.addChild(boba)
                print("🧋 ✅ Boba: \(bobaTexture.size()) scaled to \(boba.size)")
            } else {
                let boba = SKSpriteNode(color: .black, size: CGSize(width: 25, height: 12))
                boba.position = CGPoint(x: 0, y: -15)
                boba.zPosition = 3
                drinkDisplay.addChild(boba)
                print("🧋 ❌ Boba fallback used")
            }
        }
        
        // Cheese foam (if present)
        if hasFoam {
            print("🧋 Loading foam...")
            let foamTexture = SKTexture(imageNamed: "foam_cheese")
            if foamTexture.size().width > 0 {
                let foam = SKSpriteNode(texture: foamTexture)
                foam.setScale(0.06)
                foam.position = CGPoint(x: 0, y: 18)
                foam.zPosition = 4
                drinkDisplay.addChild(foam)
                print("🧋 ✅ Foam: \(foamTexture.size()) scaled to \(foam.size)")
            } else {
                let foam = SKSpriteNode(color: .yellow, size: CGSize(width: 32, height: 10))
                foam.position = CGPoint(x: 0, y: 18)
                foam.zPosition = 4
                drinkDisplay.addChild(foam)
                print("🧋 ❌ Foam fallback used")
            }
        }
        
        // Lid with straw (if present)
        if hasLid {
            print("🧋 Loading lid...")
            let lidTexture = SKTexture(imageNamed: "lid_straw")
            if lidTexture.size().width > 0 {
                let lid = SKSpriteNode(texture: lidTexture)
                lid.setScale(0.07)
                lid.position = CGPoint(x: 0, y: 22)
                lid.zPosition = 5
                drinkDisplay.addChild(lid)
                print("🧋 ✅ Lid: \(lidTexture.size()) scaled to \(lid.size)")
            } else {
                let lid = SKSpriteNode(color: .gray, size: CGSize(width: 38, height: 20))
                lid.position = CGPoint(x: 0, y: 22)
                lid.zPosition = 5
                drinkDisplay.addChild(lid)
                print("🧋 ❌ Lid fallback used")
            }
        }
    }
    
    private func updateShaking() {
        drinkDisplay.removeAction(forKey: "shake")
        
        if isComplete {
            let shakeAction = SKAction.repeatForever(
                SKAction.sequence([
                    SKAction.moveBy(x: 2, y: 0, duration: 0.1),
                    SKAction.moveBy(x: -4, y: 0, duration: 0.2),
                    SKAction.moveBy(x: 2, y: 0, duration: 0.1),
                    SKAction.wait(forDuration: 2.5)
                ])
            )
            drinkDisplay.run(shakeAction, withKey: "shake")
            drinkDisplay.name = "completed_drink_pickup"
            print("🧋 ✅ Drink is complete and ready for pickup!")
        } else {
            drinkDisplay.name = "drink_display"
        }
    }
    
    func createCompletedDrink(from stations: [IngredientStation]) -> RotatableObject? {
        guard isComplete else { 
            print("🧋 ❌ Cannot create drink - not complete")
            return nil 
        }
        
        // NEW: Use Recipe system to evaluate the completed drink
        let evaluation = RecipeConverter.evaluateRecipe(from: stations)
        let ingredients = RecipeConverter.convertToIngredients(from: stations)
        
        // Extract visual states for backward compatibility
        var iceLevel = 0
        var hasBoba = false
        var hasFoam = false
        var hasTea = false
        var hasLid = false
        
        for ingredient in ingredients {
            switch ingredient.type {
            case .ice:
                iceLevel = ingredient.level == .regular ? 0 : (ingredient.level == .light ? 1 : 2)
            case .boba:
                hasBoba = ingredient.isPresent
            case .foam:
                hasFoam = ingredient.isPresent
            case .tea:
                hasTea = ingredient.isPresent
            case .lid:
                hasLid = ingredient.isPresent
            }
        }
        
        // Create completed drink (smaller version)
        let completedDrink = RotatableObject(type: .completedDrink, color: .clear, shape: "drink")
        
        // NEW: Include recipe info in the name for NPCs to read
        if let recipe = evaluation.recipe {
            completedDrink.name = "completed_\(recipe.name.replacingOccurrences(of: " ", with: "_").lowercased())_\(evaluation.quality.rawValue)"
        } else {
            completedDrink.name = "completed_unknown_drink_\(evaluation.quality.rawValue)"
        }
        
        completedDrink.size = CGSize(width: 30, height: 45)
        
        // Add layers using same scaling approach but smaller
        let cupTexture = SKTexture(imageNamed: "cup_empty")
        let cup = cupTexture.size().width > 0 ? 
            SKSpriteNode(texture: cupTexture) : 
            SKSpriteNode(color: .white, size: CGSize(width: 25, height: 35))
        cup.setScale(0.05) // Even smaller for carried version
        cup.position = CGPoint.zero
        cup.zPosition = 0
        completedDrink.addChild(cup)
        
        if hasTea {
            let teaTexture = SKTexture(imageNamed: "tea_black")
            let tea = teaTexture.size().width > 0 ? 
                SKSpriteNode(texture: teaTexture) : 
                SKSpriteNode(color: .brown, size: CGSize(width: 22, height: 25))
            tea.setScale(0.04)
            tea.position = CGPoint(x: 0, y: -1)
            tea.zPosition = 1
            completedDrink.addChild(tea)
        }
        
        if hasTea && iceLevel < 2 {
            let iceTexture = SKTexture(imageNamed: "ice_cubes")
            let ice = iceTexture.size().width > 0 ? 
                SKSpriteNode(texture: iceTexture) : 
                SKSpriteNode(color: .cyan, size: CGSize(width: 20, height: 10))
            ice.setScale(0.03)
            ice.position = CGPoint(x: 0, y: 3)
            ice.zPosition = 2
            ice.alpha = iceLevel == 0 ? 1.0 : 0.6
            completedDrink.addChild(ice)
        }
        
        if hasBoba {
            let bobaTexture = SKTexture(imageNamed: "topping_tapioca")
            let boba = bobaTexture.size().width > 0 ? 
                SKSpriteNode(texture: bobaTexture) : 
                SKSpriteNode(color: .black, size: CGSize(width: 18, height: 8))
            boba.setScale(0.03)
            boba.position = CGPoint(x: 0, y: -10)
            boba.zPosition = 3
            completedDrink.addChild(boba)
        }
        
        if hasFoam {
            let foamTexture = SKTexture(imageNamed: "foam_cheese")
            let foam = foamTexture.size().width > 0 ? 
                SKSpriteNode(texture: foamTexture) : 
                SKSpriteNode(color: .yellow, size: CGSize(width: 23, height: 7))
            foam.setScale(0.04)
            foam.position = CGPoint(x: 0, y: 12)
            foam.zPosition = 4
            completedDrink.addChild(foam)
        }
        
        if hasLid {
            let lidTexture = SKTexture(imageNamed: "lid_straw")
            let lid = lidTexture.size().width > 0 ? 
                SKSpriteNode(texture: lidTexture) : 
                SKSpriteNode(color: .gray, size: CGSize(width: 27, height: 15))
            lid.setScale(0.05)
            lid.position = CGPoint(x: 0, y: 15)
            lid.zPosition = 5
            completedDrink.addChild(lid)
        }
        
        print("🎆 ✅ Created completed drink: \(evaluation.feedback)")
        if let recipe = evaluation.recipe {
            print("📖 Recipe: \(recipe.name) - Quality: \(evaluation.quality.displayName) \(evaluation.quality.emoji)")
        }
        
        return completedDrink
    }
    
    func resetStations(_ stations: [IngredientStation]) {
        print("🧋 💥 === STARTING COMPLETE STATION RESET ===")
        
        // Force clear the drink display first
        isComplete = false
        drinkDisplay.removeAllActions()
        drinkDisplay.name = "drink_display"
        drinkDisplay.removeAllChildren()
        
        // Add just empty cup to show it's reset
        let emptyCup = SKSpriteNode(color: .lightGray, size: CGSize(width: 35, height: 50))
        emptyCup.position = CGPoint.zero
        emptyCup.zPosition = 0
        emptyCup.alpha = 0.3 // Dim to show it's empty
        drinkDisplay.addChild(emptyCup)
        
        // Reset all stations
        for station in stations {
            print("🧋 🔄 Resetting \(station.stationType) station...")
            station.resetToDefault()
        }
        
        // Force update display to show empty state  
        updateDrink(from: stations)
        
        // Visual feedback for complete reset
        let resetPulse = SKAction.sequence([
            SKAction.scale(to: 1.2, duration: 0.15),
            SKAction.scale(to: 0.8, duration: 0.15),
            SKAction.scale(to: 1.0, duration: 0.15)
        ])
        drinkDisplay.run(resetPulse)
        
        print("🎆 ✅ === COMPLETE STATION RESET FINISHED ===")
        print("🧋 Ready to make a new drink!")
    }
}
