//
//  AnimationService.swift
//  BobaAtDawn
//
//  Centralized animation service for consistent visual effects
//

import SpriteKit

// MARK: - Animation Types
enum AnimationType {
    case pulse
    case fade
    case float
    case shimmer
    case shake
    case colorFlash
    case entrance
    case scale
    case move
}

enum EasingType {
    case linear
    case easeIn
    case easeOut
    case easeInOut
}

// MARK: - Animation Configuration
struct AnimationConfig {
    let duration: TimeInterval
    let easing: EasingType
    let repeatCount: Int // 0 = no repeat, -1 = forever
    let autoreverses: Bool
    
    init(duration: TimeInterval, 
         easing: EasingType = .easeInOut, 
         repeatCount: Int = 0, 
         autoreverses: Bool = false) {
        self.duration = duration
        self.easing = easing
        self.repeatCount = repeatCount
        self.autoreverses = autoreverses
    }
}

// MARK: - Animation Service Protocol
protocol AnimationService {
    
    // MARK: - Basic Animations
    
    /// Creates a pulse effect (scale up and down)
    func pulse(_ node: SKNode, 
               scale: CGFloat, 
               config: AnimationConfig) -> SKAction
    
    /// Creates a fade in/out effect
    func fade(_ node: SKNode, 
              to alpha: CGFloat, 
              config: AnimationConfig) -> SKAction
    
    /// Creates a floating animation (up and down movement)
    func float(_ node: SKNode, 
               distance: CGFloat, 
               config: AnimationConfig) -> SKAction
    
    /// Creates a scale animation
    func scale(_ node: SKNode, 
               to scale: CGFloat, 
               config: AnimationConfig) -> SKAction
    
    /// Creates a move animation
    func move(_ node: SKNode, 
              to position: CGPoint, 
              config: AnimationConfig) -> SKAction
    
    /// Creates a rotation animation
    func rotate(_ node: SKNode, 
                by angle: CGFloat, 
                config: AnimationConfig) -> SKAction
    
    // MARK: - Game-Specific Effects
    
    /// Station interaction pulse (from GameConfig)
    func stationInteractionPulse(_ node: SKNode) -> SKAction
    
    /// Long press feedback pulse (from InputService patterns)
    func longPressFeedback(_ node: SKNode) -> SKAction
    
    /// Character carried item floating (from Character.swift)
    func carriedItemFloat(_ node: SKNode) -> SKAction
    
    /// NPC entrance animation (from NPC.swift)
    func npcEntrance(_ node: SKNode) -> SKAction
    
    /// NPC happy celebration (shimmer + shake + color flash)
    func npcHappyCelebration(_ node: SKNode) -> [SKAction]
    
    /// NPC neutral disappointment (sigh + gray tint)
    func npcNeutralLeaving(_ node: SKNode) -> [SKAction]
    
    /// Forest room transition effects
    func forestRoomTransition(_ node: SKNode, 
                             fadeOut: Bool, 
                             completion: @escaping () -> Void) -> SKAction
    
    /// Touch feedback for occupied cells
    func occupiedCellFeedback(_ node: SKNode) -> SKAction
    
    /// Object rotation feedback (from RotatableObject)
    func objectRotationFeedback(_ node: SKNode) -> SKAction
    
    // MARK: - Complex Sequences
    
    /// Creates a sequence of animations with callbacks
    func sequence(_ actions: [SKAction], 
                  completion: (() -> Void)?) -> SKAction
    
    /// Creates parallel animations (run simultaneously)
    func parallel(_ actions: [SKAction]) -> SKAction
    
    /// Runs animation and calls completion when done
    func run(_ action: SKAction, 
             on node: SKNode, 
             withKey key: String?, 
             completion: (() -> Void)?)
    
    // MARK: - Animation Management
    
    /// Stops animation by key
    func stopAnimation(_ node: SKNode, withKey key: String)
    
    /// Stops all animations on node
    func stopAllAnimations(_ node: SKNode)
    
    /// Checks if node has animation with key
    func hasAnimation(_ node: SKNode, withKey key: String) -> Bool
    
    // MARK: - Easing Utilities
    
    /// Applies easing to an action
    func applyEasing(_ action: SKAction, type: EasingType) -> SKAction
}

// MARK: - Animation Keys (Constants for consistency)
struct AnimationKeys {
    static let pulse = "animation_pulse"
    static let fade = "animation_fade"
    static let float = "animation_float"
    static let shimmer = "animation_shimmer"
    static let shake = "animation_shake"
    static let colorFlash = "animation_color_flash"
    static let entrance = "animation_entrance"
    static let scale = "animation_scale"
    static let move = "animation_move"
    static let rotation = "animation_rotation"
    static let longPress = "animation_long_press"
    static let stationInteraction = "animation_station_interaction"
    static let carriedFloat = "animation_carried_float"
    static let npcHappy = "animation_npc_happy"
    static let npcNeutral = "animation_npc_neutral"
    static let occupiedCell = "animation_occupied_cell"
    static let forestTransition = "animation_forest_transition"
    static let objectRotation = "animation_object_rotation"
}
