//
//  BaseGameScene.swift
//  BobaAtDawn
//
//  Base class for GameScene and ForestScene with shared camera, movement, and touch handling
//

import SpriteKit
import UIKit

// MARK: - Camera State Management
struct GameCameraState {
    var scale: CGFloat
    var lastPinchScale: CGFloat
    let defaultScale: CGFloat
    let minZoom: CGFloat
    let maxZoom: CGFloat
    
    init(defaultScale: CGFloat, minZoom: CGFloat, maxZoom: CGFloat) {
        self.scale = defaultScale
        self.lastPinchScale = defaultScale
        self.defaultScale = defaultScale
        self.minZoom = minZoom
        self.maxZoom = maxZoom
    }
}

// MARK: - Base Game Scene
class BaseGameScene: SKScene, InputServiceDelegate {
    
    // MARK: - Initializers
    override init(size: CGSize) {
        super.init(size: size)
        self.scaleMode = .aspectFill
    }
    
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        self.scaleMode = .aspectFill
    }
    
    // MARK: - Shared Services (Protected - accessible to subclasses)
    internal lazy var serviceContainer: GameServiceContainer = ServiceSetup.createGameServices()
    internal lazy var configService: ConfigurationService = serviceContainer.resolve(ConfigurationService.self)
    internal lazy var gridService: GridService = serviceContainer.resolve(GridService.self)
    internal lazy var transitionService: SceneTransitionService = serviceContainer.resolve(SceneTransitionService.self)
    internal lazy var animationService: AnimationService = serviceContainer.resolve(AnimationService.self)
    internal lazy var inputService: InputService = serviceContainer.resolve(InputService.self)
    
    // MARK: - Camera System (Protected - accessible to subclasses)
    internal var gameCamera: SKCameraNode!
    internal lazy var cameraLerpSpeed: CGFloat = configService.cameraLerpSpeed
    internal lazy var cameraState = GameCameraState(
        defaultScale: configService.cameraDefaultScale,
        minZoom: configService.cameraMinZoom,
        maxZoom: configService.cameraMaxZoom
    )
    internal var isHandlingPinch = false
    
    // MARK: - World Settings (Protected - accessible to subclasses)
    internal lazy var worldWidth: CGFloat = configService.worldWidth
    internal lazy var worldHeight: CGFloat = configService.worldHeight
    
    // MARK: - Character (Protected - accessible to subclasses)
    internal var character: Character!
    
    // MARK: - Long Press System (Protected - accessible to subclasses)
    internal var longPressTimer: Timer?
    internal var longPressTarget: SKNode?
    internal lazy var longPressDuration: TimeInterval = configService.touchLongPressDuration
    
    // MARK: - Scene Setup (Template Methods - Override in subclasses)
    override func didMove(to view: SKView) {
        print("🎬 BaseGameScene: Starting setup with size: \(self.size)")
        
        // Validate scene size before proceeding
        guard self.size.width > 0 && self.size.height > 0 else {
            print("❌ CRITICAL ERROR: BaseGameScene has invalid size: \(self.size)")
            print("❌ This will cause crashes when creating sprites")
            return
        }
        
        setupCamera()
        setupWorld()
        setupCharacter()
        setupSpecificContent() // Template method for subclass-specific setup
        setupGestures()
        
        print("🎬 BaseGameScene: Setup complete")
    }
    
    // MARK: - Camera System (Shared Implementation)
    private func setupCamera() {
        gameCamera = SKCameraNode()
        camera = gameCamera
        addChild(gameCamera)
    }
    
    internal func updateCamera() {
        guard let character = character else { return }
        
        let targetPosition = character.position
        let currentPosition = gameCamera.position
        
        let deltaX = targetPosition.x - currentPosition.x
        let deltaY = targetPosition.y - currentPosition.y
        
        let newX = currentPosition.x + deltaX * cameraLerpSpeed * 0.016
        let newY = currentPosition.y + deltaY * cameraLerpSpeed * 0.016
        
        let effectiveViewWidth = size.width * cameraState.scale
        let effectiveViewHeight = size.height * cameraState.scale
        
        let halfViewWidth = effectiveViewWidth / 2
        let halfViewHeight = effectiveViewHeight / 2
        
        let edgeInset: CGFloat = 80
        let worldLeft = -worldWidth/2 + edgeInset
        let worldRight = worldWidth/2 - edgeInset
        let worldBottom = -worldHeight/2 + edgeInset
        let worldTop = worldHeight/2 - edgeInset
        
        let clampedX = max(worldLeft + halfViewWidth, min(worldRight - halfViewWidth, newX))
        let clampedY = max(worldBottom + halfViewHeight, min(worldTop - halfViewHeight, newY))
        
        gameCamera.position = CGPoint(x: clampedX, y: clampedY)
    }
    
    internal func centerCameraOnCharacter() {
        guard let character = character else { return }
        gameCamera.position = character.position
        gameCamera.setScale(cameraState.scale)
    }
    
    // MARK: - World Setup (Template Method - Override in subclasses)
    open func setupWorld() {
        // Base implementation - can be overridden
        backgroundColor = configService.backgroundColor
        
        // Validate world dimensions
        guard worldWidth > 0 && worldHeight > 0 else {
            print("❌ ERROR: Invalid world dimensions: \(worldWidth) x \(worldHeight)")
            return
        }
        
        print("🌍 BaseGameScene: World setup with dimensions \(worldWidth) x \(worldHeight)")
    }
    
    // MARK: - Character Setup (Shared Implementation)
    private func setupCharacter() {
        character = Character(gridService: gridService, animationService: animationService)
        
        // Position character at center by default (subclasses can override)
        let startCell = configService.characterStartPosition
        character.position = gridService.gridToWorld(startCell)
        addChild(character)
        
        centerCameraOnCharacter()
        
        print("👤 BaseGameScene: Character positioned at \(startCell)")
    }
    
    // MARK: - Template Methods (Override in subclasses)
    
    /// Override this method in subclasses to add specific content
    open func setupSpecificContent() {
        // Base implementation does nothing - override in subclasses
    }
    
    /// Override this method in subclasses to handle scene-specific long press actions
    open func handleSceneSpecificLongPress(on node: SKNode, at location: CGPoint) {
        // Base implementation does nothing - override in subclasses
        print("🔍 BaseGameScene: No specific long press handler for \(node.name ?? "unnamed")")
    }
    
    /// Override this method in subclasses for scene-specific touch handling
    open func handleSceneSpecificTouch(_ touches: Set<UITouch>, with event: UIEvent?) -> Bool {
        // Return true if handled, false if should use default behavior
        return false
    }
    
    // MARK: - Gestures Setup (Shared Implementation)
    private func setupGestures() {
        guard let view = view else { return }
        
        // Determine context based on scene type
        let context: InputContext = (self is GameScene) ? .gameScene : .forestScene
        
        inputService.setupGestures(for: view, context: context, config: nil, delegate: self)
        print("🎮 BaseGameScene: Gestures setup using InputService with context: \(context)")
    }
    
    // MARK: - Touch Handling (Shared Implementation with Template Methods)
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        // Don't handle touches during pinch
        guard !isHandlingPinch else { return }
        
        // Allow subclasses to handle scene-specific touches first
        if handleSceneSpecificTouch(touches, with: event) {
            return
        }
        
        // Default touch handling using InputService
        let result = inputService.handleTouchBegan(touches, with: event, in: self, gridService: gridService, context: getCurrentContext())
        
        switch result {
        case .handled:
            break // Already handled by service
            
        case .notHandled:
            break // Not handled, ignore
            
        case .longPress(let node, let location):
            startLongPress(for: node, at: location)
            
        case .movement(let targetCell):
            character.moveToGridCell(targetCell)
            print("🎯 Character moving to available cell \(targetCell)")
            
        case .occupiedCell(let cell):
            inputService.showOccupiedCellFeedback(at: cell, in: self, gridService: gridService)
            print("❌ Cell \(cell) is occupied")
        }
    }
    
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        inputService.handleTouchEnded(touches, with: event)
        cancelLongPress()
    }
    
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        inputService.handleTouchCancelled(touches, with: event)
        cancelLongPress()
    }
    
    // MARK: - Long Press System (Shared Implementation)
    internal func startLongPress(for node: SKNode, at location: CGPoint) {
        longPressTarget = node
        longPressTimer = Timer.scheduledTimer(withTimeInterval: longPressDuration, repeats: false) { [weak self] _ in
            self?.handleLongPress(on: node, at: location)
        }
        
        print("🔍 Long press started on \(node.name ?? "unnamed")")
    }
    
    internal func cancelLongPress() {
        longPressTimer?.invalidate()
        longPressTimer = nil
        longPressTarget = nil
    }
    
    private func handleLongPress(on node: SKNode, at location: CGPoint) {
        // Call template method for scene-specific handling
        handleSceneSpecificLongPress(on: node, at: location)
        
        // Clean up
        longPressTimer = nil
        longPressTarget = nil
    }
    
    // MARK: - InputServiceDelegate Implementation
    func inputService(_ service: InputService, didReceivePinch gesture: UIPinchGestureRecognizer) {
        isHandlingPinch = true
        
        switch gesture.state {
        case .began:
            cameraState.lastPinchScale = cameraState.scale
        case .changed:
            let newScale = cameraState.lastPinchScale / gesture.scale
            cameraState.scale = max(cameraState.minZoom, min(cameraState.maxZoom, newScale))
            gameCamera.setScale(cameraState.scale)
        case .ended, .cancelled:
            isHandlingPinch = false
        default:
            break
        }
        
        print("🎮 BaseGameScene: Handled pinch gesture")
    }
    
    func inputService(_ service: InputService, didReceiveRotation gesture: UIRotationGestureRecognizer) {
        guard gesture.state == .ended else { return }
        
        // Default behavior - rotate carried items if character is carrying something
        if character?.isCarrying == true {
            character?.rotateCarriedItem()
            print("🎮 BaseGameScene: Rotated carried item")
        }
    }
    
    func inputService(_ service: InputService, didReceiveTwoFingerTap gesture: UITapGestureRecognizer) {
        // Reset camera zoom to default
        cameraState.scale = cameraState.defaultScale
        let zoomAction = SKAction.scale(to: cameraState.scale, duration: configService.cameraZoomResetDuration)
        gameCamera.run(zoomAction)
        
        print("🎮 BaseGameScene: Camera zoom reset")
    }
    
    // MARK: - Update Loop (Template Method)
    override func update(_ currentTime: TimeInterval) {
        updateCamera()
        character?.update()
        
        // Allow subclasses to add specific update logic
        updateSpecificContent(currentTime)
    }
    
    /// Override this method in subclasses for scene-specific update logic
    open func updateSpecificContent(_ currentTime: TimeInterval) {
        // Base implementation does nothing - override in subclasses
    }
    
    // MARK: - Helper Methods
    private func getCurrentContext() -> InputContext {
        return (self is GameScene) ? .gameScene : .forestScene
    }
    
    // MARK: - Validation Helpers (Protected)
    internal func validateSpriteSize(_ size: CGSize, name: String) -> Bool {
        guard size.width > 0 && size.height > 0 else {
            print("❌ ERROR: Invalid \(name) size: \(size)")
            return false
        }
        return true
    }
    
    internal func createValidatedSprite(color: SKColor, size: CGSize, name: String) -> SKSpriteNode? {
        guard validateSpriteSize(size, name: name) else {
            return nil
        }
        
        let sprite = SKSpriteNode(color: color, size: size)
        print("✅ Created validated sprite '\(name)' with size: \(size)")
        return sprite
    }
}

// MARK: - BaseGameScene Extensions for Common Functionality

extension BaseGameScene {
    
    // MARK: - Haptic Feedback Helpers
    internal func triggerMovementFeedback() {
        transitionService.triggerHapticFeedback(type: .selection)
    }
    
    internal func triggerInteractionFeedback() {
        transitionService.triggerHapticFeedback(type: .light)
    }
    
    internal func triggerSuccessFeedback() {
        transitionService.triggerHapticFeedback(type: .success)
    }
    
    // MARK: - Common Animation Helpers
    internal func pulseNode(_ node: SKNode, scale: CGFloat = 1.2, duration: TimeInterval = 0.2) {
        let config = AnimationConfig(duration: duration, easing: .easeInOut)
        let pulseAction = animationService.pulse(node, scale: scale, config: config)
        animationService.run(pulseAction, on: node, withKey: AnimationKeys.pulse, completion: nil)
    }
    
    internal func fadeInNode(_ node: SKNode, duration: TimeInterval = 0.3) {
        let config = AnimationConfig(duration: duration, easing: .easeInOut)
        let fadeAction = animationService.fade(node, to: 1.0, config: config)
        animationService.run(fadeAction, on: node, withKey: AnimationKeys.fade, completion: nil)
    }
    
    internal func fadeOutNode(_ node: SKNode, duration: TimeInterval = 0.3) {
        let config = AnimationConfig(duration: duration, easing: .easeInOut)
        let fadeAction = animationService.fade(node, to: 0.0, config: config)
        animationService.run(fadeAction, on: node, withKey: AnimationKeys.fade, completion: nil)
    }
    
    // MARK: - Grid Helpers
    internal func isValidGridPosition(_ position: GridCoordinate) -> Bool {
        // Check if position is within grid bounds
        return position.x >= 0 && position.x < gridService.columns && 
               position.y >= 0 && position.y < gridService.rows
    }
    
    internal func isCellAvailable(_ position: GridCoordinate) -> Bool {
        return gridService.isCellAvailable(position)
    }
    
    internal func worldToGrid(_ worldPosition: CGPoint) -> GridCoordinate {
        return gridService.worldToGrid(worldPosition)
    }
    
    internal func gridToWorld(_ gridPosition: GridCoordinate) -> CGPoint {
        return gridService.gridToWorld(gridPosition)
    }
}
