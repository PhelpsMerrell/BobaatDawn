//
//  StandardInputService.swift
//  BobaAtDawn
//
//  Standard implementation of InputService for touch and gesture handling
//

import SpriteKit
import UIKit

class StandardInputService: InputService {
    
    // MARK: - Dependencies
    private let configService: ConfigurationService
    
    // MARK: - Long Press State
    private var longPressTimer: Timer?
    private var longPressTarget: SKNode?
    private var longPressCompletion: ((SKNode, CGPoint) -> Void)?
    
    // MARK: - Pinch Handling State
    private var isHandlingPinch = false
    
    // MARK: - Delegate Reference
    private weak var delegate: InputServiceDelegate?
    
    // MARK: - Initialization
    init(configService: ConfigurationService) {
        self.configService = configService
    }
    
    // MARK: - Configuration Properties
    var longPressDuration: TimeInterval {
        return configService.touchLongPressDuration
    }
    
    var interactionSearchDepth: Int {
        return configService.touchInteractionSearchDepth
    }
    
    var isHandlingLongPress: Bool {
        return longPressTimer != nil
    }
    
    // MARK: - Gesture Setup
    func setupGestures(for view: SKView, 
                      context: InputContext,
                      config: GestureConfig? = nil,
                      delegate: InputServiceDelegate) {
        
        // Store delegate reference
        self.delegate = delegate
        
        let gestureConfig = config ?? (context == .gameScene ? .gameDefault : .forestDefault)
        
        // Setup pinch gesture - InputService handles it internally
        if gestureConfig.enablePinch {
            let pinchGesture = UIPinchGestureRecognizer(target: self, action: #selector(handlePinchGesture(_:)))
            view.addGestureRecognizer(pinchGesture)
        }
        
        // Setup rotation gesture (mainly for GameScene) - InputService handles it internally
        if gestureConfig.enableRotation {
            let rotationGesture = UIRotationGestureRecognizer(target: self, action: #selector(handleRotationGesture(_:)))
            view.addGestureRecognizer(rotationGesture)
        }
        
        // Setup two finger tap - InputService handles it internally
        if gestureConfig.enableTwoFingerTap {
            let twoFingerTap = UITapGestureRecognizer(target: self, action: #selector(handleTwoFingerTapGesture(_:)))
            twoFingerTap.numberOfTouchesRequired = 2
            view.addGestureRecognizer(twoFingerTap)
        }
        
        print("🎮 Input gestures setup for \(context) - Pinch: \(gestureConfig.enablePinch), Rotation: \(gestureConfig.enableRotation), TwoFinger: \(gestureConfig.enableTwoFingerTap)")
    }
    
    // MARK: - Touch Handling
    func handleTouchBegan(_ touches: Set<UITouch>,
                         with event: UIEvent?,
                         in scene: SKScene,
                         gridService: GridService,
                         context: InputContext) -> TouchResult {
        
        // Don't handle touches during pinch
        guard !isHandlingPinch else { return .notHandled }
        guard let touch = touches.first else { return .notHandled }
        
        let location = touch.location(in: scene)
        let targetCell = gridService.worldToGrid(location)
        let touchedNode = scene.atPoint(location)
        
        // Check what's in the tapped cell first (for GameScene)
        if context == .gameScene {
            if let gameObject = gridService.objectAt(targetCell) {
                if let interactable = findInteractableNode(gameObject.skNode, context: context, gameSpecificNodes: nil) {
                    return .longPress(node: interactable, location: location)
                }
            }
        }
        
        // Check for direct node touches
        let gameSpecificNodes = getContextSpecificNodes(from: scene, context: context)
        if let interactable = findInteractableNode(touchedNode, context: context, gameSpecificNodes: gameSpecificNodes) {
            return .longPress(node: interactable, location: location)
        }
        
        // Handle movement for available cells
        if gridService.isCellAvailable(targetCell) {
            return .movement(targetCell: targetCell)
        } else {
            return .occupiedCell(cell: targetCell)
        }
    }
    
    func handleTouchEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        cancelLongPress()
    }
    
    func handleTouchCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        cancelLongPress()
    }
    
    // MARK: - Long Press System
    func startLongPress(for node: SKNode, 
                       at location: CGPoint,
                       completion: @escaping (SKNode, CGPoint) -> Void) {
        
        longPressTarget = node
        longPressCompletion = completion
        
        longPressTimer = Timer.scheduledTimer(withTimeInterval: longPressDuration, repeats: false) { [weak self] _ in
            self?.triggerLongPress(on: node, at: location)
        }
        
        // Visual feedback for long press start
        if let rotatable = node as? RotatableObject {
            let pulseAction = SKAction.sequence([
                SKAction.scale(to: 1.05, duration: 0.1),
                SKAction.scale(to: 1.0, duration: 0.1)
            ])
            rotatable.run(pulseAction)
        }
        
        print("🎮 Long press started on \(node.name ?? "unnamed")")
    }
    
    func cancelLongPress() {
        longPressTimer?.invalidate()
        longPressTimer = nil
        longPressTarget = nil
        longPressCompletion = nil
    }
    
    private func triggerLongPress(on node: SKNode, at location: CGPoint) {
        let completion = longPressCompletion
        
        // Clear state before calling completion to avoid reentrancy
        longPressTimer = nil
        longPressTarget = nil
        longPressCompletion = nil
        
        completion?(node, location)
    }
    
    // MARK: - Internal Helper Methods - for backward compatibility
    
    /// Legacy method for scenes that haven't been updated to delegate pattern
    func handlePinch(_ gesture: UIPinchGestureRecognizer,
                    cameraState: inout CameraState,
                    camera: SKCameraNode) -> Bool {
        
        isHandlingPinch = true
        
        switch gesture.state {
        case .began:
            cameraState.lastPinchScale = cameraState.scale
        case .changed:
            let newScale = cameraState.lastPinchScale / gesture.scale
            cameraState.scale = max(cameraState.minZoom, min(cameraState.maxZoom, newScale))
            camera.setScale(cameraState.scale)
        case .ended, .cancelled:
            isHandlingPinch = false
        default:
            break
        }
        
        return isHandlingPinch
    }
    
    /// Legacy method for scenes that haven't been updated to delegate pattern
    func handleRotation(_ gesture: UIRotationGestureRecognizer, character: Character?) {
        guard gesture.state == .ended else { return }
        
        // Rotate carried items if character is carrying something
        if let character = character, character.isCarrying {
            character.rotateCarriedItem()
            print("🎮 Rotated carried item")
        }
    }
    
    /// Legacy method for scenes that haven't been updated to delegate pattern
    func handleTwoFingerTap(_ gesture: UITapGestureRecognizer,
                           cameraState: inout CameraState,
                           camera: SKCameraNode) {
        
        // Reset camera zoom to default
        cameraState.scale = configService.cameraDefaultScale
        let zoomAction = SKAction.scale(to: cameraState.scale, duration: configService.cameraZoomResetDuration)
        camera.run(zoomAction)
        
        print("🎮 Camera zoom reset to default")
    }
    
    // MARK: - Node Finding
    func findInteractableNode(_ node: SKNode,
                             context: InputContext,
                             gameSpecificNodes: [String: SKNode]?) -> SKNode? {
        
        print("🔎 Checking node: \(node.name ?? "unnamed") - \(type(of: node))")
        
        var current: SKNode? = node
        var depth = 0
        
        while current != nil && depth < interactionSearchDepth {
            print("🔎 Level \(depth): \(current?.name ?? "unnamed") - \(type(of: current!))")
            
            // Context-specific checks
            if let interactable = checkContextSpecificNodes(current!, context: context, gameSpecificNodes: gameSpecificNodes) {
                print("✅ Found context-specific interactable: \(type(of: interactable))")
                return interactable
            }
            
            // Common interactables across contexts
            if let interactable = checkCommonInteractables(current!) {
                print("✅ Found common interactable: \(type(of: interactable))")
                return interactable
            }
            
            current = current?.parent
            depth += 1
        }
        
        print("❌ No interactable found after checking \(depth) levels")
        return nil
    }
    
    // MARK: - Visual Feedback
    func showOccupiedCellFeedback(at cell: GridCoordinate,
                                 in scene: SKScene,
                                 gridService: GridService) {
        
        let worldPos = gridService.gridToWorld(cell)
        
        // Create feedback using configuration
        let feedback = SKShapeNode(circleOfRadius: configService.touchOccupiedCellFeedbackRadius)
        feedback.fillColor = SKColor.clear
        feedback.strokeColor = configService.touchFeedbackColor
        feedback.lineWidth = configService.touchFeedbackLineWidth
        feedback.position = worldPos
        feedback.zPosition = configService.touchFeedbackZPosition
        scene.addChild(feedback)
        
        // Animate feedback
        let pulseAction = SKAction.sequence([
            SKAction.scale(to: configService.touchFeedbackScaleAmount, duration: configService.touchFeedbackScaleDuration),
            SKAction.scale(to: 1.0, duration: configService.touchFeedbackScaleDuration),
            SKAction.wait(forDuration: configService.touchFeedbackWaitDuration),
            SKAction.fadeOut(withDuration: configService.touchFeedbackFadeDuration),
            SKAction.removeFromParent()
        ])
        feedback.run(pulseAction)
    }
    
    // MARK: - Private Helper Methods
    
    private func getContextSpecificNodes(from scene: SKScene, context: InputContext) -> [String: SKNode]? {
        switch context {
        case .gameScene:
            // For GameScene, we need access to specific game objects
            // These would be passed in from the scene
            return nil // Will be handled by the scene calling this service
        case .forestScene:
            // For ForestScene, check for back door
            var nodes: [String: SKNode] = [:]
            scene.enumerateChildNodes(withName: "back_door") { node, _ in
                nodes["back_door"] = node
            }
            return nodes.isEmpty ? nil : nodes
        }
    }
    
    private func checkContextSpecificNodes(_ node: SKNode, 
                                          context: InputContext, 
                                          gameSpecificNodes: [String: SKNode]?) -> SKNode? {
        switch context {
        case .gameScene:
            // GameScene specific checks
            if let nodes = gameSpecificNodes {
                // Check for power breaker
                if let timeBreaker = nodes["timeBreaker"], node == timeBreaker {
                    return timeBreaker
                }
                
                // Check for carried item
                if let carriedItem = nodes["carriedItem"], node == carriedItem {
                    return carriedItem
                }
            }
            
            // Check for ingredient stations
            if let station = node as? IngredientStation {
                return station
            }
            
            // Check for completed drink pickup
            if node.name == "completed_drink_pickup" {
                return node
            }
            
            // Check for front door (forest entrance)
            if node.name == "front_door" {
                return node
            }
            
        case .forestScene:
            // ForestScene specific checks
            if node.name == "back_door" {
                return node
            }
        }
        
        return nil
    }
    
    private func checkCommonInteractables(_ node: SKNode) -> SKNode? {
        // Check for rotatable objects (tables, furniture, etc.)
        if let rotatable = node as? RotatableObject {
            // Tables are always interactable
            if rotatable.name == "table" {
                return rotatable
            }
            
            // Other objects only if they can be carried
            if rotatable.canBeCarried {
                return rotatable
            }
        }
        
        return nil
    }
}

// MARK: - Objective-C Gesture Selectors
extension StandardInputService {
    @objc private func handlePinchGesture(_ gesture: UIPinchGestureRecognizer) {
        // Handle pinch gesture through delegate pattern
        guard let delegate = delegate else {
            print("🎮 InputService: Pinch gesture received but no delegate set")
            return
        }
        
        delegate.inputService(self, didReceivePinch: gesture)
    }
    
    @objc private func handleRotationGesture(_ gesture: UIRotationGestureRecognizer) {
        // Handle rotation gesture through delegate pattern
        guard let delegate = delegate else {
            print("🎮 InputService: Rotation gesture received but no delegate set")
            return
        }
        
        delegate.inputService(self, didReceiveRotation: gesture)
    }
    
    @objc private func handleTwoFingerTapGesture(_ gesture: UITapGestureRecognizer) {
        // Handle two finger tap through delegate pattern
        guard let delegate = delegate else {
            print("🎮 InputService: Two finger tap received but no delegate set")
            return
        }
        
        delegate.inputService(self, didReceiveTwoFingerTap: gesture)
    }
}
