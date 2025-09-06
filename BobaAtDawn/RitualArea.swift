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

class RitualArea: SKNode {
    
    // MARK: - Properties
    private(set) var ritualState: RitualState = .dormant
    private var candles: [RitualCandle] = []
    private var sacredHarp: SacredHarp!
    private var sacredTable: RotatableObject!
    
    // Grid positioning
    private let gridService: GridService
    private let centerPosition: GridCoordinate
    
    // Ritual management
    private var litCandleCount: Int = 0
    private var chosenNPC: NPCResident?
    private var liberationNPC: NPC?
    
    // Callbacks
    var onNPCSummoned: ((NPCResident) -> Void)?
    var onRitualCompleted: ((NPCResident) -> Void)?
    
    // MARK: - Initialization
    init(gridService: GridService, centerPosition: GridCoordinate) {
        self.gridService = gridService
        self.centerPosition = centerPosition
        
        super.init()
        
        self.name = "ritual_area"
        self.zPosition = ZLayers.ritualArea
        
        print("🕯️ ✨ Ritual area created at grid \(centerPosition)")
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Ritual Lifecycle
    func spawnRitual() {
        guard ritualState == .dormant else { 
            print("⚠️ Ritual already active")
            return 
        }
        
        ritualState = .available
        litCandleCount = 0
        
        // Create ritual items
        createCandles()
        createSacredHarp()
        createSacredTable()
        
        // Spawn animation
        spawnAnimation()
        
        print("🌅 ✨ DAWN RITUAL MANIFESTS - Sacred candles and harp appear!")
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
            
            print("🕯️ Candle \(index + 1) placed at grid \(gridPos)")
        }
    }
    
    private func generateCandlePositions() -> [GridCoordinate] {
        // 7 candles in a circle around center position
        let radius = 2 // Grid cells
        var positions: [GridCoordinate] = []
        
        for i in 0..<7 {
            let angle = Double(i) * (2.0 * Double.pi / 7.0) - (Double.pi / 2.0) // Start from top
            let x = centerPosition.x + Int(round(Double(radius) * cos(angle)))
            let y = centerPosition.y + Int(round(Double(radius) * sin(angle)))
            positions.append(GridCoordinate(x: x, y: y))
        }
        
        return positions
    }
    
    private func createSacredHarp() {
        sacredHarp = SacredHarp()
        let worldPos = gridService.gridToWorld(centerPosition)
        sacredHarp.position = worldPos
        
        // Set up harp callback
        sacredHarp.onPlayed = { [weak self] in
            self?.harpPlayed()
        }
        
        addChild(sacredHarp)
        print("🎵 Sacred harp placed at center grid \(centerPosition)")
    }
    
    private func createSacredTable() {
        // Sacred table positioned near the ritual circle
        let tablePosition = GridCoordinate(x: centerPosition.x, y: centerPosition.y - 4)
        let worldPos = gridService.gridToWorld(tablePosition)
        
        sacredTable = RotatableObject(type: .furniture, color: SKColor.gold, shape: "table")
        sacredTable.position = worldPos
        sacredTable.name = "sacred_table"
        sacredTable.zPosition = ZLayers.tables
        
        addChild(sacredTable)
        print("🔮 Sacred table placed at grid \(tablePosition)")
    }
    
    // MARK: - Ritual Progression
    private func candleLit() {
        litCandleCount += 1
        print("🔥 Candle lit! (\(litCandleCount)/7)")
        
        if litCandleCount >= 7 {
            allCandlesLit()
        }
    }
    
    private func allCandlesLit() {
        guard ritualState == .available else { return }
        
        ritualState = .candlesLit
        
        // Activate the sacred harp
        sacredHarp.activate()
        
        print("🔥 ✨ ALL SEVEN CANDLES BURN BRIGHT! The sacred harp awakens...")
    }
    
    private func harpPlayed() {
        guard ritualState == .candlesLit else { return }
        
        ritualState = .npcSummoned
        
        // Find and summon the chosen NPC
        summonChosenNPC()
        
        print("🎵 ✨ LIBERATION SONG ECHOES! A soul responds to the sacred call...")
    }
    
    private func summonChosenNPC() {
        // Find highest satisfaction NPC in range 45-75
        chosenNPC = selectNPCForLiberation()
        
        guard let chosenResident = chosenNPC else {
            print("❌ No eligible NPC found for liberation")
            cleanupRitual()
            return
        }
        
        print("👻 ✨ \(chosenResident.npcData.name) (\(chosenResident.npcData.emoji)) answers the sacred call!")
        
        // Notify game scene to create liberation NPC
        onNPCSummoned?(chosenResident)
    }
    
    // MARK: - NPC Selection
    private func selectNPCForLiberation() -> NPCResident? {
        // Get all NPCs and their satisfaction scores
        let allNPCs = DialogueService.shared.getAllNPCs()
        
        var eligibleNPCs: [(NPCData, Int)] = []
        
        for npcData in allNPCs {
            // Skip already liberated NPCs
            if SaveService.shared.isNPCLiberated(npcData.id) {
                continue
            }
            
            if let memory = SaveService.shared.getOrCreateNPCMemory(npcData.id, name: npcData.name, animalType: npcData.animal) {
                let satisfaction = memory.satisfactionScore
                if satisfaction >= 45 && satisfaction <= 75 {
                    eligibleNPCs.append((npcData, satisfaction))
                }
            }
        }
        
        // Sort by satisfaction score (highest first)
        eligibleNPCs.sort { $0.1 > $1.1 }
        
        if let chosenData = eligibleNPCs.first {
            print("👻 Selected \(chosenData.0.name) for liberation (satisfaction: \(chosenData.1))")
            return NPCResident(npcData: chosenData.0)
        }
        
        return nil
    }
    
    // MARK: - Final Service
    func npcArrivedAtTable(_ npc: NPC) {
        liberationNPC = npc
        print("👻 \(npc.animalType.rawValue) has arrived at the sacred table")
    }
    
    func finalBobaServed() {
        guard let chosenResident = chosenNPC else { return }
        
        ritualState = .completed
        
        // Show farewell dialogue
        showFarewellDialogue()
        
        // Complete liberation after dialogue
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            self.completeLiberation()
        }
    }
    
    private func showFarewellDialogue() {
        guard let npc = liberationNPC,
              let chosenResident = chosenNPC else { return }
        
        // Create farewell dialogue
        let farewellLines = [
            "Thank you for helping me find peace...",
            "I can finally let go of this world.",
            "The boba you made was perfect - it gave me strength.",
            "I'm ready to move on now. Farewell, kind soul."
        ]
        
        if let scene = scene {
            // Show special liberation dialogue
            let dialogueProxy = NPCDialogueProxy(npc: npc, characterId: chosenResident.npcData.id)
            DialogueService.shared.showCustomDialogue(
                for: dialogueProxy, 
                in: scene, 
                customLines: farewellLines
            )
        }
        
        print("💬 👻 \(chosenResident.npcData.name) says their final farewell...")
    }
    
    private func completeLiberation() {
        guard let chosenResident = chosenNPC else { return }
        
        // Liberation animation
        liberationAnimation()
        
        // Remove NPC from world permanently
        liberationNPC?.removeFromParent()
        
        // Notify completion
        onRitualCompleted?(chosenResident)
        
        // Cleanup ritual
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            self.cleanupRitual()
        }
        
        print("✨ 👻 \(chosenResident.npcData.name) has found eternal peace and moves on from purgatory")
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
    
    private func liberationAnimation() {
        guard let npc = liberationNPC else { return }
        
        // Beautiful ascension effect
        let ascension = SKAction.sequence([
            SKAction.group([
                SKAction.fadeOut(withDuration: 2.0),
                SKAction.scale(to: 2.0, duration: 2.0),
                SKAction.moveBy(x: 0, y: 100, duration: 2.0)
            ])
        ])
        
        // Create light particles
        for i in 0..<10 {
            let delay = Double(i) * 0.1
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                self.createLightParticle(from: npc.position)
            }
        }
        
        npc.run(ascension)
    }
    
    private func createLightParticle(from position: CGPoint) {
        let particle = SKLabelNode(text: "✨")
        particle.fontSize = 20
        particle.position = position
        particle.zPosition = ZLayers.effects
        
        if let parent = parent {
            parent.addChild(particle)
            
            let float = SKAction.sequence([
                SKAction.group([
                    SKAction.moveBy(x: CGFloat.random(in: -50...50), 
                                   y: CGFloat.random(in: 50...150), 
                                   duration: 3.0),
                    SKAction.fadeOut(withDuration: 3.0)
                ]),
                SKAction.removeFromParent()
            ])
            
            particle.run(float)
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
        
        sacredHarp?.fadeAway()
        sacredTable?.fadeAway()
        
        candles.removeAll()
        
        print("🌅 Dawn ritual fades as the sun rises... until next dawn")
    }
    
    // MARK: - Public Interface
    func hasEligibleNPCs() -> Bool {
        let allNPCs = DialogueService.shared.getAllNPCs()
        
        for npcData in allNPCs {
            // Skip already liberated NPCs
            if SaveService.shared.isNPCLiberated(npcData.id) {
                continue
            }
            
            if let memory = SaveService.shared.getOrCreateNPCMemory(npcData.id, name: npcData.name, animalType: npcData.animal) {
                let satisfaction = memory.satisfactionScore
                if satisfaction >= 45 && satisfaction <= 75 {
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
