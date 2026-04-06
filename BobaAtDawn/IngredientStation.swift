//
//  IngredientStation.swift
//  BobaAtDawn
//
//  Simple ingredient stations for boba creation
//

import SpriteKit

// MARK: - Ingredient Station
class IngredientStation: RotatableObject {
    
    enum StationType {
        case ice, boba, foam, tea, lid
    }
    
    let stationType: StationType
    private var isActive: Bool = false
    
    init(type: StationType) {
        self.stationType = type
        let color = GameConfig.stationColor(for: type)
        
        super.init(type: .station, color: color, shape: "station")
        self.name = "ingredient_station_\(type)"
        self.size = GameConfig.IngredientStations.size
        
        updateVisuals()
        _ = applyStationSpriteFromType()
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func interact() {
        isActive.toggle()
        Log.debug(.drink, "\(stationType) toggled → \(isActive ? "ON" : "OFF")")
        updateVisuals()
        
        let pulse = SKAction.sequence([
            SKAction.scale(to: GameConfig.IngredientStations.interactionScaleAmount,
                           duration: GameConfig.IngredientStations.interactionDuration),
            SKAction.scale(to: 1.0, duration: GameConfig.IngredientStations.interactionDuration)
        ])
        run(pulse)
    }
    
    private func updateVisuals() {
        alpha = isActive ? 1.0 : 0.3
    }
    
    // MARK: - State Getters (used by DrinkCreator)
    var hasIce:  Bool { stationType == .ice  && isActive }
    var hasBoba: Bool { stationType == .boba && isActive }
    var hasFoam: Bool { stationType == .foam && isActive }
    var hasTea:  Bool { stationType == .tea  && isActive }
    var hasLid:  Bool { stationType == .lid  && isActive }
    
    func resetToDefault() {
        isActive = false
        updateVisuals()
        
        let flash = SKAction.sequence([
            SKAction.colorize(with: .red, colorBlendFactor: 0.5, duration: 0.1),
            SKAction.colorize(with: .white, colorBlendFactor: 0.0, duration: 0.2),
            SKAction.colorize(withColorBlendFactor: 0.0, duration: 0.1)
        ])
        run(flash)
    }
}

// MARK: - Sprite Mapping
extension IngredientStation.StationType {
    var preferredSpriteNames: [String] {
        switch self {
        case .ice:  return ["station_ice", "station_default"]
        case .boba: return ["station_boba", "station_default"]
        case .foam: return ["station_foam", "station_default"]
        case .tea:  return ["station_tea", "station_default"]
        case .lid:  return ["station_lid", "station_default"]
        }
    }
}

extension IngredientStation {
    @discardableResult
    func createStationSprite(preferredNames: [String], atlasName: String = "Stations") -> Bool {
        let atlas = SKTextureAtlas(named: atlasName)
        guard let foundName = preferredNames.first(where: { atlas.textureNames.contains($0) }) else {
            return false
        }
        
        let texture = atlas.textureNamed(foundName)
        let node = SKSpriteNode(texture: texture)
        node.name = "station_sprite_\(foundName)"
        node.zPosition = 1
        node.position = .zero
        node.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        node.setScale(0.7)

        self.children
            .filter { $0.name?.hasPrefix("station_") == true || $0.name?.hasPrefix("shape_") == true }
            .forEach { $0.removeFromParent() }

        self.addChild(node)
        return true
    }

    @discardableResult
    func applyStationSpriteFromType(atlasName: String = "Stations") -> Bool {
        return createStationSprite(preferredNames: stationType.preferredSpriteNames, atlasName: atlasName)
    }
}
