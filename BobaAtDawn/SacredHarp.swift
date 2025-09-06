//
//  SacredHarp.swift
//  BobaAtDawn
//
//  Sacred harp for the dawn soul liberation ritual
//

import SpriteKit

class SacredHarp: SKLabelNode {
    
    private(set) var isActive: Bool = false
    private var longPressTimer: Timer?
    private let longPressDuration: TimeInterval = 1.0
    
    // Visual properties
    private let harpEmoji = "🎵"
    
    // Callbacks
    var onPlayed: (() -> Void)?
    
   override init() {
        super.init()
        
        setupHarp()
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupHarp() {
        text = harpEmoji
        fontSize = 50
        fontName = "Arial"
        horizontalAlignmentMode = .center
        verticalAlignmentMode = .center
        zPosition = ZLayers.ritualItems
        name = "sacred_harp"
        
        // Start inactive (dimmed)
        alpha = 0.3
        isActive = false
        
        // Enable interaction
        isUserInteractionEnabled = true
        
        print("🎵 Sacred harp created (inactive)")
    }
    
    // MARK: - Activation
    func activate() {
        guard !isActive else { return }
        
        isActive = true
        
        // Activation animation - golden glow
        let activation = SKAction.sequence([
            SKAction.group([
                SKAction.fadeAlpha(to: 1.0, duration: 0.5),
                SKAction.scale(to: 1.2, duration: 0.5)
            ]),
            SKAction.scale(to: 1.0, duration: 0.3)
        ])
        
        // Add mystical pulsing
        let mysticalPulse = SKAction.repeatForever(
            SKAction.sequence([
                SKAction.scale(to: 1.1, duration: 1.5),
                SKAction.scale(to: 1.0, duration: 1.5)
            ])
        )
        
        run(activation) {
            self.run(mysticalPulse, withKey: "harp_pulse")
        }
        
        print("🎵 ✨ Sacred harp activated! Ready for the liberation song")
    }
    
    // MARK: - Touch Handling
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard isActive else { 
            // Inactive harp - gentle rejection
            let shake = SKAction.sequence([
                SKAction.moveBy(x: -3, y: 0, duration: 0.1),
                SKAction.moveBy(x: 6, y: 0, duration: 0.1),
                SKAction.moveBy(x: -3, y: 0, duration: 0.1)
            ])
            run(shake)
            print("🎵 Sacred harp is not yet ready... light all candles first")
            return 
        }
        
        // Start long press timer
        startLongPress()
        
        // Visual feedback - divine glow
        let divineGlow = SKAction.sequence([
            SKAction.scale(to: 1.2, duration: 0.2),
            SKAction.scale(to: 1.0, duration: 0.2)
        ])
        run(divineGlow)
        
        print("🎵 Playing the sacred liberation song...")
    }
    
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        cancelLongPress()
    }
    
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        cancelLongPress()
    }
    
    // MARK: - Long Press System
    private func startLongPress() {
        cancelLongPress() // Cancel any existing timer
        
        longPressTimer = Timer.scheduledTimer(withTimeInterval: longPressDuration, repeats: false) { [weak self] _ in
            self?.playHarp()
        }
    }
    
    private func cancelLongPress() {
        longPressTimer?.invalidate()
        longPressTimer = nil
    }
    
    // MARK: - Harp Playing
    private func playHarp() {
        guard isActive else { return }
        
        // Magnificent liberation song effect
        let songEffect = SKAction.sequence([
            SKAction.group([
                SKAction.scale(to: 1.5, duration: 0.3),
                SKAction.fadeAlpha(to: 0.8, duration: 0.3)
            ]),
            SKAction.group([
                SKAction.scale(to: 1.0, duration: 0.5),
                SKAction.fadeAlpha(to: 1.0, duration: 0.5)
            ])
        ])
        
        // Create ripple effect
        createSoundRipples()
        
        run(songEffect)
        
        // Notify that the harp was played
        onPlayed?()
        
        print("🎵 ✨ LIBERATION SONG PLAYED! The sacred melody calls to a worthy soul...")
    }
    
    private func createSoundRipples() {
        // Create multiple ripple effects
        for i in 0..<3 {
            let delay = Double(i) * 0.2
            
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                let ripple = SKShapeNode(circleOfRadius: 20)
                ripple.strokeColor = SKColor.gold
                ripple.lineWidth = 2
                ripple.fillColor = .clear
                ripple.alpha = 0.7
                ripple.position = self.position
                ripple.zPosition = self.zPosition - 1
                
                // Add ripple to parent
                if let parent = self.parent {
                    parent.addChild(ripple)
                    
                    // Animate ripple
                    let expand = SKAction.scale(to: 5.0, duration: 2.0)
                    let fade = SKAction.fadeOut(withDuration: 2.0)
                    let remove = SKAction.removeFromParent()
                    
                    let rippleSequence = SKAction.sequence([
                        SKAction.group([expand, fade]),
                        remove
                    ])
                    
                    ripple.run(rippleSequence)
                }
            }
        }
    }
    
    // MARK: - Ritual Cleanup
    func deactivate() {
        isActive = false
        removeAction(forKey: "harp_pulse")
        alpha = 0.3
        setScale(1.0)
        
        print("🎵 Sacred harp returns to slumber")
    }
    
    func fadeAway() {
        let fadeOut = SKAction.sequence([
            SKAction.group([
                SKAction.fadeOut(withDuration: 1.5),
                SKAction.scale(to: 0.3, duration: 1.5)
            ]),
            SKAction.removeFromParent()
        ])
        
        run(fadeOut)
        print("🎵 Sacred harp fades as the dawn ends...")
    }
}

// MARK: - Color Extension
extension SKColor {
    static let gold = SKColor(red: 1.0, green: 0.8, blue: 0.0, alpha: 1.0)
}
