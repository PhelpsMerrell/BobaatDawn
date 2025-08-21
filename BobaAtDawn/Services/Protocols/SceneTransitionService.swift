//
//  SceneTransitionService.swift
//  BobaAtDawn
//
//  Dependency injection protocol for scene transition management
//

import SpriteKit

// MARK: - Scene Types
enum GameSceneType {
    case game
    case forest
    case title
}

// MARK: - Transition Configuration
struct SceneTransitionConfig {
    let fadeOutDuration: TimeInterval
    let fadeInDuration: TimeInterval
    let transitionType: SKTransition?
    let hapticFeedback: Bool
    
    init(fadeOutDuration: TimeInterval = 0.5, 
         fadeInDuration: TimeInterval = 0.5, 
         transitionType: SKTransition? = nil,
         hapticFeedback: Bool = true) {
        self.fadeOutDuration = fadeOutDuration
        self.fadeInDuration = fadeInDuration
        self.transitionType = transitionType
        self.hapticFeedback = hapticFeedback
    }
}

// MARK: - Scene Transition Service Protocol
protocol SceneTransitionService {
    
    // MARK: - Primary Transition Methods
    
    /// Transition from current scene to a new scene type
    /// - Parameters:
    ///   - from: Current scene
    ///   - to: Target scene type
    ///   - config: Transition configuration (optional, uses defaults)
    ///   - completion: Optional completion handler
    func transition(from currentScene: SKScene, 
                   to targetSceneType: GameSceneType, 
                   config: SceneTransitionConfig?, 
                   completion: (() -> Void)?)
    
    /// Transition from GameScene to ForestScene
    /// - Parameters:
    ///   - gameScene: The current GameScene
    ///   - completion: Optional completion handler
    func transitionToForest(from gameScene: SKScene, completion: (() -> Void)?)
    
    /// Transition from ForestScene to GameScene
    /// - Parameters:
    ///   - forestScene: The current ForestScene
    ///   - completion: Optional completion handler
    func transitionToGame(from forestScene: SKScene, completion: (() -> Void)?)
    
    // MARK: - Forest Room Transitions
    
    /// Handle forest room-to-room transitions with black overlay
    /// - Parameters:
    ///   - forestScene: The ForestScene
    ///   - fromRoom: Current room number
    ///   - toRoom: Target room number
    ///   - character: Character to reposition
    ///   - camera: Camera to manage
    ///   - gridService: Grid service for positioning
    ///   - lastTriggeredSide: Which side triggered transition ("left" or "right")
    ///   - roomSetupAction: Action to setup the new room
    ///   - completion: Optional completion handler
    func transitionForestRoom(in forestScene: SKScene,
                             from fromRoom: Int,
                             to toRoom: Int,
                             character: SKNode,
                             camera: SKCameraNode,
                             gridService: GridService,
                             lastTriggeredSide: String,
                             roomSetupAction: @escaping () -> Void,
                             completion: (() -> Void)?)
    
    // MARK: - Configuration Access
    
    /// Get default transition config for scene type transitions
    var defaultSceneTransitionConfig: SceneTransitionConfig { get }
    
    /// Get default transition config for forest room transitions
    var defaultForestRoomTransitionConfig: SceneTransitionConfig { get }
    
    // MARK: - Scene Creation
    
    /// Create a new scene instance of the specified type
    /// - Parameters:
    ///   - type: Scene type to create
    ///   - size: Scene size
    /// - Returns: New scene instance
    func createScene(type: GameSceneType, size: CGSize) -> SKScene
    
    // MARK: - Haptic Feedback
    
    /// Trigger haptic feedback for transitions
    /// - Parameter type: Type of haptic feedback
    func triggerHapticFeedback(type: HapticFeedbackType)
}

// MARK: - Haptic Feedback Types
enum HapticFeedbackType {
    case success       // For successful transitions (door interactions)
    case light         // For room transitions
    case selection     // For movement/footsteps
}
