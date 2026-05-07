//
//  CaveScene+Multiplayer.swift
//  CaveScene+Multiplayer.swift
//  BobaAtDawn
//
//  Multiplayer support for CaveScene — remote character visibility,
//  position sync, mushroom pickup sync, and incoming message handling
//  while inside the cave.
//
//  Mirrors BigOakTreeScene+Multiplayer.swift.
//

import SpriteKit

extension CaveScene: MultiplayerServiceDelegate {

    func setupCaveMultiplayer() {
        MultiplayerService.shared.delegate = self
        if MultiplayerService.shared.isConnected {
            addLocalPlayerLabelCave()
            spawnRemoteCharacterInCave()
        }
    }

    private func addLocalPlayerLabelCave() {
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

    private func spawnRemoteCharacterInCave() {
        guard remoteCharacter == nil else { return }
        let remote = RemoteCharacter()
        remote.position = character.position
        addChild(remote)
        remoteCharacter = remote
        Log.info(.network, "Remote character spawned in CaveScene room \(currentCaveRoom.debugName)")
    }

    // MARK: - MultiplayerServiceDelegate

    func multiplayerDidConnect(isHost: Bool) {
        addLocalPlayerLabelCave()
        spawnRemoteCharacterInCave()
    }

    func multiplayerDidDisconnect() {
        remoteCharacter?.removeFromParent()
        remoteCharacter = nil
    }

    func multiplayerDidFail(error: String) {
        Log.error(.network, "CaveScene: \(error)")
    }

    func multiplayerDidReceive(_ envelope: NetworkEnvelope) {
        switch envelope.type {

        case .playerPosition:
            guard let msg = try? envelope.decode(PlayerPositionMessage.self) else { return }
            // Show the remote character only if they're in the same cave room
            if msg.sceneType == "cave_\(currentCaveRoom.rawValue)" {
                if remoteCharacter == nil { spawnRemoteCharacterInCave() }
                remoteCharacter?.isHidden = false
                remoteCharacter?.applyRemoteUpdate(msg)
            } else {
                remoteCharacter?.isHidden = true
            }

        case .dialogueShown:
            guard let msg = try? envelope.decode(DialogueShownMessage.self) else { return }
            DialogueService.shared.showRemoteDialogue(
                npcID: msg.npcID,
                speakerName: msg.speakerName,
                text: msg.text,
                mood: msg.mood,
                at: msg.position.cgPoint,
                in: self
            )

        case .dialogueDismissed:
            DialogueService.shared.dismissRemoteDialogue()

        case .itemForaged:
            guard let msg = try? envelope.decode(ItemForagedMessage.self) else { return }
            ForagingManager.shared.collect(spawnID: msg.spawnID)
            // If we're viewing the same cave room, remove the visual node
            guard let location = SpawnLocation(stringKey: msg.locationKey) else { return }
            if case let .caveRoom(room) = location, room == currentCaveRoom.rawValue {
                let forageNodes = children.compactMap { $0 as? ForageNode }
                if let match = forageNodes.first(where: { $0.spawnID == msg.spawnID }) {
                    match.pickUp { Log.debug(.network, "Remote foraged item collected") }
                }
            }

        case .gnomeStateSync:
            guard let msg = try? envelope.decode(GnomeStateSyncMessage.self) else { return }
            GnomeManager.shared.applyRemoteState(msg)

        case .gnomeRosterRefresh:
            guard let msg = try? envelope.decode(GnomeRosterRefreshMessage.self) else { return }
            GnomeManager.shared.applyRemoteRosterRefresh(msg)

        case .treasuryUpdate:
            guard let msg = try? envelope.decode(TreasuryUpdateMessage.self) else { return }
            GnomeManager.shared.applyRemoteTreasury(newCount: msg.newCount, didReset: msg.didReset)

        case .mineMachineFed:
            guard let msg = try? envelope.decode(MineMachineFedMessage.self) else { return }
            // Apply same flash on the remote — verdict is deterministic.
            flashMineMachineIfPresent(green: msg.verdict)
            if !msg.verdict { bumpWasteBinIfPresent() }
            // Mark the rock collected if it isn't already.
            ForagingManager.shared.collect(spawnID: msg.rockID)

        case .gnomeConversationLine:
            guard let msg = try? envelope.decode(GnomeConversationLineMessage.self) else { return }
            GnomeConversationService.shared.handleRemoteLine(msg, in: self)

        case .gnomeConversationEnded:
            guard let msg = try? envelope.decode(GnomeConversationEndedMessage.self) else { return }
            GnomeConversationService.shared.handleRemoteEnd(msg)

        case .dailySummaryGenerated:
            guard let msg = try? envelope.decode(DailySummaryGeneratedMessage.self) else { return }
            SaveService.shared.applyDailySummaryEntry(msg.entry)
            Log.info(.network, "Received chronicle for day \(msg.entry.dayCount) (cave)")

        default:
            break
        }
    }
}
