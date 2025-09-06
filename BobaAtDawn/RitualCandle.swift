//
//  RitualCandle.swift
//  BobaAtDawn
//
//  Interactive candle for the dawn soul liberation ritual
//

import SpriteKit

class RitualCandle: SKLabelNode {
    
    private(set) var isLit: Bool = false
    private var longPressTimer: Timer?
    private let longPressDuration: TimeInterval = 0.8
    
    // Visual properties
    private let unlitEmoji = "🕯️"
    private let litEmoji = "🔥"
    
    // Callbacks
    var onLit: (() -> Void)?
    
   override init() {
        super.init()
        
        setupCandle()
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupCandle() {
        text = unlitEmoji
        fontSize = 40
        fontName = "Arial"
        horizontalAlignmentMode = .center
        verticalAlignmentMode = .center
        zPosition = ZLayers.ritualItems
        name = "ritual_candle"
        
        // Enable interaction
        isUserInteractionEnabled = true
        
        print("🕯️ Ritual candle created (unlit)")
    }
    
    // MARK: - Touch Handling
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard !isLit else { return } // Can't light already lit candles
        
        // Start long press timer
        startLongPress()
        
        // Visual feedback - slight glow
        let glow = SKAction.sequence([
            SKAction.scale(to: 1.1, duration: 0.1),
            SKAction.scale(to: 1.0, duration: 0.1)
        ])
        run(glow)
        
        print("🕯️ Starting to light candle...")
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
            self?.lightCandle()
        }
    }
    
    private func cancelLongPress() {
        longPressTimer?.invalidate()
        longPressTimer = nil
    }
    
    // MARK: - Candle Lighting
    private func lightCandle() {
        guard !isLit else { return }
        
        isLit = true
        text = litEmoji
        
        // Lighting animation
        let lightingEffect = SKAction.sequence([
            SKAction.scale(to: 1.3, duration: 0.2),
            SKAction.scale(to: 1.0, duration: 0.3)
        ])
        
        // Add warm glow effect
        let warmGlow = SKAction.repeatForever(
            SKAction.sequence([
                SKAction.scale(to: 1.05, duration: 1.0),
                SKAction.scale(to: 1.0, duration: 1.0)
            ])
        )
        
        run(lightingEffect) {
            self.run(warmGlow, withKey: "candle_glow")
        }
        
        // Notify that this candle was lit
        onLit?()
        
        print("🔥 Candle lit! Sacred flame burns bright")
    }
    
    // MARK: - Ritual Cleanup
    func extinguish() {
        isLit = false
        text = unlitEmoji
        removeAction(forKey: "candle_glow")
        setScale(1.0)
        
        print("🕯️ Candle extinguished")
    }
    
    func fadeAway() {
        let fadeOut = SKAction.sequence([
            SKAction.group([
                SKAction.fadeOut(withDuration: 1.0),
                SKAction.scale(to: 0.5, duration: 1.0)
            ]),
            SKAction.removeFromParent()
        ])
        
        run(fadeOut)
        print("🕯️ Candle fading into the dawn...")
    }
}
