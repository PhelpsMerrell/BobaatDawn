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
                scheduleInitialHostSyncBurst()
            } else {
                sendGuestReady()
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

    private func sendAuthoritativeWorldSync() {
        let worldSync = SaveService.shared.exportWorldSync(timeService: timeService)
        MultiplayerService.shared.send(type: .worldSync, payload: worldSync)
        Log.info(.network, "Sent authoritative world sync")
    }

    private func sendGuestReady() {
        guard MultiplayerService.shared.isGuest else { return }
        MultiplayerService.shared.send(
            type: .guestReady,
            payload: GuestReady(guestDisplayName: "Guest")
        )
        Log.info(.network, "Guest ready in GameScene")
    }

    private func scheduleInitialHostSyncBurst() {
        guard MultiplayerService.shared.isHost else { return }
        let delays: [TimeInterval] = [0.15, 0.75]
        for (index, delay) in delays.enumerated() {
            let action = SKAction.sequence([
                SKAction.wait(forDuration: delay),
                SKAction.run { [weak self] in
                    guard let self, MultiplayerService.shared.isHost else { return }
                    self.sendHostHandshake()
                    self.sendAuthoritativeWorldSync()
                }
            ])
            run(action, withKey: "initial_host_sync_\(index)")
        }
    }

    // MARK: - MultiplayerServiceDelegate

    func multiplayerDidConnect(isHost: Bool) {
        Log.info(.network, "GameScene: connected as \(isHost ? "HOST" : "GUEST")")
        addLocalPlayerLabel()
        spawnRemoteCharacter()

        if isHost {
            scheduleInitialHostSyncBurst()
        } else {
            sendGuestReady()
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

        case .guestReady:
            guard MultiplayerService.shared.isHost else { return }
            _ = try? envelope.decode(GuestReady.self)
            sendHostHandshake()
            sendAuthoritativeWorldSync()

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
            // Post-refactor: station toggles don't mutate any drink state.
            // This message now exists purely so the remote player sees
            // OUR station pulse when we use it — a cosmetic "your partner
            // just scooped tea" cue. Do NOT call station.interact() here
            // because that would fire the pulse a second time on the
            // sender (they already saw it locally); instead play a
            // lighter pulse directly.
            guard let msg = try? envelope.decode(StationToggledMessage.self) else { return }
            if let station = ingredientStations.first(where: { "\($0.stationType)" == msg.stationName }) {
                let pulse = animationService.stationInteractionPulse(station)
                animationService.run(pulse, on: station, withKey: AnimationKeys.stationInteraction, completion: nil)
            }

        case .drinkPlacedOnTable:
            guard let msg = try? envelope.decode(DrinkPlacedOnTableMessage.self) else { return }
            // Find the table nearest to the broadcast position
            let tables = children.compactMap { $0 as? RotatableObject }.filter {
                isTableNode($0)
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
                
                // Mirror the local-placement registry behaviour so the drink
                // persists on this device too. Skip sacred_table — its drink
                // is consumed by the ritual and is never restored.
                if table.name != "sacred_table" {
                    let item = WorldItemRegistry.makeDrinkOnTable(
                        tablePosition: table.position,
                        slotIndex: slot,
                        hasTea:  msg.hasTea,
                        hasIce:  msg.hasIce,
                        hasBoba: msg.hasBoba,
                        hasFoam: msg.hasFoam,
                        hasLid:  msg.hasLid
                    )
                    WorldItemRegistry.shared.add(item)
                    drinkOnTable.userData = NSMutableDictionary()
                    drinkOnTable.userData?["worldItemID"] = item.id
                }
                
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

        case .timeSubphaseRequest:
            // Subphase debug request from the partner. Both host and
            // guest accept these so either player can drive the time-
            // control button. Host treats incoming requests from the
            // guest as authoritative and echoes the same message back
            // (closing the loop so the guest's local UI updates without
            // waiting for the next periodic timeSync).
            guard let msg = try? envelope.decode(TimeSubphaseRequestMessage.self) else { return }
            guard let subphase = TimeSubphase(rawValue: msg.subphaseRawValue) else { return }
            timeService.setDebugSubphase(subphase)
            lastTimePhase = subphase.phase
            residentManager.handleTimePhaseChange(subphase.phase)
            handleRitualTimePhaseChange(subphase.phase)
            GnomeManager.shared.handleTimePhaseChange(subphase.phase, dayCount: timeService.dayCount)
            // Host echoes back to guest so its local time-control button
            // re-renders immediately. Guest never echoes (would loop).
            if MultiplayerService.shared.isHost {
                MultiplayerService.shared.send(
                    type: .timeSubphaseRequest,
                    payload: TimeSubphaseRequestMessage(
                        subphaseRawValue: msg.subphaseRawValue,
                        dayCount: timeService.dayCount
                    )
                )
            }

        case .trashSpawned:
            guard let msg = try? envelope.decode(TrashSpawnedMessage.self) else { return }
            if msg.location == "shop" {
                let trash = Trash(at: msg.position.cgPoint, location: .shop)
                addChild(trash)
            }

        case .trashCleaned:
            guard let msg = try? envelope.decode(TrashCleanedMessage.self) else { return }
            // Only react to shop-scoped trash messages. Forest-scoped
            // messages (location like "forest_room_3") are handled by
            // ForestScene's own multiplayer handler; without this filter
            // we'd try to match forest coordinates against shop trash and
            // potentially clean an unrelated piece.
            guard msg.location == "shop" else { return }
            let trashNodes = children.compactMap { $0 as? Trash }
            if let nearest = trashNodes.min(by: {
                hypot($0.position.x - msg.position.cgPoint.x, $0.position.y - msg.position.cgPoint.y)
                <
                hypot($1.position.x - msg.position.cgPoint.x, $1.position.y - msg.position.cgPoint.y)
            }) {
                // Unregister from the world registry so the shared persistent
                // state matches. Prefer the stamped ID; fall back to spatial lookup.
                if let itemID = nearest.userData?["worldItemID"] as? String {
                    WorldItemRegistry.shared.remove(id: itemID)
                } else if let match = WorldItemRegistry.shared.nearestItem(
                    kind: .trash, at: .shop, near: msg.position.cgPoint) {
                    WorldItemRegistry.shared.remove(id: match.id)
                }
                nearest.pickUp { Log.debug(.network, "Remote trash cleaned") }
                // Chronicle hook (host receiving guest's clean event).
                DailyChronicleLedger.shared.recordTrashCleaned(location: "shop")
            }

        case .npcLiberated:
            guard let msg = try? envelope.decode(NPCLiberatedMessage.self) else { return }
            SaveService.shared.markNPCAsLiberated(msg.npcID)

        case .npcSatisfactionSync:
            // Per-NPC satisfaction broadcast. Either side can send this
            // — typically from the dev menu, but also from any future
            // gameplay path that mutates satisfaction without going
            // through the host. We mirror the entries into local
            // SwiftData and refresh any visible debug menu so the user
            // sees the partner's change land in real time.
            guard let msg = try? envelope.decode(NPCSatisfactionSync.self) else { return }
            for entry in msg.entries {
                guard let memory = SaveService.shared.getNPCMemory(entry.npcID) else { continue }
                memory.satisfactionScore = entry.satisfactionScore
                memory.totalDrinksReceived = entry.totalDrinksReceived
                // Liberation flag is sticky on the receiving side: if the
                // sender turned liberation OFF (debug reset) we follow;
                // if they turned it ON, we follow too. liberationDate is
                // recomputed only when going from not-liberated → liberated.
                if memory.isLiberated != entry.isLiberated {
                    memory.isLiberated = entry.isLiberated
                    memory.liberationDate = entry.isLiberated ? Date() : nil
                }
                SaveService.shared.persistNPCMemoryChanges(memory)
            }
            NPCDebugMenu.refreshIfOpen(in: self)
            Log.info(.network, "Applied \(msg.entries.count) NPC satisfaction sync entr\(msg.entries.count == 1 ? "y" : "ies")")

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
            // LEGACY non-streaming path — still used for liberation
            // farewells and any non-LLM path that goes through the old
            // single-shot broadcast. New host-authoritative streaming
            // dialogue uses dialogueOpened/dialogueLineDelta/etc instead.
            guard let msg = try? envelope.decode(DialogueShownMessage.self) else { return }
            guard msg.sceneType == DialogueService.sceneTypeKey(for: self) else { return }
            DialogueService.shared.showRemoteDialogue(
                npcID: msg.npcID,
                speakerName: msg.speakerName,
                text: msg.text,
                mood: msg.mood,
                at: msg.position.cgPoint,
                in: self
            )

        case .dialogueOpenRequest:
            // Either player may send this. Only the host actually opens
            // the dialogue (and broadcasts `dialogueOpened`). Guests
            // ignore — they should never receive this anyway, since
            // GKMatch broadcasts to all players and the requester's own
            // message comes back through the loopback path on host.
            guard MultiplayerService.shared.isHost else { return }
            guard let msg = try? envelope.decode(DialogueOpenRequestMessage.self) else { return }
            DialogueService.shared.hostHandleOpenRequest(msg, in: self)

        case .dialogueOpened:
            // Host → both. Open a matching empty bubble so we can fill it
            // in via subsequent dialogueLineDelta messages.
            guard let msg = try? envelope.decode(DialogueOpenedMessage.self) else { return }
            DialogueService.shared.applyDialogueOpened(msg, in: self)

        case .dialogueLineDelta:
            guard let msg = try? envelope.decode(DialogueLineDeltaMessage.self) else { return }
            DialogueService.shared.applyDialogueLineDelta(msg)

        case .dialogueFollowupsReady:
            guard let msg = try? envelope.decode(DialogueFollowupsReadyMessage.self) else { return }
            DialogueService.shared.applyDialogueFollowupsReady(msg, in: self)

        case .dialogueDismissed:
            // Per-NPC dismiss (npcID present) or legacy global flush (nil).
            let msg = try? envelope.decode(DialogueDismissedMessage.self)
            DialogueService.shared.dismissRemoteDialogue(forNPCID: msg?.npcID)

        case .dialogueFollowupChosen:
            guard let msg = try? envelope.decode(DialogueFollowupChosenMessage.self) else { return }
            // Show the partner's choice as a brief beat on whichever
            // bubble exists locally.
            DialogueService.shared.showRemoteFollowupChoice(
                npcID: msg.npcID, chosenText: msg.chosenText, tone: msg.tone, in: self
            )
            // Host runs turn-2 in response to a guest's pill-tap.
            if MultiplayerService.shared.isHost {
                DialogueService.shared.applyRemoteFollowupChosen(
                    npcID: msg.npcID, chosenText: msg.chosenText, toneRaw: msg.tone
                )
            }

        case .npcConversationLine:
            guard let msg = try? envelope.decode(NPCConversationLineMessage.self) else { return }
            guard msg.sceneType == DialogueService.sceneTypeKey(for: self) else { return }
            NPCConversationService.shared.handleRemoteLine(msg, in: self)

        case .npcConversationEnded:
            guard let msg = try? envelope.decode(NPCConversationEndedMessage.self) else { return }
            NPCConversationService.shared.handleRemoteEnd(msg)

        case .ritualStepCompleted:
            guard let msg = try? envelope.decode(RitualStepMessage.self) else { return }
            applyRemoteRitualStep(msg)

        case .ritualStateSync:
            guard let msg = try? envelope.decode(RitualStateSyncMessage.self) else { return }
            applyRemoteRitualState(msg)

        case .stateRequest:
            // In the lobby-driven flow the host owns the session's world.
            // Any guest reconciliation request gets the host's current save.
            guard MultiplayerService.shared.isHost else { return }
            guard let msg = try? envelope.decode(StateRequestMessage.self) else { return }
            Log.info(.network, "Host answering state request from \(msg.requestingScene)")
            sendHostHandshake()
            sendAuthoritativeWorldSync()

        case .worldSync:
            guard let msg = try? envelope.decode(WorldSyncMessage.self) else { return }
            applyWorldSync(msg)

        case .dailySummaryGenerated:
            guard let msg = try? envelope.decode(DailySummaryGeneratedMessage.self) else { return }
            SaveService.shared.applyDailySummaryEntry(msg.entry)
            Log.info(.network, "Received chronicle for day \(msg.entry.dayCount)")

        case .timeSync:
            guard MultiplayerService.shared.isGuest else { return }
            guard let msg = try? envelope.decode(TimeSyncMessage.self) else { return }
            applyTimeSync(msg)

        case .itemForaged:
            guard let msg = try? envelope.decode(ItemForagedMessage.self) else { return }
            // Just update the foraging manager — visual removal happens in
            // ForestScene / CaveScene when the player is actually there.
            ForagingManager.shared.collect(spawnID: msg.spawnID)

        case .storageDeposited:
            guard let msg = try? envelope.decode(StorageDepositedMessage.self) else { return }
            let ok = StorageRegistry.shared.store(ingredient: msg.ingredient, in: msg.containerName)
            if !ok {
                // Registry state has drifted between host and guest. Shouldn't
                // happen in practice — log so we notice if it does.
                Log.warn(.network, "Remote deposit rejected: \(msg.containerName) can't accept \(msg.ingredient). Possible desync.")
            }
            if let storage = storageContainers.first(where: { $0.storageType.rawValue == msg.containerName }) {
                storage.onInventoryChanged()
            }
            Log.info(.network, "Remote deposited \(msg.ingredient) into \(msg.containerName)")

        case .storageRetrieved:
            guard let msg = try? envelope.decode(StorageRetrievedMessage.self) else { return }
            let ok = StorageRegistry.shared.retrieveOne(ingredient: msg.ingredient, from: msg.containerName)
            if !ok {
                Log.warn(.network, "Remote retrieve rejected: \(msg.containerName) had no \(msg.ingredient). Possible desync.")
            }
            if let storage = storageContainers.first(where: { $0.storageType.rawValue == msg.containerName }) {
                storage.onInventoryChanged()
            }
            Log.info(.network, "Remote retrieved \(msg.ingredient) from \(msg.containerName)")

        case .objectPickedUp:
            guard let msg = try? envelope.decode(ObjectPickedUpMessage.self) else { return }
            applyRemoteObjectPickedUp(msg)

        case .objectDropped:
            guard let msg = try? envelope.decode(ObjectDroppedMessage.self) else { return }
            applyRemoteObjectDropped(msg)

        case .objectRotated:
            guard let msg = try? envelope.decode(ObjectRotatedMessage.self) else { return }
            applyRemoteObjectRotated(msg)

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
        Log.info(.network, "Applying world sync: day \(msg.dayCount), \(msg.npcMemories.count) NPC memories, \(msg.worldItems.count) world items")
        
        // Import into SwiftData (overwrites NPC memories + world state +
        // world item registry).
        SaveService.shared.importWorldSync(msg)
        
        // Update runtime state to match
        timeService.syncDayCount(msg.dayCount)
        
        if let phase = TimePhase.allCases.first(where: { $0.displayName == msg.timePhase }) {
            timeService.setDebugPhase(phase)
            lastTimePhase = phase
        }
        
        // Reconcile the live scene against the freshly-imported registry so
        // trash + drinks on tables reflect the other player's state without
        // waiting for a scene reload.
        reconcileSceneWithWorldItemRegistry()
        // Re-apply the movable-object registry on top of the live scene so
        // any rearrangement the partner made before we connected lands here.
        applyMovableObjectRegistryToScene()
        
        // Refresh any open/closed pantry/fridge so their label counts and
        // slot sprites match the freshly-imported StorageRegistry contents.
        for container in storageContainers {
            container.onInventoryChanged()
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

    // MARK: - Movable Object Sync (Remote)

    /// Find the editor-placed node by `editorName` (e.g. `table_3`,
    /// `furniture_arrow`). Sacred table is excluded.
    private func findMovableObject(named editorName: String) -> RotatableObject? {
        guard editorName != "sacred_table" else { return nil }
        for child in children {
            if let rot = child as? RotatableObject, rot.name == editorName {
                return rot
            }
        }
        return nil
    }

    /// Remote player picked up a table/furniture. Detach from the grid
    /// (free its old cell), bump z-position so it floats, and stop any
    /// in-flight movement. We do NOT visibly parent it to the
    /// RemoteCharacter — the partner's position deltas already convey
    /// where they are, and floating the object at its current spot until
    /// the matching `objectDropped` arrives is simpler and avoids
    /// per-frame parent reattachment.
    private func applyRemoteObjectPickedUp(_ msg: ObjectPickedUpMessage) {
        guard let node = findMovableObject(named: msg.editorName) else {
            Log.debug(.network, "Remote pickup ignored — no node for \(msg.editorName)")
            return
        }
        // Mirror local registry update so a worldSync at this moment
        // would carry the right state.
        MovableObjectRegistry.shared.recordPickup(
            editorName: msg.editorName,
            byHost: msg.byHost
        )

        // Free its old cell so the local player can walk through where
        // the table used to be.
        let oldCell = gridService.worldToGrid(node.position)
        gridService.freeCell(oldCell)
        node.zPosition = ZLayers.carriedItems
        // Cancel any in-flight tween (e.g. mid-drop animation).
        node.removeAllActions()

        Log.info(.network, "Remote picked up \(msg.editorName)")
    }

    /// Remote player dropped a table/furniture at a specific position +
    /// rotation. Tween the local copy to match, then occupy the new
    /// grid cell.
    private func applyRemoteObjectDropped(_ msg: ObjectDroppedMessage) {
        guard let node = findMovableObject(named: msg.editorName) else {
            Log.debug(.network, "Remote drop ignored — no node for \(msg.editorName)")
            return
        }
        // Mirror local registry.
        MovableObjectRegistry.shared.recordPlacement(
            editorName: msg.editorName,
            position: msg.position.cgPoint,
            rotationDegrees: msg.rotationDegrees
        )

        let target = msg.position.cgPoint
        let distance = hypot(target.x - node.position.x, target.y - node.position.y)
        let duration = max(0.15, min(0.4, TimeInterval(distance / 400)))

        node.removeAllActions()
        let move = SKAction.move(to: target, duration: duration)
        move.timingMode = .easeOut
        node.run(move) { [weak self] in
            guard let self = self else { return }
            // Apply rotation snap.
            if let state = RotationState(rawValue: msg.rotationDegrees) {
                node.setRotationState(state)
            }
            // Restore floor z + occupy the new cell.
            node.zPosition = ZLayers.tables   // tables layer; furniture also OK on this layer for our purposes
            let newCell = self.gridService.worldToGrid(target)
            let go = GameObject(
                skNode: node,
                gridPosition: newCell,
                objectType: node.objectType,
                gridService: self.gridService
            )
            self.gridService.occupyCell(newCell, with: go)
        }
        Log.info(.network, "Remote dropped \(msg.editorName) at \(target)")
    }

    /// Remote player rotated the carried object. Animate the local copy
    /// to match.
    private func applyRemoteObjectRotated(_ msg: ObjectRotatedMessage) {
        guard let node = findMovableObject(named: msg.editorName) else { return }
        MovableObjectRegistry.shared.recordRotation(
            editorName: msg.editorName,
            rotationDegrees: msg.rotationDegrees
        )
        if let state = RotationState(rawValue: msg.rotationDegrees) {
            node.setRotationState(state)
        }
    }
}
