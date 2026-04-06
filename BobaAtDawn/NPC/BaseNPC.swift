//
//  BaseNPC.swift
//  BobaAtDawn
//
//  Unified base class for all NPCs (shop and forest).
//  Contains an emoji label as a child node — NPCs ARE NOT labels.
//

import SpriteKit

// MARK: - Dialogue Presenter Protocol
/// Anything that can present dialogue through DialogueService
protocol DialoguePresenter: AnyObject {
    var dialogueCharacterId: String? { get }
    var position: CGPoint { get }
    func freeze()
    func unfreeze()
}

// MARK: - Base NPC
class BaseNPC: SKNode, DialoguePresenter {

    // MARK: - Identity
    let npcData: NPCData
    let animalType: AnimalType

    // MARK: - Visual
    /// The emoji label rendered as a child — not inherited from.
    let emojiLabel: SKLabelNode

    // MARK: - State
    private(set) var isFrozen: Bool = false

    // MARK: - Dialogue Presenter Conformance
    var dialogueCharacterId: String? { animalType.characterId }

    // MARK: - Init
    init(npcData: NPCData, animalType: AnimalType, at position: CGPoint) {
        self.npcData = npcData
        self.animalType = animalType
        self.emojiLabel = SKLabelNode(text: animalType.rawValue)

        super.init()

        // Configure label
        emojiLabel.fontSize = GameConfig.NPC.fontSize
        emojiLabel.fontName = GameConfig.NPC.fontName
        emojiLabel.horizontalAlignmentMode = .center
        emojiLabel.verticalAlignmentMode = .center
        emojiLabel.zPosition = 1
        addChild(emojiLabel)

        // Configure node
        self.position = position
        self.zPosition = ZLayers.npcs
        self.name = "npc_\(animalType.rawValue)"
        self.isUserInteractionEnabled = true

        Log.info(.npc, "\(npcData.name) (\(animalType.rawValue)) created at \(position)")
    }

    /// Convenience: build from AnimalType alone (resolves NPCData from DialogueService)
    convenience init(animal: AnimalType, at position: CGPoint) {
        let data: NPCData
        if let charId = animal.characterId,
           let resolved = DialogueService.shared.getNPC(byId: charId) {
            data = resolved
        } else {
            // Fallback placeholder data
            data = NPCData(id: animal.characterId ?? "unknown",
                           name: animal.rawValue,
                           animal: animal.rawValue,
                           causeOfDeath: "unknown",
                           homeRoom: 1,
                           dialogue: NPCDialogue(day: ["..."], night: ["..."]))
        }
        self.init(npcData: data, animalType: animal, at: position)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Freeze / Unfreeze (Dialogue)

    func freeze() {
        isFrozen = true
        onFreeze()
        let emphasize = SKAction.scale(to: 1.1, duration: 0.2)
        emojiLabel.run(emphasize, withKey: "freeze_scale")
        Log.debug(.dialogue, "\(npcData.name) frozen for dialogue")
    }

    func unfreeze() {
        isFrozen = false
        onUnfreeze()
        let normalize = SKAction.scale(to: 1.0, duration: 0.2)
        emojiLabel.run(normalize, withKey: "freeze_scale")
        Log.debug(.dialogue, "\(npcData.name) unfrozen")
    }

    /// Subclass hook — called inside freeze(). Override to pause movement.
    func onFreeze() {}

    /// Subclass hook — called inside unfreeze(). Override to resume movement.
    func onUnfreeze() {}

    // MARK: - Time Context

    /// Subclasses override this to provide the actual time context.
    func currentTimeContext() -> TimeContext {
        // Default: derive from TimeManager
        return TimeManager.shared.currentPhase == .night ? .night : .day
    }

    // MARK: - Touch → Dialogue

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard !DialogueService.shared.isDialogueActive() else {
            Log.debug(.dialogue, "Ignoring tap — dialogue already active")
            return
        }
        guard !isFrozen else { return }
        guard dialogueCharacterId != nil else {
            Log.debug(.dialogue, "No dialogue data for \(animalType.rawValue)")
            return
        }

        showDialogue()
    }

    func showDialogue() {
        freeze()
        if let scene = scene {
            DialogueService.shared.showDialogue(for: self, in: scene, timeContext: currentTimeContext())
        }
    }
}
