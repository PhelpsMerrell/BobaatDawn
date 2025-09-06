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
            
            print("💾 SwiftData initialized successfully")
            
            // Create initial data if needed
            createInitialDataIfNeeded()
            
        } catch {
            print("❌ Failed to initialize SwiftData: \(error)")
            // Graceful fallback - game still works without saves
        }
    }
    
    // MARK: - Save Game State
    func saveCurrentGameState(timeService: TimeService, residentManager: NPCResidentManager) {
        guard let context = modelContext else {
            print("❌ Cannot save - SwiftData not initialized")
            return
        }
        
        do {
            // Get or create world state
            let worldState = getOrCreateWorldState()
            
            // Update world state with current game data
            worldState.currentTimePhase = timeService.currentPhase.displayName
            worldState.timeProgress = timeService.phaseProgress
            worldState.isTimeFlowing = timeService.isTimeActive
            
            // Save NPC states as JSON (simple approach)
            if let npcData = try? JSONSerialization.data(withJSONObject: createNPCStateDict(residentManager), options: []),
               let npcJSON = String(data: npcData, encoding: .utf8) {
                worldState.npcStatesJSON = npcJSON
            }
            
            worldState.lastSaved = Date()
            
            // Save to disk
            try context.save()
            
            print("💾 ✅ Game saved successfully at \(Date())")
            
        } catch {
            print("❌ Failed to save game: \(error)")
        }
    }
    
    // MARK: - Load Game State
    func loadGameState() -> WorldState? {
        guard let context = modelContext else { return nil }
        
        do {
            let descriptor = FetchDescriptor<WorldState>(
                predicate: #Predicate { $0.worldID == "main_world" }
            )
            
            let worldStates = try context.fetch(descriptor)
            return worldStates.first
            
        } catch {
            print("❌ Failed to load game state: \(error)")
            return nil
        }
    }
    
    // MARK: - NPC Memory Management
    func saveNPCMemory(_ npcID: String, memory: NPCMemory) {
        guard let context = modelContext else { return }
        
        // Check if memory already exists
        do {
            let descriptor = FetchDescriptor<NPCMemory>(
                predicate: #Predicate { $0.npcID == npcID }
            )
            
            let existing = try context.fetch(descriptor)
            if existing.isEmpty {
                context.insert(memory)
            }
            
            try context.save()
            print("💾 Saved memory for NPC \(npcID)")
            
        } catch {
            print("❌ Failed to save NPC memory: \(error)")
        }
    }
    
    func getNPCMemory(_ npcID: String) -> NPCMemory? {
        guard let context = modelContext else { return nil }
        
        do {
            let descriptor = FetchDescriptor<NPCMemory>(
                predicate: #Predicate { $0.npcID == npcID }
            )
            
            let memories = try context.fetch(descriptor)
            return memories.first
            
        } catch {
            print("❌ Failed to load NPC memory: \(error)")
            return nil
        }
    }
    
    func getOrCreateNPCMemory(_ npcID: String, name: String, animalType: String) -> NPCMemory? {
        guard let context = modelContext else { return nil }
        
        do {
            let descriptor = FetchDescriptor<NPCMemory>(
                predicate: #Predicate { $0.npcID == npcID }
            )
            
            let memories = try context.fetch(descriptor)
            if let existing = memories.first {
                return existing
            } else {
                // Create new memory with neutral satisfaction
                let newMemory = NPCMemory(npcID: npcID, name: name, animalType: animalType)
                context.insert(newMemory)
                try context.save()
                print("🎆 Created new NPC memory for \(name) (\(animalType))")
                return newMemory
            }
            
        } catch {
            print("❌ Failed to get/create NPC memory: \(error)")
            return nil
        }
    }
    
    // MARK: - NPC Interaction Tracking
    func recordNPCInteraction(_ npcID: String, responseType: NPCResponseType) {
        guard let memory = getNPCMemory(npcID) else { return }
        
        // Record the interaction
        memory.recordInteraction()
        
        // Apply satisfaction changes based on response
        switch responseType {
        case .dismiss:
            break // No satisfaction change
        case .nice:
            memory.receivedNiceTreatment()
            print("😊 NPC \(npcID) received nice treatment (+1 satisfaction)")
        case .mean:
            memory.receivedMeanTreatment()
            print("😠 NPC \(npcID) received mean treatment (-1 satisfaction)")
        }
        
        // Save changes
        saveNPCMemoryChanges(memory)
    }
    
    func recordNPCDrinkReceived(_ npcID: String) {
        guard let memory = getNPCMemory(npcID) else { return }
        
        memory.receivedDrink()
        print("🥤 NPC \(npcID) received drink (+5 satisfaction, total: \(memory.satisfactionScore))")
        
        saveNPCMemoryChanges(memory)
    }
    
    private func saveNPCMemoryChanges(_ memory: NPCMemory) {
        guard let context = modelContext else { return }
        
        do {
            try context.save()
            print("📦 Saved NPC memory changes - Satisfaction: \(memory.satisfactionScore)")
        } catch {
            print("❌ Failed to save NPC memory changes: \(error)")
        }
    }
    
    // MARK: - Data Management
    func clearAllSaveData() {
        guard let context = modelContext else {
            print("❌ Cannot clear data - SwiftData not initialized")
            return
        }
        
        do {
            // Delete all WorldState objects
            let worldStates = try context.fetch(FetchDescriptor<WorldState>())
            for state in worldStates {
                context.delete(state)
            }
            
            // Delete all NPCMemory objects
            let npcMemories = try context.fetch(FetchDescriptor<NPCMemory>())
            for memory in npcMemories {
                context.delete(memory)
            }
            
            // Delete all ShopMemory objects
            let shopMemories = try context.fetch(FetchDescriptor<ShopMemory>())
            for memory in shopMemories {
                context.delete(memory)
            }
            
            try context.save()
            print("📦 ✅ All save data cleared successfully!")
            
        } catch {
            print("❌ Failed to clear save data: \(error)")
        }
    }
    
    // MARK: - LLM Dialogue Management
    func addDialogueLine(npcID: String, text: String, timeContext: String, 
                        minSatisfaction: Int = 0, maxSatisfaction: Int = 100) {
        guard let context = modelContext else { return }
        
        do {
            // Find or create NPC character
            let npcCharacter = try getOrCreateNPCCharacter(npcID: npcID)
            
            // Create new dialogue line
            let lineID = UUID().uuidString
            let dialogueLine = DialogueLine(
                lineID: lineID,
                text: text,
                timeContext: timeContext,
                minSatisfaction: minSatisfaction,
                maxSatisfaction: maxSatisfaction
            )
            
            // Link to character
            dialogueLine.character = npcCharacter
            npcCharacter.dialogueLines.append(dialogueLine)
            
            context.insert(dialogueLine)
            try context.save()
            
            print("💬 Added dialogue line for \(npcID): '\(text.prefix(30))...'")
            
        } catch {
            print("❌ Failed to add dialogue line: \(error)")
        }
    }
    
    func getDialogueForNPC(_ npcID: String, timeContext: String, satisfactionScore: Int) -> String? {
        do {
            let npcCharacter = try getNPCCharacter(npcID: npcID)
            let dialogueLine = npcCharacter?.getDialogue(timeContext: timeContext, satisfactionScore: satisfactionScore)
            return dialogueLine?.text
            
        } catch {
            print("❌ Failed to get dialogue: \(error)")
            return nil
        }
    }
    
    func getAllDialogueForAnalysis(_ npcID: String, timeContext: String) -> [String] {
        do {
            let npcCharacter = try getNPCCharacter(npcID: npcID)
            let dialogueLines = npcCharacter?.getAllDialogue(timeContext: timeContext) ?? []
            return dialogueLines.map { $0.text }
            
        } catch {
            print("❌ Failed to get dialogue for analysis: \(error)")
            return []
        }
    }
    
    // MARK: - Data Migration from JSON
    func migrateDialogueFromJSON(_ jsonData: Data) {
        guard let context = modelContext else { return }
        
        do {
            let decoder = JSONDecoder()
            let npcDatabase = try decoder.decode(NPCDatabase.self, from: jsonData)
            
            for npcData in npcDatabase.npcs {
                // Create NPC character
                let npcCharacter = NPCCharacter(
                    npcID: npcData.id,
                    name: npcData.name,
                    animalType: npcData.animal,
                    causeOfDeath: npcData.causeOfDeath,
                    homeRoom: npcData.homeRoom
                )
                
                // Add day dialogue
                for dayLine in npcData.dialogue.day {
                    let dialogueLine = DialogueLine(
                        lineID: UUID().uuidString,
                        text: dayLine,
                        timeContext: "day"
                    )
                    dialogueLine.character = npcCharacter
                    npcCharacter.dialogueLines.append(dialogueLine)
                    context.insert(dialogueLine)
                }
                
                // Add night dialogue
                for nightLine in npcData.dialogue.night {
                    let dialogueLine = DialogueLine(
                        lineID: UUID().uuidString,
                        text: nightLine,
                        timeContext: "night"
                    )
                    dialogueLine.character = npcCharacter
                    npcCharacter.dialogueLines.append(dialogueLine)
                    context.insert(dialogueLine)
                }
                
                context.insert(npcCharacter)
            }
            
            try context.save()
            print("📦 Successfully migrated dialogue from JSON to SwiftData")
            
        } catch {
            print("❌ Failed to migrate dialogue from JSON: \(error)")
        }
    }
    
    // MARK: - Helper Methods
    private func getOrCreateWorldState() -> WorldState {
        if let existing = loadGameState() {
            return existing
        } else {
            let newState = WorldState()
            modelContext?.insert(newState)
            return newState
        }
    }
    
    private func createInitialDataIfNeeded() {
        guard let context = modelContext else { return }
        
        // Check if world state exists
        do {
            let descriptor = FetchDescriptor<WorldState>()
            let existingStates = try context.fetch(descriptor)
            
            if existingStates.isEmpty {
                let initialState = WorldState()
                context.insert(initialState)
                
                let initialShopMemory = ShopMemory()
                context.insert(initialShopMemory)
                
                try context.save()
                print("💾 Created initial save data")
            }
            
        } catch {
            print("❌ Failed to create initial data: \(error)")
        }
    }
    
    private func createNPCStateDict(_ residentManager: NPCResidentManager) -> [String: Any] {
        // Simple NPC state tracking - expand as needed
        return [
            "timestamp": Date().timeIntervalSince1970,
            "shopNPCCount": 0, // Will be filled by actual data
            "forestNPCCount": 0 // Will be filled by actual data
        ]
    }
    
    private func getOrCreateNPCCharacter(npcID: String) throws -> NPCCharacter {
        guard let context = modelContext else { throw NSError(domain: "SaveService", code: 1) }
        
        let descriptor = FetchDescriptor<NPCCharacter>(
            predicate: #Predicate { $0.npcID == npcID }
        )
        
        let characters = try context.fetch(descriptor)
        if let existing = characters.first {
            return existing
        } else {
            // Create basic character (LLM can fill details later)
            let newCharacter = NPCCharacter(
                npcID: npcID,
                name: "Unknown",
                animalType: "Unknown",
                causeOfDeath: "Unknown",
                homeRoom: 1
            )
            context.insert(newCharacter)
            return newCharacter
        }
    }
    
    private func getNPCCharacter(npcID: String) throws -> NPCCharacter? {
        guard let context = modelContext else { return nil }
        
        let descriptor = FetchDescriptor<NPCCharacter>(
            predicate: #Predicate { $0.npcID == npcID }
        )
        
        let characters = try context.fetch(descriptor)
        return characters.first
    }
    
    // MARK: - Debug and Inspection
    func inspectSwiftDataContents() {
        guard let context = modelContext else {
            print("❌ SwiftData not initialized")
            return
        }
        
        print("🔍 ==========================")
        print("🔍   SWIFTDATA INSPECTION")
        print("🔍 ==========================")
        
        do {
            // Check WorldState
            let worldStates = try context.fetch(FetchDescriptor<WorldState>())
            print("🌍 WorldState objects: \(worldStates.count)")
            for state in worldStates {
                print("🌍 - ID: \(state.worldID), Phase: \(state.currentTimePhase), LastSaved: \(state.lastSaved)")
            }
            
            // Check NPCMemory
            let npcMemories = try context.fetch(FetchDescriptor<NPCMemory>())
            print("🤖 NPCMemory objects: \(npcMemories.count)")
            for memory in npcMemories {
                print("🤖 - \(memory.name) (\(memory.animalType)): Satisfaction \(memory.satisfactionScore)/100")
                print("🤖   Interactions: \(memory.totalInteractions), Drinks: \(memory.totalDrinksReceived)")
                print("🤖   Preferred: \(memory.preferredFlavors), Disliked: \(memory.dislikedFlavors)")
            }
            
            // Check ShopMemory
            let shopMemories = try context.fetch(FetchDescriptor<ShopMemory>())
            print("🏢 ShopMemory objects: \(shopMemories.count)")
            for shop in shopMemories {
                print("🏢 - Drinks made: \(shop.totalDrinksMade), Customers: \(shop.totalCustomersServed)")
            }
            
            // Check NPCCharacter
            let npcCharacters = try context.fetch(FetchDescriptor<NPCCharacter>())
            print("💬 NPCCharacter objects: \(npcCharacters.count)")
            for character in npcCharacters {
                print("💬 - \(character.name) (\(character.npcID)): \(character.dialogueLines.count) dialogue lines")
            }
            
            // Check DialogueLine
            let dialogueLines = try context.fetch(FetchDescriptor<DialogueLine>())
            print("🗨️ DialogueLine objects: \(dialogueLines.count)")
            
        } catch {
            print("❌ Failed to inspect SwiftData: \(error)")
        }
        
        print("🔍 ==========================")
    }
}
