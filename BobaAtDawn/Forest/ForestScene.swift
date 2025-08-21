//
//  ForestScene.swift
//  BobaAtDawn
//
//  5-room looping forest exploration area
//

import SpriteKit
import UIKit // For haptic feedback

class ForestScene: SKScene {
    
    // MARK: - Room System
    private var currentRoom: Int = 1 // Rooms 1-5
    private let roomEmojis = ["", "🍄", "⛰️", "⭐", "💎", "🌳"] // Index 0 unused, rooms 1-5
    
    // MARK: - Camera System (Reuse from GameScene)
    private var gameCamera: SKCameraNode!
    private let cameraLerpSpeed: CGFloat = 2.0
    private var cameraScale: CGFloat = 1.0
    private let minZoom: CGFloat = 0.3
    private let maxZoom: CGFloat = 1.5
    private var lastPinchScale: CGFloat = 1.0
    
    // MARK: - World Settings (Same as shop)
    private let worldWidth: CGFloat = 2000
    private let worldHeight: CGFloat = 1500
    
    // MARK: - Dependencies (Temporary - will be improved)
    private lazy var gridService: GridService = {
        let container = ServiceSetup.createGameServices()
        return container.resolve(GridService.self)
    }()
    
    // MARK: - Game Objects
    private var character: Character!
    
    // MARK: - Room Elements
    private var roomIdentifier: SKLabelNode! // Big emoji in center
    private var backDoor: SKLabelNode! // Return to shop (Room 1 only)
    
    // MARK: - Transition Control
    private var isTransitioning: Bool = false
    private var transitionCooldown: TimeInterval = 0
    private let transitionCooldownDuration: TimeInterval = 1.0 // 1 second cooldown
    private var lastTriggeredSide: String = "" // Track which side last triggered ("left" or "right")
    private var hasLeftTransitionZone: Bool = true // Must leave zone before triggering again
    
    // MARK: - Misty Visual Effects
    private var leftMist: SKSpriteNode!
    private var rightMist: SKSpriteNode!
    private var leftHintEmoji: SKLabelNode!
    private var rightHintEmoji: SKLabelNode!
    
    // MARK: - Touch Handling
    private var longPressTimer: Timer?
    private var longPressTarget: SKNode?
    private let longPressDuration: TimeInterval = 0.8
    private var isHandlingPinch = false
    
    // MARK: - Scene Setup
    override func didMove(to view: SKView) {
        setupCamera()
        setupWorld()
        setupCharacter()
        setupCurrentRoom()
        setupGestures()
        
        print("🌲 Forest Scene initialized - Room \(currentRoom): \(roomEmojis[currentRoom])")
    }
    
    private func setupCamera() {
        gameCamera = SKCameraNode()
        camera = gameCamera
        addChild(gameCamera)
    }
    
    private func setupWorld() {
        // Forest atmosphere - darker than shop
        backgroundColor = SKColor(red: 0.2, green: 0.3, blue: 0.2, alpha: 1.0)
        
        // Forest floor
        let forestFloor = SKSpriteNode(color: SKColor(red: 0.15, green: 0.25, blue: 0.15, alpha: 1.0), 
                                      size: CGSize(width: worldWidth, height: worldHeight))
        forestFloor.position = CGPoint(x: 0, y: 0)
        forestFloor.zPosition = -10
        addChild(forestFloor)
        
        // Forest boundaries (darker trees)
        setupForestBounds()
    }
    
    private func setupForestBounds() {
        let treeColor = SKColor(red: 0.1, green: 0.15, blue: 0.1, alpha: 1.0)
        
        // Top boundary
        let wallTop = SKSpriteNode(color: treeColor, size: CGSize(width: worldWidth, height: 60))
        wallTop.position = CGPoint(x: 0, y: worldHeight/2 - 30)
        wallTop.zPosition = -5
        addChild(wallTop)
        
        // Bottom boundary  
        let wallBottom = SKSpriteNode(color: treeColor, size: CGSize(width: worldWidth, height: 60))
        wallBottom.position = CGPoint(x: 0, y: -worldHeight/2 + 30)
        wallBottom.zPosition = -5
        addChild(wallBottom)
        
        // Left boundary (transition zone)
        let wallLeft = SKSpriteNode(color: treeColor, size: CGSize(width: 60, height: worldHeight))
        wallLeft.position = CGPoint(x: -worldWidth/2 + 30, y: 0)
        wallLeft.zPosition = -5
        wallLeft.name = "left_transition"
        addChild(wallLeft)
        
        // Right boundary (transition zone)
        let wallRight = SKSpriteNode(color: treeColor, size: CGSize(width: 60, height: worldHeight))
        wallRight.position = CGPoint(x: worldWidth/2 - 30, y: 0)
        wallRight.zPosition = -5
        wallRight.name = "right_transition"
        addChild(wallRight)
    }
    
    private func setupCharacter() {
        character = Character(gridService: gridService)
        
        // Start character in center-bottom of room
        let startCell = GridCoordinate(x: 16, y: 8) // Bottom center
        character.position = gridService.gridToWorld(startCell)
        addChild(character)
        
        // Center camera on character
        gameCamera.position = character.position
        gameCamera.setScale(cameraScale)
        
        print("👤 Character positioned at forest entrance")
    }
    
    private func setupCurrentRoom() {
        // Remove previous room elements
        roomIdentifier?.removeFromParent()
        backDoor?.removeFromParent()
        leftMist?.removeFromParent()
        rightMist?.removeFromParent()
        leftHintEmoji?.removeFromParent()
        rightHintEmoji?.removeFromParent()
        
        // Add room identifier emoji (big, center)
        roomIdentifier = SKLabelNode(text: roomEmojis[currentRoom])
        roomIdentifier.fontSize = 120 // Very big for identification
        roomIdentifier.fontName = "Arial"
        roomIdentifier.horizontalAlignmentMode = .center
        roomIdentifier.verticalAlignmentMode = .center
        roomIdentifier.position = CGPoint(x: 0, y: 0) // World center
        roomIdentifier.zPosition = 5
        addChild(roomIdentifier)
        
        // Add misty transition effects
        setupMistyEffects()
        
        // Add back door only in Room 1
        if currentRoom == 1 {
            backDoor = SKLabelNode(text: "🚪")
            backDoor.fontSize = 80
            backDoor.fontName = "Arial"
            backDoor.horizontalAlignmentMode = .center
            backDoor.verticalAlignmentMode = .center
            backDoor.position = CGPoint(x: 0, y: worldHeight/2 - 150) // Top center
            backDoor.zPosition = 10
            backDoor.name = "back_door"
            addChild(backDoor)
            
            print("🚪 Back door to shop added to Room 1")
        }
        
        print("🌲 Room \(currentRoom) setup complete: \(roomEmojis[currentRoom])")
    }
    
    // MARK: - Misty Visual Effects
    private func setupMistyEffects() {
        // Create smaller walkable side transition areas (1/3 width)
        let baseColor = SKColor(red: 0.25, green: 0.35, blue: 0.25, alpha: 1.0) // Slightly lighter than floor
        
        // Left transition area - smaller walkable rectangle (1/3 width = ~133pt)
        leftMist = SKSpriteNode(color: baseColor, size: CGSize(width: 133, height: worldHeight))
        leftMist.position = CGPoint(x: -worldWidth/2 + 67, y: 0) // Left side, centered in area
        leftMist.zPosition = -8 // Below character but above floor
        addChild(leftMist)
        
        // Right transition area - smaller walkable rectangle (1/3 width = ~133pt)
        rightMist = SKSpriteNode(color: baseColor, size: CGSize(width: 133, height: worldHeight))
        rightMist.position = CGPoint(x: worldWidth/2 - 67, y: 0) // Right side, centered in area
        rightMist.zPosition = -8 // Below character but above floor
        addChild(rightMist)
        
        // Start the pulsing animation immediately
        startPulsingAnimation()
        
        // Add subtle hint emojis for next/previous rooms
        setupHintEmojis()
        
        print("🌫️ Smaller transition areas created (133pt wide) with pulsing effect")
    }
    
    private func startPulsingAnimation() {
        let baseColor = SKColor(red: 0.25, green: 0.35, blue: 0.25, alpha: 1.0)
        let lightColor = SKColor(red: 0.4, green: 0.5, blue: 0.4, alpha: 1.0) // Lighter version
        
        // Create pulsing color animation that repeats forever
        let colorPulse = SKAction.repeatForever(
            SKAction.sequence([
                SKAction.colorize(with: lightColor, colorBlendFactor: 1.0, duration: 1.0),
                SKAction.colorize(with: baseColor, colorBlendFactor: 1.0, duration: 1.0)
            ])
        )
        
        // Apply to both transition areas
        leftMist.run(colorPulse, withKey: "colorPulse")
        rightMist.run(colorPulse, withKey: "colorPulse")
        
        print("✨ Pulsing animation started")
    }
    
    private func setupHintEmojis() {
        let hintAlpha: CGFloat = 0.3 // Subtle visibility
        let hintSize: CGFloat = 40 // Small size
        
        // Left hint (previous room) - on edge of forest floor, vertically centered
        let previousRoomEmoji = roomEmojis[getPreviousRoom()]
        leftHintEmoji = SKLabelNode(text: previousRoomEmoji)
        leftHintEmoji.fontSize = hintSize
        leftHintEmoji.fontName = "Arial"
        leftHintEmoji.alpha = hintAlpha
        leftHintEmoji.horizontalAlignmentMode = .center
        leftHintEmoji.verticalAlignmentMode = .center
        leftHintEmoji.position = CGPoint(x: -worldWidth/2 + 50, y: 0) // Left edge, vertically centered
        leftHintEmoji.zPosition = 3
        addChild(leftHintEmoji)
        
        // Right hint (next room) - on edge of forest floor, vertically centered
        let nextRoomEmoji = roomEmojis[getNextRoom()]
        rightHintEmoji = SKLabelNode(text: nextRoomEmoji)
        rightHintEmoji.fontSize = hintSize
        rightHintEmoji.fontName = "Arial"
        rightHintEmoji.alpha = hintAlpha
        rightHintEmoji.horizontalAlignmentMode = .center
        rightHintEmoji.verticalAlignmentMode = .center
        rightHintEmoji.position = CGPoint(x: worldWidth/2 - 50, y: 0) // Right edge, vertically centered
        rightHintEmoji.zPosition = 3
        addChild(rightHintEmoji)
        
        print("👁️ Hint emojis added: \(previousRoomEmoji) ←→ \(nextRoomEmoji)")
    }
    
    private func setupGestures() {
        guard let view = view else { return }
        
        // Reuse gesture system from GameScene
        let pinchGesture = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        let twoFingerTap = UITapGestureRecognizer(target: self, action: #selector(handleTwoFingerTap(_:)))
        twoFingerTap.numberOfTouchesRequired = 2
        
        view.addGestureRecognizer(pinchGesture)
        view.addGestureRecognizer(twoFingerTap)
    }
    
    // MARK: - Touch Handling
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard !isHandlingPinch else { return }
        guard let touch = touches.first else { return }
        let location = touch.location(in: self)
        let touchedNode = atPoint(location)
        
        // Check for door interaction (only in Room 1)
        if currentRoom == 1 && touchedNode.name == "back_door" {
            startLongPress(for: touchedNode, at: location)
            return
        }
        
        // Regular movement with subtle haptic feedback
        let targetCell = gridService.worldToGrid(location)
        if gridService.isCellAvailable(targetCell) {
            // Very light haptic for footsteps
            let selectionFeedback = UISelectionFeedbackGenerator()
            selectionFeedback.selectionChanged()
            
            character.moveToGridCell(targetCell)
            print("👤 Character moving to forest cell \(targetCell)")
        }
    }
    
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        cancelLongPress()
    }
    
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        cancelLongPress()
    }
    
    // MARK: - Long Press System (For Door)
    private func startLongPress(for node: SKNode, at location: CGPoint) {
        longPressTarget = node
        longPressTimer = Timer.scheduledTimer(withTimeInterval: longPressDuration, repeats: false) { [weak self] _ in
            self?.handleLongPress(on: node, at: location)
        }
        
        print("🚪 Long press started on door")
    }
    
    private func cancelLongPress() {
        longPressTimer?.invalidate()
        longPressTimer = nil
        longPressTarget = nil
    }
    
    private func handleLongPress(on node: SKNode, at location: CGPoint) {
        if node.name == "back_door" {
            // Haptic feedback for door interaction
            let notificationFeedback = UINotificationFeedbackGenerator()
            notificationFeedback.notificationOccurred(.success)
            returnToShop()
        }
        
        longPressTimer = nil
        longPressTarget = nil
    }
    
    // MARK: - Room Transition System
    private func isNearLeftEdge(_ location: CGPoint) -> Bool {
        return location.x < -worldWidth/2 + 300 // Expanded transition zone (was 100)
    }
    
    private func isNearRightEdge(_ location: CGPoint) -> Bool {
        return location.x > worldWidth/2 - 300 // Expanded transition zone (was 100)
    }
    
    private func getPreviousRoom() -> Int {
        return currentRoom == 1 ? 5 : currentRoom - 1 // Loop: Room 1 → Room 5
    }
    
    private func getNextRoom() -> Int {
        return currentRoom == 5 ? 1 : currentRoom + 1 // Loop: Room 5 → Room 1
    }
    
    private func transitionToRoom(_ newRoom: Int) {
        // Prevent multiple transitions
        guard !isTransitioning else { return }
        isTransitioning = true
        transitionCooldown = transitionCooldownDuration
        
        print("🌲 Transitioning from Room \(currentRoom) to Room \(newRoom)")
        
        // Store previous room for character repositioning logic
        let previousRoom = currentRoom
        currentRoom = newRoom
        
        // Create full-screen black overlay that follows camera
        let blackOverlay = SKSpriteNode(color: .black, size: CGSize(width: 4000, height: 3000))
        blackOverlay.zPosition = 1000 // Above everything
        blackOverlay.alpha = 0
        addChild(blackOverlay)
        
        // Position overlay relative to camera, not world coordinates
        func updateOverlayPosition() {
            blackOverlay.position = gameCamera.position
        }
        
        // Update overlay position initially
        updateOverlayPosition()
        
        // Enhanced transition sequence with camera management
        let fadeToBlack = SKAction.fadeAlpha(to: 1.0, duration: 0.3)
        let waitInDarkness = SKAction.wait(forDuration: 0.1)
        
        let repositionEverything = SKAction.run { [weak self] in
            // Store current Y position before room change
            let currentY = self?.character.position.y ?? 0
            
            // During black screen, reposition everything instantly
            self?.setupCurrentRoom()
            self?.repositionCharacterForTransition(from: previousRoom, preservingY: currentY)
            
            // Instantly snap camera to character (hidden by black screen)
            if let characterPos = self?.character.position {
                self?.gameCamera.position = characterPos
            }
            
            // Update overlay position after camera snap
            updateOverlayPosition()
        }
        
        let waitAfterReposition = SKAction.wait(forDuration: 0.1)
        let fadeFromBlack = SKAction.fadeAlpha(to: 0.0, duration: 0.3)
        
        let cleanup = SKAction.run {
            blackOverlay.removeFromParent()
        }
        
        let resetTransition = SKAction.run { [weak self] in
            self?.isTransitioning = false
            self?.hasLeftTransitionZone = false
        }
        
        // Run the complete sequence
        let transitionSequence = SKAction.sequence([
            fadeToBlack,
            waitInDarkness,
            repositionEverything,
            waitAfterReposition,
            fadeFromBlack,
            cleanup,
            resetTransition
        ])
        
        blackOverlay.run(transitionSequence)
    }
    
    private func repositionCharacterForTransition(from previousRoom: Int, preservingY yPosition: CGFloat) {
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
        
        print("👤 Character repositioned to \(targetCell) for room \(currentRoom), at transition edge")
    }
    
    private func returnToShop() {
        print("🚪 Returning to boba shop")
        
        // Transition back to GameScene
        let fadeOut = SKAction.fadeOut(withDuration: 0.5)
        
        run(fadeOut) { [weak self] in
            // Create and present GameScene
            let gameScene = GameScene(size: self?.size ?? CGSize(width: 1024, height: 768))
            gameScene.scaleMode = .aspectFill
            self?.view?.presentScene(gameScene, transition: SKTransition.fade(withDuration: 0.5))
        }
    }
    
    // MARK: - Gesture Handlers (Reused from GameScene)
    @objc private func handlePinch(_ gesture: UIPinchGestureRecognizer) {
        isHandlingPinch = true
        
        switch gesture.state {
        case .began:
            lastPinchScale = cameraScale
        case .changed:
            let newScale = lastPinchScale / gesture.scale
            cameraScale = max(minZoom, min(maxZoom, newScale))
            gameCamera.setScale(cameraScale)
        case .ended, .cancelled:
            isHandlingPinch = false
        default:
            break
        }
    }
    
    @objc private func handleTwoFingerTap(_ gesture: UITapGestureRecognizer) {
        // Reset camera zoom
        cameraScale = 1.0
        let zoomAction = SKAction.scale(to: cameraScale, duration: 0.3)
        gameCamera.run(zoomAction)
    }
    
    // MARK: - Camera Update (Reused from GameScene)
    private func updateCamera() {
        let targetPosition = character.position
        let currentPosition = gameCamera.position
        
        let deltaX = targetPosition.x - currentPosition.x
        let deltaY = targetPosition.y - currentPosition.y
        
        let newX = currentPosition.x + deltaX * cameraLerpSpeed * 0.016
        let newY = currentPosition.y + deltaY * cameraLerpSpeed * 0.016
        
        let effectiveViewWidth = size.width * cameraScale
        let effectiveViewHeight = size.height * cameraScale
        
        let halfViewWidth = effectiveViewWidth / 2
        let halfViewHeight = effectiveViewHeight / 2
        
        let forestLeft = -worldWidth/2 + 80
        let forestRight = worldWidth/2 - 80
        let forestBottom = -worldHeight/2 + 80
        let forestTop = worldHeight/2 - 80
        
        let clampedX = max(forestLeft + halfViewWidth, min(forestRight - halfViewWidth, newX))
        let clampedY = max(forestBottom + halfViewHeight, min(forestTop - halfViewHeight, newY))
        
        gameCamera.position = CGPoint(x: clampedX, y: clampedY)
    }
    
    // MARK: - Update Loop
    override func update(_ currentTime: TimeInterval) {
        updateCamera()
        character.update()
        
        // Update transition cooldown
        if transitionCooldown > 0 {
            transitionCooldown -= 1.0/60.0 // Approximate frame time
        }
        
        // Only check transitions if not in cooldown
        if !isTransitioning && transitionCooldown <= 0 {
            checkForRoomTransitions()
        }
    }
    
    // MARK: - Character Position Monitoring
    private func checkForRoomTransitions() {
        let characterPos = character.position
        
        // Check if character is in center (forest floor) to reset zone tracking
        if characterPos.x > -worldWidth/2 + 133 && characterPos.x < worldWidth/2 - 133 {
            if !hasLeftTransitionZone {
                hasLeftTransitionZone = true
                lastTriggeredSide = ""
                print("🌲 Character returned to forest center - transitions re-enabled")
            }
        }
        
        // Only allow transitions if character has left transition zones
        guard hasLeftTransitionZone else { return }
        
        // Transition zones match the entire pulsing area (133pt wide)
        // Check if character walked into left transition area (entire pulsing zone)
        if characterPos.x < -worldWidth/2 + 133 && lastTriggeredSide != "left" {
            // Haptic feedback for room transition
            let impactFeedback = UIImpactFeedbackGenerator(style: .light)
            impactFeedback.impactOccurred()
            lastTriggeredSide = "left"
            transitionToRoom(getPreviousRoom())
        }
        // Check if character walked into right transition area (entire pulsing zone)
        else if characterPos.x > worldWidth/2 - 133 && lastTriggeredSide != "right" {
            // Haptic feedback for room transition
            let impactFeedback = UIImpactFeedbackGenerator(style: .light)
            impactFeedback.impactOccurred()
            lastTriggeredSide = "right"
            transitionToRoom(getNextRoom())
        }
    }
}
