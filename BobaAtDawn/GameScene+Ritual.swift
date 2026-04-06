//
//  GameScene+Ritual.swift
//  BobaAtDawn
//
//  Ritual system: setup, NPC summoning, liberation sequence, and visual effects.
//  Extracted from GameScene.swift for maintainability.
//

import SpriteKit

extension GameScene {
    
    // MARK: - Ritual Area Setup
    
    func setupRitualArea() {
        let ritualCenter = GameConfig.Ritual.centerPosition
        
        ritualArea = RitualArea(gridService: gridService, centerPosition: ritualCenter)
        
        ritualArea.onNPCSummoned = { [weak self] chosenResident in
            self?.handleNPCSummoned(chosenResident)
        }
        
        ritualArea.onRitualCompleted = { [weak self] liberatedResident in
            self?.handleRitualCompleted(liberatedResident)
        }
        
        addChild(ritualArea)
        Log.info(.ritual, "Ritual area ready at grid \(ritualCenter)")
    }
    
    // MARK: - NPC Creation for Resident Manager
    
    func createShopNPC(animalType: AnimalType, resident: NPCResident) -> ShopNPC {
        let npc = ShopNPC(animal: animalType,
                          startPosition: GameConfig.World.doorGridPosition,
                          gridService: gridService,
                          npcService: npcService)
        
        addChild(npc)
        npcs.append(npc)
        addEntranceAnimation(for: npc)
        
        Log.info(.npc, "Created shop NPC \(animalType.rawValue) for \(resident.npcData.name)")
        return npc
    }
    
    func addEntranceAnimation(for npc: ShopNPC) {
        npc.alpha = 0.0
        npc.setScale(0.8)
        
        let anim = SKAction.group([
            SKAction.fadeIn(withDuration: 0.5),
            SKAction.scale(to: 1.0, duration: 0.5)
        ])
        anim.timingMode = .easeOut
        npc.run(anim)
    }
    
    // MARK: - Ritual Time Phase Integration
    
    func handleRitualTimePhaseChange(_ phase: TimePhase) {
        switch phase {
        case .dawn:
            timeService.advanceDay()
            
            if timeService.isRitualDay && ritualArea.hasEligibleNPCs() {
                ritualArea.spawnRitual()
                isRitualActive = true
                Log.info(.ritual, "DAY \(timeService.dayCount) — RITUAL DAY! Sacred ritual manifests")
            } else if timeService.isRitualDay {
                Log.info(.ritual, "Day \(timeService.dayCount) is a ritual day, but no souls are ready")
            } else {
                let nextRitual = (timeService.dayCount / GameConfig.Ritual.ritualDayInterval + 1) * GameConfig.Ritual.ritualDayInterval
                Log.debug(.ritual, "Day \(timeService.dayCount) — next ritual on day \(nextRitual)")
            }
            
        case .day, .dusk, .night:
            if isRitualActive {
                ritualArea.forceCleanup()
                isRitualActive = false
                residentManager.clearRitualNPC()
                Log.info(.ritual, "Ritual fades as \(phase.displayName) begins")
            }
        }
    }
    
    // MARK: - NPC Summoning
    
    func handleNPCSummoned(_ chosenResident: NPCResident) {
        Log.info(.ritual, "NPC summoned: \(chosenResident.npcData.name)")
        
        let matchingNPC = npcs.first { $0.animalType.characterId == chosenResident.npcData.id }
        
        Log.debug(.ritual, "Looking for character ID: \(chosenResident.npcData.id)")
        Log.debug(.ritual, "Shop NPCs: \(npcs.map { "\($0.animalType.rawValue)(\($0.animalType.characterId ?? "no-id"))" })")
        
        guard let ritualNPC = matchingNPC else {
            Log.warn(.ritual, "No matching shop NPC — creating fallback")
            createRitualNPC(chosenResident)
            return
        }
        
        let preferredSpot = GameConfig.Ritual.ritualSittingSpot
        let altSpots = GameConfig.Ritual.alternativeSittingSpots
        
        var chosenSpot = preferredSpot
        if !gridService.isCellAvailable(preferredSpot) {
            chosenSpot = altSpots.first { gridService.isCellAvailable($0) } ?? preferredSpot
            if !gridService.isCellAvailable(chosenSpot) {
                gridService.freeCell(chosenSpot)
                Log.debug(.ritual, "Force-cleared spot \(chosenSpot) for ritual NPC")
            }
        }
        
        ritualNPC.movementController.moveToGrid(chosenSpot) { [weak self] in
            guard let self = self else { return }
            self.gridService.reserveCell(chosenSpot)
            
            if let sacredTable = self.findSacredTable() {
                ritualNPC.transitionToRitualSitting(table: sacredTable)
                Log.info(.ritual, "RITUAL MODE ACTIVATED for \(ritualNPC.animalType.rawValue)")
            } else {
                Log.error(.ritual, "Could not find sacred table for ritual sitting")
            }
        }
        
        startRitualPulsing(ritualNPC)
        residentManager.setRitualNPC(chosenResident.npcData.id)
        ritualArea.npcArrivedAtTable(ritualNPC)
        
        Log.info(.ritual, "\(chosenResident.npcData.name) moves to sacred table for liberation")
    }
    
    func createRitualNPC(_ chosenResident: NPCResident) {
        let animalType = AnimalType.allCases.first { $0.characterId == chosenResident.npcData.id } ?? .fox
        let sittingSpot = GameConfig.Ritual.ritualSittingSpot
        
        let npc = ShopNPC(animal: animalType, startPosition: sittingSpot,
                          gridService: gridService, npcService: npcService)
        npc.position = gridService.gridToWorld(sittingSpot)
        
        addChild(npc)
        npcs.append(npc)
        
        if let sacredTable = findSacredTable() {
            npc.transitionToRitualSitting(table: sacredTable)
        }
        
        startRitualPulsing(npc)
        ritualArea.npcArrivedAtTable(npc)
        
        // Summoning animation
        npc.alpha = 0.0
        npc.setScale(0.5)
        npc.run(SKAction.group([
            SKAction.fadeIn(withDuration: 1.5),
            SKAction.scale(to: 1.0, duration: 1.5)
        ]))
        
        Log.info(.ritual, "\(chosenResident.npcData.name) materializes at the sacred table")
    }
    
    // MARK: - Ritual Visual Effects
    
    func startRitualPulsing(_ npc: ShopNPC) {
        let pulse = SKAction.repeatForever(SKAction.sequence([
            SKAction.scale(to: 1.2, duration: 1.0),
            SKAction.scale(to: 1.0, duration: 1.0)
        ]))
        npc.run(pulse, withKey: "ritual_pulse")
        
        // Colorize targets emojiLabel (SKLabelNode), not the SKNode itself
        let glow = SKAction.repeatForever(SKAction.sequence([
            SKAction.colorize(with: .gold, colorBlendFactor: 0.3, duration: 1.0),
            SKAction.colorize(withColorBlendFactor: 0.0, duration: 1.0)
        ]))
        npc.emojiLabel.run(glow, withKey: "ritual_glow")
        
        Log.debug(.ritual, "\(npc.animalType.rawValue) pulsing with sacred energy")
    }
    
    func handleRitualCompleted(_ liberatedResident: NPCResident) {
        if let ritualNPC = npcs.first(where: { $0.animalType.characterId == liberatedResident.npcData.id }) {
            ritualNPC.removeAction(forKey: "ritual_pulse")
            ritualNPC.emojiLabel.removeAction(forKey: "ritual_glow")
            ritualNPC.setScale(1.0)
            ritualNPC.emojiLabel.colorBlendFactor = 0.0
        }
        Log.info(.ritual, "\(liberatedResident.npcData.name) has found eternal peace")
    }
    
    // MARK: - Ritual Drink Sequence
    
    func triggerRitualSequence(drinkOnTable: SKNode, sacredTable: RotatableObject) {
        Log.info(.ritual, "RITUAL SEQUENCE TRIGGERED — sacred boba placed!")
        
        guard let ritualNPC = npcs.first(where: { $0.isCurrentlyInRitual() }) else {
            Log.error(.ritual, "No ritual NPC found to complete the sequence")
            return
        }
        
        Log.debug(.ritual, "Found ritual NPC: \(ritualNPC.animalType.rawValue)")
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            self?.ritualNPCTakesDrink(npc: ritualNPC, drink: drinkOnTable)
        }
    }
    
    func ritualNPCTakesDrink(npc: ShopNPC, drink: SKNode) {
        Log.info(.ritual, "\(npc.animalType.rawValue) takes their final boba")
        
        let pickup = SKAction.move(to: CGPoint(x: npc.position.x, y: npc.position.y + 30), duration: 1.0)
        drink.run(pickup)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            self?.npcTransformsAndLeaves(npc: npc, drink: drink)
        }
    }
    
    func npcTransformsAndLeaves(npc: ShopNPC, drink: SKNode) {
        let isDivine = ritualArea.liberationType == .divine
        Log.info(.ritual, "\(npc.animalType.rawValue) \(isDivine ? "ascends in divine light" : "descends in hellish fire")")
        
        drink.removeFromParent()
        
        // Stop ritual effects
        npc.removeAction(forKey: "ritual_pulse")
        npc.emojiLabel.removeAction(forKey: "ritual_glow")
        
        if isDivine {
            // Divine liberation — golden/white light
            npc.emojiLabel.run(SKAction.sequence([
                SKAction.colorize(with: .yellow, colorBlendFactor: 0.8, duration: 0.5),
                SKAction.colorize(with: .white, colorBlendFactor: 1.0, duration: 0.5)
            ]))
            npc.run(SKAction.fadeAlpha(to: 0.8, duration: 1.0))
            
            let burst = SKSpriteNode(color: .yellow, size: CGSize(width: 200, height: 200))
            burst.position = npc.position
            burst.alpha = 0
            burst.zPosition = ZLayers.effects
            burst.blendMode = .add
            addChild(burst)
            burst.run(SKAction.sequence([
                SKAction.fadeAlpha(to: 0.6, duration: 0.3),
                SKAction.fadeOut(withDuration: 2.0),
                SKAction.removeFromParent()
            ]))
        } else {
            // Hellish liberation — red/orange fire
            npc.emojiLabel.run(SKAction.sequence([
                SKAction.colorize(with: .red, colorBlendFactor: 0.8, duration: 0.5),
                SKAction.colorize(with: .orange, colorBlendFactor: 0.6, duration: 0.5)
            ]))
            npc.run(SKAction.fadeAlpha(to: 0.8, duration: 1.0))
            
            let burst = SKSpriteNode(color: .red, size: CGSize(width: 200, height: 200))
            burst.position = npc.position
            burst.alpha = 0
            burst.zPosition = ZLayers.effects
            burst.blendMode = .add
            addChild(burst)
            burst.run(SKAction.sequence([
                SKAction.fadeAlpha(to: 0.6, duration: 0.3),
                SKAction.colorize(with: .orange, colorBlendFactor: 0.5, duration: 1.0),
                SKAction.fadeOut(withDuration: 1.5),
                SKAction.removeFromParent()
            ]))
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
            self?.completeRitualLiberation(npc: npc)
        }
    }
    
    func completeRitualLiberation(npc: ShopNPC) {
        Log.info(.ritual, "LIBERATION COMPLETE — \(npc.animalType.rawValue) leaves forever")
        
        if let characterId = npc.animalType.characterId {
            SaveService.shared.markNPCAsLiberated(characterId)
        }
        
        npc.clearRitualMode()
        
        if let index = npcs.firstIndex(where: { $0 === npc }) {
            npcs.remove(at: index)
        }
        npc.removeFromParent()
        
        residentManager.clearRitualNPC()
        ritualArea.finalBobaServed()
        
        Log.info(.ritual, "Ritual complete — the soul has found peace")
    }
    
    // MARK: - Helpers
    
    func findSacredTable() -> RotatableObject? {
        // Check ritual area children first, then scene children
        if let table = ritualArea?.children.first(where: { $0.name == "sacred_table" }) as? RotatableObject {
            return table
        }
        return children.first(where: { $0.name == "sacred_table" }) as? RotatableObject
    }
}
