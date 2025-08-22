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
    
    /// Setup gesture recognizers for a scene view - service handles all gestures internally
    /// - Parameters:
    ///   - view: The SKView to add gestures to
    ///   - context: Input context (game vs forest)
    ///   - config: Gesture configuration
    ///   - delegate: Delegate to receive gesture callbacks
    func setupGestures(for view: SKView, 
                      context: InputContext,
                      config: GestureConfig?,
                      delegate: InputServiceDelegate)
    
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

// MARK: - Input Service Delegate Protocol
protocol InputServiceDelegate: AnyObject {
    
    /// Called when pinch gesture occurs
    /// - Parameters:
    ///   - service: The input service
    ///   - gesture: The pinch gesture
    func inputService(_ service: InputService, 
                     didReceivePinch gesture: UIPinchGestureRecognizer)
    
    /// Called when rotation gesture occurs
    /// - Parameters:
    ///   - service: The input service
    ///   - gesture: The rotation gesture
    func inputService(_ service: InputService,
                     didReceiveRotation gesture: UIRotationGestureRecognizer)
    
    /// Called when two finger tap occurs
    /// - Parameters:
    ///   - service: The input service
    ///   - gesture: The two finger tap gesture
    func inputService(_ service: InputService,
                     didReceiveTwoFingerTap gesture: UITapGestureRecognizer)
}
