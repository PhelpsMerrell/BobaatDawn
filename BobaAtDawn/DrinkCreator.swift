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
        
        // Base cup (proper cup shape using SKShapeNode)
        let cup = createCupShape()
        drinkDisplay.addChild(cup)
        
        // Tea (if present) - create tea shape that fits inside cup
        if hasTea {
            let teaColor: SKColor
            switch iceLevel {
            case 0: teaColor = SKColor(red: 0.6, green: 0.3, blue: 0.1, alpha: 0.8) // Dark (full ice)
            case 1: teaColor = SKColor(red: 0.8, green: 0.6, blue: 0.4, alpha: 0.8) // Light (lite ice)
            case 2: teaColor = SKColor(red: 0.7, green: 0.4, blue: 0.2, alpha: 0.8) // Amber (no ice)
            default: teaColor = SKColor(red: 0.6, green: 0.3, blue: 0.1, alpha: 0.8)
            }
            
            // Create tea shape that fits inside the cup
            let teaShape = createTeaShape(color: teaColor)
            drinkDisplay.addChild(teaShape)
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
            // Restore the shaking animation every 2-3 seconds
            let shakeAction = SKAction.repeatForever(
                SKAction.sequence([
                    SKAction.moveBy(x: 2, y: 0, duration: 0.1),
                    SKAction.moveBy(x: -4, y: 0, duration: 0.2),
                    SKAction.moveBy(x: 2, y: 0, duration: 0.1),
                    SKAction.wait(forDuration: 2.5)  // Wait 2.5 seconds between shakes
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
        
        // Get recipe from stations (independent snapshot)
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
        
        // Create tea color based on recipe
        let teaColor: SKColor
        switch iceLevel {
        case 0: teaColor = SKColor(red: 0.6, green: 0.3, blue: 0.1, alpha: 1.0) // Dark
        case 1: teaColor = SKColor(red: 0.8, green: 0.6, blue: 0.4, alpha: 1.0) // Light
        case 2: teaColor = SKColor(red: 0.7, green: 0.4, blue: 0.2, alpha: 1.0) // Amber
        default: teaColor = SKColor(red: 0.6, green: 0.3, blue: 0.1, alpha: 1.0)
        }
        
        // Create completely independent completed drink
        let completedDrink = RotatableObject(type: .completedDrink, color: .clear, shape: "drink")
        completedDrink.name = "completed_boba_\(Int.random(in: 1000...9999))"  // Unique name
        completedDrink.size = CGSize(width: 30, height: 45)  // Smaller carried size
        
        // Add cup shape (independent copy)
        let cupShape = createCompletedDrinkCupShape()
        cupShape.fillColor = teaColor  // Cup shows tea type
        completedDrink.addChild(cupShape)
        
        // Add visual layers (completely independent from display)
        if hasBoba {
            let boba = SKSpriteNode(color: .black, size: CGSize(width: 12, height: 3))
            boba.position = CGPoint(x: 0, y: -10)
            boba.alpha = 0.8
            boba.name = "boba_layer"
            completedDrink.addChild(boba)
        }
        
        if hasFoam {
            let foam = SKSpriteNode(color: SKColor(red: 1.0, green: 0.9, blue: 0.7, alpha: 0.9), size: CGSize(width: 15, height: 3))
            foam.position = CGPoint(x: 0, y: 12)
            foam.name = "foam_layer"
            completedDrink.addChild(foam)
        }
        
        if hasLid {
            let lid = SKSpriteNode(color: .darkGray, size: CGSize(width: 18, height: 3))
            lid.position = CGPoint(x: 0, y: 15)
            lid.name = "lid_layer"
            completedDrink.addChild(lid)
            
            let straw = SKSpriteNode(color: .white, size: CGSize(width: 1, height: 10))
            straw.position = CGPoint(x: 6, y: 12)
            straw.name = "straw_layer"
            completedDrink.addChild(straw)
        }
        
        print("🎆 Created independent completed drink: \(completedDrink.name!)")
        return completedDrink
    }
    
    // MARK: - Cup Shape Creation
    private func createCupShape() -> SKShapeNode {
        // Create cup shape using bezier path
        let cupPath = UIBezierPath()
        
        // Cup dimensions
        let cupWidth: CGFloat = 30
        let cupHeight: CGFloat = 50
        let bottomWidth: CGFloat = 25
        
        // Start at bottom-left
        cupPath.move(to: CGPoint(x: -bottomWidth/2, y: -cupHeight/2))
        
        // Bottom edge
        cupPath.addLine(to: CGPoint(x: bottomWidth/2, y: -cupHeight/2))
        
        // Right edge (slightly curved outward)
        cupPath.addQuadCurve(to: CGPoint(x: cupWidth/2, y: cupHeight/2), 
                            controlPoint: CGPoint(x: cupWidth/2, y: 0))
        
        // Top edge
        cupPath.addLine(to: CGPoint(x: -cupWidth/2, y: cupHeight/2))
        
        // Left edge (slightly curved outward)
        cupPath.addQuadCurve(to: CGPoint(x: -bottomWidth/2, y: -cupHeight/2), 
                            controlPoint: CGPoint(x: -cupWidth/2, y: 0))
        
        cupPath.close()
        
        // Create shape node
        let cupShape = SKShapeNode(path: cupPath.cgPath)
        cupShape.fillColor = SKColor.white
        cupShape.strokeColor = SKColor(red: 0.8, green: 0.8, blue: 0.8, alpha: 1.0)
        cupShape.lineWidth = 1.5
        cupShape.alpha = 0.9
        
        return cupShape
    }
    
    private func createCompletedDrinkCupShape() -> SKShapeNode {
        // Smaller version for completed drinks
        let cupPath = UIBezierPath()
        
        // Smaller cup dimensions
        let cupWidth: CGFloat = 18
        let cupHeight: CGFloat = 30
        let bottomWidth: CGFloat = 15
        
        // Start at bottom-left
        cupPath.move(to: CGPoint(x: -bottomWidth/2, y: -cupHeight/2))
        
        // Bottom edge
        cupPath.addLine(to: CGPoint(x: bottomWidth/2, y: -cupHeight/2))
        
        // Right edge (slightly curved outward)
        cupPath.addQuadCurve(to: CGPoint(x: cupWidth/2, y: cupHeight/2), 
                            controlPoint: CGPoint(x: cupWidth/2, y: 0))
        
        // Top edge
        cupPath.addLine(to: CGPoint(x: -cupWidth/2, y: cupHeight/2))
        
        // Left edge (slightly curved outward)
        cupPath.addQuadCurve(to: CGPoint(x: -bottomWidth/2, y: -cupHeight/2), 
                            controlPoint: CGPoint(x: -cupWidth/2, y: 0))
        
        cupPath.close()
        
        // Create shape node
        let cupShape = SKShapeNode(path: cupPath.cgPath)
        cupShape.fillColor = SKColor.white
        cupShape.strokeColor = SKColor(red: 0.8, green: 0.8, blue: 0.8, alpha: 1.0)
        cupShape.lineWidth = 1.0
        cupShape.alpha = 0.9
        
        return cupShape
    }
    
    private func createTeaShape(color: SKColor) -> SKShapeNode {
        // Create tea shape that fits nicely inside the cup
        let teaPath = UIBezierPath()
        
        // Tea dimensions (slightly smaller than cup)
        let teaWidth: CGFloat = 26
        let teaHeight: CGFloat = 35
        let bottomWidth: CGFloat = 22
        
        // Start at bottom-left (leave space at bottom for boba)
        teaPath.move(to: CGPoint(x: -bottomWidth/2, y: -teaHeight/2 + 8))
        
        // Bottom edge
        teaPath.addLine(to: CGPoint(x: bottomWidth/2, y: -teaHeight/2 + 8))
        
        // Right edge (slightly curved)
        teaPath.addQuadCurve(to: CGPoint(x: teaWidth/2, y: teaHeight/2), 
                            controlPoint: CGPoint(x: teaWidth/2, y: 0))
        
        // Top edge (flat)
        teaPath.addLine(to: CGPoint(x: -teaWidth/2, y: teaHeight/2))
        
        // Left edge (slightly curved)
        teaPath.addQuadCurve(to: CGPoint(x: -bottomWidth/2, y: -teaHeight/2 + 8), 
                            controlPoint: CGPoint(x: -teaWidth/2, y: 0))
        
        teaPath.close()
        
        // Create shape node
        let teaShape = SKShapeNode(path: teaPath.cgPath)
        teaShape.fillColor = color
        teaShape.strokeColor = SKColor.clear
        teaShape.zPosition = 1
        
        return teaShape
    }
    
    func resetStations(_ stations: [IngredientStation]) {
        // Reset all stations to default state
        for station in stations {
            station.resetToDefault()
        }
        
        // Clear display and update to show empty state
        isComplete = false
        updateDrink(from: stations)
        
        print("🎆 Stations reset - ready for next drink creation")
    }
}


