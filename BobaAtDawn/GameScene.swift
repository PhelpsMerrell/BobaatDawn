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
    private var ingredientStations: [IngredientStation] = []
    private var drinkCreator: DrinkCreator!
    private var rotatableObjects: [RotatableObject] = []
    private var tables: [RotatableObject] = []
    
    // MARK: - Time System
    private var timeBreaker: PowerBreaker!
    private var timeWindow: Window!
    
    // MARK: - Interaction System
    private var selectedObject: RotatableObject?
    
    // MARK: - World Areas
    private var shopFloor: SKSpriteNode!
    
    // MARK: - Touch Handling (Pure Long Press System)
    private var longPressTimer: Timer?
    private var longPressTarget: SKNode?
    private let longPressDuration: TimeInterval = 0.8
    private var isHandlingPinch = false
    
    // MARK: - Scene Setup
    override func didMove(to view: SKView) {
        setupCamera()
        setupWorld()
        setupTables()
        setupCharacter()
        setupIngredientStations()
        setupRotatableObjects()
        setupTimeSystem()
        setupPathfinding()
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
        
        // Add shop floor boundary (visual only)
        setupShopFloorBounds()
        
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
    
    private func setupShopFloorBounds() {
        // Main shop floor area - light blue rectangle under brewing stations
        let shopFloorBounds = SKSpriteNode(color: SKColor(red: 0.7, green: 0.85, blue: 1.0, alpha: 0.6), 
                                          size: CGSize(width: 800, height: 400))
        shopFloorBounds.position = CGPoint(x: 0, y: 150)  // Centered under stations
        shopFloorBounds.zPosition = -8
        addChild(shopFloorBounds)
        
        print("🏠 Light blue shop floor added under brewing stations")
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
            tables.append(table)
        }
    }
    
    private func setupCharacter() {
        character = Character()
        character.position = CGPoint(x: 0, y: 0)
        addChild(character)
        
        gameCamera.position = character.position
        gameCamera.setScale(cameraScale)
    }
    
    private func setupIngredientStations() {
        // 5 simple ingredient stations in a row
        let stationTypes: [IngredientStation.StationType] = [.ice, .boba, .foam, .tea, .lid]
        let startX: CGFloat = -300
        let spacing: CGFloat = 120
        
        for (index, type) in stationTypes.enumerated() {
            let station = IngredientStation(type: type)
            station.position = CGPoint(x: startX + CGFloat(index) * spacing, y: 200)
            station.zPosition = 5
            addChild(station)
            ingredientStations.append(station)
        }
        
        // Central drink creator display
        drinkCreator = DrinkCreator()
        drinkCreator.position = CGPoint(x: 0, y: 100)
        drinkCreator.zPosition = 6
        addChild(drinkCreator)
        
        // Initial update
        drinkCreator.updateDrink(from: ingredientStations)
    }
    
    private func setupRotatableObjects() {
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
        
        print("🌅 Time system: Game starts in Day, flows until Dawn completion trips breaker")
    }
    
    private func setupPathfinding() {
        refreshPathfinding()
    }
    
    private func refreshPathfinding() {
        // Collect all obstacles
        var allObstacles = tables
        allObstacles.append(contentsOf: ingredientStations.map { $0 as RotatableObject })
        
        for object in rotatableObjects {
            if object.canBeArranged {
                allObstacles.append(object)
            }
        }
        
        let worldBounds = CGRect(x: -worldWidth/2, y: -worldHeight/2, width: worldWidth, height: worldHeight)
        character.setupPathfinding(with: allObstacles, worldBounds: worldBounds)
    }
    
    private func setupGestures() {
        guard let view = view else { return }
        
        // Clean gesture system - only essential gestures
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
    
    // MARK: - Touch Handling (Pure Long Press System)
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard !isHandlingPinch else { return }
        guard let touch = touches.first else { return }
        let location = touch.location(in: self)
        let touchedNode = atPoint(location)
        
        // Check for long press interactions first
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
        
        // Visual feedback for long press start
        if let rotatable = node as? RotatableObject {
            let pulseAction = SKAction.sequence([
                SKAction.scale(to: 1.05, duration: 0.1),
                SKAction.scale(to: 1.0, duration: 0.1)
            ])
            rotatable.run(pulseAction)
        }
    }
    
    private func cancelLongPress() {
        longPressTimer?.invalidate()
        longPressTimer = nil
        longPressTarget = nil
    }
    
    private func handleLongPress(on node: SKNode, at location: CGPoint) {
        print("🔍 Long press on: \(node.name ?? "unnamed") - \(type(of: node))")
        
        // 1. Drop carried item if long pressing it
        if node == character.carriedItem {
            character.dropItem()
            print("📦 Dropped carried item")
            
        // 2. Power breaker (only works when tripped)
        } else if node == timeBreaker {
            print("⏰ Attempting to toggle time breaker")
            timeBreaker.toggle()
            
        // 3. Ingredient station interactions
        } else if let station = node as? IngredientStation {
            print("🧋 Interacting with \(station.stationType) station")
            station.interact()
            drinkCreator.updateDrink(from: ingredientStations)
            print("🧋 Updated drink display")
            
        // 4. Pick up completed drink
        } else if node.name == "completed_drink_pickup" {
            print("🧋 Attempting to pick up completed drink")
            if character.carriedItem == nil {
                if let completedDrink = drinkCreator.createCompletedDrink(from: ingredientStations) {
                    character.pickupItem(completedDrink)
                    drinkCreator.resetStations(ingredientStations)
                    print("🧋 Picked up completed drink and reset stations")
                }
            } else {
                print("❌ Already carrying something")
            }
            
        // 5. Pick up small objects (drinks, small furniture)
        } else if let rotatable = node as? RotatableObject {
            print("📦 Found rotatable object: \(rotatable.objectType), canBeCarried: \(rotatable.canBeCarried)")
            if rotatable.canBeCarried {
                if character.carriedItem == nil {
                    character.pickupItem(rotatable)
                    print("📦 Picked up \(rotatable.objectType)")
                } else {
                    print("❌ Already carrying something")
                }
            } else {
                print("❌ Cannot carry this object type")
            }
        } else {
            print("🤷‍♂️ No action for this node")
        }
        
        longPressTimer = nil
        longPressTarget = nil
    }
    
    // MARK: - Helper Methods
    private func findInteractableNode(_ node: SKNode) -> SKNode? {
        print("🔎 Checking node: \(node.name ?? "unnamed") - \(type(of: node))")
        
        // Start with the touched node and search up the hierarchy
        var current: SKNode? = node
        var depth = 0
        
        while current != nil && depth < 5 {
            print("🔎 Level \(depth): \(current?.name ?? "unnamed") - \(type(of: current!))")
            
            // 1. Check for power breaker
            if current == timeBreaker {
                print("✅ Found power breaker")
                return timeBreaker
            }
            
            // 2. Check for ingredient stations
            if let station = current as? IngredientStation {
                print("✅ Found ingredient station: \(station.stationType)")
                return station
            }
            
            // 3. Check for completed drink pickup
            if current?.name == "completed_drink_pickup" {
                print("✅ Found completed drink ready for pickup")
                return current
            }
            
            // 4. Check for carried item (to drop)
            if current == character.carriedItem {
                print("✅ Found carried item")
                return character.carriedItem
            }
            
            // 5. Check for pickupable objects
            if let rotatable = current as? RotatableObject {
                print("🔎 Found rotatable: \(rotatable.objectType), canBeCarried: \(rotatable.canBeCarried)")
                if rotatable.canBeCarried {
                    print("✅ Object can be carried")
                    return rotatable
                } else {
                    print("🔎 Object cannot be carried, checking parents...")
                }
            }
            
            current = current?.parent
            depth += 1
        }
        
        print("❌ No interactable found after checking \(depth) levels")
        return nil
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
        
        // Update time system
        TimeManager.shared.update()
    }
}
