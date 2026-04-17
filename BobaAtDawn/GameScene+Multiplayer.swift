//
//  GameScene+Multiplayer.swift
//  BobaAtDawn
//
//  Handles incoming multiplayer messages and syncs world state
//  between host and guest in the shop scene.
//

import SpriteKit

extension GameScene: MultiplayerServiceDelegate {

    // MARK: - Setup

    func setupMultiplayer() {
        MultiplayerService.shared.delegate = self

        if MultiplayerService.shared.isConnected {
            addLocalPlayerLabel()
            spawnRemoteCharacter()
            if MultiplayerService.shared.isHost {
                sendHostHandshake()
            }
        }
    }

    /// Adds a "P1" label above the local character so both players can tell who is who
    private func addLocalPlayerLabel() {
        guard character.childNode(withName: "local_player_label") == nil else { return }
        let label = SKLabelNode(fontNamed: "Helvetica-Bold")
        label.text = "P1"
        label.fontSize = 12
        label.fontColor = SKColor(red: 0.3, green: 0.9, blue: 0.3, alpha: 0.9)
        label.horizontalAlignmentMode = .center
        label.verticalAlignmentMode = .bottom
        label.position = CGPoint(x: 0, y: character.size.height / 2 + 4)
        label.zPosition = 200
        label.name = "local_player_label"
        character.addChild(label)
    }

    private func spawnRemoteCharacter() {
        guard remoteCharacter == nil else { return }
        let remote = RemoteCharacter()
        remote.position = character.position
        addChild(remote)
        remoteCharacter = remote
        Log.info(.network, "Remote character spawned in GameScene")
    }

    private func sendHostHandshake() {
        let handshake = HostHandshake(
            dayCount: timeService.dayCount,
            timePhase: timeService.currentPhase.displayName,
            timeProgress: timeService.phaseProgress,
            isTimeFlowing: timeService.isTimeActive,
            npcStatesJSON: SaveService.shared.loadGameState()?.npcStatesJSON ?? "{}",
            hostPlayerPosition: CodablePoint(character.position),
            ritualActive: isRitualActive
        )
        MultiplayerService.shared.send(type: .hostHandshake, payload: handshake)
        Log.info(.network, "Sent host handshake")
    }

    // MARK: - MultiplayerServiceDelegate

    func multiplayerDidConnect(isHost: Bool) {
        Log.info(.network, "GameScene: connected as \(isHost ? "HOST" : "GUEST")")
        addLocalPlayerLabel()
        spawnRemoteCharacter()
        
        // Both players exchange save timestamps. The player with the newer
        // save sends a full WorldSync to the other so both devices share
        // the same persistent world.
        let myTimestamp = SaveService.shared.getSaveTimestamp()
        
        if isHost {
            sendHostHandshake()
            // Send our timestamp too so the guest can compare.
            // If the guest's save is newer, THEY will send worldSync to us.
            MultiplayerService.shared.send(
                type: .stateRequest,
                payload: StateRequestMessage(
                    requestingScene: "shop",
                    saveTimestamp: myTimestamp
                )
            )
        } else {
            MultiplayerService.shared.send(
                type: .stateRequest,
                payload: StateRequestMessage(
                    requestingScene: "shop",
                    saveTimestamp: myTimestamp
                )
            )
        }
    }

    func multiplayerDidDisconnect() {
        Log.info(.network, "GameScene: remote player disconnected")
        remoteCharacter?.removeFromParent()
        remoteCharacter = nil
        
        // Auto-save the shared world so the other player can pick up where we left off.
        SaveService.shared.autoSave(timeService: timeService)
    }

    func multiplayerDidFail(error: String) {
        Log.error(.network, "GameScene: multiplayer error — \(error)")
    }

    func multiplayerDidReceive(_ envelope: NetworkEnvelope) {
        switch envelope.type {

        case .playerPosition:
            guard let msg = try? envelope.decode(PlayerPositionMessage.self) else { return }
            if msg.sceneType == "shop" {
                if remoteCharacter == nil { spawnRemoteCharacter() }
                remoteCharacter?.isHidden = false
                remoteCharacter?.applyRemoteUpdate(msg)
            } else {
                remoteCharacter?.isHidden = true
            }

        case .hostHandshake:
            guard MultiplayerService.shared.isGuest else { return }
            guard let handshake = try? envelope.decode(HostHandshake.self) else { return }
            applyHostHandshake(handshake)

        case .npcInteraction:
            guard let msg = try? envelope.decode(NPCInteractionMessage.self) else { return }
            let responseType: NPCResponseType = {
                switch msg.responseType {
                case "nice": return .nice
                case "mean": return .mean
                default:     return .dismiss
                }
            }()
            SaveService.shared.recordNPCInteraction(msg.npcID, responseType: responseType)

        case .drinkServed:
            guard let msg = try? envelope.decode(DrinkServedMessage.self) else { return }
            SaveService.shared.recordNPCDrinkReceived(msg.npcID)

        case .stationToggled:
            guard let msg = try? envelope.decode(StationToggledMessage.self) else { return }
            if let station = ingredientStations.first(where: { "\($0.stationType)" == msg.stationName }) {
                station.interact()
                drinkCreator.updateDrink(from: ingredientStations)
                // NOTE: Do NOT rebuild the local player's carried drink here.
                // Remote station toggles update the station visuals and the
                // counter display, but only YOUR OWN toggles should change
                // the drink in your hand. Local rebuilds happen in
                // GameScene.handleGameSceneLongPress.
            }

        case .drinkPlacedOnTable:
            guard let msg = try? envelope.decode(DrinkPlacedOnTableMessage.self) else { return }
            // Find the table nearest to the broadcast position
            let tables = children.compactMap { $0 as? RotatableObject }.filter {
                $0.name == "table" || $0.name == "sacred_table"
            }
            if let table = tables.min(by: {
                hypot($0.position.x - msg.tablePosition.cgPoint.x,
                      $0.position.y - msg.tablePosition.cgPoint.y)
                <
                hypot($1.position.x - msg.tablePosition.cgPoint.x,
                      $1.position.y - msg.tablePosition.cgPoint.y)
            }) {
                let drinkOnTable = buildRemoteTableDrink(msg)
                let offsets: [CGPoint] = [
                    configService.tableDrinkOnTableOffset,
                    CGPoint(x: configService.tableDrinkOnTableOffset.x - 15,
                            y: configService.tableDrinkOnTableOffset.y + 10),
                    CGPoint(x: configService.tableDrinkOnTableOffset.x + 15,
                            y: configService.tableDrinkOnTableOffset.y + 10)
                ]
                let slot = min(msg.slotIndex, offsets.count - 1)
                drinkOnTable.position = offsets[slot]
                drinkOnTable.zPosition = ZLayers.childLayer(for: ZLayers.tables)
                drinkOnTable.name = "drink_on_table"
                table.addChild(drinkOnTable)
                Log.info(.network, "Remote drink placed on table")
            }

        case .timePhaseChanged:
            guard MultiplayerService.shared.isGuest else { return }
            guard let msg = try? envelope.decode(TimePhaseChangedMessage.self) else { return }
            Log.info(.network, "Remote time phase: \(msg.newPhase), day \(msg.dayCount)")
            
            // Apply the host's phase change locally
            if let phase = TimePhase.allCases.first(where: { $0.displayName == msg.newPhase }) {
                timeService.setDebugPhase(phase)
                lastTimePhase = phase
                residentManager.handleTimePhaseChange(phase)
                handleRitualTimePhaseChange(phase)
            }
            if msg.dayCount > 0 {
                timeService.syncDayCount(msg.dayCount)
            }

        case .trashSpawned:
            guard let msg = try? envelope.decode(TrashSpawnedMessage.self) else { return }
            if msg.location == "shop" {
                let trash = Trash(at: msg.position.cgPoint, location: .shop)
                addChild(trash)
            }

        case .trashCleaned:
            guard let msg = try? envelope.decode(TrashCleanedMessage.self) else { return }
            let trashNodes = children.compactMap { $0 as? Trash }
            if let nearest = trashNodes.min(by: {
                hypot($0.position.x - msg.position.cgPoint.x, $0.position.y - msg.position.cgPoint.y)
                <
                hypot($1.position.x - msg.position.cgPoint.x, $1.position.y - msg.position.cgPoint.y)
            }) {
                nearest.pickUp { Log.debug(.network, "Remote trash cleaned") }
            }

        case .npcLiberated:
            guard let msg = try? envelope.decode(NPCLiberatedMessage.self) else { return }
            SaveService.shared.markNPCAsLiberated(msg.npcID)

        case .fullStateSync:
            guard MultiplayerService.shared.isGuest else { return }
            guard let msg = try? envelope.decode(FullStateSyncMessage.self) else { return }
            applyHostHandshake(msg.handshake)

        case .npcShopSync:
            guard MultiplayerService.shared.isGuest else { return }
            guard let msg = try? envelope.decode(NPCShopSyncMessage.self) else { return }
            applyNPCShopSync(msg)

        case .snailSync:
            guard MultiplayerService.shared.isGuest else { return }
            guard let msg = try? envelope.decode(SnailSyncMessage.self) else { return }
            applySnailSync(msg)

        case .dialogueShown:
            guard let msg = try? envelope.decode(DialogueShownMessage.self) else { return }
            DialogueService.shared.showRemoteDialogue(
                npcID: msg.npcID,
                speakerName: msg.speakerName,
                text: msg.text,
                at: msg.position.cgPoint,
                in: self
            )

        case .dialogueDismissed:
            DialogueService.shared.dismissRemoteDialogue()

        case .ritualStepCompleted:
            guard let msg = try? envelope.decode(RitualStepMessage.self) else { return }
            applyRemoteRitualStep(msg)

        case .ritualStateSync:
            guard let msg = try? envelope.decode(RitualStateSyncMessage.self) else { return }
            applyRemoteRitualState(msg)

        case .stateRequest:
            // Other player sent their save timestamp. Compare with ours.
            // If our save is newer, we send them the full world state.
            guard let msg = try? envelope.decode(StateRequestMessage.self) else { return }
            let myTimestamp = SaveService.shared.getSaveTimestamp()
            
            if myTimestamp >= msg.saveTimestamp {
                // Our save is newer (or equal) — we are the source of truth.
                let worldSync = SaveService.shared.exportWorldSync(timeService: timeService)
                MultiplayerService.shared.send(type: .worldSync, payload: worldSync)
                Log.info(.network, "Our save is newer (\(myTimestamp) vs \(msg.saveTimestamp)) — sending world sync")
            } else {
                // Their save is newer — they'll send us the worldSync when
                // they receive our stateRequest.
                Log.info(.network, "Their save is newer (\(msg.saveTimestamp) vs \(myTimestamp)) — waiting for their world sync")
            }
            
            // Also respond with handshake if we're host (for real-time state)
            if MultiplayerService.shared.isHost {
                sendHostHandshake()
            }

        case .worldSync:
            guard let msg = try? envelope.decode(WorldSyncMessage.self) else { return }
            applyWorldSync(msg)

        case .timeSync:
            guard MultiplayerService.shared.isGuest else { return }
            guard let msg = try? envelope.decode(TimeSyncMessage.self) else { return }
            applyTimeSync(msg)

        default:
            Log.debug(.network, "Unhandled message type: \(envelope.type.rawValue)")
        }
    }
    
    // MARK: - Host-Authoritative NPC Sync (Guest Side)
    
    /// Reconcile local shop NPCs against the host's broadcast state.
    /// Creates new NPCs that appear in the sync, lerps existing NPCs to
    /// broadcast positions, and removes NPCs that are no longer present.
    private func applyNPCShopSync(_ msg: NPCShopSyncMessage) {
        let syncIDs = Set(msg.entries.map { $0.npcID })
        
        // 1. Create or update NPCs from sync
        for entry in msg.entries {
            if let existing = npcs.first(where: { $0.animalType.characterId == entry.npcID }) {
                // Lerp existing NPC toward broadcast position
                let target = entry.position.cgPoint
                let dx = target.x - existing.position.x
                let dy = target.y - existing.position.y
                let factor: CGFloat = 0.25 // Smooth lerp
                existing.position = CGPoint(
                    x: existing.position.x + dx * factor,
                    y: existing.position.y + dy * factor
                )
            } else {
                // New NPC from host — create it
                guard let animal = AnimalType.allCases.first(where: { $0.rawValue == entry.animalType }) else { continue }
                let npc = ShopNPC(animal: animal,
                                  startPosition: gridService.worldToGrid(entry.position.cgPoint),
                                  gridService: gridService,
                                  npcService: npcService)
                npc.position = entry.position.cgPoint
                addChild(npc)
                npcs.append(npc)
                addEntranceAnimation(for: npc)
                Log.info(.network, "Guest: created sync NPC \(entry.npcID)")
            }
        }
        
        // 2. Remove NPCs that are no longer in the host's sync
        let toRemove = npcs.filter { npc in
            guard let charId = npc.animalType.characterId else { return false }
            return !syncIDs.contains(charId)
        }
        for npc in toRemove {
            npc.removeFromParent()
            if let idx = npcs.firstIndex(where: { $0 === npc }) {
                npcs.remove(at: idx)
            }
            Log.info(.network, "Guest: removed NPC no longer in host sync")
        }
    }
    
    // MARK: - Host-Authoritative Snail Sync (Guest Side)
    
    /// Override local snail world state with host's broadcast.
    private func applySnailSync(_ msg: SnailSyncMessage) {
        let world = SnailWorldState.shared
        world.currentRoom = msg.room
        world.roomPosition = msg.position.cgPoint
        if msg.isActive && !world.isActive {
            world.isActive = true
        } else if !msg.isActive && world.isActive {
            world.isActive = false
        }
    }
    
    // MARK: - Shared Persistent World
    
    /// Apply a full world sync from the other player (their save was newer).
    /// Overwrites local NPC memories, day count, and world state so both
    /// devices share the same persistent world.
    private func applyWorldSync(_ msg: WorldSyncMessage) {
        Log.info(.network, "Applying world sync: day \(msg.dayCount), \(msg.npcMemories.count) NPC memories")
        
        // Import into SwiftData (overwrites NPC memories + world state)
        SaveService.shared.importWorldSync(msg)
        
        // Update runtime state to match
        timeService.syncDayCount(msg.dayCount)
        
        if let phase = TimePhase.allCases.first(where: { $0.displayName == msg.timePhase }) {
            timeService.setDebugPhase(phase)
            lastTimePhase = phase
        }
        
        Log.info(.network, "Shared world loaded from other player (day \(msg.dayCount))")
    }

    private func applyHostHandshake(_ handshake: HostHandshake) {
        Log.info(.network, "Applying host handshake: day \(handshake.dayCount), phase \(handshake.timePhase)")
        
        // Sync time phase
        if let phase = TimePhase.allCases.first(where: { $0.displayName == handshake.timePhase }) {
            timeService.setDebugPhase(phase)
            lastTimePhase = phase
        }
        
        // Sync day count (updates runtime cache so isRitualDay works)
        if handshake.dayCount > 0 {
            timeService.syncDayCount(handshake.dayCount)
        }
        
        // Sync ritual state
        if handshake.ritualActive && !isRitualActive {
            isRitualActive = true
            Log.info(.network, "Guest: ritual is active on host")
        }
    }
    
    // MARK: - Time Sync
    
    private func applyTimeSync(_ msg: TimeSyncMessage) {
        if let phase = TimePhase.allCases.first(where: { $0.displayName == msg.phase }) {
            if phase != timeService.currentPhase {
                timeService.setDebugPhase(phase)
                lastTimePhase = phase
            }
        }
        if msg.dayCount > 0 {
            timeService.syncDayCount(msg.dayCount)
        }
    }
    
    // MARK: - Ritual Sync (Remote)
    
    private func applyRemoteRitualStep(_ msg: RitualStepMessage) {
        switch msg.step {
        case "candle_lit":
            // Light the next unlit candle in the ritual area
            if let ritualAreaNode = ritualArea {
                let candles = ritualAreaNode.children.compactMap { $0 as? RitualCandle }
                if let unlit = candles.first(where: { !$0.isLit }) {
                    unlit.lightFromNetwork()
                }
            }
        case "harp_played":
            if let ritualAreaNode = ritualArea {
                let harps = ritualAreaNode.children.compactMap { $0 as? SacredHarp }
                harps.first?.playFromNetwork()
            }
        default:
            Log.debug(.network, "Unknown ritual step: \(msg.step)")
        }
    }
    
    private func applyRemoteRitualState(_ msg: RitualStateSyncMessage) {
        if msg.isActive && !isRitualActive {
            isRitualActive = true
            if ritualArea.hasEligibleNPCs() {
                ritualArea.spawnRitual()
            }
            Log.info(.network, "Guest: ritual spawned from host sync")
        } else if !msg.isActive && isRitualActive {
            isRitualActive = false
            ritualArea.forceCleanup()
            Log.info(.network, "Guest: ritual cleaned up from host sync")
        }
    }
    
    /// Build a visual table-drink node from a remote placement message.
    /// Matches the same atlas/scale logic used in `createTableDrink`.
    private func buildRemoteTableDrink(_ msg: DrinkPlacedOnTableMessage) -> SKNode {
        let tableDrink = SKNode()
        let atlas = SKTextureAtlas(named: "Boba")
        guard atlas.textureNames.count > 0 else { return tableDrink }
        
        let cupTex = atlas.textureNamed("cup_empty")
        let tableScale = 15.0 / cupTex.size().width
        
        func addLayer(_ name: String, z: CGFloat) {
            guard atlas.textureNames.contains(name) else { return }
            let tex = atlas.textureNamed(name)
            tex.filteringMode = .nearest
            let node = SKSpriteNode(texture: tex)
            node.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            node.position = .zero
            node.setScale(tableScale)
            node.zPosition = z
            node.blendMode = .alpha
            node.name = name
            tableDrink.addChild(node)
        }
        
        addLayer("cup_empty", z: 0)
        if msg.hasTea  { addLayer("tea_black",       z: 1) }
        if msg.hasIce  { addLayer("ice_cubes",       z: 2) }
        if msg.hasBoba { addLayer("topping_tapioca", z: 3) }
        if msg.hasFoam { addLayer("foam_cheese",     z: 4) }
        if msg.hasLid  { addLayer("lid_straw",       z: 5) }
        
        return tableDrink
    }
}
