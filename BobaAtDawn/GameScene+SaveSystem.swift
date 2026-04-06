//
//  GameScene+SaveSystem.swift
//  BobaAtDawn
//
//  Save/load system, data clearing, and NPC status reporting.
//  Extracted from GameScene.swift for maintainability.
//

import SpriteKit

extension GameScene {
    
    // MARK: - Save System Setup
    
    func setupSaveSystem() {
        saveJournal = SaveSystemButton(type: .saveJournal)
        let journalCell = GridCoordinate(x: 2, y: 7)
        saveJournal.position = gridService.gridToWorld(journalCell)
        saveJournal.zPosition = ZLayers.timeSystem
        addChild(saveJournal)
        
        clearDataButton = SaveSystemButton(type: .clearData)
        let clearCell = GridCoordinate(x: 4, y: 7)
        clearDataButton.position = gridService.gridToWorld(clearCell)
        clearDataButton.zPosition = ZLayers.timeSystem
        addChild(clearDataButton)
        
        npcStatusTracker = SaveSystemButton(type: .npcStatus)
        let statusCell = GridCoordinate(x: 6, y: 7)
        npcStatusTracker.position = gridService.gridToWorld(statusCell)
        npcStatusTracker.zPosition = ZLayers.timeSystem
        addChild(npcStatusTracker)
        
        Log.info(.save, "Save system buttons placed at grid \(journalCell), \(clearCell), \(statusCell)")
    }
    
    // MARK: - Save Actions
    
    func saveGameState() {
        let glow = SKAction.sequence([
            SKAction.scale(to: 1.2, duration: 0.1),
            SKAction.scale(to: 1.0, duration: 0.1)
        ])
        saveJournal.run(glow)
        transitionService.triggerHapticFeedback(type: .success)
        
        SaveService.shared.saveCurrentGameState(timeService: timeService, residentManager: residentManager)
        Log.info(.save, "Game saved successfully")
    }
    
    func clearSaveData() {
        let flash = SKAction.sequence([
            SKAction.colorize(with: .red, colorBlendFactor: 0.8, duration: 0.1),
            SKAction.colorize(with: .white, colorBlendFactor: 0.0, duration: 0.1)
        ])
        clearDataButton.run(flash)
        transitionService.triggerHapticFeedback(type: .light)
        
        SaveService.shared.clearAllSaveData()
        Log.info(.save, "All save data cleared")
    }
    
    func showNPCStatusReport() {
        let glow = SKAction.sequence([
            SKAction.scale(to: 1.2, duration: 0.1),
            SKAction.scale(to: 1.0, duration: 0.1)
        ])
        npcStatusTracker.run(glow)
        transitionService.triggerHapticFeedback(type: .selection)
        
        SaveService.shared.inspectSwiftDataContents()
        showNPCStatusBubble()
        Log.info(.save, "NPC status report displayed")
    }
    
    // MARK: - NPC Status Bubble Display
    
    func showNPCStatusBubble() {
        DialogueService.shared.dismissDialogue()
        
        let allNPCs = DialogueService.shared.getAllNPCs()
        var statusLines: [String] = ["📈 NPC STATUS REPORT", ""]
        
        if allNPCs.isEmpty {
            statusLines.append("🤷‍♂️ No NPCs found")
        } else {
            var liberatedCount = 0
            
            for npcData in allNPCs {
                if let memory = SaveService.shared.getOrCreateNPCMemory(
                    npcData.id, name: npcData.name, animalType: npcData.animal
                ) {
                    if memory.isLiberated {
                        liberatedCount += 1
                        statusLines.append("👻 \(npcData.animal) \(npcData.name) - LIBERATED ✨")
                        if let date = memory.liberationDate {
                            let fmt = DateFormatter()
                            fmt.dateStyle = .short
                            statusLines.append("Found peace: \(fmt.string(from: date))")
                        }
                    } else {
                        statusLines.append("\(npcData.animal) \(npcData.name) \(memory.satisfactionLevel.emoji)")
                        statusLines.append("Satisfaction: \(memory.satisfactionScore)/100")
                        statusLines.append("Interactions: \(memory.totalInteractions)")
                        
                        if memory.satisfactionScore <= 20 {
                            statusLines.append("🔥 Ready for hellish liberation ritual")
                        } else if memory.satisfactionScore >= 80 {
                            statusLines.append("✨ Ready for divine liberation ritual")
                        }
                    }
                    statusLines.append("")
                } else {
                    statusLines.append("\(npcData.animal) \(npcData.name) - No data")
                    statusLines.append("")
                }
            }
            
            statusLines.append("📈 Total NPCs: \(allNPCs.count)")
            statusLines.append("✨ Liberated souls: \(liberatedCount)")
            
            let eligibleCount = allNPCs.filter { npcData in
                guard !SaveService.shared.isNPCLiberated(npcData.id) else { return false }
                guard let memory = SaveService.shared.getOrCreateNPCMemory(
                    npcData.id, name: npcData.name, animalType: npcData.animal
                ) else { return false }
                return memory.satisfactionScore <= 20 || memory.satisfactionScore >= 80
            }.count
            
            statusLines.append("🕯️ Ready for ritual: \(eligibleCount)")
        }
        
        let bubble = NPCStatusBubble(statusLines: statusLines, position: npcStatusTracker.position)
        addChild(bubble)
    }
}
