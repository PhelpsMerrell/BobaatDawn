//
//  BobaBrewingStation.swift
//  BobaAtDawn
//
//  Created by Phelps Merrell on 8/18/25.
//

import SpriteKit

// MARK: - Drink State Management
struct DrinkState {
    var teaType: TeaType = .none
    var hasTapioca: Bool = false
    var hasFoam: Bool = false
    var hasLid: Bool = false
    
    var isComplete: Bool {
        return teaType != .none && hasLid
    }
    
    enum TeaType {
        case none, regular, light, noIce
    }
}

// MARK: - Boba Brewing Station
class BobaBrewingStation: RotatableObject {
    
    // MARK: - Power & Mode State
    private var isPowered: Bool = true
    
    // MARK: - Station Components
    private var drinkState = DrinkState()
    private var baseStation: SKSpriteNode!
    private var drinkContainer: SKNode!
    
    // Boba layers (large size)
    private var cupEmpty: SKSpriteNode!
    private var drinkRegular: SKSpriteNode!
    private var drinkLight: SKSpriteNode!
    private var drinkNoIce: SKSpriteNode!
    private var toppingTapioca: SKSpriteNode!
    private var foamCheese: SKSpriteNode!
    private var lidStraw: SKSpriteNode!
    
    // Interaction areas (large size)
    private var teaArea: BrewingArea!
    private var tapiocarArea: BrewingArea!
    private var foamArea: BrewingArea!
    private var lidArea: BrewingArea!
    
    init() {
        super.init(type: .station, color: SKColor(red: 0.5, green: 0.3, blue: 0.2, alpha: 1.0), shape: "station")
        
        // Override size for station (brewing stations are large)
        self.size = CGSize(width: 600, height: 400)
        
        setupStation()
        setupDrinkLayers()
        setupInteractionAreas()
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupStation() {
        // Large base brewing station
        baseStation = SKSpriteNode(color: SKColor(red: 0.5, green: 0.3, blue: 0.2, alpha: 1.0), size: size)
        baseStation.name = "brewing_station"
        baseStation.zPosition = 0
        addChild(baseStation)
        
        // Container for drink layers
        drinkContainer = SKNode()
        drinkContainer.position = CGPoint(x: 0, y: 0)
        drinkContainer.zPosition = 5
        addChild(drinkContainer)
    }
    
    private func setupDrinkLayers() {
        // Create large placeholder sprites for boba components
        cupEmpty = createPlaceholderSprite(color: .white, size: CGSize(width: 80, height: 120), name: "cup_empty")
        drinkRegular = createPlaceholderSprite(color: SKColor(red: 0.6, green: 0.3, blue: 0.1, alpha: 0.8), size: CGSize(width: 70, height: 100), name: "drink_regular")
        drinkLight = createPlaceholderSprite(color: SKColor(red: 0.8, green: 0.6, blue: 0.4, alpha: 0.8), size: CGSize(width: 70, height: 100), name: "drink_light")
        drinkNoIce = createPlaceholderSprite(color: SKColor(red: 0.7, green: 0.4, blue: 0.2, alpha: 0.8), size: CGSize(width: 70, height: 100), name: "drink_no_ice")
        toppingTapioca = createPlaceholderSprite(color: .black, size: CGSize(width: 65, height: 25), name: "topping_tapioca")
        foamCheese = createPlaceholderSprite(color: SKColor(red: 1.0, green: 0.9, blue: 0.7, alpha: 0.9), size: CGSize(width: 75, height: 20), name: "foam_cheese")
        lidStraw = createPlaceholderSprite(color: .darkGray, size: CGSize(width: 85, height: 25), name: "lid_straw")
        
        // Add to drink container
        drinkContainer.addChild(cupEmpty)
        drinkContainer.addChild(drinkRegular)
        drinkContainer.addChild(drinkLight)
        drinkContainer.addChild(drinkNoIce)
        drinkContainer.addChild(toppingTapioca)
        drinkContainer.addChild(foamCheese)
        drinkContainer.addChild(lidStraw)
        
        // Position layers
        toppingTapioca.position = CGPoint(x: 0, y: -25)
        foamCheese.position = CGPoint(x: 0, y: 35)
        lidStraw.position = CGPoint(x: 0, y: 50)
        
        updateDrinkVisuals()
    }
    
    private func createPlaceholderSprite(color: SKColor, size: CGSize, name: String) -> SKSpriteNode {
        let sprite = SKSpriteNode(color: color, size: size)
        sprite.name = name
        return sprite
    }
    
    private func setupInteractionAreas() {
        // Large interaction areas - easy to tap
        
        // Tea selection area (left side)
        teaArea = BrewingArea(type: .tea, size: CGSize(width: 120, height: 100))
        teaArea.position = CGPoint(x: -180, y: 50)
        addChild(teaArea)
        
        // Tapioca area (right side, top)
        tapiocarArea = BrewingArea(type: .tapioca, size: CGSize(width: 100, height: 80))
        tapiocarArea.position = CGPoint(x: 180, y: 80)
        addChild(tapiocarArea)
        
        // Foam area (right side, middle)
        foamArea = BrewingArea(type: .foam, size: CGSize(width: 100, height: 80))
        foamArea.position = CGPoint(x: 180, y: 0)
        addChild(foamArea)
        
        // Lid area (bottom)
        lidArea = BrewingArea(type: .lid, size: CGSize(width: 120, height: 80))
        lidArea.position = CGPoint(x: 0, y: -120)
        addChild(lidArea)
    }
    
    // MARK: - Power Management
    func setPowered(_ powered: Bool) {
        isPowered = powered
        updatePowerVisuals()
    }
    
    private func updatePowerVisuals() {
        let alpha: CGFloat = isPowered ? 1.0 : 0.5
        baseStation.alpha = alpha
        
        // Disable interactions when unpowered
        teaArea.isUserInteractionEnabled = isPowered
        tapiocarArea.isUserInteractionEnabled = isPowered
        foamArea.isUserInteractionEnabled = isPowered
        lidArea.isUserInteractionEnabled = isPowered
        
        if !isPowered {
            // Show that station is movable
            let pulseAction = SKAction.repeatForever(
                SKAction.sequence([
                    SKAction.fadeAlpha(to: 0.7, duration: 1.0),
                    SKAction.fadeAlpha(to: 0.5, duration: 1.0)
                ])
            )
            baseStation.run(pulseAction, withKey: "powerOff")
        } else {
            baseStation.removeAction(forKey: "powerOff")
            baseStation.alpha = 1.0
        }
    }
    
    // MARK: - Brewing Interactions
    func handleInteraction(_ areaType: BrewingArea.AreaType, at location: CGPoint) {
        guard isPowered else { return }
        
        switch areaType {
        case .tea:
            cycleTea()
        case .tapioca:
            toggleTapioca()
        case .foam:
            toggleFoam()
        case .lid:
            addLid()
        }
        
        updateDrinkVisuals()
        
        // Add interaction feedback
        let pulseAction = SKAction.sequence([
            SKAction.scale(to: 1.15, duration: 0.15),
            SKAction.scale(to: 1.0, duration: 0.15)
        ])
        drinkContainer.run(pulseAction)
    }
    
    private func cycleTea() {
        switch drinkState.teaType {
        case .none:
            drinkState.teaType = .regular
        case .regular:
            drinkState.teaType = .light
        case .light:
            drinkState.teaType = .noIce
        case .noIce:
            drinkState.teaType = .regular
        }
    }
    
    private func toggleTapioca() {
        drinkState.hasTapioca.toggle()
    }
    
    private func toggleFoam() {
        drinkState.hasFoam.toggle()
    }
    
    private func addLid() {
        if drinkState.teaType != .none {
            drinkState.hasLid = true
        }
    }
    
    private func updateDrinkVisuals() {
        // Hide all drink layers first
        drinkRegular.isHidden = true
        drinkLight.isHidden = true
        drinkNoIce.isHidden = true
        toppingTapioca.isHidden = true
        foamCheese.isHidden = true
        lidStraw.isHidden = true
        
        // Show appropriate tea
        switch drinkState.teaType {
        case .none:
            break
        case .regular:
            drinkRegular.isHidden = false
        case .light:
            drinkLight.isHidden = false
        case .noIce:
            drinkNoIce.isHidden = false
        }
        
        // Show toppings
        toppingTapioca.isHidden = !drinkState.hasTapioca
        foamCheese.isHidden = !drinkState.hasFoam
        lidStraw.isHidden = !drinkState.hasLid
        
        // Update interactable shaking
        updateShaking()
    }
    
    private func updateShaking() {
        // Remove existing shake actions
        drinkContainer.removeAction(forKey: "shake")
        
        // Add shake if drink is complete and can be picked up
        if drinkState.isComplete && isPowered {
            let shakeAction = SKAction.repeatForever(
                SKAction.sequence([
                    SKAction.moveBy(x: 2, y: 0, duration: 0.1),
                    SKAction.moveBy(x: -4, y: 0, duration: 0.2),
                    SKAction.moveBy(x: 2, y: 0, duration: 0.1),
                    SKAction.wait(forDuration: 1.0)
                ])
            )
            drinkContainer.run(shakeAction, withKey: "shake")
            drinkContainer.name = "interactable_drink"
        } else {
            drinkContainer.name = nil
        }
    }
    
    func hasCompletedDrink() -> Bool {
        return drinkState.isComplete && isPowered
    }
    
    func takeCompletedDrink() -> RotatableObject? {
        guard drinkState.isComplete && isPowered else { return nil }
        
        // Create a completed drink that matches the recipe
        let completedDrink = createRecipeAccurateDrink(from: drinkState)
        completedDrink.name = "completed_drink"
        completedDrink.zPosition = 15
        
        // Position it at the station's position initially
        completedDrink.position = self.position
        parent?.addChild(completedDrink)
        
        // Reset brewing station
        drinkState = DrinkState()
        updateDrinkVisuals()
        
        return completedDrink
    }
    
    private func createRecipeAccurateDrink(from state: DrinkState) -> RotatableObject {
        // Base drink color based on tea type
        let teaColor: SKColor
        switch state.teaType {
        case .none:
            teaColor = SKColor(red: 0.8, green: 0.6, blue: 0.4, alpha: 1.0) // Default
        case .regular:
            teaColor = SKColor(red: 0.6, green: 0.3, blue: 0.1, alpha: 1.0) // Dark brown
        case .light:
            teaColor = SKColor(red: 0.8, green: 0.6, blue: 0.4, alpha: 1.0) // Light brown
        case .noIce:
            teaColor = SKColor(red: 0.7, green: 0.4, blue: 0.2, alpha: 1.0) // Amber
        }
        
        let drink = RotatableObject(type: .completedDrink, color: teaColor, shape: "drink")
        
        // Add visual layers for toppings (scaled down versions)
        if state.hasTapioca {
            let tapioca = SKSpriteNode(color: .black, size: CGSize(width: 16, height: 6))
            tapioca.position = CGPoint(x: 0, y: -15)
            tapioca.name = "mini_tapioca"
            tapioca.alpha = 0.8
            drink.addChild(tapioca)
        }
        
        if state.hasFoam {
            let foam = SKSpriteNode(color: SKColor(red: 1.0, green: 0.9, blue: 0.7, alpha: 0.9), size: CGSize(width: 20, height: 5))
            foam.position = CGPoint(x: 0, y: 18)
            foam.name = "mini_foam"
            foam.alpha = 0.8
            drink.addChild(foam)
        }
        
        if state.hasLid {
            let lid = SKSpriteNode(color: .darkGray, size: CGSize(width: 22, height: 6))
            lid.position = CGPoint(x: 0, y: 25)
            lid.name = "mini_lid"
            lid.alpha = 0.8
            drink.addChild(lid)
            
            // Add straw
            let straw = SKSpriteNode(color: .white, size: CGSize(width: 2, height: 15))
            straw.position = CGPoint(x: 8, y: 20)
            straw.name = "mini_straw"
            straw.alpha = 0.8
            drink.addChild(straw)
        }
        
        return drink
    }
    
    func update() {
        // Update any ongoing animations or state
    }
}

// MARK: - Brewing Area Helper
class BrewingArea: SKSpriteNode {
    
    enum AreaType {
        case tea, tapioca, foam, lid
    }
    
    let areaType: AreaType
    
    init(type: AreaType, size: CGSize) {
        self.areaType = type
        
        let color: SKColor
        switch type {
        case .tea:
            color = SKColor(red: 0.6, green: 0.3, blue: 0.1, alpha: 0.4)
        case .tapioca:
            color = SKColor(red: 0.2, green: 0.2, blue: 0.2, alpha: 0.4)
        case .foam:
            color = SKColor(red: 1.0, green: 0.9, blue: 0.7, alpha: 0.4)
        case .lid:
            color = SKColor(red: 0.4, green: 0.4, blue: 0.4, alpha: 0.4)
        }
        
        super.init(texture: nil, color: color, size: size)
        self.name = "brewing_area_\(type)"
        self.zPosition = 1
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
