//
//  BigOakTreeScene+Multiplayer.swift
//  BobaAtDawn
//
//  Multiplayer support for BigOakTreeScene — remote character visibility,
//  position sync, gnome state sync, treasury sync, and incoming message
//  handling while inside the oak tree.
//

import SpriteKit

extension BigOakTreeScene: MultiplayerServiceDelegate {

    func setupOakTreeMultiplayer() {
        MultiplayerService.shared.delegate = self
        if MultiplayerService.shared.isConnected {
            addLocalPlayerLabelOak()
            spawnRemoteCharacterInOak()
        }
    }

    private func addLocalPlayerLabelOak() {
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

    private func spawnRemoteCharacterInOak() {
        guard remoteCharacter == nil else { return }
        let remote = RemoteCharacter()
        remote.position = character.position
        addChild(remote)
        remoteCharacter = remote
        Log.info(.network, "Remote character spawned in BigOakTreeScene room \(currentOakRoom.debugName)")
    }

    // MARK: - MultiplayerServiceDelegate

    func multiplayerDidConnect(isHost: Bool) {
        addLocalPlayerLabelOak()
        spawnRemoteCharacterInOak()
    }

    func multiplayerDidDisconnect() {
        remoteCharacter?.removeFromParent()
        remoteCharacter = nil
    }

    func multiplayerDidFail(error: String) {
        Log.error(.network, "BigOakTreeScene: \(error)")
    }

    func multiplayerDidReceive(_ envelope: NetworkEnvelope) {
        switch envelope.type {

        case .playerPosition:
            guard let msg = try? envelope.decode(PlayerPositionMessage.self) else { return }
            // Show the remote character only if they're in the same oak room
            if msg.sceneType == "oak_\(currentOakRoom.rawValue)" {
                if remoteCharacter == nil { spawnRemoteCharacterInOak() }
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

        case .gnomeStateSync:
            guard let msg = try? envelope.decode(GnomeStateSyncMessage.self) else { return }
            GnomeManager.shared.applyRemoteState(msg)

        case .gnomeRosterRefresh:
            guard let msg = try? envelope.decode(GnomeRosterRefreshMessage.self) else { return }
            GnomeManager.shared.applyRemoteRosterRefresh(msg)

        case .treasuryUpdate:
            guard let msg = try? envelope.decode(TreasuryUpdateMessage.self) else { return }
            GnomeManager.shared.applyRemoteTreasury(newCount: msg.newCount, didReset: msg.didReset)
            updateTreasuryPileIfPresent(count: msg.newCount, didReset: msg.didReset)

        case .gnomeConversationLine:
            guard let msg = try? envelope.decode(GnomeConversationLineMessage.self) else { return }
            // Only render if the gnome is actually visible in this scene.
            GnomeConversationService.shared.handleRemoteLine(msg, in: self)

        case .gnomeConversationEnded:
            guard let msg = try? envelope.decode(GnomeConversationEndedMessage.self) else { return }
            GnomeConversationService.shared.handleRemoteEnd(msg)

        case .dailySummaryGenerated:
            guard let msg = try? envelope.decode(DailySummaryGeneratedMessage.self) else { return }
            SaveService.shared.applyDailySummaryEntry(msg.entry)
            Log.info(.network, "Received chronicle for day \(msg.entry.dayCount) (oak)")

        default:
            break
        }
    }
}
