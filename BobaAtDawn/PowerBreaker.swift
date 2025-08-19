//
//  PowerBreaker.swift
//  BobaAtDawn
//
//  Created by Phelps Merrell on 8/18/25.
//

import SpriteKit

class PowerBreaker: SKSpriteNode {
    
    // MARK: - Properties
    private(set) var isPowered: Bool = true {
        didSet {
            updateVisuals()
            onPowerChange?(isPowered)
        }
    }
    
    private var onPowerChange: ((Bool) -> Void)?
    private var switchHandle: SKSpriteNode!
    private var basePanel: SKSpriteNode!
    private var powerLight: SKSpriteNode!
    private var modeLabel: SKLabelNode!
    
    // MARK: - Initialization
    init(onPowerChange: @escaping (Bool) -> Void) {
        self.onPowerChange = onPowerChange
        
        super.init(texture: nil, color: .clear, size: CGSize(width: 80, height: 120))
        
        name = "power_breaker"
        setupVisuals()
        updateVisuals()
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupVisuals() {
        // Base panel
        basePanel = SKSpriteNode(color: SKColor(red: 0.3, green: 0.3, blue: 0.3, alpha: 1.0), 
                                size: CGSize(width: 60, height: 100))
        basePanel.position = CGPoint(x: 0, y: 0)
        basePanel.zPosition = 0
        addChild(basePanel)
        
        // Switch handle
        switchHandle = SKSpriteNode(color: .white, size: CGSize(width: 40, height: 20))
        switchHandle.position = CGPoint(x: 0, y: 0)
        switchHandle.zPosition = 1
        addChild(switchHandle)
        
        // Power indicator light
        powerLight = SKSpriteNode(color: .green, size: CGSize(width: 15, height: 15))
        powerLight.position = CGPoint(x: 0, y: 30)
        powerLight.zPosition = 1
        addChild(powerLight)
        
        // Power label
        let powerLabel = SKLabelNode(text: "POWER")
        powerLabel.fontSize = 10
        powerLabel.fontColor = .white
        powerLabel.position = CGPoint(x: 0, y: -45)
        powerLabel.zPosition = 1
        addChild(powerLabel)
        
        // Mode indicator label
        modeLabel = SKLabelNode(text: "BROWSE")
        modeLabel.fontSize = 8
        modeLabel.fontColor = .green
        modeLabel.position = CGPoint(x: 0, y: -58)
        modeLabel.zPosition = 1
        addChild(modeLabel)
    }
    
    private func updateVisuals() {
        // Switch position
        let switchY: CGFloat = isPowered ? 10 : -10
        let moveAction = SKAction.moveTo(y: switchY, duration: 0.2)
        switchHandle.run(moveAction)
        
        // Light color and brightness
        if isPowered {
            powerLight.color = .green
            powerLight.alpha = 1.0
            powerLight.removeAction(forKey: "blink")
            
            // Bright steady light for BROWSE mode
            let glowAction = SKAction.repeatForever(
                SKAction.sequence([
                    SKAction.fadeAlpha(to: 0.8, duration: 0.5),
                    SKAction.fadeAlpha(to: 1.0, duration: 0.5)
                ])
            )
            powerLight.run(glowAction, withKey: "glow")
        } else {
            powerLight.color = .red
            powerLight.alpha = 0.7
            powerLight.removeAction(forKey: "glow")
            
            // Blinking red light for ARRANGE mode
            let blinkAction = SKAction.repeatForever(
                SKAction.sequence([
                    SKAction.fadeAlpha(to: 0.2, duration: 0.3),
                    SKAction.fadeAlpha(to: 0.7, duration: 0.3)
                ])
            )
            powerLight.run(blinkAction, withKey: "blink")
        }
        
        // Base panel appearance
        basePanel.color = isPowered ? 
            SKColor(red: 0.3, green: 0.3, blue: 0.3, alpha: 1.0) : // Normal gray
            SKColor(red: 0.2, green: 0.2, blue: 0.25, alpha: 1.0)   // Darker for arrange mode
        
        // Update mode label
        if isPowered {
            modeLabel.text = "BROWSE"
            modeLabel.fontColor = .green
        } else {
            modeLabel.text = "ARRANGE"
            modeLabel.fontColor = .red
        }
    }
    
    // MARK: - Interaction
    func toggle() {
        isPowered.toggle()
        
        // Haptic-like visual feedback
        let feedbackAction = SKAction.sequence([
            SKAction.scale(to: 1.1, duration: 0.1),
            SKAction.scale(to: 1.0, duration: 0.1)
        ])
        run(feedbackAction)
    }
}
