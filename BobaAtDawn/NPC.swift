//
//  NPC.swift
//  BobaAtDawn
//
//  Physics-enhanced NPC with dependency injection, smooth movement, and dialogue system
//

import SpriteKit

// MARK: - NPC State Machine with Associated Values
enum NPCState: Equatable {
    case entering
    case wandering
    case sitting(table: RotatableObject?)
    case drinking(timeStarted: TimeInterval)
    case leaving(satisfied: Bool)

    var displayName: String {
        switch self {
        case .entering: return "Entering"
        case .wandering: return "Wandering"
        case .sitting: return "Sitting"
        case .drinking: return "Drinking"
        case .leaving(let satisfied): return satisfied ? "Leaving Happy" : "Leaving"
        }
    }

    var isExiting: Bool {
        if case .leaving = self { return true }
        return false
    }
}

// MARK: - Forest Animals with Character Mapping
enum AnimalType: String, CaseIterable {
    case fox = "🦊"
    case rabbit = "🐰"
    case hedgehog = "🦔"
    case frog = "🐸"
    case duck = "🦆"
    case bear = "🐻"
    case raccoon = "🦝"
    case squirrel = "🐿️"
    case deer = "🦌"
    case wolf = "🐺"
    case mule = "🐴"
    case pufferfish = "🐡"
    case owl = "🦉"
    case songbird = "🐦"
    case mouse = "🐭"

    // Night visitors (rare)
    case bat = "🦇"

    static var dayAnimals: [AnimalType] {
        [.fox, .rabbit, .hedgehog, .frog, .duck, .bear, .raccoon, .squirrel, .deer, .mule, .pufferfish, .songbird, .mouse]
    }

    static var nightAnimals: [AnimalType] {
        [.owl, .bat, .wolf]
    }

    static func random(isNight: Bool = false) -> AnimalType {
        let pool = isNight ? nightAnimals : dayAnimals
        return pool.randomElement() ?? .fox
    }
    
    // MARK: - Character Data Mapping
    /// Maps animal types to character IDs from JSON dialogue data
    var characterId: String? {
        switch self {
        case .deer: return "qari_deer"
        case .rabbit: return "timothy_rabbit" 
        case .wolf: return "gertrude_wolf"
        case .mule: return "stanuel_mule"
        case .pufferfish: return "bb_james_pufferfish"
        case .owl: return "luna_owl"
        case .fox: return "finn_fox"
        case .songbird: return "ivy_songbird"
        case .bear: return "oscar_bear"
        case .mouse: return "mira_mouse"
        case .hedgehog: return "hazel_hedgehog"
        case .frog: return "rivet_frog"
        case .duck: return "della_duck"
        case .raccoon: return "rascal_raccoon"
        case .squirrel: return "nixie_squirrel"
        case .bat: return "echo_bat"
        }
    }
}

// MARK: - NPC Class with Dependency Injection and Dialogue
class NPC: SKLabelNode {

    // MARK: - Dependencies
    private let gridService: GridService
    private let npcService: NPCService
    
    // MARK: - Dialogue System
    private var isInDialogue: Bool = false
    private var behaviorPausedForDialogue: Bool = false

    // MARK: - Physics Movement Controller
    private lazy var movementController: NPCMovementController = { [unowned self] in
        guard let body = self.physicsBody else {
            fatalError("NPC physics body is nil; call setupPhysicsBody() before accessing movementController.")
        }
        return NPCMovementController(
            physicsBody: body,
            gridService: gridService,
            homePosition: gridPosition
        )
    }()

    // MARK: - Properties (preserved)
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

    // MARK: - Physics Properties
    var currentSpeed: CGFloat { movementController.getCurrentSpeed() }
    var physicsVelocity: CGVector { physicsBody?.velocity ?? .zero }

    // MARK: - Initialization with Dependency Injection
    init(
        animal: AnimalType? = nil,
        startPosition: GridCoordinate? = nil,
        gridService: GridService,
        npcService: NPCService
    ) {
        // Inject dependencies
        self.gridService = gridService
        self.npcService = npcService

        // Choose random animal if not specified
        self.animalType = animal ?? AnimalType.random()

        // Default start position (at front door)
        let doorPosition = GameConfig.World.doorGridPosition
        self.gridPosition = startPosition ?? doorPosition

        // All subclass properties are now initialized; safe to call super.init()
        super.init()

        // Setup visual
        text = animalType.rawValue
        fontSize = GameConfig.NPC.fontSize
        fontName = GameConfig.NPC.fontName
        horizontalAlignmentMode = .center
        verticalAlignmentMode = .center
        zPosition = ZLayers.npcs

        // Set up physics body BEFORE any movementController use
        setupPhysicsBody()
        
        // Enable touch interaction for dialogue
        isUserInteractionEnabled = true
        name = "npc_\\(animalType.rawValue)"

        // Position in world using injected grid service
        position = gridService.gridToWorld(gridPosition)

        // Reserve grid cell using injected grid service
        gridService.reserveCell(gridPosition)

        print("🦊 PhysicsNPC \\(animalType.rawValue) spawned at grid \\(gridPosition), world \\(position)")
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Physics Setup
    private func setupPhysicsBody() {
        let body = PhysicsBodyFactory.createNPCBody()
        self.physicsBody = body
        print("⚡ NPC \\(animalType.rawValue) physics body created")
    }

    // MARK: - Dialogue System Integration
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        // Don't interact if already in dialogue or if DialogueService is busy
        guard !isInDialogue && !DialogueService.shared.isDialogueActive() else { 
            print("💬 Ignoring tap - dialogue already active")
            return 
        }
        
        // Only show dialogue if this animal has character data
        guard let characterId = animalType.characterId else {
            print("🐭 No dialogue data for \\(animalType.rawValue)")
            return
        }
        
        // Determine time context based on current game state
        let timeContext: TimeContext = determineTimeContext()
        
        // Pause NPC behavior and show dialogue
        pauseForDialogue()
        
        // Show dialogue using the service
        if let scene = scene {
            // Create a temporary ForestNPC-compatible interface for DialogueService
            let dialogueProxy = NPCDialogueProxy(npc: self, characterId: characterId)
            DialogueService.shared.showDialogue(for: dialogueProxy, in: scene, timeContext: timeContext)
        }
        
        print("💬 \\(animalType.rawValue) tapped - showing dialogue")
    }
    
    private func determineTimeContext() -> TimeContext {
        // Connect to actual game time system
        if let gameScene = scene as? GameScene {
            // Access the timeService from the game scene (it's private but we can use the timeLabel)
            if let timeLabel = gameScene.children.first(where: { $0 is SKLabelNode && ($0 as! SKLabelNode).text?.contains("%") == true }) as? SKLabelNode {
                let timeText = timeLabel.text?.uppercased() ?? "DAY"
                if timeText.contains("NIGHT") {
                    return .night
                } else {
                    return .day
                }
            }
        }
        
        // Default to day if can't determine time
        return .day
    }
    
    /// Pause NPC behavior for dialogue
    func pauseForDialogue() {
        isInDialogue = true
        behaviorPausedForDialogue = true
        
        // Stop current movement
        movementController.stop()
        
        // Visual feedback - slightly larger when talking  
        let emphasize = SKAction.scale(to: 1.1, duration: 0.2)
        run(emphasize, withKey: "dialogue_emphasis")
        
        print("💬 \\(animalType.rawValue) paused for dialogue")
    }
    
    /// Resume NPC behavior after dialogue
    func resumeFromDialogue() {
        isInDialogue = false
        behaviorPausedForDialogue = false
        
        // Return to normal size
        let normalize = SKAction.scale(to: 1.0, duration: 0.2)
        run(normalize, withKey: "dialogue_normalize")
        
        print("💬 \\(animalType.rawValue) resumed behavior after dialogue")
    }

    // MARK: - Update Loop (Physics-Enhanced with Dialogue Support)
    func update(deltaTime: TimeInterval) {
        // Skip behavior updates if in dialogue
        guard !behaviorPausedForDialogue else {
            // Still update movement controller for physics
            movementController.update(deltaTime: deltaTime)
            return
        }
        
        stateTimer += deltaTime
        totalLifetime += deltaTime

        // Update movement controller
        movementController.update(deltaTime: deltaTime)

        // Update grid position tracking
        updateGridPositionTracking()

        // State machine progression
        switch state {
        case .entering:  updateEntering()
        case .wandering: updateWandering()
        case .sitting(let table): updateSitting(table: table)
        case .drinking(let timeStarted): updateDrinking(timeStarted: timeStarted)
        case .leaving(let satisfied): updateLeaving(satisfied: satisfied)
        }

        // Safety timeout
        if totalLifetime > GameConfig.NPC.maxLifetime {
            transitionToLeaving(satisfied: false)
        }
    }

    // MARK: - Grid Position Tracking
    private func updateGridPositionTracking() {
        let currentWorldPos = position
        let newGridPos = gridService.worldToGrid(currentWorldPos)

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
        let enteringDuration = Double.random(in: GameConfig.NPC.enteringDuration.min...GameConfig.NPC.enteringDuration.max)
        if stateTimer > enteringDuration {
            transitionToWandering()
        } else if !movementController.isMoving {
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
        } else if !movementController.isMoving {
            if Int(stateTimer * 2) % 8 == 0 && Int.random(in: 1...4) == 1 {
                moveToRandomNearbyCell()
            }
        }
    }

    private func updateSitting(table: RotatableObject?) {
        guard let table = table else {
            transitionToWandering()
            return
        }

        if Int(stateTimer * 2) % 4 == 0 {
            if checkForDrinkOnTable(table: table) {
                transitionToDrinking()
                return
            }
        }

        let sittingTimeout = Double.random(in: GameConfig.NPC.sittingTimeout.min...GameConfig.NPC.sittingTimeout.max)
        if stateTimer > sittingTimeout {
            transitionToLeaving(satisfied: false)
        }
    }

    private func updateDrinking(timeStarted: TimeInterval) {
        let enjoymentTime = Double.random(in: GameConfig.NPC.drinkEnjoymentTime.min...GameConfig.NPC.drinkEnjoymentTime.max)
        if stateTimer > timeStarted + enjoymentTime {
            transitionToLeaving(satisfied: true)
        }
    }

    private func updateLeaving(satisfied: Bool) {
        // More frequent movement attempts when leaving
        if Int(stateTimer * 20) % 10 == 0 {
            if npcService.isNearExit(gridPosition) {
                print("🚺 \(animalType.rawValue) reached exit, removing from scene")
                removeSelf()
            } else {
                moveTowardExit()
            }
        }
    }

    // MARK: - Physics Movement System
    private func moveToCell(_ targetCell: GridCoordinate) {
        guard targetCell.isValid() else { return }
        guard gridService.isCellAvailable(targetCell) else { return }
        guard !movementController.isMoving else { return }

        movementController.moveToGrid(targetCell) { [weak self] in
            self?.handleCellArrival(targetCell)
        }
    }
    
    private func moveTowardWorldPosition(_ worldPosition: CGPoint) {
        // FIXED: For NPCs moving to world positions (not grid-constrained)
        movementController.currentTarget = worldPosition
        movementController.setMoving(true)
    }

    private func handleCellArrival(_ cell: GridCoordinate) {
        // Handle arrival at cell
    }

    private func moveToRandomNearbyCell() {
        let radius = Int.random(in: 1...GameConfig.NPC.wanderRadius)
        let candidates = npcService.generateCandidateCells(from: gridPosition, radius: radius)

        if let randomCell = candidates.randomElement() {
            moveToCell(randomCell)
        } else {
            movementController.wanderRandomly()
        }
    }

    // MARK: - Table System
    private func findAndMoveToTable() -> Bool {
        guard let scene = parent as? SKScene else { return false }

        let availableTables = npcService.findAvailableTables(in: scene)
        if availableTables.isEmpty {
            return false
        }

        if let chosenTable = availableTables.randomElement() {
            let tableGridPos = gridService.worldToGrid(chosenTable.position)
            let adjacentCells = gridService.getAvailableAdjacentCells(to: tableGridPos)

            if let sittingSpot = adjacentCells.randomElement() {
                currentTable = chosenTable
                moveToCell(sittingSpot)
                return true
            }
        }

        return false
    }

    private func checkForDrinkOnTable(table: RotatableObject) -> Bool {
        let drinksOnTable = table.children.filter { $0.name == "drink_on_table" }

        if let drink = drinksOnTable.first {
            pickupDrinkFromTable(drink)
            return true
        }
        return false
    }

    private func pickupDrinkFromTable(_ drink: SKNode) {
        drink.removeFromParent()

        let carriedDrink = createCarriedDrink(from: drink)
        carriedDrink.position = GameConfig.NPC.CarriedDrink.carryOffset
        carriedDrink.zPosition = ZLayers.childLayer(for: ZLayers.npcs)
        addChild(carriedDrink)

        let floatAction = SKAction.repeatForever(
            SKAction.sequence([
                SKAction.moveBy(x: 0, y: GameConfig.NPC.CarriedDrink.floatDistance, duration: GameConfig.NPC.CarriedDrink.floatDuration),
                SKAction.moveBy(x: 0, y: -GameConfig.NPC.CarriedDrink.floatDistance, duration: GameConfig.NPC.CarriedDrink.floatDuration)
            ])
        )
        carriedDrink.run(floatAction, withKey: "floating")

        self.carriedDrink = carriedDrink as? RotatableObject
    }

    private func createCarriedDrink(from tableDrink: SKNode) -> SKNode {
        // Create carried drink using actual sprites (same as player drinks)
        let carriedVersion = SKNode()
        
        // Copy all sprite children from the table drink to preserve your artwork
        for child in tableDrink.children {
            if let spriteChild = child as? SKSpriteNode {
                let copiedSprite = spriteChild.copy() as! SKSpriteNode
                // Scale up slightly for NPC carried version (from 60% table size to ~80% of original)
                copiedSprite.setScale(spriteChild.xScale * 1.33) // 60% -> 80%
                copiedSprite.position = spriteChild.position
                copiedSprite.zPosition = spriteChild.zPosition
                copiedSprite.alpha = spriteChild.alpha
                carriedVersion.addChild(copiedSprite)
            }
        }
        
        // If no sprites were found, create a fallback using actual sprite assets
        if carriedVersion.children.isEmpty {
            let bobaAtlas = SKTextureAtlas(named: "Boba")
            let cupTexture = bobaAtlas.textureNamed("cup_empty")
            let cup = SKSpriteNode(texture: cupTexture)
            let cupScale = 20.0 / cupTexture.size().width // Small scale for NPC
            cup.setScale(cupScale)
            cup.position = CGPoint.zero
            cup.zPosition = 0
            carriedVersion.addChild(cup)
            
            print("🧋 NPC created fallback drink with actual cup sprite")
        } else {
            print("🧋 NPC copied \(carriedVersion.children.count) sprite layers from table drink")
        }
        
        return carriedVersion
    }

    // MARK: - Exit System
    private func moveTowardExit() {
        if let targetCell = npcService.findPathToExit(from: gridPosition) {
            moveToCell(targetCell)
        } else {
            let doorWorldPos = GameConfig.doorWorldPosition()
            // FIXED: Use proper movement initialization for exit movement
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
        state = .leaving(satisfied: satisfied)
        stateTimer = 0
        currentTable = nil

        if satisfied {
            startHappyAnimation()
        } else {
            startNeutralAnimation()
        }
    }

    func startLeaving(satisfied: Bool) {
        transitionToLeaving(satisfied: satisfied)
    }

    // MARK: - Animations
    private func startHappyAnimation() {
        removeAction(forKey: "happy_shimmer")
        removeAction(forKey: "happy_shake")

        let shimmer = SKAction.repeatForever(
            SKAction.sequence([
                SKAction.scale(to: GameConfig.NPC.Animations.shimmerScaleAmount, duration: GameConfig.NPC.Animations.shimmerDuration),
                SKAction.scale(to: 1.0, duration: GameConfig.NPC.Animations.shimmerDuration)
            ])
        )
        run(shimmer, withKey: "happy_shimmer")

        let colorFlash = SKAction.repeatForever(
            SKAction.sequence([
                SKAction.colorize(with: .yellow, colorBlendFactor: 0.3, duration: GameConfig.NPC.Animations.colorFlashDuration),
                SKAction.colorize(withColorBlendFactor: 0.0, duration: GameConfig.NPC.Animations.colorFlashDuration)
            ])
        )
        run(colorFlash, withKey: "happy_flash")
    }

    private func startNeutralAnimation() {
        let sigh = SKAction.repeatForever(
            SKAction.sequence([
                SKAction.scale(to: GameConfig.NPC.Animations.neutralScaleAmount, duration: GameConfig.NPC.Animations.neutralSighDuration),
                SKAction.scale(to: 1.0, duration: GameConfig.NPC.Animations.neutralSighDuration)
            ])
        )
        run(sigh, withKey: "neutral_sigh")

        let grayTint = SKAction.colorize(with: .gray, colorBlendFactor: GameConfig.NPC.Animations.neutralGrayBlend, duration: GameConfig.NPC.Animations.neutralFadeDuration)
        run(grayTint, withKey: "neutral_tint")
    }

    private func stopHappyAnimation() {
        removeAction(forKey: "happy_shimmer")
        removeAction(forKey: "happy_flash")

        let resetAction = SKAction.group([
            SKAction.scale(to: 1.0, duration: GameConfig.NPC.Animations.resetDuration),
            SKAction.colorize(withColorBlendFactor: 0.0, duration: GameConfig.NPC.Animations.resetDuration)
        ])
        run(resetAction)
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

    // MARK: - Lifecycle
    private func removeSelf() {
        print("🚺 ✅ \(animalType.rawValue) leaving scene - cleaning up")
        
        switch state {
        case .leaving(let satisfied):
            if satisfied { 
                stopHappyAnimation() 
                print("🚺 \(animalType.rawValue) left satisfied 😊")
            } else { 
                stopNeutralAnimation() 
                print("🚺 \(animalType.rawValue) left disappointed 😔")
            }
        default: 
            print("🚺 \(animalType.rawValue) left in \(state.displayName) state")
        }

        // Clean up carried drink
        if let drink = carriedDrink { 
            drink.removeFromParent() 
            print("🧋 Removed carried drink from \(animalType.rawValue)")
        }
        
        // Free up grid space
        gridService.freeCell(gridPosition)
        print("🗺 Freed grid cell \(gridPosition) for \(animalType.rawValue)")
        
        // Remove from scene
        removeFromParent()
        print("🎆 \(animalType.rawValue) successfully removed from scene")
    }

    // MARK: - Debug
    func getStateInfo() -> String {
        "\\(animalType.rawValue) - \\(state.displayName) - \\(Int(stateTimer))s"
    }
}
