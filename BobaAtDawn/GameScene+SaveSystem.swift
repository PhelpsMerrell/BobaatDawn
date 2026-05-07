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
        saveJournal = requiredSceneNode(named: "save_journal", as: SaveSystemButton.self)
        saveJournal.zPosition = ZLayers.timeSystem
        
        clearDataButton = requiredSceneNode(named: "clear_data_button", as: SaveSystemButton.self)
        clearDataButton.zPosition = ZLayers.timeSystem
        
        npcStatusTracker = requiredSceneNode(named: "npc_status_tracker", as: SaveSystemButton.self)
        npcStatusTracker.zPosition = ZLayers.timeSystem
        
        let journalCell = gridService.worldToGrid(saveJournal.positionInSceneCoordinates())
        let clearCell = gridService.worldToGrid(clearDataButton.positionInSceneCoordinates())
        let statusCell = gridService.worldToGrid(npcStatusTracker.positionInSceneCoordinates())
        Log.info(.save, "Save system buttons loaded from GameScene.sks at grid \(journalCell), \(clearCell), \(statusCell)")
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
        
        SaveService.shared.clearCurrentSaveSlot()
        Log.info(.save, "Current save slot reset")
    }
    
    func showNPCStatusReport() {
        let glow = SKAction.sequence([
            SKAction.scale(to: 1.2, duration: 0.1),
            SKAction.scale(to: 1.0, duration: 0.1)
        ])
        npcStatusTracker.run(glow)
        transitionService.triggerHapticFeedback(type: .selection)
        
        SaveService.shared.inspectSwiftDataContents()
        showNPCDebugMenu()
        Log.info(.save, "NPC debug menu opened")
    }
    
    // MARK: - NPC Debug Menu
    
    /// Build the entry list, instantiate NPCDebugMenu, and parent it to
    /// the camera so it sits screen-anchored regardless of pan/zoom.
    /// Replaces the old NPCStatusBubble flow.
    func showNPCDebugMenu() {
        // Dismiss any extant dialogue / bubbles before opening.
        DialogueService.shared.dismissDialogue()
        
        // If we're in a multiplayer session, ask the partner who has the
        // newer save. The existing stateRequest → worldSync flow then
        // pushes whichever side is fresher to the other, which fixes any
        // drift that may have accumulated before the per-NPC sync
        // handler existed. The menu's own broadcasts keep things in lock
        // step from this point on; this is just a one-shot reconcile on
        // open.
        if MultiplayerService.shared.isConnected {
            MultiplayerService.shared.send(
                type: .stateRequest,
                payload: StateRequestMessage(
                    requestingScene: "shop",
                    saveTimestamp: SaveService.shared.getSaveTimestamp()
                )
            )
        }
        
        let allNPCs = DialogueService.shared.getAllNPCs()
        var entries: [NPCDebugMenu.Entry] = []
        for npcData in allNPCs {
            guard let memory = SaveService.shared.getOrCreateNPCMemory(
                npcData.id, name: npcData.name, animalType: npcData.animal
            ) else { continue }
            entries.append(NPCDebugMenu.Entry(npcData: npcData, memory: memory))
        }
        
        // Compute visible viewport in scene units. This handles aspectFill
        // scaling and camera zoom in one shot, so sizing the menu at a
        // percentage of this value gives the same percentage of the
        // visible screen.
        let visibleSize: CGSize
        if let view = view {
            let topLeft = convertPoint(fromView: .zero)
            let bottomRight = convertPoint(fromView: CGPoint(
                x: view.bounds.width, y: view.bounds.height
            ))
            visibleSize = CGSize(
                width:  abs(bottomRight.x - topLeft.x),
                height: abs(bottomRight.y - topLeft.y)
            )
        } else {
            visibleSize = size
        }
        
        // IMPORTANT: parent the menu to the SCENE, not the camera.
        // Camera-child rendering bakes the aspectFill transform into the
        // child's apparent size in a way that breaks our "size in scene
        // units" assumption: a 360-scene-unit shape parented to a
        // zoomed-in camera ends up much wider than the screen. Scene
        // children, by contrast, render with both aspectFill and camera
        // scale applied, so 92% of `visibleSize` is exactly 92% of the
        // viewport. The menu syncs its position to the camera each frame
        // so it stays anchored to the screen as the player walks.
        let host: SKNode = self
        
        // Tear down any existing instance before opening a fresh one.
        host.childNode(withName: "npc_debug_menu")?.removeFromParent()
        
        let menu = NPCDebugMenu(
            entries: entries,
            visibleSize: visibleSize,
            onClose: { [weak host] in
                host?.childNode(withName: "npc_debug_menu")?
                    .run(SKAction.sequence([
                        SKAction.fadeOut(withDuration: 0.18),
                        SKAction.removeFromParent()
                    ]))
            },
            onForceSave: { [weak self] in
                guard let self = self else { return }
                SaveService.shared.saveCurrentGameState(
                    timeService: self.timeService,
                    residentManager: self.residentManager
                )
            }
        )
        // Pin to the camera's current world position so the menu opens
        // centered on screen. The follow-camera action inside the menu
        // keeps it pinned even if the player walks.
        menu.position = gameCamera?.position ?? .zero
        host.addChild(menu)
    }
}
