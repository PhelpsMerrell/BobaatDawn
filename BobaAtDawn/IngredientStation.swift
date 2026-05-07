//
//  IngredientStation.swift
//  BobaAtDawn
//
//  Simple ingredient stations for boba creation.
//
//  Model (post-refactor): stations are dumb furniture. They do NOT track
//  any ingredient or recipe state. Tapping a station with a carried
//  drink-in-hand applies that ingredient additively to the held cup —
//  that logic lives in GameScene.handleGameSceneLongPress via
//  DrinkCreator.applyIngredient(to:type:). Tapping with empty hands is
//  a haptic no-op.
//
//  The `.trash` station is special: it discards the held drink instead
//  of adding an ingredient. See GameScene.handleStationInteraction.
//

import SpriteKit

// MARK: - Ingredient Station
@objc(IngredientStation)
class IngredientStation: RotatableObject {

    private enum CodingKeys {
        static let stationType = "editorStationType"
    }
    
    enum StationType {
        case ice, boba, foam, tea, lid, trash
    }
    
    private(set) var stationType: StationType
    
    init(type: StationType) {
        self.stationType = type
        let color = GameConfig.stationColor(for: type)
        
        super.init(type: .station, color: color, shape: "station")
        self.name = "ingredient_station_\(type)"
        self.size = GameConfig.IngredientStations.size
        
        _ = applyStationSpriteFromType()
    }
    
    required init?(coder aDecoder: NSCoder) {
        let typeString = aDecoder.decodeObject(forKey: CodingKeys.stationType) as? String
        self.stationType = IngredientStation.stationType(from: typeString)
        super.init(coder: aDecoder)

        // Xcode's scene editor doesn't know about our custom CodingKeys,
        // so `editorStationType` is never written into the .sks archive.
        // When the encoded key is absent, `stationType(from:)` returns .tea
        // for every station (its default case) — which breaks trash, lid,
        // and every non-tea ingredient application.
        //
        // Fallback: derive the station type from the node name. The
        // editor convention is `ingredient_station_<type>`.
        if typeString == nil, let nodeName = self.name {
            let prefix = "ingredient_station_"
            let suffix = nodeName.hasPrefix(prefix)
                ? String(nodeName.dropFirst(prefix.count))
                : nodeName
            switch suffix.lowercased() {
            case "ice":   self.stationType = .ice
            case "boba":  self.stationType = .boba
            case "foam":  self.stationType = .foam
            case "tea":   self.stationType = .tea
            case "lid":   self.stationType = .lid
            case "trash": self.stationType = .trash
            default:      break
            }
        }

        _ = applyStationSpriteFromType()
    }

    override func encode(with coder: NSCoder) {
        super.encode(with: coder)
        coder.encode(IngredientStation.string(from: stationType), forKey: CodingKeys.stationType)
    }
    
    /// Play the station's interaction pulse. Called whenever the player
    /// taps this station (whether carrying a drink or not). Does not
    /// change any drink state — that's handled by the caller.
    func interact() {
        let pulse = SKAction.sequence([
            SKAction.scale(to: GameConfig.IngredientStations.interactionScaleAmount,
                           duration: GameConfig.IngredientStations.interactionDuration),
            SKAction.scale(to: 1.0, duration: GameConfig.IngredientStations.interactionDuration)
        ])
        run(pulse)
    }
    
    /// Map a station type to the ingredient sprite-layer name applied to
    /// the drink sprite when this station is used. Returns nil for `.trash`
    /// (which doesn't add a layer — it discards the drink) and `.lid`
    /// callers can switch on the enum directly if they need lid-specific
    /// handling, but the layer name is provided here for completeness.
    var ingredientLayerName: String? {
        switch stationType {
        case .tea:   return "tea_black"
        case .ice:   return "ice_cubes"
        case .boba:  return "topping_tapioca"
        case .foam:  return "foam_cheese"
        case .lid:   return "lid_straw"
        case .trash: return nil
        }
    }
}

private extension IngredientStation {
    static func string(from type: StationType) -> String {
        switch type {
        case .ice:   return "ice"
        case .boba:  return "boba"
        case .foam:  return "foam"
        case .tea:   return "tea"
        case .lid:   return "lid"
        case .trash: return "trash"
        }
    }

    static func stationType(from string: String?) -> StationType {
        switch string {
        case "ice":   return .ice
        case "boba":  return .boba
        case "foam":  return .foam
        case "lid":   return .lid
        case "trash": return .trash
        default:      return .tea
        }
    }
}

// MARK: - Sprite Mapping
extension IngredientStation.StationType {
    var preferredSpriteNames: [String] {
        switch self {
        case .ice:   return ["station_ice",   "station_default"]
        case .boba:  return ["station_boba",  "station_default"]
        case .foam:  return ["station_foam",  "station_default"]
        case .tea:   return ["station_tea",   "station_default"]
        case .lid:   return ["station_lid",   "station_default"]
        case .trash: return ["station_trash", "station_default"]
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
        texture.filteringMode = .nearest

        self.children
            .filter { $0.name?.hasPrefix("station_") == true || $0.name?.hasPrefix("shape_") == true }
            .forEach { $0.removeFromParent() }

        self.texture = texture
        self.color = .white
        self.colorBlendFactor = 0.0
        return true
    }

    @discardableResult
    func applyStationSpriteFromType(atlasName: String = "Stations") -> Bool {
        return createStationSprite(preferredNames: stationType.preferredSpriteNames, atlasName: atlasName)
    }
}
