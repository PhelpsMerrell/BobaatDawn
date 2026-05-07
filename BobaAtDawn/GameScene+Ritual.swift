//
//  GameScene+Ritual.swift
//  BobaAtDawn
//
//  Ritual system: setup, NPC summoning, liberation sequence, and visual effects.
//  Extracted from GameScene.swift for maintainability.
//

import SpriteKit

// MARK: - Ritual NPC Liberation Lines
//
// Spoken once when the chosen NPC arrives at the sacred table at dawn.
// Pool selection is keyed off `RitualArea.liberationType` (computed from
// the NPC's satisfaction score — ≥80 → divine, ≤20 → hellish).

private let divineLiberationLines: [String] = [
    "I'm ready. The shop has been kind to me.",
    "I came here lost. Now I leave full.",
    "I think… I think I can let go now.",
    "Thank you. For all of it.",
    "I'm at peace.",
    "It tastes like home, in the end.",
    "Take me where the light goes."
]

private let hellishLiberationLines: [String] = [
    "Why did it have to be like this?",
    "Nothing helped. Nothing ever did.",
    "Let it end. I'm so tired of this place.",
    "I never got what I wanted here.",
    "Just take me. I'm done.",
    "Bitter all the way down.",
    "I won't miss any of it."
]

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
        
        // If the player placed a drink on the sacred table BEFORE
        // lighting all candles, this callback completes the ritual the
        // moment the seventh candle ignites.
        ritualArea.onCandlesAllLit = { [weak self] in
            self?.handleAllCandlesLit()
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
            // Only host advances the day counter — guest receives
            // day count via timeSync/hostHandshake.
            if !MultiplayerService.shared.isGuest {
                // Capture the day that just ended BEFORE advancing.
                let endingDay = timeService.dayCount
                timeService.advanceDay()
                
                // Generate the chronicle for the day that just ended.
                generateDailyChronicleAtDawn(endingDay: endingDay)
            }
            
            // Dawn clears in-progress drink state: station toggles reset,
            // the display reverts to an empty cup, and any drink in the
            // player's hand evaporates. Trash is intentionally NOT cleared
            // (the purgatory shop doesn't clean itself). Foraged ingredients
            // in hand also survive (see CharacterCarryState.clearDrinkOnly).
            clearInProgressDrinkAtDawn()
            
            // Refresh foraged spawns for the new day
            ForagingManager.shared.refreshIfNeeded(dayCount: timeService.dayCount)
            
            if timeService.isRitualDay && ritualArea.hasEligibleNPCs() {
                ritualArea.spawnRitual()
                isRitualActive = true
                Log.info(.ritual, "DAY \(timeService.dayCount) — RITUAL DAY! Sacred ritual manifests")
                
                // Broadcast ritual spawn to guest
                if MultiplayerService.shared.isHost {
                    MultiplayerService.shared.send(type: .ritualStateSync, payload: RitualStateSyncMessage(
                        isActive: true, currentStep: "available", ritualNPCId: nil
                    ))
                }
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
                
                // Broadcast ritual cleanup to guest
                if MultiplayerService.shared.isHost {
                    MultiplayerService.shared.send(type: .ritualStateSync, payload: RitualStateSyncMessage(
                        isActive: false, currentStep: nil, ritualNPCId: nil
                    ))
                }
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
                
                // Brief beat after sitting, then speak based on extremity.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                    self?.showRitualNPCDialogue(npc: ritualNPC)
                }
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
        
        // Wait for the materialization to finish, then speak.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { [weak self] in
            self?.showRitualNPCDialogue(npc: npc)
        }
        
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
            
            // Broadcast liberation to other player
            let libType = ritualArea.liberationType == .divine ? "divine" : "hellish"
            MultiplayerService.shared.send(type: .npcLiberated, payload: NPCLiberatedMessage(
                npcID: characterId, liberationType: libType
            ))
            // Chronicle hook — record divine vs hellish so the page can
            // colour the line correctly.
            let isDivine = ritualArea.liberationType == .divine
            let name = DialogueService.shared.getNPC(byId: characterId)?.name
                ?? npc.animalType.rawValue
            DailyChronicleLedger.shared.recordNPCLiberated(
                npcID: characterId, npcName: name, divine: isDivine
            )
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
    
    // MARK: - Ritual NPC Arrival Dialogue
    
    /// Show one line of liberation dialogue based on the NPC's satisfaction
    /// extremity. Called from both the existing-shop-NPC path
    /// (`handleNPCSummoned`) and the materialization-fallback path
    /// (`createRitualNPC`) once the NPC is at the sacred table.
    func showRitualNPCDialogue(npc: ShopNPC) {
        let pool = (ritualArea.liberationType == .divine)
            ? divineLiberationLines
            : hellishLiberationLines
        DialogueService.shared.showCustomDialogue(
            for: npc, in: self, customLines: pool
        )
    }
    
    // MARK: - Candles-Lit Hook
    
    /// Fired by RitualArea when the seventh candle is lit. If the player
    /// already placed a drink on the sacred table while the candles were
    /// being lit, complete the ritual immediately. Otherwise wait —
    /// the next placeDrinkOnTable will trigger it (since
    /// `areCandlesAllLit()` is now true).
    func handleAllCandlesLit() {
        guard let sacredTable = findSacredTable() else { return }
        guard let drink = sacredTable.children.first(where: {
            $0.name == "drink_on_table"
        }) else {
            Log.info(.ritual, "All candles lit — waiting for player to place a drink on the sacred table")
            return
        }
        Log.info(.ritual, "All candles lit AND drink already on sacred table — completing ritual")
        triggerRitualSequence(drinkOnTable: drink, sacredTable: sacredTable)
    }
    
    // MARK: - Dawn Drink Clear
    
    /// Wipe in-progress drink state at the start of a new day.
    ///   - Carried drink → dropped silently (matcha leaves survive)
    ///   - CharacterCarryState → clearDrinkOnly (belt-and-suspenders with
    ///     dropItemSilently, which also clears carry state)
    ///
    /// Stations no longer hold drink state post-refactor — they're dumb
    /// furniture — so there's nothing to reset there.
    /// Trash is intentionally left alone — the purgatory shop accumulates.
    private func clearInProgressDrinkAtDawn() {
        // Drop any drink in hand (leave matcha leaves alone)
        if let carried = character?.carriedItem, carried.name != "carried_matcha_leaf" {
            character.dropItemSilently()
        }
        // Clear persisted carry state for drinks only (no-op if already empty
        // or if carrying a matcha leaf).
        CharacterCarryState.shared.clearDrinkOnly()
        
        // Keep the counter display as a pristine empty cup.
        drinkCreator?.rebuildDisplayAsEmptyCup()
        
        Log.info(.ritual, "Dawn: cleared in-progress drink (trash preserved)")
    }
    
    // MARK: - Daily Chronicle
    
    /// Run on the host (or solo) at dawn rollover. Snapshots the previous
    /// day's ledger, hands it to DailyChronicleService, persists the
    /// resulting DailySummary, broadcasts it to the partner, and resets
    /// the ledger for the new day.
    ///
    /// - Parameter endingDay: The day count value that BELONGS to the
    ///   chronicle being written (i.e. the day that just ended, captured
    ///   before `advanceDay()` ran).
    func generateDailyChronicleAtDawn(endingDay: Int) {
        let snapshot = DailyChronicleLedger.shared.snapshot()
        DailyChronicleLedger.shared.reset()
        
        // Skip the very first dawn (no day 0 chronicle). On a fresh
        // world the first dawn rollover takes us 0 → 1, and there's
        // nothing meaningful in the day-0 ledger.
        guard endingDay > 0 else {
            Log.info(.dialogue, "[Chronicle] Skipping day \(endingDay) (initial rollover)")
            return
        }
        
        Log.info(.dialogue, "[Chronicle] Generating chronicle for day \(endingDay) (\(snapshot.count) events)")
        
        DailyChronicleService.shared.generate(
            dayCount: endingDay,
            events: snapshot
        ) { result in
            // Encode headlines + ledger for storage.
            let headlines = DailyChronicleHeadlines.aggregate(snapshot)
            let headlinesJSON: String = {
                guard let data = try? JSONEncoder().encode(headlines),
                      let s = String(data: data, encoding: .utf8) else { return "{}" }
                return s
            }()
            let ledgerJSON: String = {
                guard let data = try? JSONEncoder().encode(snapshot),
                      let s = String(data: data, encoding: .utf8) else { return "[]" }
                return s
            }()
            
            let summary = DailySummary(
                dayCount: endingDay,
                generatedAt: Date(),
                usedLLM: result.usedLLM,
                openingLine: result.openingLine,
                forestSection: result.forestSection,
                minesSection: result.minesSection,
                shopSection: result.shopSection,
                socialSection: result.socialSection,
                closingLine: result.closingLine,
                headlinesJSON: headlinesJSON,
                ledgerJSON: ledgerJSON
            )
            SaveService.shared.upsertDailySummary(summary)
            
            // Broadcast so the guest's book stays in sync.
            if MultiplayerService.shared.isConnected {
                MultiplayerService.shared.send(
                    type: .dailySummaryGenerated,
                    payload: DailySummaryGeneratedMessage(entry: summary.toEntry())
                )
            }
            Log.info(.dialogue, "[Chronicle] Day \(endingDay) page sealed (LLM: \(result.usedLLM))")
        }
    }
}
