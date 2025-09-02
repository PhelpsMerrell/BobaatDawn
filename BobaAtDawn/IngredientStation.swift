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
        
        switch type {
        case .ice:
            currentState = 0 // 0=ice, 1=lite, 2=none
        case .boba, .foam, .tea, .lid:
            currentState = false
        }
        
        super.init(type: .station, color: color, shape: "station")
        self.name = "ingredient_station_\(type)"
        self.size = GameConfig.IngredientStations.size
        
        updateVisuals()
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func interact() {
        print("🧋 💆 Interacting with \(stationType) station (current state: \(currentState))")
        
        switch stationType {
        case .ice:
            var iceLevel = currentState as! Int
            let oldLevel = iceLevel
            iceLevel = (iceLevel + 1) % 3 // 0, 1, 2, back to 0
            currentState = iceLevel
            print("🧏 Ice level changed: \(oldLevel) -> \(iceLevel) (0=full, 1=light, 2=none)")
            
        case .boba, .foam, .tea, .lid:
            var toggle = currentState as! Bool
            let oldState = toggle
            toggle.toggle()
            currentState = toggle
            print("🍵 \(stationType) toggled: \(oldState) -> \(toggle)")
        }
        
        updateVisuals()
        
        // Enhanced visual feedback
        let pulseAction = SKAction.sequence([
            SKAction.scale(to: GameConfig.IngredientStations.interactionScaleAmount, duration: GameConfig.IngredientStations.interactionDuration),
            SKAction.scale(to: 1.0, duration: GameConfig.IngredientStations.interactionDuration)
        ])
        run(pulseAction)
        
        print("🧋 ✅ \(stationType) interaction complete - new state: \(currentState)")
    }
    
    private func updateVisuals() {
        // Simple visual indicator - just change alpha/brightness
        switch stationType {
        case .ice:
            let iceLevel = currentState as! Int
            alpha = iceLevel == 2 ? 0.3 : (iceLevel == 1 ? 0.6 : 1.0) // none, lite, full
            
        case .boba, .foam, .tea, .lid:
            let isActive = currentState as! Bool
            alpha = isActive ? 1.0 : 0.3
        }
    }
    
    // Getters for drink creation
    var iceLevel: Int { return currentState as! Int }
    var hasBoba: Bool { return stationType == .boba ? currentState as! Bool : false }
    var hasFoam: Bool { return stationType == .foam ? currentState as! Bool : false }
    var hasTea: Bool { return stationType == .tea ? currentState as! Bool : false }
    var hasLid: Bool { return stationType == .lid ? currentState as! Bool : false }
    
    func resetToDefault() {
        print("🧋 🔄 Resetting \(stationType) station from state \(currentState)")
        
        switch stationType {
        case .ice:
            currentState = 0
        case .boba, .foam, .tea, .lid:
            currentState = false
        }
        
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
