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
        
        let color: SKColor
        switch type {
        case .ice:
            color = SKColor.cyan
            currentState = 0 // 0=ice, 1=lite, 2=none
        case .boba:
            color = SKColor.black
            currentState = false
        case .foam:
            color = SKColor(red: 1.0, green: 0.9, blue: 0.7, alpha: 1.0)
            currentState = false
        case .tea:
            color = SKColor(red: 0.6, green: 0.3, blue: 0.1, alpha: 1.0)
            currentState = false
        case .lid:
            color = SKColor.gray
            currentState = false
        }
        
        super.init(type: .station, color: color, shape: "station")
        self.name = "ingredient_station_\(type)"
        self.size = CGSize(width: 80, height: 80)
        
        updateVisuals()
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func interact() {
        switch stationType {
        case .ice:
            var iceLevel = currentState as! Int
            iceLevel = (iceLevel + 1) % 3 // 0, 1, 2, back to 0
            currentState = iceLevel
            
        case .boba, .foam, .tea, .lid:
            var toggle = currentState as! Bool
            toggle.toggle()
            currentState = toggle
        }
        
        updateVisuals()
        
        // Visual feedback
        let pulseAction = SKAction.sequence([
            SKAction.scale(to: 1.2, duration: 0.1),
            SKAction.scale(to: 1.0, duration: 0.1)
        ])
        run(pulseAction)
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
        switch stationType {
        case .ice:
            currentState = 0
        case .boba, .foam, .tea, .lid:
            currentState = false
        }
        updateVisuals()
    }
}
