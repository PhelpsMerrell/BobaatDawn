//
//  GameScene.swift
//  BobaAtDawn
//
//  Created by Phelps Merrell on 8/18/25.
//

import SpriteKit
import GameplayKit

// MARK: - Main Game Scene
class GameScene: SKScene {
    
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
    
    // MARK: - Interaction System
    private var selectedObject: RotatableObject?
    
    // MARK: - World Areas
    private var shopFloor: SKSpriteNode!
    
    // MARK: - Touch Handling
    private var isHandlingPinch = false
    
    // MARK: - Scene Setup
    override func didMove(to view: SKView) {
        setupCamera()
        setupWorld()
        setupTables()
        setupCharacter()
        setupBrewingStation()
        setupRotatableObjects()
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
    
    private func setupGestures() {
        guard let view = view else { return }
        
        let pinchGesture = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        let rotationGesture = UIRotationGestureRecognizer(target: self, action: #selector(handleRotation(_:)))
        let twoFingerTap = UITapGestureRecognizer(target: self, action: #selector(handleTwoFingerTap(_:)))
        twoFingerTap.numberOfTouchesRequired = 2
        
        view.addGestureRecognizer(pinchGesture)
        view.addGestureRecognizer(rotationGesture)
        view.addGestureRecognizer(twoFingerTap)
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
    
    // MARK: - Touch Handling
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard !isHandlingPinch else { return }
        guard let touch = touches.first else { return }
        let location = touch.location(in: self)
        let touchedNode = atPoint(location)
        
        handleContextTap(at: location, node: touchedNode)
    }
    
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        // No longer needed - context taps are immediate
    }
    
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        // No longer needed - context taps are immediate
    }
    
    private func handleContextTap(at location: CGPoint, node: SKNode) {
        // Check what was tapped and respond contextually
        
        // 1. Check for carried item drop
        if node == character.carriedItem {
            character.dropItem()
            return
        }
        
        // 2. Check for rotatable objects (pickup)
        if let rotatableObj = node as? RotatableObject {
            if rotatableObj.canBeCarried && character.carriedItem == nil {
                character.pickupItem(rotatableObj)
            } else if rotatableObj.name == "table" || rotatableObj == brewingStation {
                // Tables and station: arrange in place (future feature)
                // For now, do nothing with station, allow table selection
                if rotatableObj.name == "table" {
                    selectObjectForArrangement(rotatableObj)
                }
            }
            return
        }
        
        // 3. Check for brewing areas
        if let brewingArea = node as? BrewingArea {
            brewingStation.handleInteraction(brewingArea.areaType, at: location)
            return
        }
        
        // 4. Check for completed drink in brewing station
        if brewingStation.hasCompletedDrink() && 
           (node == brewingStation || node.parent == brewingStation || node.name == "interactable_drink") {
            if character.carriedItem == nil {
                if let completedDrink = brewingStation.takeCompletedDrink() {
                    character.pickupItem(completedDrink)
                }
            }
            return
        }
        
        // 5. Default: Move character to location
        character.moveTo(location, avoiding: tables)
    }
    
    private func selectObjectForArrangement(_ object: RotatableObject) {
        // Clear any previous selection
        selectedObject?.forceHideSelection()
        
        // Select new object (only for arrangement, no visual indicators)
        selectedObject = object
    }
    
    // MARK: - Helper Methods
    private func findRotatableObject(at location: CGPoint) -> RotatableObject? {
        let touchedNode = atPoint(location)
        return touchedNode as? RotatableObject
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
    }
}
