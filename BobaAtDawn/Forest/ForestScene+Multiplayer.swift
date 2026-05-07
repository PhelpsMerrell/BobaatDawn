//
//  ForestScene+Multiplayer.swift
//  BobaAtDawn
//
//  Multiplayer support for ForestScene — remote character, position sync,
//  and incoming message handling while in the forest.
//

import SpriteKit

extension ForestScene: MultiplayerServiceDelegate {

    func setupForestMultiplayer() {
        MultiplayerService.shared.delegate = self
        if MultiplayerService.shared.isConnected {
            addLocalPlayerLabelForest()
            spawnRemoteCharacterInForest()
        }
    }

    private func addLocalPlayerLabelForest() {
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

    private func spawnRemoteCharacterInForest() {
        guard remoteCharacter == nil else { return }
        let remote = RemoteCharacter()
        remote.position = character.position
        addChild(remote)
        remoteCharacter = remote
        Log.info(.network, "Remote character spawned in ForestScene room \(currentRoom)")
    }

    func multiplayerDidConnect(isHost: Bool) {
        addLocalPlayerLabelForest()
        spawnRemoteCharacterInForest()
        if MultiplayerService.shared.isGuest {
            MultiplayerService.shared.send(
                type: .stateRequest,
                payload: StateRequestMessage(
                    requestingScene: "forest",
                    saveTimestamp: SaveService.shared.getSaveTimestamp()
                )
            )
        }
    }

    func multiplayerDidDisconnect() {
        remoteCharacter?.removeFromParent()
        remoteCharacter = nil
        
        // Auto-save shared world on disconnect
        let ts = serviceContainer.resolve(TimeService.self)
        SaveService.shared.autoSave(timeService: ts)
    }

    func multiplayerDidFail(error: String) {
        Log.error(.network, "ForestScene: \(error)")
    }

    func multiplayerDidReceive(_ envelope: NetworkEnvelope) {
        // Gnome-related envelopes are handled by ForestScene+Gnomes.
        // Returns true if it consumed the message, in which case we
        // short-circuit the rest of the switch.
        if handleForestGnomeNetworkMessage(envelope) { return }

        switch envelope.type {

        case .playerPosition:
            guard let msg = try? envelope.decode(PlayerPositionMessage.self) else { return }
            if msg.sceneType == "forest_\(currentRoom)" {
                if remoteCharacter == nil { spawnRemoteCharacterInForest() }
                remoteCharacter?.isHidden = false
                remoteCharacter?.applyRemoteUpdate(msg)
            } else {
                remoteCharacter?.isHidden = true
            }

        case .trashCleaned:
            guard let msg = try? envelope.decode(TrashCleanedMessage.self) else { return }
            if msg.location == "forest_room_\(currentRoom)" {
                let trashNodes = children.compactMap { $0 as? Trash }
                if let nearest = trashNodes.min(by: {
                    hypot($0.position.x - msg.position.cgPoint.x, $0.position.y - msg.position.cgPoint.y)
                    <
                    hypot($1.position.x - msg.position.cgPoint.x, $1.position.y - msg.position.cgPoint.y)
                }) {
                    if let id = nearest.userData?["worldItemID"] as? String {
                        WorldItemRegistry.shared.remove(id: id)
                    }
                    nearest.pickUp { Log.debug(.network, "Remote forest trash cleaned") }
                    // Chronicle hook
                    DailyChronicleLedger.shared.recordTrashCleaned(
                        location: "forest room \(currentRoom)"
                    )
                }
            }

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

        case .npcLiberated:
            guard let msg = try? envelope.decode(NPCLiberatedMessage.self) else { return }
            SaveService.shared.markNPCAsLiberated(msg.npcID)

        case .snailSync:
            guard MultiplayerService.shared.isGuest else { return }
            guard let msg = try? envelope.decode(SnailSyncMessage.self) else { return }
            let world = SnailWorldState.shared
            world.currentRoom = msg.room
            world.roomPosition = msg.position.cgPoint
            if msg.isActive && !world.isActive {
                world.isActive = true
            } else if !msg.isActive && world.isActive {
                world.isActive = false
            }

        case .forestNpcSync:
            guard MultiplayerService.shared.isGuest else { return }
            guard let msg = try? envelope.decode(ForestNpcSyncMessage.self) else { return }
            applyForestNpcSync(msg)

        case .dialogueShown:
            // LEGACY non-streaming path — still used for liberation
            // farewells. Streaming LLM dialogue uses
            // dialogueOpened/dialogueLineDelta/etc instead.
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
            guard MultiplayerService.shared.isHost else { return }
            guard let msg = try? envelope.decode(DialogueOpenRequestMessage.self) else { return }
            DialogueService.shared.hostHandleOpenRequest(msg, in: self)

        case .dialogueOpened:
            guard let msg = try? envelope.decode(DialogueOpenedMessage.self) else { return }
            DialogueService.shared.applyDialogueOpened(msg, in: self)

        case .dialogueLineDelta:
            guard let msg = try? envelope.decode(DialogueLineDeltaMessage.self) else { return }
            DialogueService.shared.applyDialogueLineDelta(msg)

        case .dialogueFollowupsReady:
            guard let msg = try? envelope.decode(DialogueFollowupsReadyMessage.self) else { return }
            DialogueService.shared.applyDialogueFollowupsReady(msg, in: self)

        case .dialogueDismissed:
            let msg = try? envelope.decode(DialogueDismissedMessage.self)
            DialogueService.shared.dismissRemoteDialogue(forNPCID: msg?.npcID)

        case .dialogueFollowupChosen:
            guard let msg = try? envelope.decode(DialogueFollowupChosenMessage.self) else { return }
            DialogueService.shared.showRemoteFollowupChoice(
                npcID: msg.npcID, chosenText: msg.chosenText, tone: msg.tone, in: self
            )
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

        case .itemForaged:
            guard let msg = try? envelope.decode(ItemForagedMessage.self) else { return }
            // Mark the spawn collected locally
            ForagingManager.shared.collect(spawnID: msg.spawnID)
            // If we're viewing the same forest room, remove the visual node
            guard let location = SpawnLocation(stringKey: msg.locationKey) else { return }
            if case let .forestRoom(room) = location, room == currentRoom {
                let forageNodes = children.compactMap { $0 as? ForageNode }
                if let match = forageNodes.first(where: { $0.spawnID == msg.spawnID }) {
                    match.pickUp { Log.debug(.network, "Remote foraged item collected") }
                }
            }

        case .stateRequest:
            // The host owns the shared world for the invite-driven flow,
            // so any guest request gets the host's current save.
            guard MultiplayerService.shared.isHost else { return }
            guard let msg = try? envelope.decode(StateRequestMessage.self) else { return }
            let ts = serviceContainer.resolve(TimeService.self)
            let worldSync = SaveService.shared.exportWorldSync(timeService: ts)
            MultiplayerService.shared.send(type: .worldSync, payload: worldSync)
            Log.info(.network, "Forest: host answered state request from \(msg.requestingScene)")

        case .worldSync:
            guard let msg = try? envelope.decode(WorldSyncMessage.self) else { return }
            applyForestWorldSync(msg)

        case .dailySummaryGenerated:
            guard let msg = try? envelope.decode(DailySummaryGeneratedMessage.self) else { return }
            SaveService.shared.applyDailySummaryEntry(msg.entry)
            Log.info(.network, "Received chronicle for day \(msg.entry.dayCount) (forest)")

        default:
            break
        }
    }
    
    // MARK: - Shared Persistent World (Forest side)
    
    /// Apply a full world sync received while the player is in the forest.
    /// Mirrors GameScene's applyWorldSync but only reconciles the visible
    /// scene for the current forest room's trash. Trash for other rooms
    /// sits in the registry until the player walks into that room, at
    /// which point `NPCResidentManager.spawnPendingTrash` picks it up.
    private func applyForestWorldSync(_ msg: WorldSyncMessage) {
        Log.info(.network, "Forest: applying world sync: day \(msg.dayCount), \(msg.npcMemories.count) NPC memories, \(msg.worldItems.count) world items")
        
        // Import into SwiftData (overwrites NPC memories + world state +
        // world item registry + gnome state + treasury).
        SaveService.shared.importWorldSync(msg)
        
        // Sync time / day count so ritual day logic stays consistent.
        let ts = serviceContainer.resolve(TimeService.self)
        if msg.dayCount > 0 {
            ts.syncDayCount(msg.dayCount)
        }
        if let phase = TimePhase.allCases.first(where: { $0.displayName == msg.timePhase }) {
            ts.setDebugPhase(phase)
        }
        
        // Reconcile only the current room's trash — other rooms aren't
        // rendered right now, so their registry entries will be picked up
        // on room entry.
        reconcileForestTrashWithRegistry(room: currentRoom)
        
        // Refresh any gnome visuals that should now be in this forest
        // room (importWorldSync may have shifted their logical location).
        refreshForestGnomeSpawns()
    }
    
    /// Sync visible trash nodes for `room` against the registry. Adds
    /// missing trash, removes orphaned trash. Nodes without a stamped
    /// `worldItemID` are treated as untracked and left alone.
    private func reconcileForestTrashWithRegistry(room: Int) {
        var existingByID: [String: Trash] = [:]
        var untrackedNodes: [Trash] = []
        for trash in children.compactMap({ $0 as? Trash }) {
            if let id = trash.userData?["worldItemID"] as? String {
                existingByID[id] = trash
            } else {
                untrackedNodes.append(trash)
            }
        }
        
        let registryItems = WorldItemRegistry.shared.items(of: .trash, at: .forestRoom(room))
        let registryIDs = Set(registryItems.map { $0.id })
        
        var spawned = 0
        for item in registryItems where existingByID[item.id] == nil {
            let trash = Trash(at: item.position.cgPoint, location: .forest(room: room))
            trash.userData = NSMutableDictionary()
            trash.userData?["worldItemID"] = item.id
            addChild(trash)
            spawned += 1
        }
        
        var removed = 0
        for (id, node) in existingByID where !registryIDs.contains(id) {
            node.removeFromParent()
            removed += 1
        }
        
        if spawned > 0 || removed > 0 || !untrackedNodes.isEmpty {
            Log.info(.network, "Forest: reconciled room \(room) trash: +\(spawned) / -\(removed) (\(untrackedNodes.count) untracked left alone)")
        }
    }
    
    // MARK: - Forest NPC Sync (Guest Side)
    
    /// Apply host-broadcast forest NPC positions. When the guest is in the
    /// same room as the host, each NPC stops local wandering and lerps to
    /// the host's position. When in a different room, NPCs resume their
    /// own wandering since nobody's comparing.
    private func applyForestNpcSync(_ msg: ForestNpcSyncMessage) {
        let forestNPCs = children.compactMap { $0 as? ForestNPCEntity }
        
        if msg.room == currentRoom {
            // Same room — take host authority
            for entry in msg.entries {
                if let local = forestNPCs.first(where: { $0.npcData.id == entry.npcID }) {
                    local.setNetworkControlled(true)
                    local.applyNetworkPosition(entry.position.cgPoint)
                }
            }
        } else {
            // Different room — release network control, let local wander resume
            for npc in forestNPCs where npc.isNetworkControlled {
                npc.setNetworkControlled(false)
            }
        }
    }
}
