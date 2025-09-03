//
//  ForestNPC.swift
//  BobaAtDawn
//
//  Interactive NPCs for forest scenes with dialogue system
//

import SpriteKit

class ForestNPC: SKLabelNode {
    let npcId: String
    let npcData: NPCData
    private var isFrozen: Bool = false
    private var wanderTimer: Timer?
    private let wanderRadius: CGFloat = 100.0
    private let wanderInterval: TimeInterval = 3.0
    
    private var originalPosition: CGPoint = .zero
    
    init(npcData: NPCData, at position: CGPoint) {
        self.npcId = npcData.id
        self.npcData = npcData
        
        super.init()
        
        // Set up visual appearance
        text = npcData.emoji
        fontSize = 50
        fontName = "Arial"
        horizontalAlignmentMode = .center
        verticalAlignmentMode = .center
        
        // Set position and enable interaction
        self.position = position
        self.originalPosition = position
        self.zPosition = 10
        self.name = "npc_\\(npcData.id)"
        
        // Enable touch interaction
        isUserInteractionEnabled = true
        
        // Start wandering behavior
        startWandering()
        
        print("🎭 Spawned \\(npcData.name) (\\(npcData.emoji)) at \\(position)")
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
        stopWandering()
    }
    
    // MARK: - Movement Behavior
    private func startWandering() {
        guard !isFrozen else { return }
        
        wanderTimer = Timer.scheduledTimer(withTimeInterval: wanderInterval, repeats: true) { [weak self] _ in
            self?.wander()
        }
    }
    
    private func stopWandering() {
        wanderTimer?.invalidate()
        wanderTimer = nil
    }
    
    private func wander() {
        guard !isFrozen else { return }
        
        // Generate random position within wander radius
        let angle = Double.random(in: 0...(2 * Double.pi))
        let distance = CGFloat.random(in: 30...wanderRadius)
        
        let newX = originalPosition.x + cos(angle) * distance
        let newY = originalPosition.y + sin(angle) * distance
        let newPosition = CGPoint(x: newX, y: newY)
        
        // Animate to new position
        let moveAction = SKAction.move(to: newPosition, duration: 2.0)
        moveAction.timingMode = .easeInEaseOut
        
        run(moveAction)
    }
    
    // MARK: - Dialogue Interaction
    func freeze() {
        isFrozen = true
        removeAllActions() // Stop any current movement
        
        // Visual feedback - slightly larger when talking
        let emphasize = SKAction.scale(to: 1.1, duration: 0.2)
        run(emphasize)
    }
    
    func unfreeze() {
        isFrozen = false
        
        // Return to normal size
        let normalize = SKAction.scale(to: 1.0, duration: 0.2)
        run(normalize)
        
        // Resume wandering after a short delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.startWandering()
        }
    }
    
    // MARK: - Touch Handling
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        // Don't interact if already in dialogue
        guard !DialogueService.shared.isDialogueActive() else { return }
        
        // Determine time context (for now, always day - we'll hook this up to game time later)
        // TODO: Connect to actual time system when ForestNPCs need day/night dialogue
        let timeContext: TimeContext = .day // TODO: Connect to actual game time system
        
        // Show dialogue
        if let scene = scene {
            DialogueService.shared.showDialogue(for: self, in: scene, timeContext: timeContext)
        }
    }
}


