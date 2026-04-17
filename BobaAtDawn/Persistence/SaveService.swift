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
    
    private var modelContainer: ModelContainer?
    private var modelContext: ModelContext?
    
    private init() {
        setupSwiftData()
    }
    
    // MARK: - SwiftData Setup
    private func setupSwiftData() {
        do {
            let schema = Schema([
                WorldState.self,
                NPCMemory.self,
                ShopMemory.self,
                NPCCharacter.self,
                DialogueLine.self
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
            
            worldState.currentTimePhase = timeService.currentPhase.displayName
            worldState.timeProgress = timeService.phaseProgress
            worldState.isTimeFlowing = timeService.isTimeActive
            worldState.dayCount = timeService.dayCount
            
            if let npcData = try? JSONSerialization.data(withJSONObject: createNPCStateDict(residentManager), options: []),
               let npcJSON = String(data: npcData, encoding: .utf8) {
                worldState.npcStatesJSON = npcJSON
            }
            
            worldState.lastSaved = Date()
            try context.save()
            Log.info(.save, "Game saved (day \(worldState.dayCount))")
            
        } catch {
            Log.error(.save, "Failed to save game: \(error)")
        }
    }
    
    // MARK: - Load Game State
    func loadGameState() -> WorldState? {
        guard let context = modelContext else { return nil }
        
        do {
            let descriptor = FetchDescriptor<WorldState>(
                predicate: #Predicate { $0.worldID == "main_world" }
            )
            return try context.fetch(descriptor).first
        } catch {
            Log.error(.save, "Failed to load game state: \(error)")
            return nil
        }
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
            let descriptor = FetchDescriptor<NPCMemory>(
                predicate: #Predicate { $0.npcID == npcID }
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
            let descriptor = FetchDescriptor<NPCMemory>(
                predicate: #Predicate { $0.npcID == npcID }
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
            let descriptor = FetchDescriptor<NPCMemory>(
                predicate: #Predicate { $0.npcID == npcID }
            )
            if let existing = try context.fetch(descriptor).first {
                return existing
            }
            let newMemory = NPCMemory(npcID: npcID, name: name, animalType: animalType)
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
    }
    
    private func saveNPCMemoryChanges(_ memory: NPCMemory) {
        do {
            try modelContext?.save()
        } catch {
            Log.error(.save, "Failed to save NPC memory changes: \(error)")
        }
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
            for shop in try context.fetch(FetchDescriptor<ShopMemory>()) { context.delete(shop) }
            try context.save()
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
        if let existing = loadGameState() { return existing }
        let newState = WorldState()
        modelContext?.insert(newState)
        return newState
    }
    
    private func createInitialDataIfNeeded() {
        guard let context = modelContext else { return }
        do {
            if try context.fetch(FetchDescriptor<WorldState>()).isEmpty {
                context.insert(WorldState())
                context.insert(ShopMemory())
                try context.save()
                Log.info(.save, "Created initial save data")
            }
        } catch {
            Log.error(.save, "Failed to create initial data: \(error)")
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
            case .traveling: entry["status"] = "traveling"
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
        loadGameState()?.lastSaved.timeIntervalSince1970 ?? 0
    }
    
    /// Export the full world state + all NPC memories for network transfer.
    func exportWorldSync(timeService: TimeService) -> WorldSyncMessage {
        let worldState = loadGameState()
        
        // Gather all NPC memories
        var memoryEntries: [NPCMemoryEntry] = []
        if let context = modelContext {
            do {
                let allMemories = try context.fetch(FetchDescriptor<NPCMemory>())
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
            saveTimestamp: worldState?.lastSaved.timeIntervalSince1970 ?? 0
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
            worldState.dayCount = msg.dayCount
            worldState.currentTimePhase = msg.timePhase
            worldState.timeProgress = msg.timeProgress
            worldState.npcStatesJSON = msg.npcStatesJSON
            worldState.lastSaved = Date(timeIntervalSince1970: msg.saveTimestamp)
            
            // Import NPC memories (overwrite existing, create missing)
            for entry in msg.npcMemories {
                let descriptor = FetchDescriptor<NPCMemory>(
                    predicate: #Predicate { $0.npcID == entry.npcID }
                )
                let memory: NPCMemory
                if let existing = try context.fetch(descriptor).first {
                    memory = existing
                } else {
                    memory = NPCMemory(npcID: entry.npcID, name: entry.name, animalType: entry.animalType)
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
            
            try context.save()
            Log.info(.save, "World sync imported: day \(msg.dayCount), \(msg.npcMemories.count) NPC memories")
            
        } catch {
            Log.error(.save, "Failed to import world sync: \(error)")
        }
    }
    
    /// Quick auto-save that touches the timestamp. Call on disconnect.
    func autoSave(timeService: TimeService) {
        let worldState = getOrCreateWorldState()
        worldState.dayCount = timeService.dayCount
        worldState.currentTimePhase = timeService.currentPhase.displayName
        worldState.timeProgress = timeService.phaseProgress
        worldState.lastSaved = Date()
        
        do {
            try modelContext?.save()
            Log.info(.save, "Auto-saved on disconnect (day \(worldState.dayCount))")
        } catch {
            Log.error(.save, "Auto-save failed: \(error)")
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
