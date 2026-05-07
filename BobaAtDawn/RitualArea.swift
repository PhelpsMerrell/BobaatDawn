//
//  RitualArea.swift
//  BobaAtDawn
//
//  Sacred ritual area for dawn soul liberation ceremonies
//

import SpriteKit

enum RitualState {
    case dormant        // No ritual items visible
    case available     // Candles present, waiting for lighting
    case candlesLit    // All candles lit, harp ready
    case npcSummoned   // NPC at table awaiting final service
    case completed     // Ritual finished, cleanup
}

/// Whether the NPC is being liberated through divine grace or hellish judgement
enum LiberationType {
    case divine   // Satisfaction >= 80 — flash of golden light
    case hellish  // Satisfaction <= 20 — eruption of hellish fire
    
    var displayName: String {
        switch self {
        case .divine: return "Divine Light"
        case .hellish: return "Hellish Fire"
        }
    }
}

class RitualArea: SKNode {
    
    // MARK: - Properties
    private(set) var ritualState: RitualState = .dormant
    private var candles: [RitualCandle] = []
    private var sacredTable: RotatableObject!
    
    // Grid positioning
    private let gridService: GridService
    private let centerPosition: GridCoordinate
    
    // Ritual management
    private var litCandleCount: Int = 0
    private var chosenNPC: NPCResident?
    private var liberationNPC: ShopNPC?
    private(set) var liberationType: LiberationType = .divine
    
    // Callbacks
    var onNPCSummoned: ((NPCResident) -> Void)?
    var onRitualCompleted: ((NPCResident) -> Void)?
    /// Fired when the seventh candle is lit. GameScene uses this to
    /// detect the case where the player placed a drink on the sacred
    /// table BEFORE finishing the candles — the ritual completes the
    /// moment the gate opens.
    var onCandlesAllLit: (() -> Void)?
    
    // MARK: - Initialization
    init(gridService: GridService, centerPosition: GridCoordinate) {
        self.gridService = gridService
        self.centerPosition = centerPosition
        
        super.init()
        
        self.name = "ritual_area"
        self.zPosition = ZLayers.ritualArea
        
        Log.info(.ritual, "Ritual area created at grid \(centerPosition)")
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Ritual Lifecycle
    func spawnRitual() {
        guard ritualState == .dormant else { 
            Log.warn(.ritual, "Ritual already active")
            return 
        }
        
        ritualState = .available
        litCandleCount = 0
        
        // Create ritual items
        createCandles()
        createSacredTable()
        
        // Spawn animation
        spawnAnimation()
        
        Log.info(.ritual, "DAWN RITUAL MANIFESTS — candles and harp appear")
        
        // Summon the chosen NPC NOW, at dawn, rather than waiting for the
        // player to play the harp. The NPC walks to the sacred table and
        // sits, ready to receive their final boba once the player has
        // lit all 7 candles. The harp is now atmospheric.
        summonChosenNPC()
    }
    
    private func createCandles() {
        candles.removeAll()
        
        // 7 candles in perfect circle formation
        let candlePositions = generateCandlePositions()
        
        for (index, gridPos) in candlePositions.enumerated() {
            let candle = RitualCandle()
            let worldPos = gridService.gridToWorld(gridPos)
            candle.position = worldPos
            
            // Set up candle callback
            candle.onLit = { [weak self] in
                self?.candleLit()
            }
            
            addChild(candle)
            candles.append(candle)
            
            Log.debug(.ritual, "Candle \(index + 1) placed at grid \(gridPos)")
        }
    }
    
    private func generateCandlePositions() -> [GridCoordinate] {
        let radius = GameConfig.Ritual.candleRadius
        let count = GameConfig.Ritual.candleCount
        var positions: [GridCoordinate] = []
        
        for i in 0..<count {
            let angle = Double(i) * (2.0 * Double.pi / Double(count)) - (Double.pi / 2.0)
            let x = centerPosition.x + Int(round(Double(radius) * cos(angle)))
            let y = centerPosition.y + Int(round(Double(radius) * sin(angle)))
            positions.append(GridCoordinate(x: x, y: y))
        }
        
        return positions
    }
    
    private func createSacredTable() {
        let tablePosition = centerPosition
        let worldPos = gridService.gridToWorld(tablePosition)
        
        sacredTable = RotatableObject(type: .furniture, color: SKColor.gold, shape: "table")
        sacredTable.position = worldPos
        sacredTable.name = "sacred_table"  // CRITICAL: Special name for ritual table
        sacredTable.zPosition = ZLayers.tables
        
        addChild(sacredTable)
        Log.debug(.ritual, "Sacred table at grid \(tablePosition)")
        
        // FIXED: Reserve the grid cell for the sacred table
        gridService.reserveCell(tablePosition)
        let gameObject = GameObject(skNode: sacredTable, gridPosition: tablePosition, objectType: .furniture, gridService: gridService)
        gridService.occupyCell(tablePosition, with: gameObject)
        Log.debug(.ritual, "Sacred table registered in grid")
    }
    
    // MARK: - Ritual Progression
    private func candleLit() {
        litCandleCount += 1
        Log.info(.ritual, "Candle lit (\(litCandleCount)/\(GameConfig.Ritual.candleCount))")
        
        if litCandleCount >= GameConfig.Ritual.candleCount {
            allCandlesLit()
        }
    }
    
    private func allCandlesLit() {
        guard ritualState == .available else { return }
        
        ritualState = .candlesLit
        
        Log.info(.ritual, "ALL CANDLES LIT — the gate opens")
        
        // Notify GameScene so it can complete a ritual whose drink was
        // placed on the sacred table BEFORE the last candle was lit.
        onCandlesAllLit?()
    }
    
    private func summonChosenNPC() {
        // Idempotent: spawnRitual now calls this, and harpPlayed used to
        // (legacy paths may still flow through). Don't double-summon.
        guard chosenNPC == nil else { return }
        
        chosenNPC = selectNPCForLiberation()
        
        guard let chosenResident = chosenNPC else {
            Log.error(.ritual, "No eligible NPC for liberation")
            cleanupRitual()
            return
        }
        
        Log.info(.ritual, "\(chosenResident.npcData.name) answers the sacred call (\(liberationType.displayName))")
        
        // Notify game scene to create liberation NPC
        onNPCSummoned?(chosenResident)
    }
    
    // MARK: - NPC Selection
    private func selectNPCForLiberation() -> NPCResident? {
        let allNPCs = DialogueService.shared.getAllNPCs()
        
        var eligibleNPCs: [(NPCData, Int)] = []
        
        for npcData in allNPCs {
            // Skip already liberated NPCs
            if SaveService.shared.isNPCLiberated(npcData.id) {
                continue
            }
            
            if let memory = SaveService.shared.getOrCreateNPCMemory(npcData.id, name: npcData.name, animalType: npcData.animal) {
                let satisfaction = memory.satisfactionScore
                // Eligible if OUTSIDE the normal range: below 20 or above 80
                if satisfaction <= 20 || satisfaction >= 80 {
                    eligibleNPCs.append((npcData, satisfaction))
                }
            }
        }
        
        // Sort by extremity — furthest from center (50) first
        eligibleNPCs.sort { abs($0.1 - 50) > abs($1.1 - 50) }
        
        if let chosenData = eligibleNPCs.first {
            // Determine liberation type based on satisfaction
            liberationType = chosenData.1 >= 80 ? .divine : .hellish
            
            let direction = liberationType == .divine ? "divine (high satisfaction)" : "hellish (low satisfaction)"
            Log.debug(.ritual, "Selected \(chosenData.0.name) for \(direction) liberation (satisfaction: \(chosenData.1))")
            return NPCResident(npcData: chosenData.0)
        }
        
        return nil
    }
    
    // MARK: - Final Service
    func npcArrivedAtTable(_ npc: ShopNPC) {
        liberationNPC = npc
        Log.debug(.ritual, "\(npc.animalType.rawValue) arrived at sacred table")
    }
    
    func finalBobaServed() {
        guard let chosenResident = chosenNPC else { return }
        
        ritualState = .completed
        
        // NOTE: Save system marking is handled by GameScene.completeRitualLiberation()
        // RitualArea only manages its own visual state and fires the callback.
        onRitualCompleted?(chosenResident)
        
        // Cleanup ritual after delay
        DispatchQueue.main.asyncAfter(deadline: .now() + GameConfig.Ritual.cleanupDelay) {
            self.cleanupRitual()
        }
        
        Log.info(.ritual, "Final boba served — \(liberationType.displayName) liberation initiated")
    }
    
    // MARK: - Animations
    private func spawnAnimation() {
        // All items start invisible and scale up
        for child in children {
            child.alpha = 0.0
            child.setScale(0.5)
        }
        
        // Staggered appearance
        for (index, child) in children.enumerated() {
            let delay = Double(index) * 0.2
            
            let appear = SKAction.sequence([
                SKAction.wait(forDuration: delay),
                SKAction.group([
                    SKAction.fadeIn(withDuration: 0.5),
                    SKAction.scale(to: 1.0, duration: 0.5)
                ])
            ])
            
            child.run(appear)
        }
    }
    
    // MARK: - Cleanup
    private func cleanupRitual() {
        ritualState = .dormant
        litCandleCount = 0
        chosenNPC = nil
        liberationNPC = nil
        
        // Fade away all ritual items
        for candle in candles {
            candle.fadeAway()
        }
        
        sacredTable?.fadeAway()
        
        candles.removeAll()
        
        Log.info(.ritual, "Dawn ritual fades — until next dawn")
    }
    
    /// True once every ritual candle is lit. Used by GameScene to gate
    /// the "drink on sacred table → trigger ritual sequence" path so the
    /// player must complete the candle round before liberation can fire.
    func areCandlesAllLit() -> Bool {
        return litCandleCount >= GameConfig.Ritual.candleCount
    }
    
    // MARK: - Public Interface
    func hasEligibleNPCs() -> Bool {
        let allNPCs = DialogueService.shared.getAllNPCs()
        
        for npcData in allNPCs {
            if SaveService.shared.isNPCLiberated(npcData.id) {
                continue
            }
            
            if let memory = SaveService.shared.getOrCreateNPCMemory(npcData.id, name: npcData.name, animalType: npcData.animal) {
                let satisfaction = memory.satisfactionScore
                // Eligible if OUTSIDE the normal range
                if satisfaction <= 20 || satisfaction >= 80 {
                    return true
                }
            }
        }
        
        return false
    }
    
    func forceCleanup() {
        cleanupRitual()
    }
}
