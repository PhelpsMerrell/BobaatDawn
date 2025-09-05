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
    private var currentState: Any = false // Bool for toggles, Int for cycles
    
    init(type: StationType) {
        self.stationType = type
        
        let color = GameConfig.stationColor(for: type)
        
        currentState = false
        
        super.init(type: .station, color: color, shape: "station")
        self.name = "ingredient_station_\(type)"
        self.size = GameConfig.IngredientStations.size
        
        updateVisuals()
        
        // CRITICAL: Apply the correct sprite based on station type
        let spriteApplied = applyStationSpriteFromType()
        print("🧋 🎨 \(type) station sprite applied: \(spriteApplied)")
        if !spriteApplied {
            print("🧋 ⚠️ \(type) station falling back to colored shape")
        }
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func interact() {
        print("🧋 💆 Interacting with \(stationType) station (current state: \(currentState))")
        print("🧋 🔍 Station name: \(self.name ?? "unnamed")")
        print("🧋 🔍 Station position: \(self.position)")
        
        var toggle = currentState as! Bool
        let oldState = toggle
        toggle.toggle()
        currentState = toggle
        print("🍵 \(stationType) toggled: \(oldState) -> \(toggle)")
        
        updateVisuals()
        
        // Enhanced visual feedback
        let pulseAction = SKAction.sequence([
            SKAction.scale(to: GameConfig.IngredientStations.interactionScaleAmount, duration: GameConfig.IngredientStations.interactionDuration),
            SKAction.scale(to: 1.0, duration: GameConfig.IngredientStations.interactionDuration)
        ])
        run(pulseAction)
        
        print("🧋 ✅ \(stationType) interaction complete - new state: \(currentState)")
        
        // Debug: Print what this station will return for drink creation
        print("🧋 🔍 hasIce: \(hasIce), hasBoba: \(hasBoba), hasFoam: \(hasFoam), hasTea: \(hasTea), hasLid: \(hasLid)")
    }
    
    private func updateVisuals() {
        
            let isActive = currentState as! Bool
            alpha = isActive ? 1.0 : 0.3
        
    }
    
    // Getters for drink creation
    var hasIce: Bool { 
        let result = stationType == .ice ? currentState as! Bool : false
        print("🧋 🧞 hasIce called on \(stationType) station: \(result) (currentState: \(currentState))")
        return result
    }
    var hasBoba: Bool { 
        let result = stationType == .boba ? currentState as! Bool : false
        print("🧋 🔴 hasBoba called on \(stationType) station: \(result) (currentState: \(currentState))")
        return result
    }
    var hasFoam: Bool { 
        let result = stationType == .foam ? currentState as! Bool : false
        print("🧋 🫧 hasFoam called on \(stationType) station: \(result) (currentState: \(currentState))")
        return result
    }
    var hasTea: Bool { 
        let result = stationType == .tea ? currentState as! Bool : false
        print("🧋 🍵 hasTea called on \(stationType) station: \(result) (currentState: \(currentState))")
        return result
    }
    var hasLid: Bool { 
        let result = stationType == .lid ? currentState as! Bool : false
        print("🧋 🥇 hasLid called on \(stationType) station: \(result) (currentState: \(currentState))")
        return result
    }
    
    func resetToDefault() {
        print("🧋 🔄 Resetting \(stationType) station from state \(currentState)")
        
       
        currentState = false
        
        
        updateVisuals()
        
        // Add visual feedback for reset
        let resetFeedback = SKAction.sequence([
            SKAction.colorize(with: .red, colorBlendFactor: 0.5, duration: 0.1),
            SKAction.colorize(with: .white, colorBlendFactor: 0.0, duration: 0.2),
            SKAction.colorize(withColorBlendFactor: 0.0, duration: 0.1)
        ])
        run(resetFeedback)
        
        print("🧋 ✅ \(stationType) reset to state \(currentState)")
    }
}


// MARK: - Sprite Mapping for Stations
extension IngredientStation.StationType {
    /// Preferred texture names to try (in order) for this station type.
    /// 1) A type-specific sprite (e.g., "station_ice")
    /// 2) A generic fallback sprite (e.g., "station_default")
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
    /// Attempts to create a station sprite by trying each name in `preferredNames`.
    /// Returns true if a texture was found and added; false if we should fall back to vector shapes.
    @discardableResult
    func createStationSprite(preferredNames: [String], atlasName: String = "Stations") -> Bool {
        let atlas = SKTextureAtlas(named: atlasName)
        
        print("🧋 🗺 Available textures in \(atlasName) atlas: \(atlas.textureNames.sorted())")
        print("🧋 🔍 Looking for \(stationType) station textures: \(preferredNames)")

        guard let foundName = preferredNames.first(where: { atlas.textureNames.contains($0) }) else {
            if let first = preferredNames.first {
                print("🧋⚠️ No textures found in \(atlasName).atlas for \(preferredNames) — falling back to shape for \(first).")
            } else {
                print("🧋⚠️ No preferredNames provided — falling back to shape.")
            }
            return false
        }

        print("🧋 ✅ Found texture '\(foundName)' for \(stationType) station")
        
        let texture = atlas.textureNamed(foundName)
        let node = SKSpriteNode(texture: texture)
        node.name = "station_sprite_\(foundName)"
        node.zPosition = 1
        node.position = .zero
        node.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        node.setScale(0.7)

        // Remove prior visual children this object added (keep physics/body)
        self.children
            .filter { $0.name?.hasPrefix("station_") == true || $0.name?.hasPrefix("shape_") == true }
            .forEach { $0.removeFromParent() }

        self.addChild(node)
        print("🧋 🎨 Applied \(foundName) sprite to \(stationType) station")
        return true
    }

    /// Convenience: build from the enum you already have (tries type-specific, then "station_default").
    @discardableResult
    func applyStationSpriteFromType(atlasName: String = "Stations") -> Bool {
        return createStationSprite(preferredNames: stationType.preferredSpriteNames, atlasName: atlasName)
    }
}
