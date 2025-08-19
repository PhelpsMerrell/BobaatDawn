//
//  DrinkCreator.swift
//  BobaAtDawn
//
//  Simple drink creation system
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
        // Get current recipe from all stations
        var iceLevel = 0
        var hasBoba = false
        var hasFoam = false
        var hasTea = false
        var hasLid = false
        
        for station in stations {
            switch station.stationType {
            case .ice:
                iceLevel = station.iceLevel
            case .boba:
                hasBoba = station.hasBoba
            case .foam:
                hasFoam = station.hasFoam
            case .tea:
                hasTea = station.hasTea
            case .lid:
                hasLid = station.hasLid
            }
        }
        
        // Check if complete (tea + lid required)
        isComplete = hasTea && hasLid
        
        // Update visual display
        updateDrinkVisuals(iceLevel: iceLevel, hasBoba: hasBoba, hasFoam: hasFoam, hasTea: hasTea, hasLid: hasLid)
        
        // Add shaking if complete
        updateShaking()
    }
    
    private func updateDrinkVisuals(iceLevel: Int, hasBoba: Bool, hasFoam: Bool, hasTea: Bool, hasLid: Bool) {
        // Clear existing children
        drinkDisplay.removeAllChildren()
        
        // Base cup (always visible)
        let cup = SKSpriteNode(color: .white, size: CGSize(width: 35, height: 55))
        cup.alpha = 0.8
        drinkDisplay.addChild(cup)
        
        // Tea (if present)
        if hasTea {
            let teaColor: SKColor
            switch iceLevel {
            case 0: teaColor = SKColor(red: 0.6, green: 0.3, blue: 0.1, alpha: 0.8) // Dark (full ice)
            case 1: teaColor = SKColor(red: 0.8, green: 0.6, blue: 0.4, alpha: 0.8) // Light (lite ice)
            case 2: teaColor = SKColor(red: 0.7, green: 0.4, blue: 0.2, alpha: 0.8) // Amber (no ice)
            default: teaColor = SKColor(red: 0.6, green: 0.3, blue: 0.1, alpha: 0.8)
            }
            
            let tea = SKSpriteNode(color: teaColor, size: CGSize(width: 30, height: 45))
            drinkDisplay.addChild(tea)
        }
        
        // Boba (if present)
        if hasBoba {
            let boba = SKSpriteNode(color: .black, size: CGSize(width: 25, height: 8))
            boba.position = CGPoint(x: 0, y: -20)
            boba.alpha = 0.8
            drinkDisplay.addChild(boba)
        }
        
        // Foam (if present)
        if hasFoam {
            let foam = SKSpriteNode(color: SKColor(red: 1.0, green: 0.9, blue: 0.7, alpha: 0.9), size: CGSize(width: 32, height: 8))
            foam.position = CGPoint(x: 0, y: 20)
            drinkDisplay.addChild(foam)
        }
        
        // Lid (if present)
        if hasLid {
            let lid = SKSpriteNode(color: .darkGray, size: CGSize(width: 38, height: 8))
            lid.position = CGPoint(x: 0, y: 25)
            drinkDisplay.addChild(lid)
            
            // Straw
            let straw = SKSpriteNode(color: .white, size: CGSize(width: 2, height: 15))
            straw.position = CGPoint(x: 12, y: 20)
            drinkDisplay.addChild(straw)
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
                    SKAction.wait(forDuration: 1.0)
                ])
            )
            drinkDisplay.run(shakeAction, withKey: "shake")
            drinkDisplay.name = "completed_drink_pickup"
        } else {
            drinkDisplay.name = "drink_display"
        }
    }
    
    func createCompletedDrink(from stations: [IngredientStation]) -> RotatableObject? {
        guard isComplete else { return nil }
        
        // Get recipe
        var iceLevel = 0
        var hasBoba = false
        var hasFoam = false
        var hasTea = false
        var hasLid = false
        
        for station in stations {
            switch station.stationType {
            case .ice:
                iceLevel = station.iceLevel
            case .boba:
                hasBoba = station.hasBoba
            case .foam:
                hasFoam = station.hasFoam
            case .tea:
                hasTea = station.hasTea
            case .lid:
                hasLid = station.hasLid
            }
        }
        
        // Create completed drink with recipe
        let teaColor: SKColor
        switch iceLevel {
        case 0: teaColor = SKColor(red: 0.6, green: 0.3, blue: 0.1, alpha: 1.0) // Dark
        case 1: teaColor = SKColor(red: 0.8, green: 0.6, blue: 0.4, alpha: 1.0) // Light
        case 2: teaColor = SKColor(red: 0.7, green: 0.4, blue: 0.2, alpha: 1.0) // Amber
        default: teaColor = SKColor(red: 0.6, green: 0.3, blue: 0.1, alpha: 1.0)
        }
        
        let completedDrink = RotatableObject(type: .completedDrink, color: teaColor, shape: "drink")
        completedDrink.name = "completed_boba"
        
        // Add visual layers (mini versions)
        if hasBoba {
            let boba = SKSpriteNode(color: .black, size: CGSize(width: 14, height: 4))
            boba.position = CGPoint(x: 0, y: -12)
            boba.alpha = 0.8
            completedDrink.addChild(boba)
        }
        
        if hasFoam {
            let foam = SKSpriteNode(color: SKColor(red: 1.0, green: 0.9, blue: 0.7, alpha: 0.9), size: CGSize(width: 18, height: 4))
            foam.position = CGPoint(x: 0, y: 15)
            completedDrink.addChild(foam)
        }
        
        if hasLid {
            let lid = SKSpriteNode(color: .darkGray, size: CGSize(width: 20, height: 4))
            lid.position = CGPoint(x: 0, y: 18)
            completedDrink.addChild(lid)
            
            let straw = SKSpriteNode(color: .white, size: CGSize(width: 1, height: 12))
            straw.position = CGPoint(x: 8, y: 15)
            completedDrink.addChild(straw)
        }
        
        return completedDrink
    }
    
    func resetStations(_ stations: [IngredientStation]) {
        // Reset all stations to default state
        for station in stations {
            station.resetToDefault()
        }
        
        // Clear display
        isComplete = false
        updateDrink(from: stations)
    }
}


