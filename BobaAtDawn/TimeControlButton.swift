//
//  TimeControlButton.swift
//  BobaAtDawn
//
//  Debug button for advancing time phases during development
//

import SpriteKit
import Foundation

// MARK: - Time Control Button
class TimeControlButton: SKNode {
    
    private let buttonBackground: SKSpriteNode
    private let buttonIcon: SKLabelNode
    private let progressIndicator: SKShapeNode
    private weak var timeService: TimeService?
    
    // Visual properties
    private let buttonSize = CGSize(width: 60, height: 60)
    private let baseColor = SKColor(red: 0.2, green: 0.3, blue: 0.4, alpha: 0.8)
    private let pressedColor = SKColor(red: 0.3, green: 0.4, blue: 0.5, alpha: 0.9)
    
    // Long press handling
    private var longPressTimer: Timer?
    private let longPressDuration: TimeInterval = 0.5
    
    // MARK: - Initialization
    init(timeService: TimeService) {
        self.timeService = timeService
        
        // Create button background
        buttonBackground = SKSpriteNode(color: baseColor, size: buttonSize)
        buttonBackground.name = "time_control_button"
        
        // Create button icon (clock emoji)
        buttonIcon = SKLabelNode(text: "⏰")
        buttonIcon.fontSize = 28
        buttonIcon.verticalAlignmentMode = .center
        buttonIcon.horizontalAlignmentMode = .center
        
        // Create progress indicator (circle around button)
        let progressPath = CGPath(ellipseIn: CGRect(
            x: -buttonSize.width/2 - 3,
            y: -buttonSize.height/2 - 3,
            width: buttonSize.width + 6,
            height: buttonSize.height + 6
        ), transform: nil)
        
        progressIndicator = SKShapeNode(path: progressPath)
        progressIndicator.strokeColor = SKColor.cyan
        progressIndicator.lineWidth = 3
        progressIndicator.fillColor = .clear
        progressIndicator.alpha = 0
        
        super.init()
        
        // Add components
        addChild(buttonBackground)
        addChild(buttonIcon)
        addChild(progressIndicator)
        
        // Set properties
        isUserInteractionEnabled = true
        zPosition = 1000 // Always on top
        
        // Start with current time phase color
        updateButtonAppearance()
        
        print("⏰ Time control button created")
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Visual Updates
    private func updateButtonAppearance() {
        guard let timeService = timeService else { return }
        
        // Update icon and color based on current phase
        let phase = timeService.currentPhase
        let progress = timeService.phaseProgress
        
        switch phase {
        case .dawn:
            buttonIcon.text = "🌅"
            buttonBackground.color = SKColor(red: 1.0, green: 0.6, blue: 0.3, alpha: 0.8)
        case .day:
            buttonIcon.text = "☀️"
            buttonBackground.color = SKColor(red: 1.0, green: 1.0, blue: 0.3, alpha: 0.8)
        case .dusk:
            buttonIcon.text = "🌆"
            buttonBackground.color = SKColor(red: 0.8, green: 0.4, blue: 0.2, alpha: 0.8)
        case .night:
            buttonIcon.text = "🌙"
            buttonBackground.color = SKColor(red: 0.2, green: 0.2, blue: 0.4, alpha: 0.8)
        }
        
        // Update progress indicator
        let progressAngle = CGFloat(progress) * 2 * .pi
        updateProgressIndicator(progress: progressAngle)
    }
    
    private func updateProgressIndicator(progress: CGFloat) {
        progressIndicator.removeAllActions()
        
        // Create arc path showing progress through current phase
        let center = CGPoint.zero
        let radius: CGFloat = buttonSize.width/2 + 3
        let startAngle: CGFloat = -.pi/2 // Start at top
        let endAngle = startAngle + progress
        
        let arcPath = CGMutablePath()
        arcPath.addArc(center: center, radius: radius, startAngle: startAngle, endAngle: endAngle, clockwise: false)
        
        progressIndicator.path = arcPath
        progressIndicator.alpha = 0.7
    }
    
    // MARK: - Touch Handling
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        // Visual feedback - press down
        buttonBackground.color = pressedColor
        let scaleDown = SKAction.scale(to: 0.95, duration: 0.1)
        buttonBackground.run(scaleDown)
        
        // Start long press timer
        startLongPress()
        
        // Light haptic feedback
        let impact = UIImpactFeedbackGenerator(style: .light)
        impact.impactOccurred()
    }
    
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        cancelLongPress()
        resetButtonAppearance()
    }
    
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        cancelLongPress()
        resetButtonAppearance()
    }
    
    private func resetButtonAppearance() {
        // Reset visual state
        let scaleUp = SKAction.scale(to: 1.0, duration: 0.1)
        buttonBackground.run(scaleUp)
        updateButtonAppearance() // Reset to phase color
    }
    
    // MARK: - Long Press System
    private func startLongPress() {
        longPressTimer = Timer.scheduledTimer(withTimeInterval: longPressDuration, repeats: false) { [weak self] _ in
            self?.handleLongPress()
        }
    }
    
    private func cancelLongPress() {
        longPressTimer?.invalidate()
        longPressTimer = nil
    }
    
    private func handleLongPress() {
        print("⏰ Time control activated - advancing to next phase!")
        
        // Strong haptic feedback for time advance
        let impact = UIImpactFeedbackGenerator(style: .medium)
        impact.impactOccurred()
        
        // Advance time phase
        advanceTimePhase()
        
        // Visual effect for time advance
        createTimeAdvanceEffect()
        
        longPressTimer = nil
    }
    
    // MARK: - Time Control
    private func advanceTimePhase() {
        guard let timeService = timeService else { return }
        
        // Get current phase and advance to next
        let currentPhase = timeService.currentPhase
        let nextPhase = getNextPhase(currentPhase)
        
        print("⏰ Advancing from \(currentPhase.displayName) to \(nextPhase.displayName)")
        
        // Force set the time service to the next phase
        timeService.setDebugPhase(nextPhase)
        
        // Update button appearance immediately
        updateButtonAppearance()
    }
    
    private func getNextPhase(_ current: TimePhase) -> TimePhase {
        switch current {
        case .dawn:
            return .day
        case .day:
            return .dusk
        case .dusk:
            return .night
        case .night:
            return .dawn
        }
    }
    
    // MARK: - Visual Effects
    private func createTimeAdvanceEffect() {
        // Create ripple effect
        let ripple = SKShapeNode(circleOfRadius: buttonSize.width/2)
        ripple.strokeColor = .cyan
        ripple.lineWidth = 3
        ripple.fillColor = .clear
        ripple.alpha = 0.8
        ripple.zPosition = -1
        addChild(ripple)
        
        // Animate ripple
        let expand = SKAction.scale(to: 3.0, duration: 0.6)
        let fade = SKAction.fadeOut(withDuration: 0.6)
        let remove = SKAction.removeFromParent()
        
        let rippleSequence = SKAction.sequence([
            SKAction.group([expand, fade]),
            remove
        ])
        
        ripple.run(rippleSequence)
        
        // Flash button
        let flash = SKAction.sequence([
            SKAction.fadeAlpha(to: 0.3, duration: 0.1),
            SKAction.fadeAlpha(to: 1.0, duration: 0.1),
            SKAction.fadeAlpha(to: 0.3, duration: 0.1),
            SKAction.fadeAlpha(to: 1.0, duration: 0.1)
        ])
        
        buttonIcon.run(flash)
    }
    
    // MARK: - Update
    func update() {
        // Update appearance if time has changed
        updateButtonAppearance()
    }
    
    // MARK: - Debug Info
    func printStatus() {
        guard let timeService = timeService else { return }
        print("⏰ === TIME CONTROL STATUS ===")
        print("⏰ Current Phase: \(timeService.currentPhase.displayName)")
        print("⏰ Progress: \(Int(timeService.phaseProgress * 100))%")
        print("⏰ Button Icon: \(buttonIcon.text ?? "none")")
        print("⏰ =============================")
    }
}
