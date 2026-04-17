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
                    nearest.pickUp { Log.debug(.network, "Remote forest trash cleaned") }
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

        default:
            break
        }
    }
    
    // MARK: - Forest NPC Sync (Guest Side)
    
    /// Apply host-broadcast forest NPC positions. When the guest is in the
    /// same room as the host, each NPC stops local wandering and lerps to
    /// the host’s position. When in a different room, NPCs resume their
    /// own wandering since nobody’s comparing.
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
