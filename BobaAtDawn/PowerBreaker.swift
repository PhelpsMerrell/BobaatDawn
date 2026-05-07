//
//  PowerBreaker.swift
//  BobaAtDawn
//
//  Created by Phelps Merrell on 8/18/25.
//

import SpriteKit

@objc(PowerBreaker)
class PowerBreaker: SKSpriteNode {

    private enum CodingKeys {
        static let isBreakerTripped = "editorPowerBreakerTripped"
    }
    
    // MARK: - Properties
    private(set) var isBreakerTripped: Bool = false {
        didSet {
            updateVisuals()
        }
    }
    
    private var switchHandle: SKSpriteNode!
    private var basePanel: SKSpriteNode!
    private var statusLight: SKSpriteNode!
    private var timeLabel: SKLabelNode!
    
    // MARK: - Initialization
    init() {
        super.init(texture: nil, color: .clear, size: CGSize(width: 80, height: 120))
        
        name = "power_breaker"
        setupVisuals()
        setupTimeCallbacks()
        updateVisuals()
    }
    
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        basePanel = childNode(withName: "breaker_panel") as? SKSpriteNode
        switchHandle = childNode(withName: "breaker_switch_handle") as? SKSpriteNode
        statusLight = childNode(withName: "breaker_status_light") as? SKSpriteNode
        timeLabel = childNode(withName: "breaker_status_label") as? SKLabelNode
        if basePanel == nil || switchHandle == nil || statusLight == nil || timeLabel == nil {
            removeAllChildren()
            setupVisuals()
        }
        setupTimeCallbacks()
        isBreakerTripped = aDecoder.decodeBool(forKey: CodingKeys.isBreakerTripped)
    }

    override func encode(with coder: NSCoder) {
        super.encode(with: coder)
        coder.encode(isBreakerTripped, forKey: CodingKeys.isBreakerTripped)
    }
    
    private func setupVisuals() {
        // Base panel
        basePanel = SKSpriteNode(color: SKColor(red: 0.2, green: 0.4, blue: 0.2, alpha: 1.0), 
                                size: CGSize(width: 60, height: 100))
        basePanel.position = CGPoint(x: 0, y: 0)
        basePanel.zPosition = 0
        basePanel.name = "breaker_panel"
        addChild(basePanel)
        
        // Switch handle
        switchHandle = SKSpriteNode(color: .white, size: CGSize(width: 40, height: 20))
        switchHandle.position = CGPoint(x: 0, y: 10) // Start in up position
        switchHandle.zPosition = 1
        switchHandle.name = "breaker_switch_handle"
        addChild(switchHandle)
        
        // Status indicator light
        statusLight = SKSpriteNode(color: .green, size: CGSize(width: 15, height: 15))
        statusLight.position = CGPoint(x: 0, y: 30)
        statusLight.zPosition = 1
        statusLight.name = "breaker_status_light"
        addChild(statusLight)
        
        // Time label
        let mainLabel = SKLabelNode(text: "TIME")
        mainLabel.fontSize = 10
        mainLabel.fontColor = .white
        mainLabel.position = CGPoint(x: 0, y: -45)
        mainLabel.zPosition = 1
        mainLabel.name = "breaker_main_label"
        addChild(mainLabel)
        
        // Status indicator label
        timeLabel = SKLabelNode(text: "FLOWING")
        timeLabel.fontSize = 8
        timeLabel.fontColor = .green
        timeLabel.position = CGPoint(x: 0, y: -58)
        timeLabel.zPosition = 1
        timeLabel.name = "breaker_status_label"
        addChild(timeLabel)
    }
    
    private func setupTimeCallbacks() {
        // Listen for breaker trips
        TimeManager.shared.onBreakerTripped = { [weak self] in
            self?.tripBreaker()
        }
    }
    
    private func updateVisuals() {
        let timeManager = TimeManager.shared
        
        if isBreakerTripped {
            // Breaker is tripped - needs player reset
            statusLight.color = .red
            statusLight.removeAllActions()
            
            // Flashing red light
            let flashAction = SKAction.repeatForever(
                SKAction.sequence([
                    SKAction.fadeAlpha(to: 0.3, duration: 0.3),
                    SKAction.fadeAlpha(to: 1.0, duration: 0.3)
                ])
            )
            statusLight.run(flashAction, withKey: "flash")
            
            timeLabel.text = "TRIPPED"
            timeLabel.fontColor = .red
            
            // Switch in down position
            let switchY: CGFloat = -10
            let moveAction = SKAction.moveTo(y: switchY, duration: 0.2)
            switchHandle.run(moveAction)
            
        } else if timeManager.isTimeActive {
            // Time is flowing normally
            statusLight.color = .green
            statusLight.removeAllActions()
            
            // Steady green light
            let glowAction = SKAction.repeatForever(
                SKAction.sequence([
                    SKAction.fadeAlpha(to: 0.8, duration: 1.0),
                    SKAction.fadeAlpha(to: 1.0, duration: 1.0)
                ])
            )
            statusLight.run(glowAction, withKey: "glow")
            
            timeLabel.text = "FLOWING"
            timeLabel.fontColor = .green
            
            // Switch in up position
            let switchY: CGFloat = 10
            let moveAction = SKAction.moveTo(y: switchY, duration: 0.2)
            switchHandle.run(moveAction)
        }
        
        // Base panel color
        basePanel.color = isBreakerTripped ? 
            SKColor(red: 0.4, green: 0.2, blue: 0.2, alpha: 1.0) : // Reddish when tripped
            SKColor(red: 0.2, green: 0.4, blue: 0.2, alpha: 1.0)   // Greenish when flowing
    }
    
    // MARK: - Time Callbacks
    private func tripBreaker() {
        isBreakerTripped = true
        print("🔴 Power breaker tripped! Dawn cycle complete")
    }
    
    private func resetBreaker() {
        isBreakerTripped = false
        let currentTime = CFAbsoluteTimeGetCurrent()
        TimeManager.shared.advancePhase(at: currentTime)
        print("⚡ Power breaker reset! Advancing to next day")
    }
    
    // MARK: - Interaction
    func toggle() {
        guard isBreakerTripped else { return } // Only works when tripped
        
        resetBreaker()
        
        // Haptic-like visual feedback
        let feedbackAction = SKAction.sequence([
            SKAction.scale(to: 1.1, duration: 0.1),
            SKAction.scale(to: 1.0, duration: 0.1)
        ])
        run(feedbackAction)
        
        // Reset glow effect
        let resetGlow = SKAction.sequence([
            SKAction.colorize(with: .green, colorBlendFactor: 0.4, duration: 0.3),
            SKAction.colorize(withColorBlendFactor: 0.0, duration: 0.3)
        ])
        basePanel.run(resetGlow)
    }
    
    // MARK: - Public Interface
    func getBreakerStatus() -> String {
        if isBreakerTripped {
            return "Tripped - Ready to Advance"
        } else if TimeManager.shared.isTimeActive {
            return "Time Flowing"
        } else {
            return "Time Stopped"
        }
    }
}
