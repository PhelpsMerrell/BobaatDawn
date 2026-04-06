//
//  Trash.swift
//  BobaAtDawn
//
//  Trash left behind by NPCs after drinking boba.
//  Player picks it up to keep the shop (and forest) tidy.
//

import SpriteKit

class Trash: SKLabelNode {
    
    /// Whether this trash is in the shop or the forest
    enum Location {
        case shop
        case forest(room: Int)
    }
    
    let trashID: String
    let location: Location
    
    init(at worldPosition: CGPoint, location: Location = .shop) {
        self.trashID = UUID().uuidString
        self.location = location
        
        super.init()
        
        // Visual — crumpled cup
        text = "🥤"
        fontSize = 22
        fontName = "Arial"
        horizontalAlignmentMode = .center
        verticalAlignmentMode = .center
        position = worldPosition
        zPosition = ZLayers.groundObjects + 1 // Slightly above ground
        name = "trash"
        alpha = 0.85
        
        // Slight random rotation so it looks tossed
        zRotation = CGFloat.random(in: -0.4...0.4)
        
        // Subtle spawn animation
        setScale(0.0)
        let appear = SKAction.sequence([
            SKAction.wait(forDuration: Double.random(in: 0.0...0.3)),
            SKAction.group([
                SKAction.scale(to: 1.0, duration: 0.3),
                SKAction.fadeIn(withDuration: 0.3)
            ])
        ])
        appear.timingMode = .easeOut
        run(appear)
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    /// Pickup animation — shrinks and disappears
    func pickUp(completion: @escaping () -> Void) {
        let pickup = SKAction.sequence([
            SKAction.group([
                SKAction.scale(to: 0.0, duration: 0.2),
                SKAction.fadeOut(withDuration: 0.2)
            ]),
            SKAction.removeFromParent(),
            SKAction.run { completion() }
        ])
        run(pickup)
    }
}
