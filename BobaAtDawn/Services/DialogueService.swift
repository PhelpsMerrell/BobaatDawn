//
//  DialogueService.swift
//  BobaAtDawn
//
//  Service for managing NPC dialogue and character interactions
//

import SpriteKit
import Foundation

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
            position: npc.position
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
            position: proxy.position
        )
        
        activeBubble = bubble
        scene.addChild(bubble)
        
        print("💬 \\(npcData.name): \\(dialogueText)")
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
    private let tapToClose: SKLabelNode
    
    init(text: String, speakerName: String, position: CGPoint) {
        // Create bubble background
        let bubbleSize = CGSize(width: 300, height: 120)
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
        textLabel.numberOfLines = 4 // Allow multi-line text
        textLabel.preferredMaxLayoutWidth = bubbleSize.width - 20 // Text padding
        
        // Create tap to close hint
        tapToClose = SKLabelNode(text: "tap to close")
        tapToClose.fontName = "Arial"
        tapToClose.fontSize = 10
        tapToClose.fontColor = SKColor.gray
        tapToClose.horizontalAlignmentMode = .center
        tapToClose.verticalAlignmentMode = .center
        tapToClose.alpha = 0.6
        
        super.init()
        
        // Position bubble above NPC
        self.position = CGPoint(x: position.x, y: position.y + 80)
        self.zPosition = 100 // High z-position to appear above everything
        
        // Add components
        addChild(bubbleBackground)
        
        // Position text elements within bubble
        nameLabel.position = CGPoint(x: 0, y: 35)
        textLabel.position = CGPoint(x: 0, y: 0)
        tapToClose.position = CGPoint(x: 0, y: -35)
        
        addChild(nameLabel)
        addChild(textLabel)
        addChild(tapToClose)
        
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
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        // Dismiss dialogue when bubble is tapped
        DialogueService.shared.dismissDialogue()
    }
}
