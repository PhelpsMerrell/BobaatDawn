//
//  DialogueService.swift
//  BobaAtDawn
//
//  Service for managing NPC dialogue and character interactions
//

import SpriteKit
import Foundation

// MARK: - NPC Response Types
enum NPCResponseType: String {
    case dismiss = "dismiss"  // No satisfaction change
    case nice = "nice"        // +1 satisfaction
    case mean = "mean"        // -1 satisfaction
}

// MARK: - Dialogue Service
class DialogueService {
    static let shared = DialogueService()
    
    private var npcDatabase: NPCDatabase?
    private var activeBubble: DialogueBubble?
    
    private init() {
        loadNPCData()
    }
    
    // MARK: - Data Loading
    private func loadNPCData() {
        guard let url = Bundle.main.url(forResource: "npc_dialogue", withExtension: "json") else {
            print("❌ ERROR: Could not find npc_dialogue.json")
            return
        }
        
        do {
            let data = try Data(contentsOf: url)
            npcDatabase = try JSONDecoder().decode(NPCDatabase.self, from: data)
            print("✅ Loaded \\(npcDatabase?.npcs.count ?? 0) NPCs from dialogue data")
        } catch {
            print("❌ ERROR: Failed to load NPC dialogue data: \\(error)")
        }
    }
    
    // MARK: - NPC Access
    func getAllNPCs() -> [NPCData] {
        return npcDatabase?.npcs ?? []
    }
    
    func getNPC(byId id: String) -> NPCData? {
        return npcDatabase?.npcs.first { $0.id == id }
    }
    
    func getRandomNPCs(count: Int) -> [NPCData] {
        let allNPCs = getAllNPCs()
        guard allNPCs.count > 0 else { return [] }
        
        return Array(allNPCs.shuffled().prefix(count))
    }
    
    // MARK: - Dialogue Interaction for ForestNPC
    func showDialogue(for npc: ForestNPC, in scene: SKScene, timeContext: TimeContext) {
        // Dismiss any existing bubble first
        dismissDialogue()
        
        // Get NPC data
        guard let npcData = getNPC(byId: npc.npcId) else {
            print("❌ ERROR: No dialogue data found for NPC: \\(npc.npcId)")
            return
        }
        
        // Freeze the NPC
        npc.freeze()
        
        // Get random dialogue for current time
        let dialogueText = npcData.getRandomDialogue(isNight: timeContext.isNight)
        
        // Create and show speech bubble
        let bubble = DialogueBubble(
            text: dialogueText,
            speakerName: npcData.name,
            position: npc.position,
            npcID: npc.npcId
        )
        
        activeBubble = bubble
        scene.addChild(bubble)
        
        print("💬 \\(npcData.name): \\(dialogueText)")
    }
    
    // MARK: - Dialogue Interaction for Shop NPC (via proxy)
    func showDialogue(for proxy: NPCDialogueProxy, in scene: SKScene, timeContext: TimeContext) {
        // Dismiss any existing bubble first
        dismissDialogue()
        
        // Get NPC data
        guard let npcData = getNPC(byId: proxy.npcId) else {
            print("❌ ERROR: No dialogue data found for NPC: \\(proxy.npcId)")
            return
        }
        
        // Freeze the NPC via proxy
        proxy.freeze()
        
        // Get random dialogue for current time
        let dialogueText = npcData.getRandomDialogue(isNight: timeContext.isNight)
        
        // Create and show speech bubble
        let bubble = DialogueBubble(
            text: dialogueText,
            speakerName: npcData.name,
            position: proxy.position,
            npcID: proxy.npcId
        )
        
        activeBubble = bubble
        scene.addChild(bubble)
        
        print("💬 \\(npcData.name): \\(dialogueText)")
    }
    
    // MARK: - Custom Dialogue (for ritual farewells)
    func showCustomDialogue(for proxy: NPCDialogueProxy, in scene: SKScene, customLines: [String]) {
        // Dismiss any existing bubble first
        dismissDialogue()
        
        // Get NPC data for name
        guard let npcData = getNPC(byId: proxy.npcId) else {
            print("❌ ERROR: No dialogue data found for NPC: \(proxy.npcId)")
            return
        }
        
        // Freeze the NPC via proxy
        proxy.freeze()
        
        // Use custom dialogue text
        let dialogueText = customLines.randomElement() ?? "Farewell..."
        
        // Create and show speech bubble (no response buttons for liberation)
        let bubble = DialogueBubble(
            text: dialogueText,
            speakerName: npcData.name,
            position: proxy.position,
            npcID: proxy.npcId,
            showResponseButtons: false  // No response buttons for liberation dialogue
        )
        
        activeBubble = bubble
        scene.addChild(bubble)
        
        print("💬 👻 \(npcData.name) (liberation): \(dialogueText)")
    }
    
    func dismissDialogue() {
        // Get scene reference before removing bubble
        let currentScene = activeBubble?.scene
        
        // Remove bubble
        activeBubble?.removeFromParent()
        activeBubble = nil
        
        // Unfreeze NPCs in current scene
        if let scene = currentScene {
            // Unfreeze ForestNPCs (in forest scenes)
            unfreezeAllNPCs(in: scene)
            
            // Unfreeze shop NPCs (in game scene)
            unfreezeAllShopNPCs(in: scene)
        }
    }
    
    func isDialogueActive() -> Bool {
        return activeBubble != nil
    }
    
    // MARK: - NPC Management
    func unfreezeAllNPCs(in scene: SKScene) {
        scene.enumerateChildNodes(withName: "npc_*") { node, _ in
            if let npc = node as? ForestNPC {
                npc.unfreeze()
            }
        }
    }
    
    /// Unfreeze shop NPCs specifically
    private func unfreezeAllShopNPCs(in scene: SKScene) {
        scene.enumerateChildNodes(withName: "npc_*") { node, _ in
            if let shopNPC = node as? NPC {
                shopNPC.resumeFromDialogue()
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
        
        // Create bubble background (adjust height based on whether buttons are shown)
        let bubbleHeight: CGFloat = showResponseButtons ? 160 : 120
        let bubbleSize = CGSize(width: 320, height: bubbleHeight)
        bubbleBackground = SKShapeNode(rectOf: bubbleSize, cornerRadius: 15)
        bubbleBackground.fillColor = SKColor.white.withAlphaComponent(0.95)
        bubbleBackground.strokeColor = SKColor.black.withAlphaComponent(0.7)
        bubbleBackground.lineWidth = 2
        
        // Create speaker name label
        nameLabel = SKLabelNode(text: speakerName)
        nameLabel.fontName = "Arial-Bold"
        nameLabel.fontSize = 14
        nameLabel.fontColor = SKColor.darkGray
        nameLabel.horizontalAlignmentMode = .center
        nameLabel.verticalAlignmentMode = .center
        
        // Create dialogue text label
        textLabel = SKLabelNode()
        textLabel.text = text
        textLabel.fontName = "Arial"
        textLabel.fontSize = 12
        textLabel.fontColor = SKColor.black
        textLabel.horizontalAlignmentMode = .center
        textLabel.verticalAlignmentMode = .center
        textLabel.numberOfLines = showResponseButtons ? 3 : 4 // More lines if no buttons
        textLabel.preferredMaxLayoutWidth = bubbleSize.width - 20 // Text padding
        
        // Create response buttons container
        responseButtons = SKNode()
        
        super.init()
        
        // Position bubble above NPC
        self.position = CGPoint(x: position.x, y: position.y + 100)
        self.zPosition = 100 // High z-position to appear above everything
        
        // Add components
        addChild(bubbleBackground)
        
        // Position text elements within bubble
        let nameY: CGFloat = showResponseButtons ? 50 : 35
        let textY: CGFloat = showResponseButtons ? 15 : 0
        
        nameLabel.position = CGPoint(x: 0, y: nameY)
        textLabel.position = CGPoint(x: 0, y: textY)
        
        addChild(nameLabel)
        addChild(textLabel)
        
        // Only create response buttons if requested
        if showResponseButtons {
            setupResponseButtons()
            addChild(responseButtons)
        }
        
        // Make the entire bubble interactive
        bubbleBackground.name = "dialogue_bubble"
        isUserInteractionEnabled = true
        
        // Animate bubble appearance
        alpha = 0
        setScale(0.5)
        let showAnimation = SKAction.group([
            SKAction.fadeIn(withDuration: 0.3),
            SKAction.scale(to: 1.0, duration: 0.3)
        ])
        run(showAnimation)
    }
    
    private func setupResponseButtons() {
        let buttonSpacing: CGFloat = 90
        let buttonY: CGFloat = -45
        
        // Dismiss button (❌)
        let dismissButton = createResponseButton(emoji: "❌", responseType: NPCResponseType.dismiss, position: CGPoint(x: -buttonSpacing, y: buttonY))
        
        // Nice button (😊)
        let niceButton = createResponseButton(emoji: "😊", responseType: NPCResponseType.nice, position: CGPoint(x: 0, y: buttonY))
        
        // Mean button (😠)
        let meanButton = createResponseButton(emoji: "😠", responseType: NPCResponseType.mean, position: CGPoint(x: buttonSpacing, y: buttonY))
        
        responseButtons.addChild(dismissButton)
        responseButtons.addChild(niceButton)
        responseButtons.addChild(meanButton)
    }
    
    private func createResponseButton(emoji: String, responseType: NPCResponseType, position: CGPoint) -> SKNode {
        let buttonContainer = SKNode()
        buttonContainer.position = position
        
        // Button background
        let buttonBG = SKShapeNode(circleOfRadius: 20)
        buttonBG.fillColor = SKColor.lightGray.withAlphaComponent(0.3)
        buttonBG.strokeColor = SKColor.gray
        buttonBG.lineWidth = 1
        
        // Button emoji
        let buttonLabel = SKLabelNode(text: emoji)
        buttonLabel.fontSize = 24
        buttonLabel.fontName = "Arial"
        buttonLabel.horizontalAlignmentMode = .center
        buttonLabel.verticalAlignmentMode = .center
        
        buttonContainer.addChild(buttonBG)
        buttonContainer.addChild(buttonLabel)
        
        // Set name for touch detection
        buttonContainer.name = "response_\(responseType.rawValue)"
        
        return buttonContainer
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let location = touch.location(in: self)
        let touchedNode = atPoint(location)
        
        // Check if a response button was tapped
        if let nodeName = touchedNode.parent?.name, nodeName.hasPrefix("response_") {
            let responseTypeString = String(nodeName.dropFirst("response_".count))
            
            if let responseType = NPCResponseType(rawValue: responseTypeString) {
                handleResponse(responseType)
                return
            }
        }
        
        // If no button was tapped, dismiss dialogue
        DialogueService.shared.dismissDialogue()
    }
    
    private func handleResponse(_ responseType: NPCResponseType) {
        // Record the interaction in SwiftData
        SaveService.shared.recordNPCInteraction(npcID, responseType: responseType)
        
        // Visual feedback for button press
        if let buttonNode = responseButtons.childNode(withName: "response_\(responseType.rawValue)") {
            let pressAction = SKAction.sequence([
                SKAction.scale(to: 0.8, duration: 0.1),
                SKAction.scale(to: 1.0, duration: 0.1)
            ])
            buttonNode.run(pressAction)
        }
        
        // Brief delay then dismiss
        let waitAction = SKAction.wait(forDuration: 0.3)
        let dismissAction = SKAction.run {
            DialogueService.shared.dismissDialogue()
        }
        
        run(SKAction.sequence([waitAction, dismissAction]))
        
        // Debug output
        let responseText = responseType == NPCResponseType.dismiss ? "dismissed" : 
                          responseType == NPCResponseType.nice ? "was nice to" : "was mean to"
        print("💬 Player \(responseText) \(npcID)")
    }
}
