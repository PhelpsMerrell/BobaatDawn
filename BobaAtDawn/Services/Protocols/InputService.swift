//
//  InputService.swift
//  BobaAtDawn
//
//  Dependency injection protocol for input handling consolidation
//

import SpriteKit
import UIKit

// MARK: - Input Context Types
enum InputContext {
    case gameScene
    case forestScene
}

// MARK: - Touch Result Types
enum TouchResult {
    case handled
    case notHandled
    case longPress(node: SKNode, location: CGPoint)
    case movement(targetCell: GridCoordinate)
    case occupiedCell(cell: GridCoordinate)
}

// MARK: - Gesture Configuration
struct GestureConfig {
    let enablePinch: Bool
    let enableRotation: Bool
    let enableTwoFingerTap: Bool
    let enableLongPress: Bool
    
    static let gameDefault = GestureConfig(
        enablePinch: true,
        enableRotation: true, 
        enableTwoFingerTap: true,
        enableLongPress: true
    )
    
    static let forestDefault = GestureConfig(
        enablePinch: true,
        enableRotation: false,
        enableTwoFingerTap: true,
        enableLongPress: true
    )
}

// MARK: - Camera State
struct CameraState {
    var scale: CGFloat
    var lastPinchScale: CGFloat
    let minZoom: CGFloat
    let maxZoom: CGFloat
    
    init(defaultScale: CGFloat, minZoom: CGFloat, maxZoom: CGFloat) {
        self.scale = defaultScale
        self.lastPinchScale = defaultScale
        self.minZoom = minZoom
        self.maxZoom = maxZoom
    }
}

// MARK: - Input Service Protocol
protocol InputService {
    
    // MARK: - Gesture Setup
    
    /// Setup gesture recognizers for a scene view
    /// - Parameters:
    ///   - view: The SKView to add gestures to
    ///   - context: Input context (game vs forest)
    ///   - config: Gesture configuration
    ///   - target: Target object for gesture callbacks
    func setupGestures(for view: SKView, 
                      context: InputContext,
                      config: GestureConfig?,
                      target: AnyObject)
    
    // MARK: - Touch Handling
    
    /// Process touch began event
    /// - Parameters:
    ///   - touches: Set of touches
    ///   - event: Touch event
    ///   - scene: Current scene
    ///   - gridService: Grid service for coordinate conversion
    ///   - context: Input context
    /// - Returns: Touch result indicating what action should be taken
    func handleTouchBegan(_ touches: Set<UITouch>,
                         with event: UIEvent?,
                         in scene: SKScene,
                         gridService: GridService,
                         context: InputContext) -> TouchResult
    
    /// Process touch ended event
    func handleTouchEnded(_ touches: Set<UITouch>, with event: UIEvent?)
    
    /// Process touch cancelled event  
    func handleTouchCancelled(_ touches: Set<UITouch>, with event: UIEvent?)
    
    // MARK: - Long Press System
    
    /// Start long press timer for a node
    /// - Parameters:
    ///   - node: Target node
    ///   - location: Touch location
    ///   - completion: Completion handler when long press triggers
    func startLongPress(for node: SKNode, 
                       at location: CGPoint,
                       completion: @escaping (SKNode, CGPoint) -> Void)
    
    /// Cancel current long press
    func cancelLongPress()
    
    /// Check if currently handling long press
    var isHandlingLongPress: Bool { get }
    
    // MARK: - Gesture Handlers
    
    /// Handle pinch gesture for camera zoom
    /// - Parameters:
    ///   - gesture: Pinch gesture recognizer
    ///   - cameraState: Current camera state (will be modified)
    ///   - camera: Camera node to update
    func handlePinch(_ gesture: UIPinchGestureRecognizer,
                    cameraState: inout CameraState,
                    camera: SKCameraNode) -> Bool // Returns if handling
    
    /// Handle rotation gesture
    /// - Parameters:
    ///   - gesture: Rotation gesture recognizer
    ///   - character: Character with potential carried items
    func handleRotation(_ gesture: UIRotationGestureRecognizer, 
                       character: Character?)
    
    /// Handle two finger tap for camera reset
    /// - Parameters:
    ///   - gesture: Two finger tap gesture
    ///   - cameraState: Current camera state (will be modified)
    ///   - camera: Camera node to reset
    func handleTwoFingerTap(_ gesture: UITapGestureRecognizer,
                           cameraState: inout CameraState,
                           camera: SKCameraNode)
    
    // MARK: - Node Finding
    
    /// Find interactable node in hierarchy for game scene
    /// - Parameters:
    ///   - node: Starting node
    ///   - context: Input context for different interaction rules
    ///   - gameSpecificNodes: Optional scene-specific nodes to check
    /// - Returns: Interactable node or nil
    func findInteractableNode(_ node: SKNode,
                             context: InputContext,
                             gameSpecificNodes: [String: SKNode]?) -> SKNode?
    
    // MARK: - Visual Feedback
    
    /// Show feedback for occupied grid cell
    /// - Parameters:
    ///   - cell: Grid coordinate
    ///   - scene: Scene to add feedback to
    ///   - gridService: Grid service for coordinate conversion
    func showOccupiedCellFeedback(at cell: GridCoordinate,
                                 in scene: SKScene,
                                 gridService: GridService)
    
    // MARK: - Configuration Access
    
    /// Get long press duration from configuration
    var longPressDuration: TimeInterval { get }
    
    /// Get interaction search depth
    var interactionSearchDepth: Int { get }
}
