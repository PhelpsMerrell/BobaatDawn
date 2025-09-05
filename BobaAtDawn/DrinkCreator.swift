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
        print("🧋 🔄 updateDrink called with \(stations.count) stations")
        
        // SIMPLIFIED: Direct station state checking
        var hasIce = false
        var hasBoba = false
        var hasFoam = false
        var hasTea = false
        var hasLid = false
        
        print("🧋 🔍 === STATION STATE CHECK ===")
        for (index, station) in stations.enumerated() {
            switch station.stationType {
            case .ice:
                hasIce = station.hasIce
                print("🧋 Station \(index + 1): ICE -> \(hasIce ? "ON" : "OFF")")
            case .boba:
                hasBoba = station.hasBoba
                print("🧋 Station \(index + 1): BOBA -> \(hasBoba ? "ON" : "OFF")")
            case .foam:
                hasFoam = station.hasFoam
                print("🧋 Station \(index + 1): FOAM -> \(hasFoam ? "ON" : "OFF")")
            case .tea:
                hasTea = station.hasTea
                print("🧋 Station \(index + 1): TEA -> \(hasTea ? "ON" : "OFF")")
            case .lid:
                hasLid = station.hasLid
                print("🧋 Station \(index + 1): LID -> \(hasLid ? "ON" : "OFF")")
            }
        }
        print("🧋 🔍 === END STATION CHECK ===")
        
        // Simple completion check: tea + lid
        isComplete = hasTea && hasLid
        print("🧋 ✅ Completion: tea=\(hasTea), lid=\(hasLid) -> complete=\(isComplete)")
        
        // Update visual display
        updateDrinkVisuals(hasIce: hasIce, hasBoba: hasBoba, hasFoam: hasFoam, hasTea: hasTea, hasLid: hasLid)
        
        // Add shaking if complete
        updateShaking()
        
        // Simple feedback
        let activeCount = [hasIce, hasBoba, hasFoam, hasTea, hasLid].filter { $0 }.count
        if activeCount == 0 {
            print("🧋 Empty cup - add some ingredients!")
        } else if isComplete {
            print("🧋 Drink ready! (\(activeCount) ingredients)")
        } else {
            print("🧋 Needs tea + lid to complete (\(activeCount) ingredients so far)")
        }
    }
    
    private func updateDrinkVisuals(
        hasIce: Bool,
        hasBoba: Bool,
        hasFoam: Bool,
        hasTea: Bool,
        hasLid: Bool
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

        // 2) Ice (simple on/off)
        if hasIce {
            let ice = makeLayer("ice_cubes", z: 2, visible: true)
            drinkDisplay.addChild(ice)
            print("🧊 Ice on")
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
        
        // SIMPLIFIED: Direct station state checking
        var hasIce = false
        var hasBoba = false
        var hasFoam = false
        var hasTea = false
        var hasLid = false
        
        for station in stations {
            switch station.stationType {
            case .ice: hasIce = station.hasIce
            case .boba: hasBoba = station.hasBoba
            case .foam: hasFoam = station.hasFoam
            case .tea: hasTea = station.hasTea
            case .lid: hasLid = station.hasLid
            }
        }
        
        // Create completed drink (smaller version)
        let completedDrink = RotatableObject(type: .completedDrink, color: .clear, shape: "drink")
        completedDrink.name = "completed_drink"
        completedDrink.size = CGSize(width: 30, height: 45)
        
        // FIXED: Use identical sprite system as display with consistent scaling
        let bobaAtlas = SKTextureAtlas(named: "Boba")
        
        // Get the common scale factor for carried drinks (smaller than display)
        let cupTexture = bobaAtlas.textureNamed("cup_empty")
        let carriedScale = 25.0 / cupTexture.size().width
        
        // Helper function to create perfectly aligned layers (same as display)
        func makeCarriedLayer(_ name: String, z: CGFloat, visible: Bool = true, alpha: CGFloat = 1.0) -> SKSpriteNode? {
            // Validate texture exists before creating sprite
            guard bobaAtlas.textureNames.contains(name) else {
                print("⚠️ WARNING: Texture '\(name)' not found in Boba atlas for completed drink")
                return nil
            }
            
            let tex = bobaAtlas.textureNamed(name)
            tex.filteringMode = .nearest
            let node = SKSpriteNode(texture: tex)
            node.anchorPoint = CGPoint(x: 0.5, y: 0.5)   // identical for all
            node.position = .zero                         // identical for all
            node.setScale(carriedScale)                   // identical for all
            node.zPosition = z
            node.isHidden = !visible
            node.alpha = alpha
            node.blendMode = .alpha
            node.name = name
            return node
        }
        
        // Build drink with identical layering system as display
        if let cup = makeCarriedLayer("cup_empty", z: 0, visible: true) {
            completedDrink.addChild(cup)
        }
        
        if hasTea {
            if let tea = makeCarriedLayer("tea_black", z: 1, visible: true) {
                completedDrink.addChild(tea)
            }
        }
        
        if hasIce {
            if let ice = makeCarriedLayer("ice_cubes", z: 2, visible: true) {
                completedDrink.addChild(ice)
            }
        }
        
        if hasBoba {
            if let boba = makeCarriedLayer("topping_tapioca", z: 3, visible: true) {
                completedDrink.addChild(boba)
            }
        }
        
        if hasFoam {
            if let foam = makeCarriedLayer("foam_cheese", z: 4, visible: true) {
                completedDrink.addChild(foam)
            }
        }
        
        if hasLid {
            if let lid = makeCarriedLayer("lid_straw", z: 5, visible: true) {
                completedDrink.addChild(lid)
            }
        }
        
        print("🎆 ✅ Created completed drink: Tea=\(hasTea), Ice=\(hasIce), Boba=\(hasBoba), Foam=\(hasFoam), Lid=\(hasLid)")
        
        return completedDrink
    }
    
    func createPickupDrink(from stations: [IngredientStation]) -> RotatableObject {
        // Get current ingredient states
        var hasIce = false
        var hasBoba = false
        var hasFoam = false
        var hasTea = false
        var hasLid = false
        
        for station in stations {
            switch station.stationType {
            case .ice: hasIce = station.hasIce
            case .boba: hasBoba = station.hasBoba
            case .foam: hasFoam = station.hasFoam
            case .tea: hasTea = station.hasTea
            case .lid: hasLid = station.hasLid
            }
        }
        
        // Create the appropriate drink type based on completion
        let drinkType: ObjectType = isComplete ? .completedDrink : .drink
        let pickedUpDrink = RotatableObject(type: drinkType, color: .clear, shape: "drink")
        pickedUpDrink.size = CGSize(width: 30, height: 45)
        pickedUpDrink.name = isComplete ? "completed_drink" : "picked_up_drink"
        
        // FIXED: Use identical sprite system as display and completed drink
        let bobaAtlas = SKTextureAtlas(named: "Boba")
        
        // Get the common scale factor for carried drinks (same as other methods)
        let cupTexture = bobaAtlas.textureNamed("cup_empty")
        let carriedScale = 25.0 / cupTexture.size().width
        
        // Helper function to create perfectly aligned layers (identical to other methods)
        func makePickupLayer(_ name: String, z: CGFloat, visible: Bool = true, alpha: CGFloat = 1.0) -> SKSpriteNode? {
            // Validate texture exists before creating sprite
            guard bobaAtlas.textureNames.contains(name) else {
                print("⚠️ WARNING: Texture '\(name)' not found in Boba atlas for pickup drink")
                return nil
            }
            
            let tex = bobaAtlas.textureNamed(name)
            tex.filteringMode = .nearest
            let node = SKSpriteNode(texture: tex)
            node.anchorPoint = CGPoint(x: 0.5, y: 0.5)   // identical for all
            node.position = .zero                         // identical for all
            node.setScale(carriedScale)                   // identical for all
            node.zPosition = z
            node.isHidden = !visible
            node.alpha = alpha
            node.blendMode = .alpha
            node.name = name
            return node
        }
        
        // Build drink with identical layering system as display and completed drink
        if let cup = makePickupLayer("cup_empty", z: 0, visible: true) {
            pickedUpDrink.addChild(cup)
        }
        
        if hasTea {
            if let tea = makePickupLayer("tea_black", z: 1, visible: true) {
                pickedUpDrink.addChild(tea)
            }
        }
        
        if hasIce {
            if let ice = makePickupLayer("ice_cubes", z: 2, visible: true) {
                pickedUpDrink.addChild(ice)
            }
        }
        
        if hasBoba {
            if let boba = makePickupLayer("topping_tapioca", z: 3, visible: true) {
                pickedUpDrink.addChild(boba)
            }
        }
        
        if hasFoam {
            if let foam = makePickupLayer("foam_cheese", z: 4, visible: true) {
                pickedUpDrink.addChild(foam)
            }
        }
        
        if hasLid {
            if let lid = makePickupLayer("lid_straw", z: 5, visible: true) {
                pickedUpDrink.addChild(lid)
            }
        }
        
        print("🧋 ✨ Created pickup drink matching your creation - Tea:\(hasTea), Ice:\(hasIce), Boba:\(hasBoba), Foam:\(hasFoam), Lid:\(hasLid)")
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
