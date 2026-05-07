//
//  HouseScene+Multiplayer.swift
//  BobaAtDawn
//
//  Multiplayer support for HouseScene — remote character visibility,
//  scene-type filtering, and incoming message handling while inside a
//  forest house. Mirrors BigOakTreeScene+Multiplayer.swift.
//

import SpriteKit

extension HouseScene: MultiplayerServiceDelegate {

    func setupHouseMultiplayer() {
        MultiplayerService.shared.delegate = self
        if MultiplayerService.shared.isConnected {
            addLocalPlayerLabelHouse()
            spawnRemoteCharacterInHouse()
        }
    }

    private func addLocalPlayerLabelHouse() {
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

    private func spawnRemoteCharacterInHouse() {
        guard remoteCharacter == nil else { return }
        let remote = RemoteCharacter()
        remote.position = character.position
        addChild(remote)
        remoteCharacter = remote
        Log.info(.network, "Remote character spawned in HouseScene R\(currentForestRoom)H\(currentHouseNumber)")
    }

    // MARK: - MultiplayerServiceDelegate

    func multiplayerDidConnect(isHost: Bool) {
        addLocalPlayerLabelHouse()
        spawnRemoteCharacterInHouse()
    }

    func multiplayerDidDisconnect() {
        remoteCharacter?.removeFromParent()
        remoteCharacter = nil
    }

    func multiplayerDidFail(error: String) {
        Log.error(.network, "HouseScene: \(error)")
    }

    func multiplayerDidReceive(_ envelope: NetworkEnvelope) {
        switch envelope.type {

        case .playerPosition:
            guard let msg = try? envelope.decode(PlayerPositionMessage.self) else { return }
            // Only show the remote character if they're in the SAME
            // house (same forest room + same house number).
            let mySceneType = "house_\(currentForestRoom)_\(currentHouseNumber)"
            if msg.sceneType == mySceneType {
                if remoteCharacter == nil { spawnRemoteCharacterInHouse() }
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

        default:
            break
        }
    }
}
