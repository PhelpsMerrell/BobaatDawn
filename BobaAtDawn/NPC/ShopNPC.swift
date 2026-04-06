//
//  ShopNPC.swift
//  BobaAtDawn
//
//  Shop-scene NPC with state machine, physics movement, table/drink interaction,
//  and ritual support.  Extends BaseNPC (which provides visual + dialogue).
//

import SpriteKit

// MARK: - Shop NPC State Machine
enum NPCState: Equatable {
    case entering
    case wandering
    case sitting(table: RotatableObject?)
    case drinking(timeStarted: TimeInterval)
    case leaving(satisfied: Bool)

    var displayName: String {
        switch self {
        case .entering:              return "Entering"
        case .wandering:             return "Wandering"
        case .sitting:               return "Sitting"
        case .drinking:              return "Drinking"
        case .leaving(let sat):      return sat ? "Leaving Happy" : "Leaving"
        }
    }

    var isExiting: Bool {
        if case .leaving = self { return true }
        return false
    }
}

// MARK: - Shop NPC
class ShopNPC: BaseNPC {

    // MARK: - Dependencies
    private let gridService: GridService
    private let npcService: NPCService

    // MARK: - Physics Movement
    // FIXED: Removed [unowned self] — direct self access is safe in lazy var initializers.
    internal lazy var movementController: NPCMovementController = {
        guard let body = self.physicsBody else {
            fatalError("ShopNPC physics body is nil; call setupPhysicsBody() before accessing movementController.")
        }
        return NPCMovementController(
            physicsBody: body,
            gridService: self.gridService,
            homePosition: self.gridPosition
        )
    }()

    // MARK: - State
    private(set) var state: NPCState = .entering
    private(set) var gridPosition: GridCoordinate

    // Timers
    private var stateTimer: TimeInterval = 0
    private var totalLifetime: TimeInterval = 0

    // Behavior
    private var currentTable: RotatableObject?
    private var carriedDrink: RotatableObject?
    private var targetCell: GridCoordinate?

    // Ritual
    private var isInRitualMode: Bool = false

    // Movement
    private var isMoving: Bool = false
    private let moveSpeed: TimeInterval = GameConfig.NPC.moveSpeed

    // Leaving state
    private(set) var hadDrink: Bool = false

    // MARK: - Physics Convenience
    var currentSpeed: CGFloat { movementController.getCurrentSpeed() }
    var physicsVelocity: CGVector { physicsBody?.velocity ?? .zero }

    // MARK: - Initialization
    init(
        animal: AnimalType? = nil,
        startPosition: GridCoordinate? = nil,
        gridService: GridService,
        npcService: NPCService
    ) {
        self.gridService = gridService
        self.npcService = npcService

        let chosenAnimal = animal ?? AnimalType.random()
        let doorPosition = GameConfig.World.doorGridPosition
        let startGrid = startPosition ?? doorPosition
        self.gridPosition = startGrid

        let worldPos = gridService.gridToWorld(startGrid)

        // Resolve NPCData from animal type
        let data: NPCData
        if let charId = chosenAnimal.characterId,
           let resolved = DialogueService.shared.getNPC(byId: charId) {
            data = resolved
        } else {
            data = NPCData(id: chosenAnimal.characterId ?? "unknown",
                           name: chosenAnimal.rawValue,
                           animal: chosenAnimal.rawValue,
                           causeOfDeath: "unknown",
                           homeRoom: 1,
                           dialogue: NPCDialogue(day: ["..."], night: ["..."]))
        }

        super.init(npcData: data, animalType: chosenAnimal, at: worldPos)

        // Physics body BEFORE any movementController use
        setupPhysicsBody()

        // Reserve grid cell
        gridService.reserveCell(gridPosition)

        Log.info(.npc, "\(chosenAnimal.rawValue) spawned at grid \(startGrid)")
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Physics Setup
    private func setupPhysicsBody() {
        let body = PhysicsBodyFactory.createNPCBody()
        self.physicsBody = body
        Log.debug(.physics, "\(animalType.rawValue) physics body created")
    }

    // MARK: - BaseNPC Hooks (dialogue pause/resume)
    override func onFreeze() {
        movementController.stop()
    }

    override func onUnfreeze() {
        // behavior resumes on next update tick automatically
    }

    // MARK: - Update Loop
    func update(deltaTime: TimeInterval) {
        // Skip if in dialogue
        guard !isFrozen else {
            movementController.update(deltaTime: deltaTime)
            return
        }

        // Ritual mode — just wait
        if isInRitualMode {
            movementController.update(deltaTime: deltaTime)
            return
        }

        stateTimer += deltaTime
        totalLifetime += deltaTime

        movementController.update(deltaTime: deltaTime)
        updateGridPositionTracking()

        // State machine
        switch state {
        case .entering:                  updateEntering()
        case .wandering:                 updateWandering()
        case .sitting(let table):        updateSitting(table: table)
        case .drinking(let timeStarted): updateDrinking(timeStarted: timeStarted)
        case .leaving(let satisfied):    updateLeaving(satisfied: satisfied)
        }

        // Safety timeout
        if totalLifetime > GameConfig.NPC.maxLifetime {
            transitionToLeaving(satisfied: false)
        }
    }

    // MARK: - Grid Tracking
    private func updateGridPositionTracking() {
        let newGridPos = gridService.worldToGrid(position)
        if newGridPos != gridPosition && newGridPos.isValid() {
            gridService.freeCell(gridPosition)
            if gridService.isCellAvailable(newGridPos) {
                gridService.reserveCell(newGridPos)
                gridPosition = newGridPos
            } else {
                gridService.reserveCell(gridPosition)
            }
        }
    }

    // MARK: - State Updates
    private func updateEntering() {
        let dur = Double.random(in: GameConfig.NPC.enteringDuration.min...GameConfig.NPC.enteringDuration.max)
        if stateTimer > dur {
            transitionToWandering()
        } else if !movementController.isMoving {
            moveToRandomNearbyCell()
        }
    }

    private func updateWandering() {
        let dur = Double.random(in: GameConfig.NPC.wanderingDuration.min...GameConfig.NPC.wanderingDuration.max)
        if stateTimer > dur {
            if findAndMoveToTable() {
                transitionToSitting()
            } else {
                stateTimer -= 10
            }
        } else if !movementController.isMoving {
            if Int(stateTimer * 2) % 8 == 0 && Int.random(in: 1...4) == 1 {
                moveToRandomNearbyCell()
            }
        }
    }

    private func updateSitting(table: RotatableObject?) {
        guard let table = table else {
            if !isInRitualMode { transitionToWandering() }
            return
        }
        if isInRitualMode { return }

        if Int(stateTimer * 2) % 4 == 0 {
            if checkForDrinkOnTable(table: table) {
                transitionToDrinking()
                return
            }
        }

        let timeout = Double.random(in: GameConfig.NPC.sittingTimeout.min...GameConfig.NPC.sittingTimeout.max)
        if stateTimer > timeout {
            transitionToLeaving(satisfied: false)
        }
    }

    private func updateDrinking(timeStarted: TimeInterval) {
        let enjoy = Double.random(in: GameConfig.NPC.drinkEnjoymentTime.min...GameConfig.NPC.drinkEnjoymentTime.max)
        if stateTimer > timeStarted + enjoy {
            transitionToLeaving(satisfied: true)
        }
    }

    private func updateLeaving(satisfied: Bool) {
        if Int(stateTimer * 30) % 5 == 0 {
            if npcService.isNearExit(gridPosition) {
                removeSelf()
            } else {
                moveTowardExitReliably()
            }
        }
    }

    // MARK: - Movement Helpers
    private func moveToCell(_ targetCell: GridCoordinate) {
        guard targetCell.isValid(),
              gridService.isCellAvailable(targetCell),
              !movementController.isMoving else { return }

        movementController.moveToGrid(targetCell) { [weak self] in
            self?.handleCellArrival(targetCell)
        }
    }
    
    private func moveTowardWorldPosition(_ worldPosition: CGPoint) {
        movementController.currentTarget = worldPosition
        movementController.setMoving(true)
    }

    private func handleCellArrival(_ cell: GridCoordinate) { /* intentionally empty */ }

    private func moveToRandomNearbyCell() {
        let radius = Int.random(in: 1...GameConfig.NPC.wanderRadius)
        let candidates = npcService.generateCandidateCells(from: gridPosition, radius: radius)
        if let cell = candidates.randomElement() {
            moveToCell(cell)
        } else {
            movementController.wanderRandomly()
        }
    }

    // MARK: - Table System
    private func findAndMoveToTable() -> Bool {
        guard let scene = parent as? SKScene else { return false }
        let tables = npcService.findAvailableTables(in: scene)
        guard let table = tables.randomElement() else { return false }

        let tableGridPos = gridService.worldToGrid(table.position)
        let adjacent = gridService.getAvailableAdjacentCells(to: tableGridPos)
        guard let spot = adjacent.randomElement() else { return false }

        currentTable = table
        moveToCell(spot)
        return true
    }

    private func checkForDrinkOnTable(table: RotatableObject) -> Bool {
        let drinks = table.children.filter { $0.name == "drink_on_table" }
        if let drink = drinks.first {
            pickupDrinkFromTable(drink)
            return true
        }
        return false
    }

    private func pickupDrinkFromTable(_ drink: SKNode) {
        drink.removeFromParent()

        let carried = createCarriedDrink(from: drink)
        carried.position = GameConfig.NPC.CarriedDrink.carryOffset
        carried.zPosition = ZLayers.childLayer(for: ZLayers.npcs)
        addChild(carried)

        let float = SKAction.repeatForever(
            SKAction.sequence([
                SKAction.moveBy(x: 0, y: GameConfig.NPC.CarriedDrink.floatDistance,
                                duration: GameConfig.NPC.CarriedDrink.floatDuration),
                SKAction.moveBy(x: 0, y: -GameConfig.NPC.CarriedDrink.floatDistance,
                                duration: GameConfig.NPC.CarriedDrink.floatDuration)
            ])
        )
        carried.run(float, withKey: "floating")
        self.carriedDrink = carried as? RotatableObject
    }

    private func createCarriedDrink(from tableDrink: SKNode) -> SKNode {
        let carriedVersion = SKNode()
        for child in tableDrink.children {
            if let spriteChild = child as? SKSpriteNode {
                let copy = spriteChild.copy() as! SKSpriteNode
                copy.setScale(spriteChild.xScale * 1.33)
                copy.position = spriteChild.position
                copy.zPosition = spriteChild.zPosition
                copy.alpha = spriteChild.alpha
                carriedVersion.addChild(copy)
            }
        }
        if carriedVersion.children.isEmpty {
            let atlas = SKTextureAtlas(named: "Boba")
            let tex = atlas.textureNamed("cup_empty")
            let cup = SKSpriteNode(texture: tex)
            cup.setScale(20.0 / tex.size().width)
            carriedVersion.addChild(cup)
        }
        return carriedVersion
    }

    // MARK: - Exit System
    private func moveTowardExitReliably() {
        let doorWorldPos = GameConfig.doorWorldPosition()
        let dist = hypot(position.x - doorWorldPos.x, position.y - doorWorldPos.y)

        if dist < 50 {
            let direct = SKAction.move(to: doorWorldPos, duration: 0.5)
            run(direct) { [weak self] in self?.removeSelf() }
            return
        }

        if let target = npcService.findPathToExit(from: gridPosition) {
            moveToCell(target)
        } else {
            moveTowardWorldPosition(doorWorldPos)
        }
    }

    // MARK: - State Transitions
    private func transitionToWandering() {
        state = .wandering
        stateTimer = 0
        currentTable = nil
    }

    private func transitionToSitting() {
        state = .sitting(table: currentTable)
        stateTimer = 0
    }

    private func transitionToDrinking() {
        state = .drinking(timeStarted: stateTimer)
    }

    private func transitionToLeaving(satisfied: Bool) {
        if isInRitualMode {
            Log.warn(.ritual, "\(animalType.rawValue) in ritual mode — cannot leave")
            return
        }
        state = .leaving(satisfied: satisfied)
        stateTimer = 0
        currentTable = nil

        if satisfied, carriedDrink != nil {
            hadDrink = true
            dropTrash()
            carriedDrink?.removeFromParent()
            carriedDrink = nil
        }

        if satisfied { startHappyAnimation() } else { startNeutralAnimation() }
    }

    func startLeaving(satisfied: Bool) {
        transitionToLeaving(satisfied: satisfied)
    }

    // MARK: - Trash
    private func dropTrash() {
        guard let parentScene = scene else { return }
        let offset = CGPoint(x: CGFloat.random(in: -20...20), y: CGFloat.random(in: -20...20))
        let trashPos = CGPoint(x: position.x + offset.x, y: position.y + offset.y)
        let trash = Trash(at: trashPos, location: .shop)
        parentScene.addChild(trash)
        Log.debug(.npc, "\(animalType.rawValue) dropped trash at \(trashPos)")
    }

    // MARK: - Ritual Support
    func transitionToRitualSitting(table: RotatableObject? = nil) {
        state = .sitting(table: table)
        stateTimer = 0
        currentTable = table
        movementController.stop()
        isInRitualMode = true
        Log.info(.ritual, "\(animalType.rawValue) enters PERMANENT ritual sitting state")
    }

    func isCurrentlyInRitual() -> Bool { isInRitualMode }

    func clearRitualMode() {
        isInRitualMode = false
        Log.info(.ritual, "\(animalType.rawValue) ritual mode cleared")
    }

    // MARK: - Public State Access
    var currentState: NPCState { state }

    // MARK: - Animations (target emojiLabel, not self — self is a plain SKNode)
    private func startHappyAnimation() {
        emojiLabel.removeAction(forKey: "happy_shimmer")

        let shimmer = SKAction.repeatForever(
            SKAction.sequence([
                SKAction.scale(to: GameConfig.NPC.Animations.shimmerScaleAmount,
                               duration: GameConfig.NPC.Animations.shimmerDuration),
                SKAction.scale(to: 1.0, duration: GameConfig.NPC.Animations.shimmerDuration)
            ])
        )
        emojiLabel.run(shimmer, withKey: "happy_shimmer")

        let flash = SKAction.repeatForever(
            SKAction.sequence([
                SKAction.colorize(with: .yellow, colorBlendFactor: 0.3,
                                  duration: GameConfig.NPC.Animations.colorFlashDuration),
                SKAction.colorize(withColorBlendFactor: 0.0,
                                  duration: GameConfig.NPC.Animations.colorFlashDuration)
            ])
        )
        emojiLabel.run(flash, withKey: "happy_flash")
    }

    private func startNeutralAnimation() {
        let sigh = SKAction.repeatForever(
            SKAction.sequence([
                SKAction.scale(to: GameConfig.NPC.Animations.neutralScaleAmount,
                               duration: GameConfig.NPC.Animations.neutralSighDuration),
                SKAction.scale(to: 1.0, duration: GameConfig.NPC.Animations.neutralSighDuration)
            ])
        )
        emojiLabel.run(sigh, withKey: "neutral_sigh")

        let tint = SKAction.colorize(with: .gray,
                                      colorBlendFactor: GameConfig.NPC.Animations.neutralGrayBlend,
                                      duration: GameConfig.NPC.Animations.neutralFadeDuration)
        emojiLabel.run(tint, withKey: "neutral_tint")
    }

    private func stopAllAnimations() {
        emojiLabel.removeAction(forKey: "happy_shimmer")
        emojiLabel.removeAction(forKey: "happy_flash")
        emojiLabel.removeAction(forKey: "neutral_sigh")
        emojiLabel.removeAction(forKey: "neutral_tint")

        let reset = SKAction.group([
            SKAction.scale(to: 1.0, duration: GameConfig.NPC.Animations.resetDuration),
            SKAction.colorize(withColorBlendFactor: 0.0, duration: GameConfig.NPC.Animations.resetDuration)
        ])
        emojiLabel.run(reset)
    }

    // MARK: - Lifecycle
    private func removeSelf() {
        Log.info(.npc, "\(animalType.rawValue) leaving scene — cleaning up")
        stopAllAnimations()

        if carriedDrink != nil {
            hadDrink = true
            carriedDrink?.removeFromParent()
            carriedDrink = nil
        }

        gridService.freeCell(gridPosition)
        removeFromParent()
    }

    // MARK: - Debug
    func getStateInfo() -> String {
        "\(animalType.rawValue) - \(state.displayName) - \(Int(stateTimer))s"
    }
}
