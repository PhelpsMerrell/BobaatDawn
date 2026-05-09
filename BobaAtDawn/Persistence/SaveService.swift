//
//  SaveService.swift
//  BobaAtDawn
//
//  Service for handling game state persistence
//

import SwiftData
import Foundation

final class SaveService {
    static let shared = SaveService()

    struct SaveSlotSummary {
        let index: Int
        let name: String
        let isEmpty: Bool
        let dayCount: Int
        let lastSaved: Date?
    }

    private static let slotCount = 3
    private static let activeSlotDefaultsKey = "BobaAtDawn.ActiveSaveSlotIndex"
    
    private var modelContainer: ModelContainer?
    private var modelContext: ModelContext?
    private var activeSlotIndex: Int = SaveService.loadPersistedActiveSlotIndex()

    var currentSaveSlotIndex: Int { activeSlotIndex }
    var currentSaveSlotID: String { WorldState.slotID(for: activeSlotIndex) }
    
    private init() {
        setupSwiftData()
    }

    private static func clampSlotIndex(_ index: Int) -> Int {
        min(max(index, 1), slotCount)
    }

    private static func loadPersistedActiveSlotIndex() -> Int {
        let stored = UserDefaults.standard.integer(forKey: activeSlotDefaultsKey)
        return clampSlotIndex(stored == 0 ? 1 : stored)
    }
    
    // MARK: - SwiftData Setup
    private func setupSwiftData() {
        do {
            let schema = Schema([
                WorldState.self,
                NPCMemory.self,
                NPCRelationshipMemory.self,
                ShopMemory.self,
                NPCCharacter.self,
                DialogueLine.self,
                DailySummary.self
            ])
            
            let configuration = ModelConfiguration(
                "BobaWorldSave",
                schema: schema,
                isStoredInMemoryOnly: false
            )
            
            modelContainer = try ModelContainer(for: schema, configurations: [configuration])
            modelContext = ModelContext(modelContainer!)
            
            Log.info(.save, "SwiftData initialized successfully")
            createInitialDataIfNeeded()
            
            // Load persistent singletons from disk and wire up
            // mutation → persist hooks so their state survives both
            // scene transitions and app restarts.
            loadPersistentSingletons(resetRuntimeState: false)
            wirePersistenceHooks()
            
        } catch {
            Log.error(.save, "Failed to initialize SwiftData: \(error)")
        }
    }
    
    // MARK: - Save Game State
    func saveCurrentGameState(timeService: TimeService, residentManager: NPCResidentManager) {
        guard let context = modelContext else {
            Log.error(.save, "Cannot save — SwiftData not initialized")
            return
        }
        
        do {
            let worldState = getOrCreateWorldState()
            worldState.hasStartedGame = true
            
            worldState.currentTimePhase = timeService.currentPhase.displayName
            worldState.timeProgress = timeService.phaseProgress
            worldState.isTimeFlowing = timeService.isTimeActive
            worldState.dayCount = timeService.dayCount
            
            if let npcData = try? JSONSerialization.data(withJSONObject: createNPCStateDict(residentManager), options: []),
               let npcJSON = String(data: npcData, encoding: .utf8) {
                worldState.npcStatesJSON = npcJSON
            }
            
            // Persist the shared-world singletons in the same transaction.
            // NOTE: stationStatesJSON is legacy — post drink-in-hand refactor,
            // stations don't hold drink state. Field remains on WorldState
            // for schema compatibility but is no longer written.
            worldState.worldItemsJSON      = encodeWorldItems()
            worldState.carryStateJSON      = encodeCarryState()
            worldState.storageJSON         = encodeStorage()
            worldState.gnomeStateJSON      = encodeGnomeState()
            worldState.brokerEconomyJSON   = GnomeManager.shared.exportBrokerEconomyJSON()
            worldState.movableObjectsJSON  = encodeMovableObjects()
            worldState.treasuryGemCount    = GnomeManager.shared.treasuryGemCount
            
            worldState.lastSaved = Date()
            try context.save()
            Log.info(.save, "Game saved (day \(worldState.dayCount))")
            
        } catch {
            Log.error(.save, "Failed to save game: \(error)")
        }
    }
    
    // MARK: - Load Game State
    func loadGameState() -> WorldState? {
        worldState(forSlotIndex: activeSlotIndex)
    }
    
    // MARK: - Day Counter
    func setDayCount(_ count: Int) {
        let worldState = getOrCreateWorldState()
        worldState.dayCount = count
        
        do {
            try modelContext?.save()
            Log.debug(.save, "Day count persisted: \(count)")
        } catch {
            Log.error(.save, "Failed to persist day count: \(error)")
        }
    }
    
    // MARK: - NPC Memory Management
    func saveNPCMemory(_ npcID: String, memory: NPCMemory) {
        guard let context = modelContext else { return }
        
        do {
            let slotID = currentSaveSlotID
            memory.saveSlotID = currentSaveSlotID
            let descriptor = FetchDescriptor<NPCMemory>(
                predicate: #Predicate { $0.npcID == npcID && $0.saveSlotID == slotID }
            )
            if try context.fetch(descriptor).isEmpty {
                context.insert(memory)
            }
            try context.save()
            Log.debug(.save, "Saved memory for \(npcID)")
        } catch {
            Log.error(.save, "Failed to save NPC memory: \(error)")
        }
    }
    
    func getNPCMemory(_ npcID: String) -> NPCMemory? {
        guard let context = modelContext else { return nil }
        
        do {
            let slotID = currentSaveSlotID
            let descriptor = FetchDescriptor<NPCMemory>(
                predicate: #Predicate { $0.npcID == npcID && $0.saveSlotID == slotID }
            )
            return try context.fetch(descriptor).first
        } catch {
            Log.error(.save, "Failed to load NPC memory: \(error)")
            return nil
        }
    }
    
    func getOrCreateNPCMemory(_ npcID: String, name: String, animalType: String) -> NPCMemory? {
        guard let context = modelContext else { return nil }
        
        do {
            let slotID = currentSaveSlotID
            let descriptor = FetchDescriptor<NPCMemory>(
                predicate: #Predicate { $0.npcID == npcID && $0.saveSlotID == slotID }
            )
            if let existing = try context.fetch(descriptor).first {
                return existing
            }
            let newMemory = NPCMemory(npcID: npcID, name: name, animalType: animalType)
            newMemory.saveSlotID = slotID
            context.insert(newMemory)
            try context.save()
            Log.info(.save, "Created new NPC memory for \(name) (\(animalType))")
            return newMemory
        } catch {
            Log.error(.save, "Failed to get/create NPC memory: \(error)")
            return nil
        }
    }
    
    // MARK: - NPC Interaction Tracking
    func recordNPCInteraction(_ npcID: String, responseType: NPCResponseType) {
        guard let memory = getNPCMemory(npcID) else { return }
        
        memory.recordInteraction()
        
        switch responseType {
        case .dismiss: break
        case .nice:
            memory.receivedNiceTreatment()
            Log.debug(.save, "\(npcID) received nice treatment (+1 satisfaction)")
        case .mean:
            memory.receivedMeanTreatment()
            Log.debug(.save, "\(npcID) received mean treatment (-1 satisfaction)")
        }
        
        saveNPCMemoryChanges(memory)
    }
    
    // MARK: - NPC Liberation Tracking
    func markNPCAsLiberated(_ npcID: String) {
        guard let memory = getNPCMemory(npcID) else { return }
        memory.isLiberated = true
        memory.liberationDate = Date()
        Log.info(.save, "\(npcID) marked as liberated from purgatory")
        saveNPCMemoryChanges(memory)
    }
    
    func isNPCLiberated(_ npcID: String) -> Bool {
        getNPCMemory(npcID)?.isLiberated ?? false
    }
    
    func recordNPCDrinkReceived(_ npcID: String) {
        guard let memory = getNPCMemory(npcID) else { return }
        memory.receivedDrink()
        Log.debug(.save, "\(npcID) received drink (+5 satisfaction, total: \(memory.satisfactionScore))")
        saveNPCMemoryChanges(memory)
        // Chronicle hook — host/solo only (the ledger gates internally).
        DailyChronicleLedger.shared.recordDrinkServed(
            npcID: npcID, npcName: memory.name
        )
    }
    
    private func saveNPCMemoryChanges(_ memory: NPCMemory) {
        do {
            try modelContext?.save()
        } catch {
            Log.error(.save, "Failed to save NPC memory changes: \(error)")
        }
    }

    /// Public hook for dev tools (e.g. NPCDebugMenu) that mutate an
    /// NPCMemory's properties directly and need to flush the model
    /// context immediately. Equivalent to `saveNPCMemoryChanges` but
    /// callable from outside SaveService.
    func persistNPCMemoryChanges(_ memory: NPCMemory) {
        saveNPCMemoryChanges(memory)
    }

    // MARK: - NPC Relationship Memory (NPC ↔ NPC opinion scores)

    /// Look up an existing relationship row for `ofNPCID` → `towardNPCID`.
    /// Returns nil if it has never been seeded.
    func getRelationship(of ofID: String, toward towardID: String) -> NPCRelationshipMemory? {
        guard let context = modelContext else { return nil }
        let key = "\(ofID)__\(towardID)"
        let slotID = currentSaveSlotID
        let descriptor = FetchDescriptor<NPCRelationshipMemory>(
            predicate: #Predicate { $0.pairKey == key && $0.saveSlotID == slotID }
        )
        return (try? context.fetch(descriptor))?.first
    }

    /// Get an existing relationship or create a new one with `initialScore`.
    /// Used by the seeding pass at world init and by ad-hoc lookups.
    @discardableResult
    func getOrCreateRelationship(
        of ofID: String,
        toward towardID: String,
        initialScore: Int = 0
    ) -> NPCRelationshipMemory? {
        guard let context = modelContext else { return nil }
        if let existing = getRelationship(of: ofID, toward: towardID) {
            return existing
        }
        let row = NPCRelationshipMemory(ofNPCID: ofID, towardNPCID: towardID, initialScore: initialScore)
        row.saveSlotID = currentSaveSlotID
        context.insert(row)
        do {
            try context.save()
        } catch {
            Log.error(.save, "Failed to insert relationship row \(ofID)→\(towardID): \(error)")
        }
        return row
    }

    /// Seed all NPC × NPC ordered pairs the first time the world boots, so
    /// every pair has a concrete starting score derived from JSON stance
    /// overlap. Idempotent — skips pairs that already have a row.
    func seedRelationshipsIfNeeded(_ database: NPCDatabase) {
        guard let context = modelContext else { return }
        let slotID = currentSaveSlotID
        do {
            let existing = try context.fetch(FetchDescriptor<NPCRelationshipMemory>(
                predicate: #Predicate { $0.saveSlotID == slotID }
            ))
            // If we already have rows for at least n*(n-1) pairs, treat as seeded.
            let n = database.npcs.count
            if existing.count >= n * (n - 1) {
                Log.debug(.save, "Relationship rows already seeded (\(existing.count) rows)")
                return
            }
        } catch {
            Log.warn(.save, "Could not query existing relationships before seed: \(error)")
        }

        var created = 0
        for a in database.npcs {
            for b in database.npcs where a.id != b.id {
                if getRelationship(of: a.id, toward: b.id) != nil { continue }
                let score = OpinionSeed.seedScore(a: a, b: b, topics: database.opinionTopics)
                let row = NPCRelationshipMemory(ofNPCID: a.id, towardNPCID: b.id, initialScore: score)
                row.saveSlotID = currentSaveSlotID
                context.insert(row)
                created += 1
            }
        }
        do {
            try context.save()
            Log.info(.save, "Seeded \(created) NPC relationship rows from JSON stance overlap")
        } catch {
            Log.error(.save, "Failed to save seeded relationships: \(error)")
        }
    }

    /// Apply a single conversation interaction to a pair's stored score.
    /// `speaker` says/does the thing; `listener` is on the receiving end.
    /// Bumps `conversationCount` only if `incrementConversationCount` is true
    /// (set this once per conversation, not once per interaction).
    func applyConversationInteraction(
        speaker: String,
        listener: String,
        interaction: ConversationInteraction,
        incrementConversationCount: Bool = false
    ) {
        guard let speakerRow = getOrCreateRelationship(of: speaker, toward: listener),
              let listenerRow = getOrCreateRelationship(of: listener, toward: speaker) else {
            return
        }
        let speakerBefore = speakerRow.score
        let listenerBefore = listenerRow.score
        speakerRow.applyDelta(interaction.selfDelta, interaction: interaction)
        listenerRow.applyDelta(interaction.otherDelta, interaction: interaction)
        if incrementConversationCount {
            speakerRow.conversationCount += 1
            listenerRow.conversationCount += 1
        }
        do {
            try modelContext?.save()
            Log.debug(.dialogue, "Conversation \(interaction.rawValue): \(speaker) \(interaction.selfDelta >= 0 ? "+" : "")\(interaction.selfDelta), \(listener) \(interaction.otherDelta >= 0 ? "+" : "")\(interaction.otherDelta)")
        } catch {
            Log.error(.save, "Failed to persist relationship deltas: \(error)")
        }

        // Chronicle hook — only fires on threshold boundary crossings.
        DailyChronicleLedger.shared.recordPossibleThresholdCrossings(
            ofID: speaker, towardID: listener,
            before: speakerBefore, after: speakerRow.score
        )
        DailyChronicleLedger.shared.recordPossibleThresholdCrossings(
            ofID: listener, towardID: speaker,
            before: listenerBefore, after: listenerRow.score
        )
    }

    /// Returns ordered pairs (of, toward) where the speaker's opinion is
    /// at or below `threshold`. Used by the hostile-behavior tick.
    func relationshipsBelow(_ threshold: Int) -> [(of: String, toward: String, score: Int)] {
        guard let context = modelContext else { return [] }
        let slotID = currentSaveSlotID
        do {
            let rows = try context.fetch(FetchDescriptor<NPCRelationshipMemory>(
                predicate: #Predicate { $0.saveSlotID == slotID }
            ))
            return rows
                .filter { $0.score <= threshold }
                .map { ($0.ofNPCID, $0.towardNPCID, $0.score) }
        } catch {
            Log.error(.save, "Failed to query hostile relationships: \(error)")
            return []
        }
    }

    /// All relationship rows for a given NPC, regardless of score.
    /// Used when building LLM prompts that need to know how this NPC
    /// feels about everyone they might mention.
    func relationshipsOf(_ npcID: String) -> [NPCRelationshipMemory] {
        guard let context = modelContext else { return [] }
        let slotID = currentSaveSlotID
        do {
            let descriptor = FetchDescriptor<NPCRelationshipMemory>(
                predicate: #Predicate { $0.ofNPCID == npcID && $0.saveSlotID == slotID }
            )
            return try context.fetch(descriptor)
        } catch {
            Log.error(.save, "Failed to query relationships of \(npcID): \(error)")
            return []
        }
    }
    
    // MARK: - Daily Chronicle

    /// Insert or update the chronicle for `summary.dayCount`. Idempotent —
    /// safe to call when reapplying a network sync.
    func upsertDailySummary(_ summary: DailySummary) {
        guard let context = modelContext else { return }
        do {
            let day = summary.dayCount
            let slotID = currentSaveSlotID
            let descriptor = FetchDescriptor<DailySummary>(
                predicate: #Predicate { $0.dayCount == day && $0.saveSlotID == slotID }
            )
            if let existing = try context.fetch(descriptor).first {
                existing.generatedAt = summary.generatedAt
                existing.usedLLM = summary.usedLLM
                existing.openingLine = summary.openingLine
                existing.forestSection = summary.forestSection
                existing.minesSection = summary.minesSection
                existing.shopSection = summary.shopSection
                existing.socialSection = summary.socialSection
                existing.closingLine = summary.closingLine
                existing.headlinesJSON = summary.headlinesJSON
                existing.ledgerJSON = summary.ledgerJSON
            } else {
                summary.saveSlotID = slotID
                context.insert(summary)
            }
            try context.save()
            Log.info(.save, "Chronicle persisted for day \(day)")
        } catch {
            Log.error(.save, "Failed to upsert daily summary: \(error)")
        }
    }

    /// Apply an incoming network entry. Creates or updates by day.
    func applyDailySummaryEntry(_ entry: DailySummaryEntry) {
        guard let context = modelContext else { return }
        do {
            let day = entry.dayCount
            let slotID = currentSaveSlotID
            let descriptor = FetchDescriptor<DailySummary>(
                predicate: #Predicate { $0.dayCount == day && $0.saveSlotID == slotID }
            )
            if let existing = try context.fetch(descriptor).first {
                existing.apply(entry)
            } else {
                let summary = DailySummary(
                    dayCount: entry.dayCount,
                    generatedAt: Date(timeIntervalSince1970: entry.generatedAt),
                    usedLLM: entry.usedLLM,
                    openingLine: entry.openingLine,
                    forestSection: entry.forestSection,
                    minesSection: entry.minesSection,
                    shopSection: entry.shopSection,
                    socialSection: entry.socialSection,
                    closingLine: entry.closingLine,
                    headlinesJSON: entry.headlinesJSON,
                    ledgerJSON: entry.ledgerJSON
                )
                summary.saveSlotID = slotID
                context.insert(summary)
            }
            try context.save()
            Log.info(.save, "Chronicle entry applied for day \(day)")
        } catch {
            Log.error(.save, "Failed to apply DailySummaryEntry: \(error)")
        }
    }

    /// All chronicles, ascending by day. Used by JournalBookOverlay.
    func loadAllDailySummaries() -> [DailySummary] {
        guard let context = modelContext else { return [] }
        let slotID = currentSaveSlotID
        do {
            let descriptor = FetchDescriptor<DailySummary>(
                predicate: #Predicate { $0.saveSlotID == slotID },
                sortBy: [SortDescriptor(\.dayCount, order: .forward)]
            )
            return try context.fetch(descriptor)
        } catch {
            Log.error(.save, "Failed to load chronicles: \(error)")
            return []
        }
    }

    /// All chronicles as wire-format entries.
    func loadAllDailySummaryEntries() -> [DailySummaryEntry] {
        loadAllDailySummaries().map { $0.toEntry() }
    }

    // MARK: - Save Slots

    func loadSaveSlots() -> [SaveSlotSummary] {
        (1...Self.slotCount).map { slotSummary(for: $0) }
    }

    func currentSaveSlotSummary() -> SaveSlotSummary {
        slotSummary(for: activeSlotIndex)
    }

    func firstEmptySaveSlotIndex() -> Int? {
        loadSaveSlots().first(where: \.isEmpty)?.index
    }

    @discardableResult
    func activateSaveSlot(index: Int) -> SaveSlotSummary {
        let clamped = Self.clampSlotIndex(index)
        activeSlotIndex = clamped
        UserDefaults.standard.set(clamped, forKey: Self.activeSlotDefaultsKey)
        loadPersistentSingletons()
        return slotSummary(for: clamped)
    }

    @discardableResult
    func renameSaveSlot(index: Int, to newName: String) -> SaveSlotSummary {
        let worldState = getOrCreateWorldState(slotIndex: index)
        worldState.slotName = WorldState.sanitizedSlotName(newName, slotIndex: worldState.slotIndex)
        try? modelContext?.save()
        return slotSummary(for: worldState.slotIndex)
    }

    @discardableResult
    func clearSaveSlot(index: Int) -> SaveSlotSummary {
        guard let context = modelContext else { return slotSummary(for: index) }
        let clamped = Self.clampSlotIndex(index)
        let slotID = WorldState.slotID(for: clamped)
        let worldState = getOrCreateWorldState(slotIndex: clamped)

        do {
            try deleteSlotScopedRows(slotID: slotID, context: context)
            reset(worldState: worldState, hasStartedGame: false)
            worldState.slotName = WorldState.defaultSlotName(for: worldState.slotIndex)
            try context.save()

            if clamped == activeSlotIndex {
                loadPersistentSingletons()
            }

            Log.info(.save, "Cleared save slot \(clamped)")
        } catch {
            Log.error(.save, "Failed to clear save slot \(clamped): \(error)")
        }

        return slotSummary(for: clamped)
    }

    func prepareActiveSlotForLaunch(startFreshIfEmpty: Bool) {
        if slotSummary(for: activeSlotIndex).isEmpty && startFreshIfEmpty {
            resetActiveSaveSlotForNewGame()
        } else {
            loadPersistentSingletons()
        }
    }

    func resetActiveSaveSlotForNewGame() {
        guard let context = modelContext else { return }
        let slotID = currentSaveSlotID
        let worldState = getOrCreateWorldState()
        do {
            try deleteSlotScopedRows(slotID: slotID, context: context)
            reset(worldState: worldState, hasStartedGame: true)
            ensureShopMemoryExists(for: slotID, context: context)
            try context.save()
            loadPersistentSingletons()
            reseedRelationshipsFromBundledDialogue()
            Log.info(.save, "Reset save slot \(activeSlotIndex) for a fresh game")
        } catch {
            Log.error(.save, "Failed to reset save slot \(activeSlotIndex): \(error)")
        }
    }

    func clearCurrentSaveSlot() {
        resetActiveSaveSlotForNewGame()
    }

    // MARK: - Data Management
    func clearAllSaveData() {
        guard let context = modelContext else {
            Log.error(.save, "Cannot clear data — SwiftData not initialized")
            return
        }
        
        do {
            for state in try context.fetch(FetchDescriptor<WorldState>()) { context.delete(state) }
            for mem in try context.fetch(FetchDescriptor<NPCMemory>()) { context.delete(mem) }
            for rel in try context.fetch(FetchDescriptor<NPCRelationshipMemory>()) { context.delete(rel) }
            for shop in try context.fetch(FetchDescriptor<ShopMemory>()) { context.delete(shop) }
            for s in try context.fetch(FetchDescriptor<DailySummary>()) { context.delete(s) }
            try context.save()

            activeSlotIndex = 1
            UserDefaults.standard.set(activeSlotIndex, forKey: Self.activeSlotDefaultsKey)
            createInitialDataIfNeeded()
            loadPersistentSingletons()

            Log.info(.save, "All save data cleared")
        } catch {
            Log.error(.save, "Failed to clear save data: \(error)")
        }
    }
    
    // MARK: - LLM Dialogue Management
    func addDialogueLine(npcID: String, text: String, timeContext: String,
                        minSatisfaction: Int = 0, maxSatisfaction: Int = 100) {
        guard let context = modelContext else { return }
        
        do {
            let npcCharacter = try getOrCreateNPCCharacter(npcID: npcID)
            let line = DialogueLine(lineID: UUID().uuidString, text: text, timeContext: timeContext,
                                   minSatisfaction: minSatisfaction, maxSatisfaction: maxSatisfaction)
            line.character = npcCharacter
            npcCharacter.dialogueLines.append(line)
            context.insert(line)
            try context.save()
            Log.debug(.dialogue, "Added line for \(npcID): '\(text.prefix(30))...'")
        } catch {
            Log.error(.dialogue, "Failed to add dialogue line: \(error)")
        }
    }
    
    func getDialogueForNPC(_ npcID: String, timeContext: String, satisfactionScore: Int) -> String? {
        do {
            return try getNPCCharacter(npcID: npcID)?
                .getDialogue(timeContext: timeContext, satisfactionScore: satisfactionScore)?.text
        } catch {
            Log.error(.dialogue, "Failed to get dialogue: \(error)")
            return nil
        }
    }
    
    func getAllDialogueForAnalysis(_ npcID: String, timeContext: String) -> [String] {
        do {
            return try getNPCCharacter(npcID: npcID)?
                .getAllDialogue(timeContext: timeContext).map(\.text) ?? []
        } catch {
            Log.error(.dialogue, "Failed to get dialogue for analysis: \(error)")
            return []
        }
    }
    
    // MARK: - Data Migration from JSON
    func migrateDialogueFromJSON(_ jsonData: Data) {
        guard let context = modelContext else { return }
        
        do {
            let npcDatabase = try JSONDecoder().decode(NPCDatabase.self, from: jsonData)
            
            for npcData in npcDatabase.npcs {
                let npcCharacter = NPCCharacter(
                    npcID: npcData.id, name: npcData.name, animalType: npcData.animal,
                    causeOfDeath: npcData.causeOfDeath, homeRoom: npcData.homeRoom
                )
                
                for dayLine in npcData.dialogue.day {
                    let line = DialogueLine(lineID: UUID().uuidString, text: dayLine, timeContext: "day")
                    line.character = npcCharacter
                    npcCharacter.dialogueLines.append(line)
                    context.insert(line)
                }
                
                for nightLine in npcData.dialogue.night {
                    let line = DialogueLine(lineID: UUID().uuidString, text: nightLine, timeContext: "night")
                    line.character = npcCharacter
                    npcCharacter.dialogueLines.append(line)
                    context.insert(line)
                }
                
                context.insert(npcCharacter)
            }
            
            try context.save()
            Log.info(.save, "Migrated dialogue from JSON to SwiftData")
        } catch {
            Log.error(.save, "Failed to migrate dialogue: \(error)")
        }
    }
    
    // MARK: - Helpers
    private func getOrCreateWorldState() -> WorldState {
        getOrCreateWorldState(slotIndex: activeSlotIndex)
    }

    private func getOrCreateWorldState(slotIndex: Int) -> WorldState {
        let clamped = Self.clampSlotIndex(slotIndex)
        if let existing = worldState(forSlotIndex: clamped) { return existing }
        let newState = WorldState(slotIndex: clamped)
        modelContext?.insert(newState)
        return newState
    }

    private func worldState(forSlotIndex slotIndex: Int) -> WorldState? {
        guard let context = modelContext else { return nil }
        let slotID = WorldState.slotID(for: Self.clampSlotIndex(slotIndex))
        do {
            let descriptor = FetchDescriptor<WorldState>(
                predicate: #Predicate { $0.worldID == slotID }
            )
            return try context.fetch(descriptor).first
        } catch {
            Log.error(.save, "Failed to load slot \(slotIndex): \(error)")
            return nil
        }
    }
    
    private func createInitialDataIfNeeded() {
        guard let context = modelContext else { return }
        do {
            var didChange = false
            let worlds = try context.fetch(FetchDescriptor<WorldState>())
            for world in worlds where world.worldID == "main_world" {
                let slotIndex = Self.clampSlotIndex(world.slotIndex == 0 ? 1 : world.slotIndex)
                world.slotIndex = slotIndex
                world.worldID = WorldState.slotID(for: slotIndex)
                world.slotName = WorldState.sanitizedSlotName(world.slotName, slotIndex: slotIndex)
                world.hasStartedGame = inferProgress(for: world)
                didChange = true
            }

            for slotIndex in 1...Self.slotCount {
                let slotID = WorldState.slotID(for: slotIndex)
                let hasWorld = worlds.contains { $0.worldID == slotID || $0.slotIndex == slotIndex }
                if !hasWorld {
                    context.insert(WorldState(slotIndex: slotIndex))
                    didChange = true
                }
                if ensureShopMemoryExists(for: slotID, context: context) {
                    didChange = true
                }
            }

            if didChange {
                try context.save()
                Log.info(.save, "Created initial save slot data")
            }
        } catch {
            Log.error(.save, "Failed to create initial data: \(error)")
        }
    }

    private func ensureShopMemoryExists(for slotID: String, context: ModelContext) -> Bool {
        do {
            let descriptor = FetchDescriptor<ShopMemory>(
                predicate: #Predicate { $0.saveSlotID == slotID }
            )
            if try context.fetch(descriptor).isEmpty {
                let shopMemory = ShopMemory()
                shopMemory.saveSlotID = slotID
                context.insert(shopMemory)
                return true
            }
        } catch {
            Log.error(.save, "Failed to ensure shop memory for \(slotID): \(error)")
        }
        return false
    }

    private func slotSummary(for slotIndex: Int) -> SaveSlotSummary {
        let worldState = getOrCreateWorldState(slotIndex: slotIndex)
        let isEmpty = !worldState.hasStartedGame
        return SaveSlotSummary(
            index: worldState.slotIndex,
            name: worldState.slotName,
            isEmpty: isEmpty,
            dayCount: isEmpty ? 0 : worldState.dayCount,
            lastSaved: isEmpty ? nil : worldState.lastSaved
        )
    }

    private func inferProgress(for worldState: WorldState) -> Bool {
        worldState.hasStartedGame
            || worldState.dayCount > 0
            || worldState.npcStatesJSON != "{}"
            || worldState.worldItemsJSON != "[]"
            || worldState.carryStateJSON != "{}"
            || worldState.storageJSON != "{}"
            || worldState.gnomeStateJSON != "[]"
            || worldState.brokerEconomyJSON != "{}"
            || worldState.movableObjectsJSON != "[]"
            || !worldState.worldFlags.isEmpty
    }

    private func deleteSlotScopedRows(slotID: String, context: ModelContext) throws {
        let npcRows = try context.fetch(FetchDescriptor<NPCMemory>(
            predicate: #Predicate { $0.saveSlotID == slotID }
        ))
        npcRows.forEach(context.delete)

        let relationshipRows = try context.fetch(FetchDescriptor<NPCRelationshipMemory>(
            predicate: #Predicate { $0.saveSlotID == slotID }
        ))
        relationshipRows.forEach(context.delete)

        let shopRows = try context.fetch(FetchDescriptor<ShopMemory>(
            predicate: #Predicate { $0.saveSlotID == slotID }
        ))
        shopRows.forEach(context.delete)

        let summaryRows = try context.fetch(FetchDescriptor<DailySummary>(
            predicate: #Predicate { $0.saveSlotID == slotID }
        ))
        summaryRows.forEach(context.delete)
    }

    private func reset(worldState: WorldState, hasStartedGame: Bool) {
        worldState.hasStartedGame = hasStartedGame
        worldState.currentTimePhase = "day"
        worldState.timeProgress = 0.0
        worldState.isTimeFlowing = true
        worldState.cycleCount = 0
        worldState.dayCount = 0
        worldState.npcStatesJSON = "{}"
        worldState.worldItemsJSON = "[]"
        worldState.carryStateJSON = "{}"
        worldState.stationStatesJSON = "{}"
        worldState.storageJSON = "{}"
        worldState.gnomeStateJSON = "[]"
        worldState.brokerEconomyJSON = "{}"
        worldState.treasuryGemCount = 0
        worldState.movableObjectsJSON = "[]"
        worldState.worldFlags = [:]
        worldState.lastSaved = Date()
    }

    private func reseedRelationshipsFromBundledDialogue() {
        guard let url = Bundle.main.url(forResource: "npc_dialogue", withExtension: "json") else {
            return
        }
        do {
            let data = try Data(contentsOf: url)
            let database = try JSONDecoder().decode(NPCDatabase.self, from: data)
            seedRelationshipsIfNeeded(database)
        } catch {
            Log.warn(.save, "Failed to reseed NPC relationships after reset: \(error)")
        }
    }

    private func createNPCStateDict(_ residentManager: NPCResidentManager) -> [String: Any] {
        var npcStates: [[String: Any]] = []
        for resident in residentManager.getAllResidents() {
            var entry: [String: Any] = [
                "id": resident.npcData.id,
                "homeRoom": resident.npcData.homeRoom,
                "homeHouse": resident.homeHouse,
                "drinkCooldown": resident.drinkCooldown
            ]
            switch resident.status {
            case .atHome(let room):
                entry["status"] = "atHome"
                entry["statusRoom"] = room
            case .inShop:    entry["status"] = "inShop"
            case .traveling,
                 .inForestRoom,
                 .inOakLobby,
                 .inCaveRoom,
                 .atFriendHouse:
                entry["status"] = "traveling"
            }
            npcStates.append(entry)
        }
        return ["timestamp": Date().timeIntervalSince1970, "residents": npcStates]
    }
    
    private func getOrCreateNPCCharacter(npcID: String) throws -> NPCCharacter {
        guard let context = modelContext else { throw NSError(domain: "SaveService", code: 1) }
        let descriptor = FetchDescriptor<NPCCharacter>(predicate: #Predicate { $0.npcID == npcID })
        if let existing = try context.fetch(descriptor).first { return existing }
        let newChar = NPCCharacter(npcID: npcID, name: "Unknown", animalType: "Unknown",
                                    causeOfDeath: "Unknown", homeRoom: 1)
        context.insert(newChar)
        return newChar
    }
    
    private func getNPCCharacter(npcID: String) throws -> NPCCharacter? {
        guard let context = modelContext else { return nil }
        let descriptor = FetchDescriptor<NPCCharacter>(predicate: #Predicate { $0.npcID == npcID })
        return try context.fetch(descriptor).first
    }
    
    // MARK: - Resident State Restoration
    func loadResidentStates() -> [[String: Any]]? {
        guard let worldState = loadGameState() else { return nil }
        let json = worldState.npcStatesJSON
        guard !json.isEmpty, json != "{}" else { return nil }
        
        do {
            guard let data = json.data(using: .utf8),
                  let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let residents = dict["residents"] as? [[String: Any]] else { return nil }
            Log.debug(.save, "Loaded \(residents.count) resident states from save")
            return residents
        } catch {
            Log.error(.save, "Failed to parse resident states: \(error)")
            return nil
        }
    }
    
    // MARK: - Shared World Sync (Export / Import)
    
    /// Get the timestamp of the last save for comparison with the other player.
    func getSaveTimestamp() -> Double {
        guard let worldState = loadGameState(), worldState.hasStartedGame else { return 0 }
        return worldState.lastSaved.timeIntervalSince1970
    }
    
    /// Export the full world state + all NPC memories for network transfer.
    func exportWorldSync(timeService: TimeService) -> WorldSyncMessage {
        let worldState = loadGameState()
        
        // Gather all NPC memories
        var memoryEntries: [NPCMemoryEntry] = []
        if let context = modelContext {
            do {
                let slotID = currentSaveSlotID
                let allMemories = try context.fetch(FetchDescriptor<NPCMemory>(
                    predicate: #Predicate { $0.saveSlotID == slotID }
                ))
                memoryEntries = allMemories.map { m in
                    NPCMemoryEntry(
                        npcID: m.npcID,
                        name: m.name,
                        animalType: m.animalType,
                        satisfactionScore: m.satisfactionScore,
                        totalInteractions: m.totalInteractions,
                        totalDrinksReceived: m.totalDrinksReceived,
                        niceTreatmentCount: m.niceTreatmentCount,
                        meanTreatmentCount: m.meanTreatmentCount,
                        isLiberated: m.isLiberated,
                        liberationDate: m.liberationDate?.timeIntervalSince1970
                    )
                }
            } catch {
                Log.error(.save, "Failed to export NPC memories: \(error)")
            }
        }
        
        return WorldSyncMessage(
            dayCount: timeService.dayCount,
            timePhase: timeService.currentPhase.displayName,
            timeProgress: timeService.phaseProgress,
            npcStatesJSON: worldState?.npcStatesJSON ?? "{}",
            npcMemories: memoryEntries,
            worldItems: WorldItemRegistry.shared.allItems(),
            storage: StorageRegistry.shared.snapshot(),
            saveTimestamp: worldState?.lastSaved.timeIntervalSince1970 ?? 0,
            gnomeSnapshotsJSON: encodeGnomeState(),
            treasuryGemCount: GnomeManager.shared.treasuryGemCount,
            cartGemCount: GnomeManager.shared.cartGemCount,
            cartLocation: GnomeManager.shared.cartLocation.stringKey,
            cartState: GnomeManager.shared.cartState.rawValue,
            recentSummaries: loadAllDailySummaryEntries(),
            movableObjects: MovableObjectRegistry.shared.allEntries(),
            brokerEconomyJSON: GnomeManager.shared.exportBrokerEconomyJSON(),
            forageSpawnsJSON: ForagingManager.shared.exportSnapshot()
        )
    }
    
    /// Import a full world state from the other player, overwriting local data.
    /// Called when the other player's save is newer than ours.
    func importWorldSync(_ msg: WorldSyncMessage) {
        guard let context = modelContext else {
            Log.error(.save, "Cannot import world sync - SwiftData not initialized")
            return
        }
        
        do {
            // Update world state
            let worldState = getOrCreateWorldState()
            let slotID = currentSaveSlotID
            worldState.hasStartedGame = true
            worldState.dayCount = msg.dayCount
            worldState.currentTimePhase = msg.timePhase
            worldState.timeProgress = msg.timeProgress
            worldState.npcStatesJSON = msg.npcStatesJSON
            worldState.lastSaved = Date(timeIntervalSince1970: msg.saveTimestamp)
            
            // Import NPC memories (overwrite existing, create missing)
            for entry in msg.npcMemories {
                let descriptor = FetchDescriptor<NPCMemory>(
                    predicate: #Predicate { $0.npcID == entry.npcID && $0.saveSlotID == slotID }
                )
                let memory: NPCMemory
                if let existing = try context.fetch(descriptor).first {
                    memory = existing
                } else {
                    memory = NPCMemory(npcID: entry.npcID, name: entry.name, animalType: entry.animalType)
                    memory.saveSlotID = slotID
                    context.insert(memory)
                }
                
                memory.satisfactionScore = entry.satisfactionScore
                memory.totalInteractions = entry.totalInteractions
                memory.totalDrinksReceived = entry.totalDrinksReceived
                memory.niceTreatmentCount = entry.niceTreatmentCount
                memory.meanTreatmentCount = entry.meanTreatmentCount
                memory.isLiberated = entry.isLiberated
                memory.liberationDate = entry.liberationDate.map { Date(timeIntervalSince1970: $0) }
            }
            
            // Import world items (trash + drinks on tables). loadAll does NOT
            // fire onDidMutate, so we explicitly encode + stash the JSON on the
            // worldState below before saving the context.
            WorldItemRegistry.shared.loadAll(msg.worldItems)
            worldState.worldItemsJSON = encodeWorldItems()
            
            // Import storage contents (pantry / fridge).
            StorageRegistry.shared.loadAll(msg.storage)
            worldState.storageJSON = encodeStorage()

            // Import movable-object placements if present (older saves
            // may omit this field). loadAll skips the onDidMutate hook
            // so we explicitly stamp the JSON onto worldState here.
            if let moves = msg.movableObjects {
                MovableObjectRegistry.shared.loadAll(moves)
                worldState.movableObjectsJSON = encodeMovableObjects()
            }
            
            // Import gnome state if present (older saves may omit).
            if let json = msg.gnomeSnapshotsJSON, !json.isEmpty {
                worldState.gnomeStateJSON = json
                applyGnomeStateJSON(json)
            }
            // Import broker economy state. Apply AFTER gnome state so any
            // task/carry on the broker/treasurer agents has been restored
            // first — the broker economy then layers the desk-level
            // bookkeeping (box contents, gem reserve, transient errand
            // flags) on top.
            if let json = msg.brokerEconomyJSON, !json.isEmpty, json != "{}" {
                worldState.brokerEconomyJSON = json
                GnomeManager.shared.applyBrokerEconomyJSON(json)
            }
            // Import forage spawn snapshot. Replaces the receiver's
            // local spawn state for today wholesale, so the guest's
            // forest looks the same as the host's. Not persisted to
            // disk — spawns regenerate at next dawn rollover.
            if let json = msg.forageSpawnsJSON, !json.isEmpty, json != "{}" {
                ForagingManager.shared.applySnapshot(json)
            }
            if let count = msg.treasuryGemCount {
                worldState.treasuryGemCount = count
                GnomeManager.shared.applyRemoteTreasury(newCount: count, didReset: false)
            }

            // Cart state — if any of the cart fields were sent, restore
            // them via the same path that handles save → manager. Older
            // builds won't include these and the manager will keep its
            // current state (which on a fresh import is the dawn default).
            if msg.cartGemCount != nil || msg.cartLocation != nil || msg.cartState != nil {
                var cartDict: [String: Any] = [:]
                if let g = msg.cartGemCount { cartDict["cartGemCount"] = g }
                if let loc = msg.cartLocation { cartDict["cartLocation"] = loc }
                if let s = msg.cartState { cartDict["cartState"] = s }
                GnomeManager.shared.restoreSaveData(cartDict)
            }

            // Import chronicles (newer-wins per dayCount, idempotent).
            if let summaries = msg.recentSummaries {
                for entry in summaries {
                    let day = entry.dayCount
                    let descriptor = FetchDescriptor<DailySummary>(
                        predicate: #Predicate { $0.dayCount == day && $0.saveSlotID == slotID }
                    )
                    if let existing = try context.fetch(descriptor).first {
                        existing.apply(entry)
                    } else {
                        let summary = DailySummary(
                            dayCount: entry.dayCount,
                            generatedAt: Date(timeIntervalSince1970: entry.generatedAt),
                            usedLLM: entry.usedLLM,
                            openingLine: entry.openingLine,
                            forestSection: entry.forestSection,
                            minesSection: entry.minesSection,
                            shopSection: entry.shopSection,
                            socialSection: entry.socialSection,
                            closingLine: entry.closingLine,
                            headlinesJSON: entry.headlinesJSON,
                            ledgerJSON: entry.ledgerJSON
                        )
                        summary.saveSlotID = slotID
                        context.insert(summary)
                    }
                }
            }
            
            try context.save()
            Log.info(.save, "World sync imported: day \(msg.dayCount), \(msg.npcMemories.count) NPC memories, \(msg.worldItems.count) world items, \(msg.storage.count) storage containers")
            
        } catch {
            Log.error(.save, "Failed to import world sync: \(error)")
        }
    }
    
    /// Quick auto-save that touches the timestamp. Call on disconnect.
    func autoSave(timeService: TimeService) {
        let worldState = getOrCreateWorldState()
        worldState.hasStartedGame = true
        worldState.dayCount = timeService.dayCount
        worldState.currentTimePhase = timeService.currentPhase.displayName
        worldState.timeProgress = timeService.phaseProgress
        
        // Capture persistent singletons too.
        // (stationStatesJSON no longer written — see saveCurrentGameState note.)
        worldState.worldItemsJSON      = encodeWorldItems()
        worldState.carryStateJSON      = encodeCarryState()
        worldState.storageJSON         = encodeStorage()
        worldState.gnomeStateJSON      = encodeGnomeState()
        worldState.brokerEconomyJSON   = GnomeManager.shared.exportBrokerEconomyJSON()
        worldState.movableObjectsJSON  = encodeMovableObjects()
        worldState.treasuryGemCount    = GnomeManager.shared.treasuryGemCount
        
        worldState.lastSaved = Date()
        
        do {
            try modelContext?.save()
            Log.info(.save, "Auto-saved on disconnect (day \(worldState.dayCount))")
        } catch {
            Log.error(.save, "Auto-save failed: \(error)")
        }
    }
    
    // MARK: - Persistent Singleton Sync
    
    /// Load WorldItemRegistry and CharacterCarryState from the stored
    /// WorldState on startup. Runs once during init.
    /// (StationPersistedState is vestigial post drink-in-hand refactor.)
    private func loadPersistentSingletons(resetRuntimeState: Bool = true) {
        if resetRuntimeState {
            resetRuntimeSingletons()
        }
        guard let worldState = loadGameState() else { return }
        
        // World items
        if let data = worldState.worldItemsJSON.data(using: .utf8),
           let items = try? JSONDecoder().decode([WorldItem].self, from: data) {
            WorldItemRegistry.shared.loadAll(items)
        }
        
        // Carry state
        if let data = worldState.carryStateJSON.data(using: .utf8),
           !worldState.carryStateJSON.isEmpty,
           worldState.carryStateJSON != "{}",
           let content = try? JSONDecoder().decode(CarryContent.self, from: data) {
            CharacterCarryState.shared.load(content)
        }
        
        // Storage contents (pantry / fridge)
        if let data = worldState.storageJSON.data(using: .utf8),
           !worldState.storageJSON.isEmpty,
           worldState.storageJSON != "{}",
           let snapshot = try? JSONDecoder().decode([String: StorageContents].self, from: data) {
            StorageRegistry.shared.loadAll(snapshot)
        }

        // Movable object placements (table / furniture rearrangements).
        if let data = worldState.movableObjectsJSON.data(using: .utf8),
           !worldState.movableObjectsJSON.isEmpty,
           worldState.movableObjectsJSON != "[]",
           let moves = try? JSONDecoder().decode([MovableObjectEntry].self, from: data) {
            MovableObjectRegistry.shared.loadAll(moves)
        }
        
        // Gnome state — restore agents and treasury count.
        applyGnomeStateJSON(worldState.gnomeStateJSON)
        // Broker economy — restore broker box contents, gem reserve,
        // and transient errand flags. Applied after gnome state so the
        // broker/treasurer agents already have their tasks/carries
        // restored before we layer desk-level bookkeeping on top.
        GnomeManager.shared.applyBrokerEconomyJSON(worldState.brokerEconomyJSON)
        GnomeManager.shared.applyRemoteTreasury(
            newCount: worldState.treasuryGemCount,
            didReset: false
        )
        syncTimeManager(from: worldState)
    }
    
    /// Wire each singleton's `onDidMutate` to a per-field persist call so
    /// mutations are flushed to SwiftData without waiting for auto-save.
    private func wirePersistenceHooks() {
        WorldItemRegistry.shared.onDidMutate = { [weak self] in
            self?.persistWorldItems()
        }
        CharacterCarryState.shared.onDidMutate = { [weak self] in
            self?.persistCarryState()
        }
        StorageRegistry.shared.onDidMutate = { [weak self] in
            self?.persistStorage()
        }
        MovableObjectRegistry.shared.onDidMutate = { [weak self] in
            self?.persistMovableObjects()
        }
    }
    
    // MARK: - Per-field Persist
    
    private func persistWorldItems() {
        let worldState = getOrCreateWorldState()
        worldState.hasStartedGame = true
        worldState.worldItemsJSON = encodeWorldItems()
        worldState.lastSaved = Date()
        try? modelContext?.save()
    }
    
    private func persistCarryState() {
        let worldState = getOrCreateWorldState()
        worldState.hasStartedGame = true
        worldState.carryStateJSON = encodeCarryState()
        worldState.lastSaved = Date()
        try? modelContext?.save()
    }
    
    private func persistStorage() {
        let worldState = getOrCreateWorldState()
        worldState.hasStartedGame = true
        worldState.storageJSON = encodeStorage()
        worldState.lastSaved = Date()
        try? modelContext?.save()
    }

    private func persistMovableObjects() {
        let worldState = getOrCreateWorldState()
        worldState.hasStartedGame = true
        worldState.movableObjectsJSON = encodeMovableObjects()
        worldState.lastSaved = Date()
        try? modelContext?.save()
    }
    
    /// Public API for GnomeManager to flush its state to disk on demand
    /// (called at dawn rollover and on rank changes).
    func persistGnomeState() {
        let worldState = getOrCreateWorldState()
        worldState.hasStartedGame = true
        worldState.gnomeStateJSON = encodeGnomeState()
        worldState.brokerEconomyJSON = GnomeManager.shared.exportBrokerEconomyJSON()
        worldState.treasuryGemCount = GnomeManager.shared.treasuryGemCount
        worldState.lastSaved = Date()
        try? modelContext?.save()
    }
    
    // MARK: - Encoders
    
    private func encodeWorldItems() -> String {
        let items = WorldItemRegistry.shared.allItems()
        guard let data = try? JSONEncoder().encode(items),
              let json = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return json
    }
    
    private func encodeCarryState() -> String {
        let content = CharacterCarryState.shared.content
        guard let data = try? JSONEncoder().encode(content),
              let json = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return json
    }
    
    private func encodeStorage() -> String {
        let snapshot = StorageRegistry.shared.snapshot()
        guard let data = try? JSONEncoder().encode(snapshot),
              let json = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return json
    }

    private func encodeMovableObjects() -> String {
        let entries = MovableObjectRegistry.shared.allEntries()
        guard let data = try? JSONEncoder().encode(entries),
              let json = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return json
    }
    
    /// Encode the GnomeManager's per-agent snapshots as a single JSON
    /// array. Used by the periodic save and the network world-sync.
    private func encodeGnomeState() -> String {
        let snapshots = GnomeManager.shared.agents.map { $0.makeSnapshot() }
        guard let data = try? JSONEncoder().encode(snapshots),
              let json = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return json
    }
    
    /// Decode a `[GnomeSnapshot]` JSON blob and apply each entry to the
    /// matching agent in GnomeManager. Tolerant of empty / malformed input.
    private func applyGnomeStateJSON(_ json: String) {
        guard !json.isEmpty, json != "[]",
              let data = json.data(using: .utf8),
              let snapshots = try? JSONDecoder().decode([GnomeSnapshot].self, from: data) else {
            return
        }
        for snap in snapshots {
            guard let agent = GnomeManager.shared.agent(byID: snap.id) else { continue }
            agent.apply(snap)
        }
        Log.info(.save, "Restored \(snapshots.count) gnome agents from save")
    }

    private func resetRuntimeSingletons() {
        WorldItemRegistry.shared.clear()
        CharacterCarryState.shared.clear()
        StorageRegistry.shared.clearAll()
        MovableObjectRegistry.shared.clear()
        DailyChronicleLedger.shared.reset()
        NPCResidentManager.shared.resetForNewGame()
        GnomeManager.shared.resetForNewGame()
    }

    private func syncTimeManager(from worldState: WorldState) {
        guard let phase = timePhase(named: worldState.currentTimePhase) else { return }
        let now = CFAbsoluteTimeGetCurrent()
        TimeManager.shared.setPhase(phase, at: now)
        if worldState.isTimeFlowing {
            TimeManager.shared.resume(at: now)
        } else {
            TimeManager.shared.pause()
        }
    }

    private func timePhase(named rawValue: String) -> TimePhase? {
        switch rawValue.lowercased() {
        case "dawn": return .dawn
        case "day": return .day
        case "dusk": return .dusk
        case "night": return .night
        default: return nil
        }
    }
    
    // MARK: - Debug
    func inspectSwiftDataContents() {
        guard let context = modelContext else {
            Log.error(.save, "SwiftData not initialized")
            return
        }
        
        Log.info(.save, "=== SWIFTDATA INSPECTION ===")
        do {
            let worlds = try context.fetch(FetchDescriptor<WorldState>())
            Log.info(.save, "WorldState: \(worlds.count)")
            
            let memories = try context.fetch(FetchDescriptor<NPCMemory>())
            Log.info(.save, "NPCMemory: \(memories.count)")
            for m in memories {
                Log.info(.save, "  \(m.name) (\(m.animalType)): satisfaction \(m.satisfactionScore)/100, interactions \(m.totalInteractions)")
            }
            
            let chars = try context.fetch(FetchDescriptor<NPCCharacter>())
            Log.info(.save, "NPCCharacter: \(chars.count)")
            
            let lines = try context.fetch(FetchDescriptor<DialogueLine>())
            Log.info(.save, "DialogueLine: \(lines.count)")
        } catch {
            Log.error(.save, "Inspection failed: \(error)")
        }
    }
}
