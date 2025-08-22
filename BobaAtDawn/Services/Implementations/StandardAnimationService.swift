//
//  StandardAnimationService.swift
//  BobaAtDawn
//
//  Standard implementation of AnimationService using GameConfig values
//

import SpriteKit

class StandardAnimationService: AnimationService {
    
    // MARK: - Dependencies
    private let configService: ConfigurationService
    
    // MARK: - Initialization
    init(configService: ConfigurationService) {
        self.configService = configService
    }
    
    // MARK: - Basic Animations
    
    func pulse(_ node: SKNode, scale: CGFloat, config: AnimationConfig) -> SKAction {
        let scaleUp = SKAction.scale(to: scale, duration: config.duration / 2)
        let scaleDown = SKAction.scale(to: 1.0, duration: config.duration / 2)
        
        let pulseSequence = SKAction.sequence([
            applyEasing(scaleUp, type: config.easing),
            applyEasing(scaleDown, type: config.easing)
        ])
        
        return createRepeatingAction(pulseSequence, config: config)
    }
    
    func fade(_ node: SKNode, to alpha: CGFloat, config: AnimationConfig) -> SKAction {
        let fadeAction = SKAction.fadeAlpha(to: alpha, duration: config.duration)
        let easedAction = applyEasing(fadeAction, type: config.easing)
        return createRepeatingAction(easedAction, config: config)
    }
    
    func float(_ node: SKNode, distance: CGFloat, config: AnimationConfig) -> SKAction {
        let moveUp = SKAction.moveBy(x: 0, y: distance, duration: config.duration / 2)
        let moveDown = SKAction.moveBy(x: 0, y: -distance, duration: config.duration / 2)
        
        let floatSequence = SKAction.sequence([
            applyEasing(moveUp, type: config.easing),
            applyEasing(moveDown, type: config.easing)
        ])
        
        return createRepeatingAction(floatSequence, config: config)
    }
    
    func scale(_ node: SKNode, to scale: CGFloat, config: AnimationConfig) -> SKAction {
        let scaleAction = SKAction.scale(to: scale, duration: config.duration)
        let easedAction = applyEasing(scaleAction, type: config.easing)
        return createRepeatingAction(easedAction, config: config)
    }
    
    func move(_ node: SKNode, to position: CGPoint, config: AnimationConfig) -> SKAction {
        let moveAction = SKAction.move(to: position, duration: config.duration)
        let easedAction = applyEasing(moveAction, type: config.easing)
        return createRepeatingAction(easedAction, config: config)
    }
    
    func rotate(_ node: SKNode, by angle: CGFloat, config: AnimationConfig) -> SKAction {
        let rotateAction = SKAction.rotate(byAngle: angle, duration: config.duration)
        let easedAction = applyEasing(rotateAction, type: config.easing)
        return createRepeatingAction(easedAction, config: config)
    }
    
    // MARK: - Game-Specific Effects
    
    func stationInteractionPulse(_ node: SKNode) -> SKAction {
        let config = AnimationConfig(
            duration: configService.stationInteractionDuration * 2, // Full pulse cycle
            easing: .easeInOut
        )
        return pulse(node, scale: configService.stationInteractionScaleAmount, config: config)
    }
    
    func longPressFeedback(_ node: SKNode) -> SKAction {
        // Based on patterns from InputService/GameScene
        let config = AnimationConfig(
            duration: configService.touchFeedbackScaleDuration * 2,
            easing: .easeInOut
        )
        return pulse(node, scale: configService.touchFeedbackScaleAmount, config: config)
    }
    
    func carriedItemFloat(_ node: SKNode) -> SKAction {
        let config = AnimationConfig(
            duration: configService.characterFloatDuration * 2, // Full cycle
            easing: .easeInOut,
            repeatCount: -1 // Repeat forever
        )
        return float(node, distance: configService.characterFloatDistance, config: config)
    }
    
    func npcEntrance(_ node: SKNode) -> SKAction {
        // Based on NPC.swift entrance patterns
        let fadeIn = fade(node, to: 1.0, config: AnimationConfig(
            duration: 0.5,
            easing: .easeOut
        ))
        
        let scaleIn = scale(node, to: 1.0, config: AnimationConfig(
            duration: 0.5,
            easing: .easeOut
        ))
        
        // Set initial state
        node.alpha = 0.0
        node.setScale(0.8)
        
        return parallel([fadeIn, scaleIn])
    }
    
    func npcHappyCelebration(_ node: SKNode) -> [SKAction] {
        // Based on NPC.swift happy animation patterns
        let shimmerConfig = AnimationConfig(
            duration: 0.25 * 2, // Full cycle
            easing: .easeInOut,
            repeatCount: -1
        )
        
        let shakeSequence = SKAction.sequence([
            SKAction.moveBy(x: -3, y: 0, duration: 0.1),
            SKAction.moveBy(x: 6, y: 0, duration: 0.1),
            SKAction.moveBy(x: -6, y: 0, duration: 0.1),
            SKAction.moveBy(x: 3, y: 0, duration: 0.1)
        ])
        let shakeRepeating = SKAction.repeatForever(shakeSequence)
        
        let colorFlashSequence = SKAction.sequence([
            SKAction.colorize(with: .yellow, colorBlendFactor: 0.3, duration: 0.2),
            SKAction.colorize(withColorBlendFactor: 0.0, duration: 0.2),
            SKAction.colorize(with: .white, colorBlendFactor: 0.2, duration: 0.2),
            SKAction.colorize(withColorBlendFactor: 0.0, duration: 0.2)
        ])
        let colorFlashRepeating = SKAction.repeatForever(colorFlashSequence)
        
        return [
            pulse(node, scale: 1.15, config: shimmerConfig),
            shakeRepeating,
            colorFlashRepeating
        ]
    }
    
    func npcNeutralLeaving(_ node: SKNode) -> [SKAction] {
        // Based on NPC.swift neutral animation patterns
        let sighConfig = AnimationConfig(
            duration: 1.0 * 2, // Full cycle
            easing: .easeInOut,
            repeatCount: -1
        )
        
        let grayTint = SKAction.colorize(with: .gray, colorBlendFactor: 0.15, duration: 0.5)
        
        return [
            pulse(node, scale: 0.95, config: sighConfig),
            grayTint
        ]
    }
    
    func forestRoomTransition(_ node: SKNode, fadeOut: Bool, completion: @escaping () -> Void) -> SKAction {
        let duration = fadeOut ? configService.forestTransitionFadeOutDuration : configService.forestTransitionFadeInDuration
        let targetAlpha: CGFloat = fadeOut ? 0.0 : 1.0
        
        let fadeAction = fade(node, to: targetAlpha, config: AnimationConfig(
            duration: duration,
            easing: fadeOut ? .easeIn : .easeOut
        ))
        
        return sequence([fadeAction], completion: completion)
    }
    
    func occupiedCellFeedback(_ node: SKNode) -> SKAction {
        // Based on GameScene touch feedback patterns
        let scaleUp = scale(node, to: configService.touchFeedbackScaleAmount, config: AnimationConfig(
            duration: configService.touchFeedbackScaleDuration,
            easing: .easeOut
        ))
        
        let wait = SKAction.wait(forDuration: configService.touchFeedbackWaitDuration)
        
        let fadeOut = fade(node, to: 0.0, config: AnimationConfig(
            duration: configService.touchFeedbackFadeDuration,
            easing: .easeIn
        ))
        
        return sequence([scaleUp, wait, fadeOut], completion: nil)
    }
    
    func objectRotationFeedback(_ node: SKNode) -> SKAction {
        // Based on RotatableObject patterns
        let config = AnimationConfig(
            duration: configService.objectRotationFeedbackDuration * 2,
            easing: .easeInOut
        )
        return pulse(node, scale: configService.objectRotationFeedbackScale, config: config)
    }
    
    // MARK: - Complex Sequences
    
    func sequence(_ actions: [SKAction], completion: (() -> Void)?) -> SKAction {
        let sequenceAction = SKAction.sequence(actions)
        
        if let completion = completion {
            let completionAction = SKAction.run(completion)
            return SKAction.sequence([sequenceAction, completionAction])
        } else {
            return sequenceAction
        }
    }
    
    func parallel(_ actions: [SKAction]) -> SKAction {
        return SKAction.group(actions)
    }
    
    func run(_ action: SKAction, on node: SKNode, withKey key: String?, completion: (() -> Void)?) {
        if let completion = completion {
            let completionAction = SKAction.run(completion)
            let sequenceWithCompletion = SKAction.sequence([action, completionAction])
            
            if let key = key {
                node.run(sequenceWithCompletion, withKey: key)
            } else {
                node.run(sequenceWithCompletion)
            }
        } else {
            if let key = key {
                node.run(action, withKey: key)
            } else {
                node.run(action)
            }
        }
    }
    
    // MARK: - Animation Management
    
    func stopAnimation(_ node: SKNode, withKey key: String) {
        node.removeAction(forKey: key)
    }
    
    func stopAllAnimations(_ node: SKNode) {
        node.removeAllActions()
    }
    
    func hasAnimation(_ node: SKNode, withKey key: String) -> Bool {
        return node.action(forKey: key) != nil
    }
    
    // MARK: - Easing Utilities
    
    func applyEasing(_ action: SKAction, type: EasingType) -> SKAction {
        switch type {
        case .linear:
            action.timingMode = .linear
        case .easeIn:
            action.timingMode = .easeIn
        case .easeOut:
            action.timingMode = .easeOut
        case .easeInOut:
            action.timingMode = .easeInEaseOut
        }
        return action
    }
    
    // MARK: - Private Helpers
    
    private func createRepeatingAction(_ action: SKAction, config: AnimationConfig) -> SKAction {
        var finalAction = action
        
        if config.autoreverses && config.repeatCount != 0 {
            finalAction = SKAction.sequence([action, action.reversed()])
        }
        
        if config.repeatCount == -1 {
            return SKAction.repeatForever(finalAction)
        } else if config.repeatCount > 0 {
            return SKAction.repeat(finalAction, count: config.repeatCount)
        } else {
            return finalAction
        }
    }
}

// MARK: - Convenience Extensions for Easy Use
extension StandardAnimationService {
    
    // Quick convenience methods using default configurations
    
    func quickPulse(_ node: SKNode, scale: CGFloat = 1.1) {
        let action = stationInteractionPulse(node)
        run(action, on: node, withKey: AnimationKeys.pulse, completion: nil)
    }
    
    func quickFade(_ node: SKNode, to alpha: CGFloat, duration: TimeInterval = 0.3) {
        let config = AnimationConfig(duration: duration, easing: .easeInOut)
        let action = fade(node, to: alpha, config: config)
        run(action, on: node, withKey: AnimationKeys.fade, completion: nil)
    }
    
    func quickFloat(_ node: SKNode) {
        let action = carriedItemFloat(node)
        run(action, on: node, withKey: AnimationKeys.carriedFloat, completion: nil)
    }
    
    func stopQuickFloat(_ node: SKNode) {
        stopAnimation(node, withKey: AnimationKeys.carriedFloat)
    }
}
