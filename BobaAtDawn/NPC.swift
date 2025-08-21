//
//  NPC.swift
//  BobaAtDawn
//
//  Forest animal customers for the boba shop
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

// MARK: - NPC Class
class NPC: SKLabelNode {
    
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
    
    // MARK: - Initialization
    init(animal: AnimalType? = nil, startPosition: GridCoordinate? = nil) {
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
        
        // Position in world
        position = GridWorld.shared.gridToWorld(gridPosition)
        
        // Reserve grid cell
        reserveCurrentCell()
        
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
        
        // Safety timeout - remove NPCs that have been around too long
        if totalLifetime > GameConfig.NPC.maxLifetime { // Configuration-based timeout
            startLeaving(satisfied: false)
        }
    }
    
    // MARK: - State Updates
    private func updateEntering() {
        // Walk toward center of shop for configured duration
        let enteringDuration = Double.random(in: GameConfig.NPC.enteringDuration.min...GameConfig.NPC.enteringDuration.max)
        if stateTimer > enteringDuration {
            transitionToWandering()
        } else if !isMoving {
            // Move toward shop center randomly
            moveToRandomNearbyCell()
        }
    }
    
    private func updateWandering() {
        // Wander for configured duration, then try to sit
        let wanderingDuration = Double.random(in: GameConfig.NPC.wanderingDuration.min...GameConfig.NPC.wanderingDuration.max)
        if stateTimer > wanderingDuration {
            if findAndMoveToTable() {
                transitionToSitting()
            } else {
                // No tables available, keep wandering a bit more
                stateTimer -= 10 // Reset timer, try again soon
            }
        } else if !isMoving {
            // More natural wandering - pause more often, move occasionally
            if Int(stateTimer * 2) % 8 == 0 { // Every 4 seconds
                if Int.random(in: 1...4) == 1 { // 25% chance to move
                    moveToRandomNearbyCell()
                }
                // 75% chance to pause and look around like browsing customers
            }
        }
    }
    
    private func updateSitting() {
        // Check for drinks immediately when sitting, then again after peaceful sitting
        let checkDelay = Double.random(in: GameConfig.NPC.sittingTimeout.min/4...GameConfig.NPC.sittingTimeout.max/4)
        if (stateTimer < 1.0 || (stateTimer > checkDelay && !hasCheckedForDrink)) && currentTable != nil {
            checkForDrinkOnTable()
            if stateTimer >= 1.0 { // Only mark as checked if it's the delayed check
                hasCheckedForDrink = true
            }
        }
        
        // If they got a drink, enjoy it for configured time before leaving
        let enjoymentTime = Double.random(in: GameConfig.NPC.drinkEnjoymentTime.min...GameConfig.NPC.drinkEnjoymentTime.max)
        if gotDrink && stateTimer > drinkReceivedTime + enjoymentTime {
            startLeaving(satisfied: true)
            return
        }
        
        // Longer timeout - customers are patient in cozy shop
        let sittingTimeout = Double.random(in: GameConfig.NPC.sittingTimeout.min...GameConfig.NPC.sittingTimeout.max)
        if stateTimer > sittingTimeout {
            // Timeout - leave neutral
            startLeaving(satisfied: false)
        }
    }
    
    private func checkForDrinkOnTable() {
        guard let table = currentTable else { return }
        
        // Look for drinks on the table
        let drinksOnTable = table.children.filter { $0.name == "drink_on_table" }
        
        if let drink = drinksOnTable.first {
            print("🦊 ✨ \(animalType.rawValue) found drink on table!")
            
            // Pick up the drink (move it above NPC's head)
            pickupDrinkFromTable(drink)
            
            // Mark that they got a drink and record time
            gotDrink = true
            drinkReceivedTime = stateTimer
            
            print("🦊 \(animalType.rawValue) will enjoy drink for 5-10 seconds before leaving")
        } else {
            print("🦊 \(animalType.rawValue) sitting at table with no drinks - waiting for service")
        }
    }
    
    private func pickupDrinkFromTable(_ drink: SKNode) {
        // Remove drink from table
        drink.removeFromParent()
        
        // Create carried drink above NPC's head
        let carriedDrink = createCarriedDrink(from: drink)
        carriedDrink.position = GameConfig.NPC.CarriedDrink.carryOffset
        carriedDrink.zPosition = 1
        addChild(carriedDrink)
        
        // Add floating animation
        let floatAction = SKAction.repeatForever(
            SKAction.sequence([
                SKAction.moveBy(x: 0, y: GameConfig.NPC.CarriedDrink.floatDistance, duration: GameConfig.NPC.CarriedDrink.floatDuration),
                SKAction.moveBy(x: 0, y: -GameConfig.NPC.CarriedDrink.floatDistance, duration: GameConfig.NPC.CarriedDrink.floatDuration)
            ])
        )
        carriedDrink.run(floatAction, withKey: "floating")
        
        self.carriedDrink = carriedDrink as? RotatableObject // Store reference
        
        print("🦊 ✨ \(animalType.rawValue) picked up drink from table!")
    }
    
    private func createCarriedDrink(from tableDrink: SKNode) -> SKNode {
        // Create a version of the drink for carrying
        let carriedVersion = SKSpriteNode(color: .brown, size: GameConfig.NPC.CarriedDrink.size)
        
        // Add basic drink details
        let lid = SKSpriteNode(color: .lightGray, size: GameConfig.NPC.CarriedDrink.lidSize)
        lid.position = GameConfig.NPC.CarriedDrink.lidOffset
        carriedVersion.addChild(lid)
        
        let straw = SKSpriteNode(color: .white, size: GameConfig.NPC.CarriedDrink.strawSize)
        straw.position = GameConfig.NPC.CarriedDrink.strawOffset
        carriedVersion.addChild(straw)
        
        return carriedVersion
    }
    
    private func updateLeaving() {
        // Move toward exit every few frames, not just when not moving
        if Int(stateTimer * 10) % 15 == 0 { // Every 1.5 seconds, try to move toward exit
            if isNearExit() {
                removeSelf()
            } else {
                moveTowardExit()
                print("🦊 \(animalType.rawValue) (\(state)) moving toward exit from \(gridPosition)")
            }
        }
    }
    
    // MARK: - State Transitions
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
            
            // FIXED: Stop shimmer after configured time and proceed to normal exit
            let shimmerDuration = Double.random(in: GameConfig.NPC.Animations.happyCelebrationTime.min...GameConfig.NPC.Animations.happyCelebrationTime.max)
            DispatchQueue.main.asyncAfter(deadline: .now() + shimmerDuration) { [weak self] in
                self?.stopHappyAnimationAndProceedToExit()
            }
        } else {
            startNeutralAnimation()
            print("🦊 \(animalType.rawValue) leaving neutral")
        }
        
        // Clean up table reference
        currentTable = nil
    }
    
    // MARK: - Movement System
    private func moveToCell(_ targetCell: GridCoordinate) {
        guard targetCell.isValid() else { return }
        guard GridWorld.shared.isCellAvailable(targetCell) else { return }
        guard !isMoving else { return }
        
        isMoving = true
        self.targetCell = targetCell
        
        // Free old cell and reserve new one
        GridWorld.shared.freeCell(gridPosition)
        GridWorld.shared.reserveCell(targetCell)
        
        // Update position
        gridPosition = targetCell
        
        // Animate movement
        let worldPos = GridWorld.shared.gridToWorld(targetCell)
        let moveAction = SKAction.move(to: worldPos, duration: moveSpeed)
        moveAction.timingMode = .easeInEaseOut
        
        run(moveAction) { [weak self] in
            self?.isMoving = false
            self?.targetCell = nil
        }
    }
    
    private func moveToRandomNearbyCell() {
        // Find random available cell within configured radius
        let radius = Int.random(in: 1...GameConfig.NPC.wanderRadius)
        let candidates = generateCandidateCells(radius: radius)
        
        if let randomCell = candidates.randomElement() {
            moveToCell(randomCell)
        }
    }
    
    private func generateCandidateCells(radius: Int) -> [GridCoordinate] {
        var candidates: [GridCoordinate] = []
        
        for dx in -radius...radius {
            for dy in -radius...radius {
                if dx == 0 && dy == 0 { continue } // Skip current position
                
                let candidate = GridCoordinate(x: gridPosition.x + dx, y: gridPosition.y + dy)
                
                // Keep NPCs within shop bounds using configuration
                let shopBounds = GameConfig.Grid.ShopBounds.self
                
                if candidate.x >= shopBounds.minX && candidate.x <= shopBounds.maxX &&
                   candidate.y >= shopBounds.minY && candidate.y <= shopBounds.maxY &&
                   candidate.isValid() && GridWorld.shared.isCellAvailable(candidate) {
                    candidates.append(candidate)
                }
            }
        }
        
        return candidates
    }
    
    // MARK: - Table System (Phase 3 - NPC Table Interaction)
    private func findAndMoveToTable() -> Bool {
        // Find all tables in the scene
        let allTables = findAllTables()
        
        if allTables.isEmpty {
            print("🦊 No tables found in scene")
            return false
        }
        
        // Try to find a table (prefer tables with drinks, but accept any)
        if let chosenTable = chooseTable(from: allTables) {
            let tableGridPos = GridWorld.shared.worldToGrid(chosenTable.position)
            let adjacentCells = tableGridPos.adjacentCells.filter { GridWorld.shared.isCellAvailable($0) }
            
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
    
    private func findAllTables() -> [RotatableObject] {
        guard let scene = parent as? GameScene else { return [] }
        
        var tables: [RotatableObject] = []
        scene.enumerateChildNodes(withName: "table") { node, _ in
            if let table = node as? RotatableObject {
                tables.append(table)
            }
        }
        
        print("🦊 Found \(tables.count) tables in scene")
        return tables
    }
    
    private func chooseTable(from tables: [RotatableObject]) -> RotatableObject? {
        // Choose tables randomly - customers don't hunt for drinks, that's the player's job!
        let availableTables = tables.filter { table in
            let tableGridPos = GridWorld.shared.worldToGrid(table.position)
            return tableGridPos.adjacentCells.contains { GridWorld.shared.isCellAvailable($0) }
        }
        
        if let chosenTable = availableTables.randomElement() {
            print("🦊 \(animalType.rawValue) chose a random table to sit at")
            return chosenTable
        } else {
            print("🦊 No tables with available seating")
            return nil
        }
    }
    
    private func hasAtLeastOneDrink(_ table: RotatableObject) -> Bool {
        return table.children.contains { $0.name == "drink_on_table" }
    }
    
    // MARK: - Exit System
    private func moveTowardExit() {
        // Move toward front door (exit) - improved pathfinding
        let doorPosition = GameConfig.World.doorPosition
        
        // Calculate direction to door
        let deltaX = doorPosition.x - gridPosition.x
        let deltaY = doorPosition.y - gridPosition.y
        
        // Move one step closer (prioritize x movement to get to door area)
        let stepX = deltaX != 0 ? (deltaX > 0 ? 1 : -1) : 0
        let stepY = deltaY != 0 ? (deltaY > 0 ? 1 : -1) : 0
        
        // Try X movement first (toward door), then Y if needed
        var targetCell: GridCoordinate
        if abs(deltaX) > abs(deltaY) || deltaX != 0 {
            targetCell = GridCoordinate(x: gridPosition.x + stepX, y: gridPosition.y)
        } else {
            targetCell = GridCoordinate(x: gridPosition.x, y: gridPosition.y + stepY)
        }
        
        // Ensure target is valid and available
        if targetCell.isValid() && GridWorld.shared.isCellAvailable(targetCell) {
            moveToCell(targetCell)
        } else {
            // If direct path blocked, try alternative
            let alternativeCell = GridCoordinate(x: gridPosition.x + stepY, y: gridPosition.y + stepX)
            if alternativeCell.isValid() && GridWorld.shared.isCellAvailable(alternativeCell) {
                moveToCell(alternativeCell)
            }
        }
    }
    
    private func isNearExit() -> Bool {
        return gridPosition.x <= GameConfig.NPC.exitThreshold && 
               abs(gridPosition.y - GameConfig.World.doorPosition.y) <= GameConfig.NPC.exitYTolerance
    }
    
    // MARK: - Animations (Phase 4 - Enhanced Exit Effects)
    private func startHappyAnimation() {
        // Remove any existing animations
        removeAction(forKey: "happy_shimmer")
        removeAction(forKey: "happy_shake")
        removeAction(forKey: "happy_scale")
        
        // Multi-layered happiness effect using configuration
        
        // 1. Shimmer effect (scale pulsing)
        let shimmer = SKAction.repeatForever(
            SKAction.sequence([
                SKAction.scale(to: GameConfig.NPC.Animations.shimmerScaleAmount, duration: GameConfig.NPC.Animations.shimmerDuration),
                SKAction.scale(to: 1.0, duration: GameConfig.NPC.Animations.shimmerDuration)
            ])
        )
        run(shimmer, withKey: "happy_shimmer")
        
        // 2. Shake effect (position wobble)
        let shake = SKAction.repeatForever(
            SKAction.sequence([
                SKAction.moveBy(x: -GameConfig.NPC.Animations.shakeDistance, y: 0, duration: GameConfig.NPC.Animations.shakeDuration),
                SKAction.moveBy(x: GameConfig.NPC.Animations.shakeDistance * 2, y: 0, duration: GameConfig.NPC.Animations.shakeDuration),
                SKAction.moveBy(x: -GameConfig.NPC.Animations.shakeDistance * 2, y: 0, duration: GameConfig.NPC.Animations.shakeDuration),
                SKAction.moveBy(x: GameConfig.NPC.Animations.shakeDistance, y: 0, duration: GameConfig.NPC.Animations.shakeDuration)
            ])
        )
        run(shake, withKey: "happy_shake")
        
        // 3. Color flash effect
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
        // Subtle disappointed animation for neutral customers using configuration
        removeAction(forKey: "neutral_sigh")
        
        // Slow, subtle scale down to show disappointment
        let sigh = SKAction.repeatForever(
            SKAction.sequence([
                SKAction.scale(to: GameConfig.NPC.Animations.neutralScaleAmount, duration: GameConfig.NPC.Animations.neutralSighDuration),
                SKAction.scale(to: 1.0, duration: GameConfig.NPC.Animations.neutralSighDuration)
            ])
        )
        run(sigh, withKey: "neutral_sigh")
        
        // Slight gray tint to show neutrality
        let grayTint = SKAction.colorize(with: .gray, colorBlendFactor: GameConfig.NPC.Animations.neutralGrayBlend, duration: GameConfig.NPC.Animations.neutralFadeDuration)
        run(grayTint, withKey: "neutral_tint")
        
        print("😐 \(animalType.rawValue) is leaving disappointed (no drink)")
    }
    
    private func stopHappyAnimation() {
        // Clean stop of all happiness effects
        removeAction(forKey: "happy_shimmer")
        removeAction(forKey: "happy_shake")
        removeAction(forKey: "happy_flash")
        
        // Reset to normal appearance
        let resetAction = SKAction.group([
            SKAction.scale(to: 1.0, duration: GameConfig.NPC.Animations.resetDuration),
            SKAction.move(to: position, duration: GameConfig.NPC.Animations.resetDuration), // Reset any shake offset
            SKAction.colorize(withColorBlendFactor: 0.0, duration: GameConfig.NPC.Animations.resetDuration)
        ])
        run(resetAction)
    }
    
    private func stopHappyAnimationAndProceedToExit() {
        // Stop shimmer effects and proceed to normal exit
        stopHappyAnimation()
        
        // Change to normal leaving state but keep the carried drink
        state = .leaving
        stateTimer = 0
        
        print("✨ \(animalType.rawValue) finished celebrating, now proceeding to exit normally")
        
        // Immediately try to move toward exit
        moveTowardExit()
    }
    
    private func stopNeutralAnimation() {
        // Clean stop of neutral effects
        removeAction(forKey: "neutral_sigh")
        removeAction(forKey: "neutral_tint")
        
        // Reset to normal appearance
        let resetAction = SKAction.group([
            SKAction.scale(to: 1.0, duration: GameConfig.NPC.Animations.resetDuration),
            SKAction.colorize(withColorBlendFactor: 0.0, duration: GameConfig.NPC.Animations.resetDuration)
        ])
        run(resetAction)
    }
    
    // MARK: - Lifecycle
    private func reserveCurrentCell() {
        GridWorld.shared.reserveCell(gridPosition)
    }
    
    private func removeSelf() {
        // Stop all animations before removal based on state
        if state == .satisfied {
            stopHappyAnimation()
        } else if state == .neutral {
            stopNeutralAnimation()
        }
        
        // Clean up carried drink if any
        if let drink = carriedDrink {
            drink.removeFromParent()
        }
        
        // Clean up grid reservation
        GridWorld.shared.freeCell(gridPosition)
        
        // Remove from scene
        removeFromParent()
        
        print("🦊 \(animalType.rawValue) left the shop")
    }
    
    // MARK: - Debug
    func getStateInfo() -> String {
        return "\(animalType.rawValue) - \(state) - \(Int(stateTimer))s"
    }
}
