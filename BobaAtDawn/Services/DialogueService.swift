//
//  DialogueService.swift
//  BobaAtDawn
//
//  Service for managing NPC dialogue and character interactions.
//  Works with any DialoguePresenter (BaseNPC, ShopNPC, ForestNPCEntity).
//

import SpriteKit
import Foundation

// MARK: - Dialogue Service
class DialogueService {
    static let shared = DialogueService()

    private var npcDatabase: NPCDatabase?
    private var activeBubble: DialogueBubble?
    
    /// Flag to prevent re-broadcasting when a dialogue action was triggered
    /// by a network message. Set true before local action, reset after.
    private var suppressNetworkBroadcast: Bool = false

    private init() {
        loadNPCData()
    }

    // MARK: - Data Loading
    private func loadNPCData() {
        guard let url = Bundle.main.url(forResource: "npc_dialogue", withExtension: "json") else {
            Log.error(.dialogue, "Could not find npc_dialogue.json")
            return
        }
        do {
            let data = try Data(contentsOf: url)
            npcDatabase = try JSONDecoder().decode(NPCDatabase.self, from: data)
            Log.info(.dialogue, "Loaded \(npcDatabase?.npcs.count ?? 0) NPCs from dialogue data")
        } catch {
            Log.error(.dialogue, "Failed to load NPC dialogue data: \(error)")
        }
    }

    // MARK: - NPC Access
    func getAllNPCs() -> [NPCData] {
        npcDatabase?.npcs ?? []
    }

    func getNPC(byId id: String) -> NPCData? {
        npcDatabase?.npcs.first { $0.id == id }
    }

    func getRandomNPCs(count: Int) -> [NPCData] {
        Array(getAllNPCs().shuffled().prefix(count))
    }

    // MARK: - Show Dialogue (unified — works with any DialoguePresenter)
    func showDialogue(for presenter: DialoguePresenter, in scene: SKScene, timeContext: TimeContext) {
        dismissDialogue()

        guard let charId = presenter.dialogueCharacterId,
              let npcData = getNPC(byId: charId) else {
            Log.error(.dialogue, "No dialogue data for character: \(presenter.dialogueCharacterId ?? "nil")")
            return
        }

        presenter.freeze()

        let text = npcData.getRandomDialogue(isNight: timeContext.isNight)

        let bubble = DialogueBubble(
            text: text,
            speakerName: npcData.name,
            position: presenter.position,
            npcID: charId
        )

        activeBubble = bubble
        scene.addChild(bubble)
        Log.info(.dialogue, "\(npcData.name): \(text)")
        
        // Broadcast to other player so they see the bubble too
        if !suppressNetworkBroadcast && MultiplayerService.shared.isConnected {
            MultiplayerService.shared.send(type: .dialogueShown, payload: DialogueShownMessage(
                npcID: charId,
                speakerName: npcData.name,
                text: text,
                position: CodablePoint(presenter.position)
            ))
        }
    }

    // MARK: - Custom Dialogue (ritual farewells)
    func showCustomDialogue(for presenter: DialoguePresenter, in scene: SKScene, customLines: [String]) {
        dismissDialogue()

        guard let charId = presenter.dialogueCharacterId,
              let npcData = getNPC(byId: charId) else {
            Log.error(.dialogue, "No dialogue data for NPC: \(presenter.dialogueCharacterId ?? "nil")")
            return
        }

        presenter.freeze()
        let text = customLines.randomElement() ?? "Farewell..."

        let bubble = DialogueBubble(
            text: text,
            speakerName: npcData.name,
            position: presenter.position,
            npcID: charId,
            showResponseButtons: false
        )

        activeBubble = bubble
        scene.addChild(bubble)
        Log.info(.dialogue, "\(npcData.name) (liberation): \(text)")
    }

    func dismissDialogue() {
        let currentScene = activeBubble?.scene
        activeBubble?.removeFromParent()
        activeBubble = nil

        // Unfreeze all NPCs in the scene (both types share BaseNPC)
        if let scene = currentScene {
            unfreezeAllNPCs(in: scene)
        }
        
        // Broadcast dismissal to other player
        if !suppressNetworkBroadcast && MultiplayerService.shared.isConnected {
            MultiplayerService.shared.send(type: .dialogueDismissed, payload: DialogueDismissedMessage())
        }
    }

    func isDialogueActive() -> Bool {
        activeBubble != nil
    }
    
    // MARK: - Network Dialogue (read-only bubble from other player)
    
    /// Show a read-only dialogue bubble triggered by the remote player.
    /// Uses suppressNetworkBroadcast to prevent a re-broadcast loop.
    func showRemoteDialogue(npcID: String, speakerName: String, text: String,
                            at position: CGPoint, in scene: SKScene) {
        suppressNetworkBroadcast = true
        dismissDialogue()
        
        let bubble = DialogueBubble(
            text: text,
            speakerName: speakerName,
            position: position,
            npcID: npcID,
            showResponseButtons: false
        )
        
        activeBubble = bubble
        scene.addChild(bubble)
        
        // Freeze the matching NPC on this side too
        scene.enumerateChildNodes(withName: "npc_*") { node, _ in
            if let npc = node as? BaseNPC,
               npc.dialogueCharacterId == npcID {
                npc.freeze()
            }
        }
        
        suppressNetworkBroadcast = false
        Log.info(.dialogue, "[Remote] \(speakerName): \(text)")
    }
    
    /// Dismiss dialogue triggered by the remote player's dismissal.
    func dismissRemoteDialogue() {
        suppressNetworkBroadcast = true
        dismissDialogue()
        suppressNetworkBroadcast = false
    }

    // MARK: - NPC Management
    private func unfreezeAllNPCs(in scene: SKScene) {
        scene.enumerateChildNodes(withName: "npc_*") { node, _ in
            if let npc = node as? BaseNPC {
                npc.unfreeze()
            }
        }
    }
}

// MARK: - Speech Bubble Component
class DialogueBubble: SKNode {
    private let bubbleBackground: SKShapeNode
    private let textLabel: SKLabelNode
    private let nameLabel: SKLabelNode
    private let responseButtons: SKNode
    private let npcID: String

    init(text: String, speakerName: String, position: CGPoint, npcID: String, showResponseButtons: Bool = true) {
        self.npcID = npcID

        let bubbleHeight: CGFloat = showResponseButtons ? 160 : 120
        let bubbleSize = CGSize(width: 320, height: bubbleHeight)
        bubbleBackground = SKShapeNode(rectOf: bubbleSize, cornerRadius: 15)
        bubbleBackground.fillColor = SKColor.white.withAlphaComponent(0.95)
        bubbleBackground.strokeColor = SKColor.black.withAlphaComponent(0.7)
        bubbleBackground.lineWidth = 2

        nameLabel = SKLabelNode(text: speakerName)
        nameLabel.fontName = "Arial-Bold"
        nameLabel.fontSize = 14
        nameLabel.fontColor = SKColor.darkGray
        nameLabel.horizontalAlignmentMode = .center
        nameLabel.verticalAlignmentMode = .center

        textLabel = SKLabelNode()
        textLabel.text = text
        textLabel.fontName = "Arial"
        textLabel.fontSize = 12
        textLabel.fontColor = SKColor.black
        textLabel.horizontalAlignmentMode = .center
        textLabel.verticalAlignmentMode = .center
        textLabel.numberOfLines = showResponseButtons ? 3 : 4
        textLabel.preferredMaxLayoutWidth = bubbleSize.width - 20

        responseButtons = SKNode()

        super.init()

        self.position = CGPoint(x: position.x, y: position.y + 100)
        self.zPosition = ZLayers.dialogueUI

        addChild(bubbleBackground)

        let nameY: CGFloat = showResponseButtons ? 50 : 35
        let textY: CGFloat = showResponseButtons ? 15 : 0
        nameLabel.position = CGPoint(x: 0, y: nameY)
        textLabel.position = CGPoint(x: 0, y: textY)
        addChild(nameLabel)
        addChild(textLabel)

        if showResponseButtons {
            setupResponseButtons()
            addChild(responseButtons)
        }

        bubbleBackground.name = "dialogue_bubble"
        isUserInteractionEnabled = true

        alpha = 0; setScale(0.5)
        run(SKAction.group([
            SKAction.fadeIn(withDuration: 0.3),
            SKAction.scale(to: 1.0, duration: 0.3)
        ]))
    }

    private func setupResponseButtons() {
        let spacing: CGFloat = 90
        let y: CGFloat = -45
        responseButtons.addChild(createResponseButton(emoji: "❌", responseType: .dismiss,
                                                       position: CGPoint(x: -spacing, y: y)))
        responseButtons.addChild(createResponseButton(emoji: "😊", responseType: .nice,
                                                       position: CGPoint(x: 0, y: y)))
        responseButtons.addChild(createResponseButton(emoji: "😠", responseType: .mean,
                                                       position: CGPoint(x: spacing, y: y)))
    }

    private func createResponseButton(emoji: String, responseType: NPCResponseType, position: CGPoint) -> SKNode {
        let container = SKNode()
        container.position = position

        let bg = SKShapeNode(circleOfRadius: 20)
        bg.fillColor = SKColor.lightGray.withAlphaComponent(0.3)
        bg.strokeColor = SKColor.gray
        bg.lineWidth = 1

        let label = SKLabelNode(text: emoji)
        label.fontSize = 24
        label.fontName = "Arial"
        label.horizontalAlignmentMode = .center
        label.verticalAlignmentMode = .center

        container.addChild(bg)
        container.addChild(label)
        container.name = "response_\(responseType.rawValue)"
        return container
    }

    required init?(coder: NSCoder) { fatalError() }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let location = touch.location(in: self)
        let touched = atPoint(location)

        if let nodeName = touched.parent?.name, nodeName.hasPrefix("response_") {
            let raw = String(nodeName.dropFirst("response_".count))
            if let type = NPCResponseType(rawValue: raw) {
                handleResponse(type)
                return
            }
        }

        DialogueService.shared.dismissDialogue()
    }

    private func handleResponse(_ type: NPCResponseType) {
        SaveService.shared.recordNPCInteraction(npcID, responseType: type)
        
        // Broadcast NPC interaction to other player
        MultiplayerService.shared.send(type: .npcInteraction, payload: NPCInteractionMessage(
            npcID: npcID, responseType: type.rawValue
        ))

        if let btn = responseButtons.childNode(withName: "response_\(type.rawValue)") {
            btn.run(SKAction.sequence([
                SKAction.scale(to: 0.8, duration: 0.1),
                SKAction.scale(to: 1.0, duration: 0.1)
            ]))
        }

        run(SKAction.sequence([
            SKAction.wait(forDuration: 0.3),
            SKAction.run { DialogueService.shared.dismissDialogue() }
        ]))

        Log.debug(.dialogue, "Player responded '\(type.rawValue)' to \(npcID)")
    }
}
