//
//  DrinkCreator.swift
//  BobaAtDawn
//
//  Visual drink builder — reads station state and shows a layered boba sprite.
//

import SpriteKit

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
        drinkDisplay = RotatableObject(type: .completedDrink, color: .clear, shape: "drink")
        drinkDisplay.size = CGSize(width: 40, height: 60)
        drinkDisplay.name = "drink_display"
        addChild(drinkDisplay)
    }
    
    // MARK: - Update Display from Station State
    
    func updateDrink(from stations: [IngredientStation]) {
        var hasIce = false, hasBoba = false, hasFoam = false, hasTea = false, hasLid = false
        
        for station in stations {
            switch station.stationType {
            case .ice:  hasIce  = station.hasIce
            case .boba: hasBoba = station.hasBoba
            case .foam: hasFoam = station.hasFoam
            case .tea:  hasTea  = station.hasTea
            case .lid:  hasLid  = station.hasLid
            }
        }
        
        isComplete = hasTea && hasLid
        updateDrinkVisuals(hasIce: hasIce, hasBoba: hasBoba, hasFoam: hasFoam, hasTea: hasTea, hasLid: hasLid)
        updateShaking()
    }
    
    // MARK: - Sprite Layering
    
    private func updateDrinkVisuals(hasIce: Bool, hasBoba: Bool, hasFoam: Bool, hasTea: Bool, hasLid: Bool) {
        drinkDisplay.removeAllChildren()
        
        let atlas = SKTextureAtlas(named: "Boba")
        let cupTex = atlas.textureNamed("cup_empty")
        cupTex.filteringMode = .nearest
        let scale = 35.0 / cupTex.size().width
        
        func layer(_ name: String, z: CGFloat, visible: Bool = true) -> SKSpriteNode {
            let tex = atlas.textureNamed(name)
            tex.filteringMode = .nearest
            let node = SKSpriteNode(texture: tex)
            node.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            node.position = .zero
            node.setScale(scale)
            node.zPosition = z
            node.isHidden = !visible
            node.blendMode = .alpha
            node.name = name
            return node
        }
        
        drinkDisplay.addChild(layer("cup_empty", z: 0))
        if hasTea  { drinkDisplay.addChild(layer("tea_black",        z: 1)) }
        if hasIce  { drinkDisplay.addChild(layer("ice_cubes",        z: 2)) }
        if hasBoba { drinkDisplay.addChild(layer("topping_tapioca",  z: 3)) }
        if hasFoam { drinkDisplay.addChild(layer("foam_cheese",      z: 4)) }
        if hasLid  { drinkDisplay.addChild(layer("lid_straw",        z: 5)) }
    }
    
    private func updateShaking() {
        drinkDisplay.removeAction(forKey: "shake")
        
        if isComplete {
            let shake = SKAction.repeatForever(SKAction.sequence([
                SKAction.moveBy(x: 2, y: 0, duration: 0.1),
                SKAction.moveBy(x: -4, y: 0, duration: 0.2),
                SKAction.moveBy(x: 2, y: 0, duration: 0.1),
                SKAction.wait(forDuration: 2.5)
            ]))
            drinkDisplay.run(shake, withKey: "shake")
            drinkDisplay.name = "completed_drink_pickup"
        } else {
            drinkDisplay.name = "drink_display"
        }
    }
    
    // MARK: - Create Portable Drinks
    
    func createCompletedDrink(from stations: [IngredientStation]) -> RotatableObject? {
        guard isComplete else { return nil }
        return buildPortableDrink(from: stations, type: .completedDrink, name: "completed_drink")
    }
    
    func createPickupDrink(from stations: [IngredientStation]) -> RotatableObject {
        let drinkType: ObjectType = isComplete ? .completedDrink : .drink
        let drinkName = isComplete ? "completed_drink" : "picked_up_drink"
        return buildPortableDrink(from: stations, type: drinkType, name: drinkName)
    }
    
    private func buildPortableDrink(from stations: [IngredientStation], type: ObjectType, name: String) -> RotatableObject {
        var hasIce = false, hasBoba = false, hasFoam = false, hasTea = false, hasLid = false
        for s in stations {
            switch s.stationType {
            case .ice:  hasIce  = s.hasIce
            case .boba: hasBoba = s.hasBoba
            case .foam: hasFoam = s.hasFoam
            case .tea:  hasTea  = s.hasTea
            case .lid:  hasLid  = s.hasLid
            }
        }
        
        let drink = RotatableObject(type: type, color: .clear, shape: "drink")
        drink.size = CGSize(width: 30, height: 45)
        drink.name = name
        
        let atlas = SKTextureAtlas(named: "Boba")
        let cupTex = atlas.textureNamed("cup_empty")
        let scale = 25.0 / cupTex.size().width
        
        func addLayer(_ texName: String, z: CGFloat) {
            guard atlas.textureNames.contains(texName) else { return }
            let tex = atlas.textureNamed(texName)
            tex.filteringMode = .nearest
            let node = SKSpriteNode(texture: tex)
            node.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            node.position = .zero
            node.setScale(scale)
            node.zPosition = z
            node.blendMode = .alpha
            node.name = texName
            drink.addChild(node)
        }
        
        addLayer("cup_empty",       z: 0)
        if hasTea  { addLayer("tea_black",       z: 1) }
        if hasIce  { addLayer("ice_cubes",       z: 2) }
        if hasBoba { addLayer("topping_tapioca", z: 3) }
        if hasFoam { addLayer("foam_cheese",     z: 4) }
        if hasLid  { addLayer("lid_straw",       z: 5) }
        
        Log.debug(.drink, "Built portable drink: tea=\(hasTea) ice=\(hasIce) boba=\(hasBoba) foam=\(hasFoam) lid=\(hasLid)")
        return drink
    }
    
    // MARK: - Reset
    
    func resetStations(_ stations: [IngredientStation]) {
        for station in stations { station.resetToDefault() }
        
        isComplete = false
        drinkDisplay.removeAllActions()
        drinkDisplay.name = "drink_display"
        updateDrink(from: stations)
        
        let pulse = SKAction.sequence([
            SKAction.scale(to: 1.2, duration: 0.15),
            SKAction.scale(to: 0.8, duration: 0.15),
            SKAction.scale(to: 1.0, duration: 0.15)
        ])
        drinkDisplay.run(pulse)
        
        Log.info(.drink, "Stations reset — ready for next drink")
    }
}
