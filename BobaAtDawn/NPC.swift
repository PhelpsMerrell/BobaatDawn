//
//  NPCRefactored.swift
//  BobaAtDawn
//
//  Refactored NPC with dependency injection
//

import SpriteKit

// MARK: - NPC State Machine
enum NPCState {
    case entering    // Walking from entrance to shop
    case wandering   // Exploring the shop randomly
    case sitting     // At a table, ready for service
    case satisfied   // Got drink, leaving happy
    case neutral     // Timeout, leaving normally
    case leaving     // Normal exit movement (post-celebration)
}

// MARK: - Forest Animals
enum AnimalType: String, CaseIterable {
    case fox = "🦊"
    case rabbit = "🐰" 
    case hedgehog = "🦔"
    case frog = "🐸"
    case duck = "🦆"
    case bear = "🐻"
    case raccoon = "🦝"
    case squirrel = "🐿️"
    
    // Night visitors (rare)
    case owl = "🦉"
    case bat = "🦇"
    case wolf = "🐺"
    
    static var dayAnimals: [AnimalType] {
        return [.fox, .rabbit, .hedgehog, .frog, .duck, .bear, .raccoon, .squirrel]
    }
    
    static var nightAnimals: [AnimalType] {
        return [.owl, .bat, .wolf]
    }
    
    static func random(isNight: Bool = false) -> AnimalType {
        let pool = isNight ? nightAnimals : dayAnimals
        return pool.randomElement() ?? .fox
    }
}

// MARK: - NPC Class with Dependency Injection
class NPC: SKLabelNode {
    
    // MARK: - Dependencies
    private let gridService: GridService
    private let npcService: NPCService
    
    // MARK: - Properties
    private(set) var state: NPCState = .entering
    private(set) var animalType: AnimalType
    private(set) var gridPosition: GridCoordinate
    
    // Timers
    private var stateTimer: TimeInterval = 0
    private var totalLifetime: TimeInterval = 0
    
    // Behavior
    private var currentTable: RotatableObject?
    private var carriedDrink: RotatableObject?
    private var targetCell: GridCoordinate?
    
    // Movement
    private let moveSpeed: TimeInterval = GameConfig.NPC.moveSpeed
    private var isMoving: Bool = false
    
    // Enhanced sitting behavior
    private var hasCheckedForDrink: Bool = false
    private var gotDrink: Bool = false
    private var drinkReceivedTime: TimeInterval = 0
    
    // MARK: - Initialization with Dependency Injection
    init(animal: AnimalType? = nil, 
         startPosition: GridCoordinate? = nil,
         gridService: GridService,
         npcService: NPCService) {
        
        // Inject dependencies
        self.gridService = gridService
        self.npcService = npcService
        
        // Choose random animal if not specified
        self.animalType = animal ?? AnimalType.random()
        
        // Default start position (at front door)
        let doorPosition = GameConfig.World.doorPosition
        self.gridPosition = startPosition ?? doorPosition
        
        super.init()
        
        // Setup visual
        text = animalType.rawValue
        fontSize = GameConfig.NPC.fontSize
        fontName = GameConfig.NPC.fontName
        horizontalAlignmentMode = .center
        verticalAlignmentMode = .center
        zPosition = GameConfig.NPC.zPosition
        
        // Position in world using injected grid service
        position = gridService.gridToWorld(gridPosition)
        
        // Reserve grid cell using injected grid service
        gridService.reserveCell(gridPosition)
        
        print("🦊 NPC \(animalType.rawValue) spawned at grid \(gridPosition), world \(position)")
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Update Loop
    func update(deltaTime: TimeInterval) {
        stateTimer += deltaTime
        totalLifetime += deltaTime
        
        // State machine progression
        switch state {
        case .entering:
            updateEntering()
        case .wandering:
            updateWandering()
        case .sitting:
            updateSitting()
        case .satisfied, .neutral, .leaving:
            updateLeaving()
        }
        
        // Safety timeout
        if totalLifetime > GameConfig.NPC.maxLifetime {
            startLeaving(satisfied: false)
        }
    }
    
    // MARK: - State Updates (Using Injected Services)
    private func updateEntering() {
        let enteringDuration = Double.random(in: GameConfig.NPC.enteringDuration.min...GameConfig.NPC.enteringDuration.max)
        if stateTimer > enteringDuration {
            transitionToWandering()
        } else if !isMoving {
            moveToRandomNearbyCell()
        }
    }
    
    private func updateWandering() {
        let wanderingDuration = Double.random(in: GameConfig.NPC.wanderingDuration.min...GameConfig.NPC.wanderingDuration.max)
        if stateTimer > wanderingDuration {
            if findAndMoveToTable() {
                transitionToSitting()
            } else {
                stateTimer -= 10
            }
        } else if !isMoving {
            if Int(stateTimer * 2) % 8 == 0 {
                if Int.random(in: 1...4) == 1 {
                    moveToRandomNearbyCell()
                }
            }
        }
    }
    
    private func updateSitting() {
        let checkDelay = Double.random(in: GameConfig.NPC.sittingTimeout.min/4...GameConfig.NPC.sittingTimeout.max/4)
        if (stateTimer < 1.0 || (stateTimer > checkDelay && !hasCheckedForDrink)) && currentTable != nil {
            checkForDrinkOnTable()
            if stateTimer >= 1.0 {
                hasCheckedForDrink = true
            }
        }
        
        let enjoymentTime = Double.random(in: GameConfig.NPC.drinkEnjoymentTime.min...GameConfig.NPC.drinkEnjoymentTime.max)
        if gotDrink && stateTimer > drinkReceivedTime + enjoymentTime {
            startLeaving(satisfied: true)
            return
        }
        
        let sittingTimeout = Double.random(in: GameConfig.NPC.sittingTimeout.min...GameConfig.NPC.sittingTimeout.max)
        if stateTimer > sittingTimeout {
            startLeaving(satisfied: false)
        }
    }
    
    private func updateLeaving() {
        if Int(stateTimer * 10) % 15 == 0 {
            if npcService.isNearExit(gridPosition) {
                removeSelf()
            } else {
                moveTowardExit()
            }
        }
    }
    
    // MARK: - Movement System (Using Injected Grid Service)
    private func moveToCell(_ targetCell: GridCoordinate) {
        guard targetCell.isValid() else { return }
        guard gridService.isCellAvailable(targetCell) else { return }
        guard !isMoving else { return }
        
        isMoving = true
        self.targetCell = targetCell
        
        gridService.freeCell(gridPosition)
        gridService.reserveCell(targetCell)
        gridPosition = targetCell
        
        let worldPos = gridService.gridToWorld(targetCell)
        let moveAction = SKAction.move(to: worldPos, duration: moveSpeed)
        moveAction.timingMode = .easeInEaseOut
        
        run(moveAction) { [weak self] in
            self?.isMoving = false
            self?.targetCell = nil
        }
    }
    
    private func moveToRandomNearbyCell() {
        let radius = Int.random(in: 1...GameConfig.NPC.wanderRadius)
        let candidates = npcService.generateCandidateCells(from: gridPosition, radius: radius)
        
        if let randomCell = candidates.randomElement() {
            moveToCell(randomCell)
        }
    }
    
    // MARK: - Table System (Using Injected Services)
    private func findAndMoveToTable() -> Bool {
        guard let scene = parent as? SKScene else { return false }
        
        let availableTables = npcService.findAvailableTables(in: scene)
        
        if availableTables.isEmpty {
            print("🦊 No tables found in scene")
            return false
        }
        
        if let chosenTable = availableTables.randomElement() {
            let tableGridPos = gridService.worldToGrid(chosenTable.position)
            let adjacentCells = gridService.getAvailableAdjacentCells(to: tableGridPos)
            
            if let sittingSpot = adjacentCells.randomElement() {
                currentTable = chosenTable
                moveToCell(sittingSpot)
                print("🦊 \(animalType.rawValue) moving to sit at table at \(tableGridPos)")
                return true
            }
        }
        
        print("🦊 \(animalType.rawValue) couldn't find available seating")
        return false
    }
    
    private func checkForDrinkOnTable() {
        guard let table = currentTable else { return }
        
        let drinksOnTable = table.children.filter { $0.name == "drink_on_table" }
        
        if let drink = drinksOnTable.first {
            print("🦊 ✨ \(animalType.rawValue) found drink on table!")
            pickupDrinkFromTable(drink)
            gotDrink = true
            drinkReceivedTime = stateTimer
            print("🦊 \(animalType.rawValue) will enjoy drink for 5-10 seconds before leaving")
        } else {
            print("🦊 \(animalType.rawValue) sitting at table with no drinks - waiting for service")
        }
    }
    
    private func pickupDrinkFromTable(_ drink: SKNode) {
        drink.removeFromParent()
        
        let carriedDrink = createCarriedDrink(from: drink)
        carriedDrink.position = GameConfig.NPC.CarriedDrink.carryOffset
        carriedDrink.zPosition = 1
        addChild(carriedDrink)
        
        let floatAction = SKAction.repeatForever(
            SKAction.sequence([
                SKAction.moveBy(x: 0, y: GameConfig.NPC.CarriedDrink.floatDistance, duration: GameConfig.NPC.CarriedDrink.floatDuration),
                SKAction.moveBy(x: 0, y: -GameConfig.NPC.CarriedDrink.floatDistance, duration: GameConfig.NPC.CarriedDrink.floatDuration)
            ])
        )
        carriedDrink.run(floatAction, withKey: "floating")
        
        self.carriedDrink = carriedDrink as? RotatableObject
        
        print("🦊 ✨ \(animalType.rawValue) picked up drink from table!")
    }
    
    private func createCarriedDrink(from tableDrink: SKNode) -> SKNode {
        let carriedVersion = SKSpriteNode(color: .brown, size: GameConfig.NPC.CarriedDrink.size)
        
        let lid = SKSpriteNode(color: .lightGray, size: GameConfig.NPC.CarriedDrink.lidSize)
        lid.position = GameConfig.NPC.CarriedDrink.lidOffset
        carriedVersion.addChild(lid)
        
        let straw = SKSpriteNode(color: .white, size: GameConfig.NPC.CarriedDrink.strawSize)
        straw.position = GameConfig.NPC.CarriedDrink.strawOffset
        carriedVersion.addChild(straw)
        
        return carriedVersion
    }
    
    // MARK: - Exit System (Using Injected Services)
    private func moveTowardExit() {
        if let targetCell = npcService.findPathToExit(from: gridPosition) {
            moveToCell(targetCell)
            print("🦊 \(animalType.rawValue) (\(state)) moving toward exit from \(gridPosition)")
        }
    }
    
    // MARK: - State Transitions & Animations
    private func transitionToWandering() {
        state = .wandering
        stateTimer = 0
        print("🦊 \(animalType.rawValue) started wandering")
    }
    
    private func transitionToSitting() {
        state = .sitting
        stateTimer = 0
        hasCheckedForDrink = false
        gotDrink = false
        drinkReceivedTime = 0
        print("🦊 \(animalType.rawValue) sat down at table and is browsing peacefully")
    }
    
    func startLeaving(satisfied: Bool) {
        state = satisfied ? .satisfied : .neutral
        stateTimer = 0
        
        if satisfied {
            startHappyAnimation()
            print("🦊 \(animalType.rawValue) leaving satisfied! ✨")
            
            let shimmerDuration = Double.random(in: GameConfig.NPC.Animations.happyCelebrationTime.min...GameConfig.NPC.Animations.happyCelebrationTime.max)
            DispatchQueue.main.asyncAfter(deadline: .now() + shimmerDuration) { [weak self] in
                self?.stopHappyAnimationAndProceedToExit()
            }
        } else {
            startNeutralAnimation()
            print("🦊 \(animalType.rawValue) leaving neutral")
        }
        
        currentTable = nil
    }
    
    private func startHappyAnimation() {
        removeAction(forKey: "happy_shimmer")
        removeAction(forKey: "happy_shake")
        removeAction(forKey: "happy_scale")
        
        let shimmer = SKAction.repeatForever(
            SKAction.sequence([
                SKAction.scale(to: GameConfig.NPC.Animations.shimmerScaleAmount, duration: GameConfig.NPC.Animations.shimmerDuration),
                SKAction.scale(to: 1.0, duration: GameConfig.NPC.Animations.shimmerDuration)
            ])
        )
        run(shimmer, withKey: "happy_shimmer")
        
        let shake = SKAction.repeatForever(
            SKAction.sequence([
                SKAction.moveBy(x: -GameConfig.NPC.Animations.shakeDistance, y: 0, duration: GameConfig.NPC.Animations.shakeDuration),
                SKAction.moveBy(x: GameConfig.NPC.Animations.shakeDistance * 2, y: 0, duration: GameConfig.NPC.Animations.shakeDuration),
                SKAction.moveBy(x: -GameConfig.NPC.Animations.shakeDistance * 2, y: 0, duration: GameConfig.NPC.Animations.shakeDuration),
                SKAction.moveBy(x: GameConfig.NPC.Animations.shakeDistance, y: 0, duration: GameConfig.NPC.Animations.shakeDuration)
            ])
        )
        run(shake, withKey: "happy_shake")
        
        let colorFlash = SKAction.repeatForever(
            SKAction.sequence([
                SKAction.colorize(with: .yellow, colorBlendFactor: 0.3, duration: GameConfig.NPC.Animations.colorFlashDuration),
                SKAction.colorize(withColorBlendFactor: 0.0, duration: GameConfig.NPC.Animations.colorFlashDuration),
                SKAction.colorize(with: .white, colorBlendFactor: 0.2, duration: GameConfig.NPC.Animations.colorFlashDuration),
                SKAction.colorize(withColorBlendFactor: 0.0, duration: GameConfig.NPC.Animations.colorFlashDuration)
            ])
        )
        run(colorFlash, withKey: "happy_flash")
        
        print("✨ \(animalType.rawValue) is VERY HAPPY with shimmer + shake + flash effects!")
    }
    
    private func startNeutralAnimation() {
        removeAction(forKey: "neutral_sigh")
        
        let sigh = SKAction.repeatForever(
            SKAction.sequence([
                SKAction.scale(to: GameConfig.NPC.Animations.neutralScaleAmount, duration: GameConfig.NPC.Animations.neutralSighDuration),
                SKAction.scale(to: 1.0, duration: GameConfig.NPC.Animations.neutralSighDuration)
            ])
        )
        run(sigh, withKey: "neutral_sigh")
        
        let grayTint = SKAction.colorize(with: .gray, colorBlendFactor: GameConfig.NPC.Animations.neutralGrayBlend, duration: GameConfig.NPC.Animations.neutralFadeDuration)
        run(grayTint, withKey: "neutral_tint")
        
        print("😐 \(animalType.rawValue) is leaving disappointed (no drink)")
    }
    
    private func stopHappyAnimation() {
        removeAction(forKey: "happy_shimmer")
        removeAction(forKey: "happy_shake")
        removeAction(forKey: "happy_flash")
        
        let resetAction = SKAction.group([
            SKAction.scale(to: 1.0, duration: GameConfig.NPC.Animations.resetDuration),
            SKAction.move(to: position, duration: GameConfig.NPC.Animations.resetDuration),
            SKAction.colorize(withColorBlendFactor: 0.0, duration: GameConfig.NPC.Animations.resetDuration)
        ])
        run(resetAction)
    }
    
    private func stopHappyAnimationAndProceedToExit() {
        stopHappyAnimation()
        state = .leaving
        stateTimer = 0
        print("✨ \(animalType.rawValue) finished celebrating, now proceeding to exit normally")
        moveTowardExit()
    }
    
    private func stopNeutralAnimation() {
        removeAction(forKey: "neutral_sigh")
        removeAction(forKey: "neutral_tint")
        
        let resetAction = SKAction.group([
            SKAction.scale(to: 1.0, duration: GameConfig.NPC.Animations.resetDuration),
            SKAction.colorize(withColorBlendFactor: 0.0, duration: GameConfig.NPC.Animations.resetDuration)
        ])
        run(resetAction)
    }
    
    // MARK: - Lifecycle (Using Injected Services)
    private func removeSelf() {
        if state == .satisfied {
            stopHappyAnimation()
        } else if state == .neutral {
            stopNeutralAnimation()
        }
        
        if let drink = carriedDrink {
            drink.removeFromParent()
        }
        
        gridService.freeCell(gridPosition)
        removeFromParent()
        
        print("🦊 \(animalType.rawValue) left the shop")
    }
    
    // MARK: - Debug
    func getStateInfo() -> String {
        return "\(animalType.rawValue) - \(state) - \(Int(stateTimer))s"
    }
}
