//
//  GameScene.swift
//  BobaAtDawn
//
//  Created by Phelps Merrell on 8/18/25.
//

import SpriteKit
import GameplayKit

// MARK: - Main Game Scene
class GameScene: SKScene, UIGestureRecognizerDelegate {
    
    // MARK: - Camera System
    private var gameCamera: SKCameraNode!
    private let cameraLerpSpeed: CGFloat = 2.0
    private var cameraScale: CGFloat = 1.0
    private let minZoom: CGFloat = 0.3
    private let maxZoom: CGFloat = 1.5
    private var lastPinchScale: CGFloat = 1.0
    
    // MARK: - World Settings
    private let worldWidth: CGFloat = 2000
    private let worldHeight: CGFloat = 1500
    
    // MARK: - Game Objects
    private var character: Character!
    private var brewingStation: BobaBrewingStation!
    private var rotatableObjects: [RotatableObject] = []
    private var tables: [RotatableObject] = []
    
    // MARK: - Time System
    private var timeBreaker: PowerBreaker!
    private var timeWindow: Window!
    
    // MARK: - Interaction System
    private var selectedObject: RotatableObject?
    
    // MARK: - World Areas
    private var shopFloor: SKSpriteNode!
    
    // MARK: - Touch Handling
    private var longPressTimer: Timer?
    private var longPressTarget: SKNode?
    private let longPressDuration: TimeInterval = 0.8
    private var isHandlingPinch = false
    private var isHandlingSwipe = false
    
    // MARK: - Scene Setup
    override func didMove(to view: SKView) {
        setupCamera()
        setupWorld()
        setupTables()
        setupCharacter()
        setupBrewingStation()
        setupRotatableObjects()
        setupTimeSystem() // Setup day/night cycle
        setupPathfinding() // Setup pathfinding after all objects are created
        setupGestures()
    }
    
    private func setupCamera() {
        gameCamera = SKCameraNode()
        camera = gameCamera
        addChild(gameCamera)
    }
    
    private func setupWorld() {
        backgroundColor = SKColor(red: 0.9, green: 0.8, blue: 0.7, alpha: 1.0)
        
        shopFloor = SKSpriteNode(color: SKColor(red: 0.8, green: 0.7, blue: 0.6, alpha: 1.0), size: CGSize(width: worldWidth, height: worldHeight))
        shopFloor.position = CGPoint(x: 0, y: 0)
        shopFloor.zPosition = -10
        addChild(shopFloor)
        
        // Add shop walls
        let wallTop = SKSpriteNode(color: SKColor(red: 0.5, green: 0.3, blue: 0.2, alpha: 1.0), size: CGSize(width: worldWidth, height: 40))
        wallTop.position = CGPoint(x: 0, y: worldHeight/2 - 20)
        wallTop.zPosition = -5
        addChild(wallTop)
        
        let wallBottom = SKSpriteNode(color: SKColor(red: 0.5, green: 0.3, blue: 0.2, alpha: 1.0), size: CGSize(width: worldWidth, height: 40))
        wallBottom.position = CGPoint(x: 0, y: -worldHeight/2 + 20)
        wallBottom.zPosition = -5
        addChild(wallBottom)
        
        let wallLeft = SKSpriteNode(color: SKColor(red: 0.5, green: 0.3, blue: 0.2, alpha: 1.0), size: CGSize(width: 40, height: worldHeight))
        wallLeft.position = CGPoint(x: -worldWidth/2 + 20, y: 0)
        wallLeft.zPosition = -5
        addChild(wallLeft)
        
        let wallRight = SKSpriteNode(color: SKColor(red: 0.5, green: 0.3, blue: 0.2, alpha: 1.0), size: CGSize(width: 40, height: worldHeight))
        wallRight.position = CGPoint(x: worldWidth/2 - 20, y: 0)
        wallRight.zPosition = -5
        addChild(wallRight)
    }
    
    private func setupTables() {
        let tablePositions = [
            CGPoint(x: 300, y: 300),
            CGPoint(x: -400, y: -200),
            CGPoint(x: 500, y: -300),
            CGPoint(x: -200, y: 400),
            CGPoint(x: 600, y: 100),
            CGPoint(x: -600, y: 0),
            CGPoint(x: 0, y: -400),
            CGPoint(x: 200, y: 0),
            CGPoint(x: -100, y: -100)
        ]
        
        for position in tablePositions {
            // Create table as movable furniture (arrange-mode only)
            let table = RotatableObject(type: .furniture, color: SKColor(red: 0.4, green: 0.2, blue: 0.1, alpha: 1.0), shape: "table")
            table.position = position
            table.zPosition = 1
            table.name = "table"
            
            // Add physics body for pathfinding obstacles
            table.physicsBody = SKPhysicsBody(rectangleOf: table.size)
            table.physicsBody?.isDynamic = false
            table.physicsBody?.categoryBitMask = 1
            table.physicsBody?.collisionBitMask = 2
            
            addChild(table)
            rotatableObjects.append(table)
            tables.append(table) // Keep tables array for pathfinding reference
        }
    }
    
    private func setupCharacter() {
        character = Character()
        character.position = CGPoint(x: 0, y: 0)
        addChild(character)
        
        gameCamera.position = character.position
        gameCamera.setScale(cameraScale)
    }
    
    private func setupPathfinding() {
        refreshPathfinding()
    }
    
    private func refreshPathfinding() {
        // Collect all obstacles (tables + large objects)
        var allObstacles = tables
        
        // Add brewing station as obstacle
        allObstacles.append(brewingStation)
        
        // Add any large rotatable objects as obstacles
        for object in rotatableObjects {
            if object.canBeArranged {
                allObstacles.append(object)
            }
        }
        
        // Setup pathfinding with all obstacles
        let worldBounds = CGRect(x: -worldWidth/2, y: -worldHeight/2, width: worldWidth, height: worldHeight)
        character.setupPathfinding(with: allObstacles, worldBounds: worldBounds)
    }
    
    private func setupBrewingStation() {
        brewingStation = BobaBrewingStation()
        brewingStation.position = CGPoint(x: -300, y: 200)
        brewingStation.zPosition = 5
        // Station is always powered now - no power system
        brewingStation.setPowered(true)
        addChild(brewingStation)
    }
    
    private func setupRotatableObjects() {
        // Create various rotatable objects for testing
        let objectConfigs = [
            (position: CGPoint(x: 400, y: 200), type: ObjectType.furniture, color: SKColor.red, shape: "arrow"),
            (position: CGPoint(x: -500, y: -100), type: ObjectType.furniture, color: SKColor.blue, shape: "L"),
            (position: CGPoint(x: 100, y: -200), type: ObjectType.drink, color: SKColor.green, shape: "triangle"),
            (position: CGPoint(x: -100, y: 300), type: ObjectType.furniture, color: SKColor.orange, shape: "rectangle")
        ]
        
        for config in objectConfigs {
            let obj = RotatableObject(type: config.type, color: config.color, shape: config.shape)
            obj.position = config.position
            obj.zPosition = 3
            addChild(obj)
            rotatableObjects.append(obj)
        }
    }
    
    private func setupTimeSystem() {
        // Create time control breaker (upper-left)
        timeBreaker = PowerBreaker()
        timeBreaker.position = CGPoint(x: -worldWidth/2 + 100, y: worldHeight/2 - 100)
        timeBreaker.zPosition = 10
        addChild(timeBreaker)
        
        // Create time window (upper-right)
        timeWindow = Window()
        timeWindow.position = CGPoint(x: worldWidth/2 - 100, y: worldHeight/2 - 100)
        timeWindow.zPosition = 10
        addChild(timeWindow)
        
        print("🌅 Time system initialized - game starts in dawn, use time breaker to activate cycle")
    }
    
    private func setupGestures() {
        guard let view = view else { return }
        
        let pinchGesture = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        let rotationGesture = UIRotationGestureRecognizer(target: self, action: #selector(handleRotation(_:)))
        let twoFingerTap = UITapGestureRecognizer(target: self, action: #selector(handleTwoFingerTap(_:)))
        twoFingerTap.numberOfTouchesRequired = 2
        
        // Add swipe gesture for pickup/drop
        let panGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        panGesture.delegate = self
        
        view.addGestureRecognizer(pinchGesture)
        view.addGestureRecognizer(rotationGesture)
        view.addGestureRecognizer(twoFingerTap)
        view.addGestureRecognizer(panGesture)
    }
    
    // MARK: - Gesture Handlers
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
    
    @objc private func handleRotation(_ gesture: UIRotationGestureRecognizer) {
        guard gesture.state == .ended else { return }
        
        // Rotate carried items or selected objects
        if character.isCarrying {
            character.rotateCarriedItem()
        } else if let selected = selectedObject {
            selected.rotateToNextState()
        }
    }
    
    @objc private func handleTwoFingerTap(_ gesture: UITapGestureRecognizer) {
        // Reset camera zoom
        cameraScale = 1.0
        let zoomAction = SKAction.scale(to: cameraScale, duration: 0.3)
        gameCamera.run(zoomAction)
    }
    
    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard !isHandlingPinch else { return }
        
        switch gesture.state {
        case .began:
            isHandlingSwipe = true
            
        case .ended:
            if isHandlingSwipe {
                let velocity = gesture.velocity(in: view)
                let location = gesture.location(in: view)
                let sceneLocation = convertPoint(fromView: location)
                handleSwipeGesture(at: sceneLocation, velocity: velocity)
            }
            isHandlingSwipe = false
            
        case .cancelled, .failed:
            isHandlingSwipe = false
            
        default:
            break
        }
    }
    
    // MARK: - Touch Handling
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard !isHandlingPinch && !isHandlingSwipe else { return }
        guard let touch = touches.first else { return }
        let location = touch.location(in: self)
        let touchedNode = atPoint(location)
        
        // Check for long press interactions (brewing, power, etc.)
        if let interactable = findInteractableNode(touchedNode) {
            startLongPress(for: interactable, at: location)
        } else {
            // Single tap = movement only
            character.moveTo(location, avoiding: tables)
        }
    }
    
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        cancelLongPress()
    }
    
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        cancelLongPress()
    }
    
    // MARK: - Long Press System
    private func startLongPress(for node: SKNode, at location: CGPoint) {
        longPressTarget = node
        longPressTimer = Timer.scheduledTimer(withTimeInterval: longPressDuration, repeats: false) { [weak self] _ in
            self?.handleLongPress(on: node, at: location)
        }
    }
    
    private func cancelLongPress() {
        longPressTimer?.invalidate()
        longPressTimer = nil
        longPressTarget = nil
    }
    
    // MARK: - Swipe System (Pickup/Drop)
    private func handleSwipeGesture(at location: CGPoint, velocity: CGPoint) {
        let swipeThreshold: CGFloat = 100 // Minimum velocity for swipe detection
        let proximityDistance: CGFloat = 100 // "Next to character" distance
        
        guard sqrt(velocity.x * velocity.x + velocity.y * velocity.y) > swipeThreshold else {
            return // Not a strong enough swipe
        }
        
        // Calculate swipe direction relative to character
        let characterPos = character.position
        let swipeDirection = CGPoint(x: velocity.x, y: velocity.y)
        let directionToCharacter = CGPoint(x: characterPos.x - location.x, y: characterPos.y - location.y)
        
        // Dot product to determine if swipe is toward or away from character
        let dotProduct = swipeDirection.x * directionToCharacter.x + swipeDirection.y * directionToCharacter.y
        
        if character.isCarrying {
            // Character is carrying something - swipe to drop
            if dotProduct < 0 { // Swipe away from character
                handleSwipeDrop(at: location, velocity: swipeDirection)
            }
        } else {
            // Character not carrying - check for pickup
            if dotProduct > 0 { // Swipe toward character
                handleSwipePickup(at: location, proximityDistance: proximityDistance)
            }
        }
    }
    
    private func handleSwipePickup(at location: CGPoint, proximityDistance: CGFloat) {
        // Find nearby objects that can be picked up
        let nearbyObjects = findNearbyPickupableObjects(near: character.position, within: proximityDistance)
        
        if let closestObject = nearbyObjects.first {
            // Animate object flying to character
            let flyAction = SKAction.move(to: character.position, duration: 0.3)
            flyAction.timingMode = .easeOut
            
            closestObject.run(flyAction) { [weak self] in
                self?.character.pickupItem(closestObject)
            }
        }
    }
    
    private func handleSwipeDrop(at location: CGPoint, velocity: CGPoint) {
        guard let carriedItem = character.carriedItem else { return }
        
        // Calculate drop position (not too far from character)
        let characterPos = character.position
        let maxDropDistance: CGFloat = 80
        
        let normalizedVelocity = normalizeVector(velocity)
        let dropPosition = CGPoint(
            x: characterPos.x + normalizedVelocity.x * maxDropDistance,
            y: characterPos.y + normalizedVelocity.y * maxDropDistance
        )
        
        // Drop the item at the calculated position
        character.dropItem()
        
        // Animate to drop position
        let dropAction = SKAction.move(to: dropPosition, duration: 0.3)
        dropAction.timingMode = .easeOut
        carriedItem.run(dropAction)
    }
    
    private func handleLongPress(on node: SKNode, at location: CGPoint) {
        if node == character.carriedItem {
            character.dropItem()
        } else if node == timeBreaker {
            // Toggle time system
            timeBreaker.toggle()
        } else if let brewingArea = node as? BrewingArea {
            brewingStation.handleInteraction(brewingArea.areaType, at: location)
        } else if node.name == "interactable_drink" {
            // Handle completed drink pickup from brewing station
            if let completedDrink = brewingStation.takeCompletedDrink() {
                character.pickupItem(completedDrink)
            }
        } else if brewingStation.hasCompletedDrink() && 
                  (node == brewingStation || node.parent == brewingStation) {
            if character.carriedItem == nil {
                if let completedDrink = brewingStation.takeCompletedDrink() {
                    character.pickupItem(completedDrink)
                }
            }
        }
        
        longPressTimer = nil
        longPressTarget = nil
    }
    
    // MARK: - Helper Methods
    private func findInteractableNode(_ node: SKNode) -> SKNode? {
        // Check for time breaker
        if node == timeBreaker {
            return timeBreaker
        }
        
        // Check for brewing areas
        if let brewingArea = node as? BrewingArea {
            return brewingArea
        }
        
        // Check for completed drink in brewing station
        if node.name?.contains("interactable") == true {
            return node
        }
        
        // Check brewing station with completed drink
        if brewingStation.hasCompletedDrink() && 
           (node == brewingStation || node.parent == brewingStation) {
            return node
        }
        
        // Check for carried item
        if node == character.carriedItem {
            return character.carriedItem
        }
        
        // Search through node hierarchy
        var current: SKNode? = node
        while current != nil {
            if current is BrewingArea {
                return current
            }
            current = current?.parent
        }
        
        return nil
    }
    
    private func findNearbyPickupableObjects(near position: CGPoint, within distance: CGFloat) -> [RotatableObject] {
        var nearbyObjects: [RotatableObject] = []
        
        // Check all rotatable objects
        for object in rotatableObjects {
            if object.canBeCarried {
                let objectDistance = sqrt(pow(object.position.x - position.x, 2) + pow(object.position.y - position.y, 2))
                if objectDistance <= distance {
                    nearbyObjects.append(object)
                }
            }
        }
        
        // Sort by distance (closest first)
        nearbyObjects.sort { obj1, obj2 in
            let dist1 = sqrt(pow(obj1.position.x - position.x, 2) + pow(obj1.position.y - position.y, 2))
            let dist2 = sqrt(pow(obj2.position.x - position.x, 2) + pow(obj2.position.y - position.y, 2))
            return dist1 < dist2
        }
        
        return nearbyObjects
    }
    
    private func normalizeVector(_ vector: CGPoint) -> CGPoint {
        let magnitude = sqrt(vector.x * vector.x + vector.y * vector.y)
        guard magnitude > 0 else { return CGPoint(x: 0, y: 0) }
        return CGPoint(x: vector.x / magnitude, y: vector.y / magnitude)
    }
    
    private func findRotatableObject(at location: CGPoint) -> RotatableObject? {
        let touchedNode = atPoint(location)
        return touchedNode as? RotatableObject
    }
    
    // MARK: - Gesture Delegate
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        // Allow pan gesture to work alongside pinch and rotation
        return true
    }
    
    // MARK: - Camera Update
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
        
        let restaurantLeft = -worldWidth/2 + 80
        let restaurantRight = worldWidth/2 - 80
        let restaurantBottom = -worldHeight/2 + 80
        let restaurantTop = worldHeight/2 - 80
        
        let clampedX = max(restaurantLeft + halfViewWidth, min(restaurantRight - halfViewWidth, newX))
        let clampedY = max(restaurantBottom + halfViewHeight, min(restaurantTop - halfViewHeight, newY))
        
        gameCamera.position = CGPoint(x: clampedX, y: clampedY)
    }
    
    // MARK: - Update Loop
    override func update(_ currentTime: TimeInterval) {
        updateCamera()
        character.update()
        brewingStation?.update()
        
        // Update time system
        TimeManager.shared.update()
    }
}
