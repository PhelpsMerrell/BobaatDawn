//
//  ForestScene.swift
//  BobaAtDawn
//
//  5-room looping forest exploration area
//

import SpriteKit
import UIKit // For haptic feedback

class ForestScene: BaseGameScene {
    
    // MARK: - Room System (Internal - accessible to extensions)
    internal var currentRoom: Int = 1 // Rooms 1-5
    internal let roomEmojis = ["", "🍄", "⛰️", "⭐", "💎", "🌳"] // Index 0 unused, rooms 1-5
    
    // MARK: - Room Elements (Internal - accessible to extensions)
    internal var roomIdentifier: SKLabelNode! // Big emoji in center
    internal var backDoor: SKLabelNode! // Return to shop (Room 1 only)
    
    // MARK: - Transition Control
    private var isTransitioning: Bool = false
    private var transitionCooldown: TimeInterval = 0
    private let transitionCooldownDuration: TimeInterval = 1.0 // 1 second cooldown
    private var lastTriggeredSide: String = "" // Track which side last triggered ("left" or "right")
    private var hasLeftTransitionZone: Bool = true // Must leave zone before triggering again
    
    // MARK: - Misty Visual Effects (Internal - accessible to extensions)
    internal var leftMist: SKSpriteNode!
    internal var rightMist: SKSpriteNode!
    internal var leftHintEmoji: SKLabelNode!
    internal var rightHintEmoji: SKLabelNode!
    
    // MARK: - NPC System (Internal - accessible to extensions)
    internal var roomNPCs: [ForestNPC] = [] // NPCs in current room
    
    // MARK: - BaseGameScene Template Method Implementation
    override open func setupWorld() {
        // Forest atmosphere - darker than shop
        backgroundColor = SKColor(red: 0.2, green: 0.3, blue: 0.2, alpha: 1.0)
        
        // Call base implementation for validation
        super.setupWorld()
        
        // Validate world dimensions before creating sprites
        guard worldWidth > 0 && worldHeight > 0 else {
            print("❌ ERROR: Invalid world dimensions: \\(worldWidth) x \\(worldHeight)")
            return
        }
        
        // Forest floor - FIXED: ensure positive size
        let floorSize = CGSize(width: worldWidth, height: worldHeight)
        guard floorSize.width > 0 && floorSize.height > 0 else {
            print("❌ ERROR: Invalid floor size: \\(floorSize)")
            return
        }
        
        let forestFloor = SKSpriteNode(color: SKColor(red: 0.15, green: 0.25, blue: 0.15, alpha: 1.0), 
                                      size: floorSize)
        forestFloor.position = CGPoint(x: 0, y: 0)
        forestFloor.zPosition = -10
        addChild(forestFloor)
        
        // Forest boundaries (darker trees)
        setupForestBounds()
        
        print("🌲 Forest world setup complete with validated sizes")
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
    
    override open func setupSpecificContent() {
        setupCurrentRoom()
        
        print("🌲 Forest Scene initialized - Room \\(currentRoom): \\(roomEmojis[currentRoom])")
    }
    
    private func setupCurrentRoom() {
        // Clear existing NPCs
        clearRoomNPCs()
        
        // Use the new grid positioning system
        setupRoomWithGrid(currentRoom)
        
        // Add misty transition effects
        setupMistyEffects()
        
        // Spawn NPCs for this room
        spawnRoomNPCs()
        
        print("🌲 Room \\(currentRoom) setup complete: \\(roomEmojis[currentRoom])")
    }
    
    // MARK: - NPC Management
    private func spawnRoomNPCs() {
        // Get 1-2 random NPCs for this room
        let npcCount = Int.random(in: 1...2)
        let selectedNPCs = DialogueService.shared.getRandomNPCs(count: npcCount)
        
        for (index, npcData) in selectedNPCs.enumerated() {
            // Generate random position within forest bounds (avoid edges)
            let margin: CGFloat = 150
            let xRange = (-worldWidth/2 + margin)...(worldWidth/2 - margin)
            let yRange = (-worldHeight/2 + margin)...(worldHeight/2 - margin)
            
            let randomX = CGFloat.random(in: xRange)
            let randomY = CGFloat.random(in: yRange)
            let position = CGPoint(x: randomX, y: randomY)
            
            // Create and add NPC
            let npc = ForestNPC(npcData: npcData, at: position)
            roomNPCs.append(npc)
            addChild(npc)
            
            print("🎭 Spawned \\(npcData.name) (\\(npcData.emoji)) in room \\(currentRoom)")
        }
    }
    
    private func clearRoomNPCs() {
        // Remove existing NPCs
        for npc in roomNPCs {
            npc.removeFromParent()
        }
        roomNPCs.removeAll()
    }
    
    // MARK: - Misty Visual Effects
    private func setupMistyEffects() {
        print("🌫️ Setting up misty effects with world dimensions: \\(worldWidth) x \\(worldHeight)")
        
        // Remove existing mist if present
        leftMist?.removeFromParent()
        rightMist?.removeFromParent()
        leftHintEmoji?.removeFromParent()
        rightHintEmoji?.removeFromParent()
        
        // Validate world dimensions before creating misty sprites
        guard worldWidth > 0 && worldHeight > 0 else {
            print("❌ ERROR: Invalid world dimensions for mist: \\(worldWidth) x \\(worldHeight)")
            return
        }
        
        // Create smaller walkable side transition areas (1/3 width)
        let baseColor = SKColor(red: 0.25, green: 0.35, blue: 0.25, alpha: 1.0) // Slightly lighter than floor
        
        // FIXED: Validate mist sizes before creating sprites
        let mistSize = CGSize(width: 133, height: worldHeight)
        guard mistSize.width > 0 && mistSize.height > 0 else {
            print("❌ ERROR: Invalid mist size: \\(mistSize)")
            return
        }
        
        // Left transition area - smaller walkable rectangle (1/3 width = ~133pt)
        leftMist = SKSpriteNode(color: baseColor, size: mistSize)
        leftMist.position = CGPoint(x: -worldWidth/2 + 67, y: 0) // Left side, centered in area
        leftMist.zPosition = -8 // Below character but above floor
        addChild(leftMist)
        
        // Right transition area - smaller walkable rectangle (1/3 width = ~133pt)
        rightMist = SKSpriteNode(color: baseColor, size: mistSize)
        rightMist.position = CGPoint(x: worldWidth/2 - 67, y: 0) // Right side, centered in area
        rightMist.zPosition = -8 // Below character but above floor
        addChild(rightMist)
        
        print("🌫️ Created mist sprites successfully with size: \\(mistSize)")
        
        // Start the pulsing animation immediately
        startPulsingAnimation()
        
        // Add subtle hint emojis for next/previous rooms
        setupHintEmojis()
        
        print("🌫️ Smaller transition areas created (133pt wide) with pulsing effect")
    }
    
    private func startPulsingAnimation() {
        // Use AnimationService for consistent pulsing effect
        let pulseConfig = AnimationConfig(
            duration: 2.0, // 2 second full cycle
            easing: .easeInOut,
            repeatCount: -1 // Repeat forever
        )
        
        let leftPulseAction = animationService.pulse(leftMist, scale: 1.2, config: pulseConfig)
        let rightPulseAction = animationService.pulse(rightMist, scale: 1.2, config: pulseConfig)
        
        animationService.run(leftPulseAction, on: leftMist, withKey: AnimationKeys.pulse, completion: nil)
        animationService.run(rightPulseAction, on: rightMist, withKey: AnimationKeys.pulse, completion: nil)
        
        print("✨ AnimationService pulsing started for forest transition areas")
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
        
        print("👁️ Hint emojis added: \\(previousRoomEmoji) ←→ \\(nextRoomEmoji)")
    }
    
    // MARK: - BaseGameScene Template Method Implementation
    override open func handleSceneSpecificTouch(_ touches: Set<UITouch>, with event: UIEvent?) -> Bool {
        guard let touch = touches.first else { return false }
        let location = touch.location(in: self)
        let touchedNode = atPoint(location)
        
        // Check for door interaction (only in Room 1)
        if currentRoom == 1 && touchedNode.name == "back_door" {
            startLongPress(for: touchedNode, at: location)
            return true
        }
        
        // Regular movement with subtle haptic feedback
        let targetCell = gridService.worldToGrid(location)
        if gridService.isCellAvailable(targetCell) {
            // Very light haptic for footsteps
            triggerMovementFeedback()
            
            character.moveToGridCell(targetCell)
            print("👤 Character moving to forest cell \\(targetCell)")
            return true
        }
        
        return false // Let base class handle
    }
    
    override open func handleSceneSpecificLongPress(on node: SKNode, at location: CGPoint) {
        if node.name == "back_door" {
            // Haptic feedback for door interaction
            triggerSuccessFeedback()
            returnToShop()
        }
    }
    
    // MARK: - Long Press System (For Door)
    internal override func startLongPress(for node: SKNode, at location: CGPoint) {
        longPressTarget = node
        longPressTimer = Timer.scheduledTimer(withTimeInterval: longPressDuration, repeats: false) { [weak self] _ in
            self?.handleLongPress(on: node, at: location)
        }
        
        print("🚪 Long press started on door")
    }
    
    internal override func cancelLongPress() {
        longPressTimer?.invalidate()
        longPressTimer = nil
        longPressTarget = nil
    }
    
    private func handleLongPress(on node: SKNode, at location: CGPoint) {
        if node.name == "back_door" {
            // Haptic feedback for door interaction
            transitionService.triggerHapticFeedback(type: .success)
            returnToShop()
        }
        
        longPressTimer = nil
        longPressTarget = nil
    }
    
    // MARK: - Room Transition System (Internal - accessible to extensions)
    private func isNearLeftEdge(_ location: CGPoint) -> Bool {
        return location.x < -worldWidth/2 + 300 // Expanded transition zone (was 100)
    }
    
    private func isNearRightEdge(_ location: CGPoint) -> Bool {
        return location.x > worldWidth/2 - 300 // Expanded transition zone (was 100)
    }
    
    internal func getPreviousRoom() -> Int {
        return currentRoom == 1 ? 5 : currentRoom - 1 // Loop: Room 1 → Room 5
    }
    
    internal func getNextRoom() -> Int {
        return currentRoom == 5 ? 1 : currentRoom + 1 // Loop: Room 5 → Room 1
    }
    
    private func transitionToRoom(_ newRoom: Int) {
        // Prevent multiple transitions
        guard !isTransitioning else { return }
        isTransitioning = true
        transitionCooldown = transitionCooldownDuration
        
        // Dismiss any active dialogue before transitioning
        DialogueService.shared.dismissDialogue()
        
        // Store previous room for character repositioning logic
        let previousRoom = currentRoom
        currentRoom = newRoom
        
        // Use transition service for room transitions
        transitionService.transitionForestRoom(
            in: self,
            from: previousRoom,
            to: newRoom,
            character: character,
            camera: gameCamera,
            gridService: gridService,
            lastTriggeredSide: lastTriggeredSide,
            roomSetupAction: { [weak self] in
                self?.setupCurrentRoom()
            },
            completion: { [weak self] in
                self?.isTransitioning = false
                self?.hasLeftTransitionZone = false
                print("🌲 Room transition complete")
            }
        )
    }

    
    private func returnToShop() {
        print("🏠 Returning to boba shop")
        
        // Dismiss any active dialogue before leaving
        DialogueService.shared.dismissDialogue()
        
        // Use transition service for returning to game
        transitionService.transitionToGame(from: self) {
            print("🏠 Successfully returned to boba shop")
        }
    }
    
    override open func updateSpecificContent(_ currentTime: TimeInterval) {
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
            transitionService.triggerHapticFeedback(type: .light)
            lastTriggeredSide = "left"
            transitionToRoom(getPreviousRoom())
        }
        // Check if character walked into right transition area (entire pulsing zone)
        else if characterPos.x > worldWidth/2 - 133 && lastTriggeredSide != "right" {
            // Haptic feedback for room transition
            transitionService.triggerHapticFeedback(type: .light)
            lastTriggeredSide = "right"
            transitionToRoom(getNextRoom())
        }
    }
}
