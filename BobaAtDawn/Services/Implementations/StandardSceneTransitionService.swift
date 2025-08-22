//
//  StandardSceneTransitionService.swift
//  BobaAtDawn
//
//  Standard implementation of SceneTransitionService
//

import SpriteKit
import UIKit

class StandardSceneTransitionService: SceneTransitionService {
    
    // MARK: - Dependencies
    private let configService: ConfigurationService
    
    // MARK: - Initialization
    init(configService: ConfigurationService) {
        self.configService = configService
    }
    
    // MARK: - Configuration Properties
    var defaultSceneTransitionConfig: SceneTransitionConfig {
        return SceneTransitionConfig(
            fadeOutDuration: configService.forestTransitionFadeOutDuration,
            fadeInDuration: configService.forestTransitionFadeInDuration,
            transitionType: SKTransition.fade(withDuration: configService.forestTransitionFadeInDuration),
            hapticFeedback: true
        )
    }
    
    var defaultForestRoomTransitionConfig: SceneTransitionConfig {
        return SceneTransitionConfig(
            fadeOutDuration: 0.3,
            fadeInDuration: 0.3,
            transitionType: nil, // No SKTransition for room transitions
            hapticFeedback: true
        )
    }
    
    // MARK: - Primary Transition Methods
    func transition(from currentScene: SKScene, 
                   to targetSceneType: GameSceneType, 
                   config: SceneTransitionConfig? = nil, 
                   completion: (() -> Void)? = nil) {
        
        let transitionConfig = config ?? defaultSceneTransitionConfig
        
        // Trigger haptic feedback if enabled
        if transitionConfig.hapticFeedback {
            triggerHapticFeedback(type: .success)
        }
        
        print("🎬 Transitioning from \(type(of: currentScene)) to \(targetSceneType)")
        
        // Create fade out action
        let fadeOut = SKAction.fadeOut(withDuration: transitionConfig.fadeOutDuration)
        
        currentScene.run(fadeOut) { [weak self] in
            guard let self = self else { return }
            
            // Create new scene
            let newScene = self.createScene(type: targetSceneType, size: currentScene.size)
            newScene.scaleMode = .aspectFill
            
            // Present with transition
            if let transition = transitionConfig.transitionType {
                currentScene.view?.presentScene(newScene, transition: transition)
            } else {
                let fadeTransition = SKTransition.fade(withDuration: transitionConfig.fadeInDuration)
                currentScene.view?.presentScene(newScene, transition: fadeTransition)
            }
            
            completion?()
        }
    }
    
    func transitionToForest(from gameScene: SKScene, completion: (() -> Void)? = nil) {
        print("🌲 Transitioning to forest scene...")
        transition(from: gameScene, to: .forest, config: nil, completion: completion)
    }
    
    func transitionToGame(from forestScene: SKScene, completion: (() -> Void)? = nil) {
        print("🏠 Returning to boba shop...")
        transition(from: forestScene, to: .game, config: nil, completion: completion)
    }
    
    // MARK: - Forest Room Transitions
    func transitionForestRoom(in forestScene: SKScene,
                             from fromRoom: Int,
                             to toRoom: Int,
                             character: SKNode,
                             camera: SKCameraNode,
                             gridService: GridService,
                             lastTriggeredSide: String,
                             roomSetupAction: @escaping () -> Void,
                             completion: (() -> Void)? = nil) {
        
        let config = defaultForestRoomTransitionConfig
        
        // Trigger haptic feedback
        if config.hapticFeedback {
            triggerHapticFeedback(type: .light)
        }
        
        print("🌲 Transitioning from Room \(fromRoom) to Room \(toRoom)")
        
        // Create full-screen black overlay that follows camera - FIXED size calculation
        // Use much larger size to ensure it covers screen at any scale
        let overlaySize = CGSize(width: 4000, height: 3000)
        // Validate the size to prevent negative values
        guard overlaySize.width > 0 && overlaySize.height > 0 else {
            print("❌ ERROR: Invalid overlay size: \(overlaySize)")
            return
        }
        
        let blackOverlay = SKSpriteNode(color: .black, size: overlaySize)
        blackOverlay.zPosition = 1000 // Above everything
        blackOverlay.alpha = 0
        forestScene.addChild(blackOverlay)
        
        // Position overlay relative to camera
        func updateOverlayPosition() {
            blackOverlay.position = camera.position
        }
        updateOverlayPosition()
        
        // Create transition sequence
        let fadeToBlack = SKAction.fadeAlpha(to: 1.0, duration: config.fadeOutDuration)
        let waitInDarkness = SKAction.wait(forDuration: 0.1)
        
        let repositionEverything = SKAction.run { [weak self] in
            // Store current Y position before room change
            let currentY = character.position.y
            
            // Setup the new room
            roomSetupAction()
            
            // Reposition character based on transition direction
            self?.repositionCharacterForRoomTransition(
                character: character,
                gridService: gridService,
                lastTriggeredSide: lastTriggeredSide,
                preservingY: currentY
            )
            
            // Instantly snap camera to character (hidden by black screen)
            camera.position = character.position
            updateOverlayPosition()
        }
        
        let waitAfterReposition = SKAction.wait(forDuration: 0.1)
        let fadeFromBlack = SKAction.fadeAlpha(to: 0.0, duration: config.fadeInDuration)
        
        let cleanup = SKAction.run {
            blackOverlay.removeFromParent()
        }
        
        let finishTransition = SKAction.run {
            completion?()
        }
        
        // Run the complete sequence
        let transitionSequence = SKAction.sequence([
            fadeToBlack,
            waitInDarkness,
            repositionEverything,
            waitAfterReposition,
            fadeFromBlack,
            cleanup,
            finishTransition
        ])
        
        blackOverlay.run(transitionSequence)
    }
    
    // MARK: - Scene Creation
    func createScene(type: GameSceneType, size: CGSize) -> SKScene {
        switch type {
        case .game:
            return GameScene(size: size)
        case .forest:
            return ForestScene(size: size)
        case .title:
            return TitleScene(size: size)
        }
    }
    
    // MARK: - Haptic Feedback
    func triggerHapticFeedback(type: HapticFeedbackType) {
        switch type {
        case .success:
            let feedback = UINotificationFeedbackGenerator()
            feedback.notificationOccurred(.success)
        case .light:
            let feedback = UIImpactFeedbackGenerator(style: .light)
            feedback.impactOccurred()
        case .selection:
            let feedback = UISelectionFeedbackGenerator()
            feedback.selectionChanged()
        }
    }
    
    // MARK: - Private Helper Methods
    private func repositionCharacterForRoomTransition(character: SKNode,
                                                     gridService: GridService,
                                                     lastTriggeredSide: String,
                                                     preservingY yPosition: CGFloat) {
        
        // Get world dimensions from config
        let worldWidth = configService.worldWidth
        
        // Convert Y position to grid coordinate and clamp to safe bounds
        let gridY = gridService.worldToGrid(CGPoint(x: 0, y: yPosition)).y
        let safeGridY = max(3, min(22, gridY)) // Keep within forest bounds
        
        let targetCell: GridCoordinate
        
        // Spawn at the edge of transition zones - like you just walked in
        if lastTriggeredSide == "left" {
            // Player walked left → spawn at right edge of right transition zone
            // Right transition starts at worldWidth/2 - 133, so spawn just inside it
            let edgeX = worldWidth/2 - 133 + 20 // 20pt inside the transition zone
            let gridX = gridService.worldToGrid(CGPoint(x: edgeX, y: 0)).x
            targetCell = GridCoordinate(x: gridX, y: safeGridY)
            print("👤 Player went LEFT → spawning at RIGHT transition edge (x: \(gridX), y: \(safeGridY))")
        } else {
            // Player walked right → spawn at left edge of left transition zone
            // Left transition ends at -worldWidth/2 + 133, so spawn just inside it
            let edgeX = -worldWidth/2 + 133 - 20 // 20pt inside the transition zone
            let gridX = gridService.worldToGrid(CGPoint(x: edgeX, y: 0)).x
            targetCell = GridCoordinate(x: gridX, y: safeGridY)
            print("👤 Player went RIGHT → spawning at LEFT transition edge (x: \(gridX), y: \(safeGridY))")
        }
        
        // Instantly position character (hidden by black screen)
        character.position = gridService.gridToWorld(targetCell)
        
        print("👤 Character repositioned to \(targetCell) for room transition")
    }
}
