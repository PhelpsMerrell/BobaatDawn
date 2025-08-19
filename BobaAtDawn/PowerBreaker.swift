//
//  PowerBreaker.swift
//  BobaAtDawn
//
//  Created by Phelps Merrell on 8/18/25.
//

import SpriteKit

class PowerBreaker: SKSpriteNode {
    
    // MARK: - Properties
    private(set) var isTimeActive: Bool = false {
        didSet {
            updateVisuals()
            handleTimeToggle()
        }
    }
    
    private var switchHandle: SKSpriteNode!
    private var basePanel: SKSpriteNode!
    private var statusLight: SKSpriteNode!
    private var timeLabel: SKLabelNode!
    
    // MARK: - Initialization
    init() {
        super.init(texture: nil, color: .clear, size: CGSize(width: 80, height: 120))
        
        name = "time_breaker"
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
        
        // Status indicator light
        statusLight = SKSpriteNode(color: .orange, size: CGSize(width: 15, height: 15))
        statusLight.position = CGPoint(x: 0, y: 30)
        statusLight.zPosition = 1
        addChild(statusLight)
        
        // Time label
        let mainLabel = SKLabelNode(text: "TIME")
        mainLabel.fontSize = 10
        mainLabel.fontColor = .white
        mainLabel.position = CGPoint(x: 0, y: -45)
        mainLabel.zPosition = 1
        addChild(mainLabel)
        
        // Status indicator label
        timeLabel = SKLabelNode(text: "PAUSED")
        timeLabel.fontSize = 8
        timeLabel.fontColor = .orange
        timeLabel.position = CGPoint(x: 0, y: -58)
        timeLabel.zPosition = 1
        addChild(timeLabel)
    }
    
    private func updateVisuals() {
        // Switch position
        let switchY: CGFloat = isTimeActive ? 10 : -10
        let moveAction = SKAction.moveTo(y: switchY, duration: 0.2)
        switchHandle.run(moveAction)
        
        // Light color and animation
        if isTimeActive {
            statusLight.color = .green
            statusLight.alpha = 1.0
            statusLight.removeAction(forKey: "pause_pulse")
            
            // Flowing green light for active time
            let flowAction = SKAction.repeatForever(
                SKAction.sequence([
                    SKAction.fadeAlpha(to: 0.7, duration: 1.0),
                    SKAction.fadeAlpha(to: 1.0, duration: 1.0)
                ])
            )
            statusLight.run(flowAction, withKey: "time_flow")
            
            timeLabel.text = "ACTIVE"
            timeLabel.fontColor = .green
        } else {
            statusLight.color = .orange
            statusLight.alpha = 0.8
            statusLight.removeAction(forKey: "time_flow")
            
            // Gentle pulse for paused state
            let pulseAction = SKAction.repeatForever(
                SKAction.sequence([
                    SKAction.fadeAlpha(to: 0.4, duration: 2.0),
                    SKAction.fadeAlpha(to: 0.8, duration: 2.0)
                ])
            )
            statusLight.run(pulseAction, withKey: "pause_pulse")
            
            timeLabel.text = "PAUSED"
            timeLabel.fontColor = .orange
        }
        
        // Base panel appearance
        basePanel.color = isTimeActive ? 
            SKColor(red: 0.2, green: 0.4, blue: 0.2, alpha: 1.0) : // Greenish tint when active
            SKColor(red: 0.3, green: 0.3, blue: 0.3, alpha: 1.0)   // Neutral gray when paused
    }
    
    private func handleTimeToggle() {
        if isTimeActive {
            TimeManager.shared.startTime()
            print("⏰ Time cycle activated via power breaker")
        } else {
            TimeManager.shared.stopTime()
            print("⏰ Time cycle paused via power breaker")
        }
    }
    
    // MARK: - Interaction
    func toggle() {
        isTimeActive.toggle()
        
        // Haptic-like visual feedback
        let feedbackAction = SKAction.sequence([
            SKAction.scale(to: 1.1, duration: 0.1),
            SKAction.scale(to: 1.0, duration: 0.1)
        ])
        run(feedbackAction)
        
        // Extra visual feedback for time activation
        if isTimeActive {
            let activationGlow = SKAction.sequence([
                SKAction.colorize(with: .green, colorBlendFactor: 0.3, duration: 0.3),
                SKAction.colorize(withColorBlendFactor: 0.0, duration: 0.3)
            ])
            basePanel.run(activationGlow)
        }
    }
    
    // MARK: - Public Interface
    func getTimeStatus() -> String {
        return isTimeActive ? "Time Active" : "Time Paused"
    }
}
