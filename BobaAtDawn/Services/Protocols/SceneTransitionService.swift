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
    case bigOakTree
    case house
    case cave
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
    
    /// Transition into the Big Oak Tree interior scene.
    /// - Parameters:
    ///   - currentScene: The scene to leave (typically ForestScene).
    ///   - completion: Optional completion handler.
    func transitionToBigOakTree(from currentScene: SKScene, completion: (() -> Void)?)
    
    /// Transition into the Cave interior scene from the forest.
    /// - Parameters:
    ///   - currentScene: The scene to leave (typically ForestScene).
    ///   - completion: Optional completion handler.
    func transitionToCave(from currentScene: SKScene, completion: (() -> Void)?)
    
    /// Transition into a forest NPC's house interior.
    /// - Parameters:
    ///   - currentScene: The scene to leave (typically ForestScene).
    ///   - room: Forest room the house belongs to (1-5).
    ///   - house: House slot within the room (1-4).
    ///   - completion: Optional completion handler.
    func transitionToHouse(from currentScene: SKScene,
                           room: Int,
                           house: Int,
                           completion: (() -> Void)?)
    
    /// Transition to the ForestScene, starting in a specific room.
    /// Use this when returning from a structure (e.g. the Big Oak Tree)
    /// back into the forest at a specific room rather than the default Room 1.
    /// - Parameters:
    ///   - currentScene: The scene to leave.
    ///   - targetRoom: The forest room number (1-5) to start in.
    ///   - completion: Optional completion handler.
    func transitionToForestRoom(from currentScene: SKScene,
                                targetRoom: Int,
                                completion: (() -> Void)?)
    
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
    
    /// Generic scene-internal room transition with an explicit spawn position.
    /// Fades to black, runs `roomSetupAction`, teleports the character to
    /// `spawnPosition`, snaps the camera, then fades back in.
    /// Used by interior structures (e.g. Big Oak Tree stair transitions)
    /// where left/right forest-edge repositioning logic doesn't apply.
    /// - Parameters:
    ///   - scene: The scene running the transition.
    ///   - character: Character node to reposition.
    ///   - camera: Camera to snap to the new position.
    ///   - spawnPosition: World-space position to place the character at.
    ///   - roomSetupAction: Action to rebuild the new room's contents.
    ///   - completion: Optional completion handler.
    func transitionInteriorRoom(in scene: SKScene,
                                character: SKNode,
                                camera: SKCameraNode,
                                spawnPosition: CGPoint,
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
