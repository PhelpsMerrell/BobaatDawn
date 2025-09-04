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
    
    private func updateDrinkVisuals(
        iceLevel: Int,
        hasBoba: Bool,
        hasFoam: Bool,
        hasTea: Bool,
        hasLid: Bool,
        quality: RecipeQuality
    ) {
        // Reset container
        drinkDisplay.removeAllChildren()

        // Load once
        let atlas = SKTextureAtlas(named: "Boba")

        // We'll scale everything to the same on-screen width using the cup as reference.
        let cupTexture = atlas.textureNamed("cup_empty")
        cupTexture.filteringMode = .nearest
        let desiredWidth: CGFloat = 35.0
        let commonScale = desiredWidth / cupTexture.size().width

        // helper: create a layer with identical geometry for all sprites
        func makeLayer(_ name: String, z: CGFloat, visible: Bool = true, alpha: CGFloat = 1.0) -> SKSpriteNode {
            let tex = atlas.textureNamed(name)
            tex.filteringMode = .nearest
            let node = SKSpriteNode(texture: tex)
            node.anchorPoint = CGPoint(x: 0.5, y: 0.5)   // identical for all
            node.position = .zero                         // identical for all
            node.setScale(commonScale)                    // identical for all
            node.zPosition = z
            node.isHidden = !visible
            node.alpha = alpha
            node.blendMode = .alpha
            node.name = name
            return node
        }

        // ALWAYS show the base cup (empty cup is still a cup!)
        let cup = makeLayer("cup_empty", z: 0, visible: true)
        drinkDisplay.addChild(cup)
        print("🧋 Cup loaded \(cupTexture.size()) → commonScale \(commonScale)")

        // Only add other ingredients if they're active
        // 1) Tea
        if hasTea {
            let tea = makeLayer("tea_black", z: 1, visible: true)
            drinkDisplay.addChild(tea)
            print("🧋 Tea on (aligned, no per-layer scaling/offset)")
        }

        // 2) Ice (visible only if tea present and iceLevel < 2); adjust opacity by ice level
        if hasTea && iceLevel < 2 {
            let iceAlpha: CGFloat = (iceLevel == 0) ? 1.0 : 0.6
            let ice = makeLayer("ice_cubes", z: 2, visible: true, alpha: iceAlpha)
            drinkDisplay.addChild(ice)
            print("🧊 Ice on (alpha \(iceAlpha))")
        }

        // 3) Boba
        if hasBoba {
            let boba = makeLayer("topping_tapioca", z: 3, visible: true)
            drinkDisplay.addChild(boba)
            print("🟤 Boba on")
        }

        // 4) Foam
        if hasFoam {
            let foam = makeLayer("foam_cheese", z: 4, visible: true)
            drinkDisplay.addChild(foam)
            print("🫧 Foam on")
        }

        // 5) Lid
        if hasLid {
            let lid = makeLayer("lid_straw", z: 5, visible: true)
            drinkDisplay.addChild(lid)
            print("🧢 Lid on")
        }
        
        // Show what state we're in
        if !hasTea && !hasBoba && !hasFoam && !hasLid {
            print("☕ Showing empty cup - ready for ingredients!")
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
        
        // FIXED: Use sprite atlas for completed drink too
        let bobaAtlas = SKTextureAtlas(named: "Boba")
        
        // Add layers using sprite atlas with smaller scaling for carried version
        let cupTexture = bobaAtlas.textureNamed("cup_empty")
        let cup = SKSpriteNode(texture: cupTexture)
        let cupScale = 25.0 / cupTexture.size().width // Even smaller for carried version
        cup.setScale(cupScale)
        cup.position = CGPoint.zero
        cup.zPosition = 0
        completedDrink.addChild(cup)
        
        if hasTea {
            let teaTexture = bobaAtlas.textureNamed("tea_black")
            let tea = SKSpriteNode(texture: teaTexture)
            let teaScale = 22.0 / teaTexture.size().width
            tea.setScale(teaScale)
            tea.position = CGPoint(x: 0, y: -1)
            tea.zPosition = 1
            completedDrink.addChild(tea)
        }
        
        if hasTea && iceLevel < 2 {
            let iceTexture = bobaAtlas.textureNamed("ice_cubes")
            let ice = SKSpriteNode(texture: iceTexture)
            let iceScale = 20.0 / iceTexture.size().width
            ice.setScale(iceScale)
            ice.position = CGPoint(x: 0, y: 3)
            ice.zPosition = 2
            ice.alpha = iceLevel == 0 ? 1.0 : 0.6
            completedDrink.addChild(ice)
        }
        
        if hasBoba {
            let bobaTexture = bobaAtlas.textureNamed("topping_tapioca")
            let boba = SKSpriteNode(texture: bobaTexture)
            let bobaScale = 18.0 / bobaTexture.size().width
            boba.setScale(bobaScale)
            boba.position = CGPoint(x: 0, y: -10)
            boba.zPosition = 3
            completedDrink.addChild(boba)
        }
        
        if hasFoam {
            let foamTexture = bobaAtlas.textureNamed("foam_cheese")
            let foam = SKSpriteNode(texture: foamTexture)
            let foamScale = 23.0 / foamTexture.size().width
            foam.setScale(foamScale)
            foam.position = CGPoint(x: 0, y: 12)
            foam.zPosition = 4
            completedDrink.addChild(foam)
        }
        
        if hasLid {
            let lidTexture = bobaAtlas.textureNamed("lid_straw")
            let lid = SKSpriteNode(texture: lidTexture)
            let lidScale = 27.0 / lidTexture.size().width
            lid.setScale(lidScale)
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
    
    func createPickupDrink(from stations: [IngredientStation]) -> RotatableObject {
        // Get current ingredient states
        let ingredients = RecipeConverter.convertToIngredients(from: stations)
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
        
        // Create the appropriate drink type based on completion
        let drinkType: ObjectType = isComplete ? .completedDrink : .drink
        let pickedUpDrink = RotatableObject(type: drinkType, color: .clear, shape: "drink")
        pickedUpDrink.size = CGSize(width: 30, height: 45)
        pickedUpDrink.name = isComplete ? "completed_drink" : "picked_up_drink"
        
        // Build the drink using the same sprite system as the display
        let bobaAtlas = SKTextureAtlas(named: "Boba")
        let cupScale = 25.0 / 35.0 // Consistent scale for carried version
        
        // Always add the base cup
        let cupTexture = bobaAtlas.textureNamed("cup_empty")
        let cup = SKSpriteNode(texture: cupTexture)
        cup.setScale(cupScale)
        cup.position = CGPoint.zero // No offset
        cup.zPosition = 0
        pickedUpDrink.addChild(cup)
        
        // Add ingredients that are active - ALL with identical positioning and scaling
        if hasTea {
            let teaTexture = bobaAtlas.textureNamed("tea_black")
            let tea = SKSpriteNode(texture: teaTexture)
            tea.setScale(cupScale) // Same scale as cup
            tea.position = CGPoint.zero // No offset
            tea.zPosition = 1
            pickedUpDrink.addChild(tea)
        }
        
        if hasTea && iceLevel < 2 {
            let iceTexture = bobaAtlas.textureNamed("ice_cubes")
            let ice = SKSpriteNode(texture: iceTexture)
            ice.setScale(cupScale) // Same scale as cup
            ice.position = CGPoint.zero // No offset
            ice.zPosition = 2
            ice.alpha = iceLevel == 0 ? 1.0 : 0.6
            pickedUpDrink.addChild(ice)
        }
        
        if hasBoba {
            let bobaTexture = bobaAtlas.textureNamed("topping_tapioca")
            let boba = SKSpriteNode(texture: bobaTexture)
            boba.setScale(cupScale) // Same scale as cup
            boba.position = CGPoint.zero // No offset
            boba.zPosition = 3
            pickedUpDrink.addChild(boba)
        }
        
        if hasFoam {
            let foamTexture = bobaAtlas.textureNamed("foam_cheese")
            let foam = SKSpriteNode(texture: foamTexture)
            foam.setScale(cupScale) // Same scale as cup
            foam.position = CGPoint.zero // No offset
            foam.zPosition = 4
            pickedUpDrink.addChild(foam)
        }
        
        if hasLid {
            let lidTexture = bobaAtlas.textureNamed("lid_straw")
            let lid = SKSpriteNode(texture: lidTexture)
            lid.setScale(cupScale) // Same scale as cup
            lid.position = CGPoint.zero // No offset
            lid.zPosition = 5
            pickedUpDrink.addChild(lid)
        }
        
        print("🧋 ✨ Created pickup drink matching your creation - Tea:\(hasTea), Ice:\(iceLevel), Boba:\(hasBoba), Foam:\(hasFoam), Lid:\(hasLid)")
        return pickedUpDrink
    }
    
    func resetStations(_ stations: [IngredientStation]) {
        print("🧋 💥 === STARTING STATION RESET FOR NEXT DRINK ===")
        
        // Reset all stations to default state
        for station in stations {
            print("🧋 🔄 Resetting \(station.stationType) station...")
            station.resetToDefault()
        }
        
        // Clear completion state
        isComplete = false
        drinkDisplay.removeAllActions()
        drinkDisplay.name = "drink_display"
        
        print("🧋 DEBUG: About to call updateDrink with reset stations")
        print("🧋 DEBUG: drinkDisplay has \(drinkDisplay.children.count) children before update")
        
        // Update display with reset stations - this should show the empty cup
        updateDrink(from: stations)
        
        print("🧋 DEBUG: drinkDisplay has \(drinkDisplay.children.count) children after update")
        print("🧋 DEBUG: drinkDisplay children: \(drinkDisplay.children.map { $0.name ?? "unnamed" })")
        
        // Visual feedback for reset
        let resetPulse = SKAction.sequence([
            SKAction.scale(to: 1.2, duration: 0.15),
            SKAction.scale(to: 0.8, duration: 0.15),
            SKAction.scale(to: 1.0, duration: 0.15)
        ])
        drinkDisplay.run(resetPulse)
        
        print("🎆 ✅ === RESET COMPLETE - READY FOR NEXT DRINK ===")
    }
}
