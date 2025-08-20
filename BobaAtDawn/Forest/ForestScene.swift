//
//  ForestScene.swift
//  BobaAtDawn
//
//  5-room looping forest exploration area
//

import SpriteKit

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
    
    // MARK: - Game Objects
    private var character: Character!
    
    // MARK: - Room Elements
    private var roomIdentifier: SKLabelNode! // Big emoji in center
    private var backDoor: SKLabelNode! // Return to shop (Room 1 only)
    
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
        character = Character()
        
        // Start character in center-bottom of room
        let startCell = GridCoordinate(x: 16, y: 8) // Bottom center
        character.position = GridWorld.shared.gridToWorld(startCell)
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
        
        // Add room identifier emoji (big, center)
        roomIdentifier = SKLabelNode(text: roomEmojis[currentRoom])
        roomIdentifier.fontSize = 120 // Very big for identification
        roomIdentifier.fontName = "Arial"
        roomIdentifier.horizontalAlignmentMode = .center
        roomIdentifier.verticalAlignmentMode = .center
        roomIdentifier.position = CGPoint(x: 0, y: 0) // World center
        roomIdentifier.zPosition = 5
        addChild(roomIdentifier)
        
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
        
        // Check for room transitions (walk to edges)
        if isNearLeftEdge(location) {
            transitionToRoom(getPreviousRoom())
            return
        } else if isNearRightEdge(location) {
            transitionToRoom(getNextRoom())
            return
        }
        
        // Regular movement
        let targetCell = GridWorld.shared.worldToGrid(location)
        if GridWorld.shared.isCellAvailable(targetCell) {
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
            returnToShop()
        }
        
        longPressTimer = nil
        longPressTarget = nil
    }
    
    // MARK: - Room Transition System
    private func isNearLeftEdge(_ location: CGPoint) -> Bool {
        return location.x < -worldWidth/2 + 100 // Within 100 points of left edge
    }
    
    private func isNearRightEdge(_ location: CGPoint) -> Bool {
        return location.x > worldWidth/2 - 100 // Within 100 points of right edge
    }
    
    private func getPreviousRoom() -> Int {
        return currentRoom == 1 ? 5 : currentRoom - 1 // Loop: Room 1 → Room 5
    }
    
    private func getNextRoom() -> Int {
        return currentRoom == 5 ? 1 : currentRoom + 1 // Loop: Room 5 → Room 1
    }
    
    private func transitionToRoom(_ newRoom: Int) {
        print("🌲 Transitioning from Room \(currentRoom) to Room \(newRoom)")
        
        currentRoom = newRoom
        
        // Fade transition
        let fadeOut = SKAction.fadeOut(withDuration: 0.3)
        let setupNewRoom = SKAction.run { [weak self] in
            self?.setupCurrentRoom()
        }
        let fadeIn = SKAction.fadeIn(withDuration: 0.3)
        
        let transition = SKAction.sequence([fadeOut, setupNewRoom, fadeIn])
        run(transition)
        
        // Reposition character to opposite side
        repositionCharacterForTransition(from: currentRoom)
    }
    
    private func repositionCharacterForTransition(from previousRoom: Int) {
        let targetCell: GridCoordinate
        
        // If coming from left, appear on right side
        // If coming from right, appear on left side
        if (previousRoom < currentRoom) || (previousRoom == 5 && currentRoom == 1) {
            // Came from left → appear on right
            targetCell = GridCoordinate(x: 26, y: 12)
        } else {
            // Came from right → appear on left
            targetCell = GridCoordinate(x: 6, y: 12)
        }
        
        character.position = GridWorld.shared.gridToWorld(targetCell)
        print("👤 Character repositioned for room transition")
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
    }
}
