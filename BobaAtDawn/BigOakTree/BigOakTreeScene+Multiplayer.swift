//
//  BigOakTreeScene+Multiplayer.swift
//  BobaAtDawn
//
//  Multiplayer support for BigOakTreeScene — remote character visibility,
//  position sync, and incoming message handling while inside the oak tree.
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
                at: msg.position.cgPoint,
                in: self
            )

        case .dialogueDismissed:
            DialogueService.shared.dismissRemoteDialogue()

        default:
            break
        }
    }
}
