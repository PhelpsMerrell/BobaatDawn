//
//  GnomeNPC.swift
//  BobaAtDawn
//
//  Gnomes are a separate NPC type from the forest soul-NPCs.
//  They live inside structures like the Big Oak Tree, carry hardcoded
//  lore/dialogue (no JSON lookup), and are NOT tracked by
//  NPCResidentManager.
//
//  SCENE EXCLUSIVITY:
//  Gnomes are only instantiated inside BigOakTreeScene (or other interior
//  structure scenes added later). They are NEVER added to GameScene or
//  ForestScene. Because they live as children of their host scene, they
//  are automatically deallocated when the player exits the structure —
//  there is no mechanism by which a gnome can "leak" into the forest or
//  the shop. Wander bounds (see below) additionally confine each gnome
//  to a rectangle within its host room so it can't overlap stairs,
//  doors, or other interactive triggers.
//
//  Visual is a placeholder emoji that can be swapped for a Sprite2D
//  (SKSpriteNode) later — see `setPlaceholderEmoji` / `setSpriteTexture`.
//
//  Behavior mirrors ForestNPCEntity's simple SKAction-based wander so no
//  new movement system is introduced.
//

import SpriteKit

// MARK: - Gnome Type
/// Hardcoded gnome identities. Add new cases as lore gets written.
/// The `rawValue` is used as a stable ID for future dialogue lookups.
enum GnomeType: String {
    case lobbyGreeter      = "gnome_lobby_greeter"
    case fireplaceKeeper   = "gnome_fireplace_keeper"
    case kitchenCook       = "gnome_kitchen_cook"
    case leftBedroomElder  = "gnome_left_bedroom_elder"
    case middleBedroomSeer = "gnome_middle_bedroom_seer"
    case rightBedroomChild = "gnome_right_bedroom_child"

    /// Placeholder display name shown in logs; real name can be set in
    /// hardcoded dialogue later.
    var displayName: String {
        switch self {
        case .lobbyGreeter:       return "Gnome Greeter"
        case .fireplaceKeeper:    return "Fireplace Keeper"
        case .kitchenCook:        return "Kitchen Gnome"
        case .leftBedroomElder:   return "Elder Gnome"
        case .middleBedroomSeer:  return "Seer Gnome"
        case .rightBedroomChild:  return "Little Gnome"
        }
    }
}

// MARK: - Gnome NPC
class GnomeNPC: BaseNPC {

    // MARK: - Identity
    let gnomeType: GnomeType

    // MARK: - Wandering (matches ForestNPCEntity pattern)
    private let wanderRadius: CGFloat
    private let wanderInterval: TimeInterval
    private let originalPosition: CGPoint
    /// Optional hard bounds (in scene/world coordinates) that confine the
    /// gnome's wander target. If non-nil, any computed wander destination
    /// is clamped to this rectangle. This prevents gnomes from drifting
    /// onto stairs, doors, or out of their intended room area.
    private let wanderBounds: CGRect?

    // MARK: - Placeholder Visual Constants
    /// Default placeholder emoji for gnomes. Not a real gnome emoji in Unicode;
    /// this is a stand-in until Sprite2D art is swapped in.
    static let defaultPlaceholderEmoji: String = "🧙"
    static let defaultFontSize: CGFloat = 44

    // MARK: - Init
    init(
        gnomeType: GnomeType,
        at position: CGPoint,
        wanderRadius: CGFloat = 60.0,
        wanderInterval: TimeInterval = 4.0,
        wanderBounds: CGRect? = nil
    ) {
        self.gnomeType = gnomeType
        self.wanderRadius = wanderRadius
        self.wanderInterval = wanderInterval
        self.originalPosition = position
        self.wanderBounds = wanderBounds

        // BaseNPC requires an AnimalType; gnomes aren't animals so we pass a
        // neutral placeholder and then override the emoji label below.
        // Hardcoded placeholder NPCData (no JSON lookup).
        let placeholderData = NPCData(
            id: gnomeType.rawValue,
            name: gnomeType.displayName,
            animal: "gnome",
            causeOfDeath: "none",
            homeRoom: 0,
            dialogue: NPCDialogue(
                day: ["..."],
                night: ["..."]
            )
        )

        super.init(
            npcData: placeholderData,
            animalType: .fox, // placeholder — visual is overridden below
            at: position
        )

        // Override the placeholder emoji with a gnome-specific visual.
        setPlaceholderEmoji(GnomeNPC.defaultPlaceholderEmoji,
                            fontSize: GnomeNPC.defaultFontSize)

        // Distinct name for scene lookups / debugging.
        self.name = "gnome_\(gnomeType.rawValue)"

        startWandering()
        Log.info(.npc, "Gnome spawned: \(gnomeType.displayName) at \(position)")
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Visual Swapping
    /// Swap the placeholder emoji label for a different emoji.
    /// Useful while dialing in the look before adding real art.
    func setPlaceholderEmoji(_ emoji: String, fontSize: CGFloat? = nil) {
        emojiLabel.text = emoji
        if let size = fontSize {
            emojiLabel.fontSize = size
        }
    }

    /// Replace the emoji placeholder with a real Sprite2D texture.
    /// Hides the emoji label and adds an `SKSpriteNode` in its place.
    /// The sprite is named `"gnome_sprite"` so it can be re-fetched later.
    ///
    /// - Parameters:
    ///   - texture: The texture to use (e.g. from an `SKTextureAtlas`).
    ///   - size: Desired render size. Defaults to a sensible placeholder size.
    ///   - zPositionOffset: How far above the node's base z to place the sprite.
    @discardableResult
    func setSpriteTexture(
        _ texture: SKTexture,
        size: CGSize = CGSize(width: 48, height: 48),
        zPositionOffset: CGFloat = 1
    ) -> SKSpriteNode {
        // Remove any previously-installed sprite
        childNode(withName: "gnome_sprite")?.removeFromParent()

        let sprite = SKSpriteNode(texture: texture, size: size)
        sprite.name = "gnome_sprite"
        sprite.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        sprite.zPosition = zPositionOffset
        addChild(sprite)

        // Hide the emoji label so the sprite takes over.
        emojiLabel.alpha = 0.0
        return sprite
    }

    // MARK: - Wandering (SKAction-based — identical pattern to ForestNPCEntity)
    private func startWandering() {
        guard !isFrozen else { return }

        let sequence = SKAction.sequence([
            SKAction.wait(forDuration: wanderInterval, withRange: 1.5),
            SKAction.run { [weak self] in self?.wander() }
        ])
        run(SKAction.repeatForever(sequence), withKey: "gnome_wander_loop")
    }

    private func stopWandering() {
        removeAction(forKey: "gnome_wander_loop")
        removeAction(forKey: "gnome_wander_move")
    }

    private func wander() {
        guard !isFrozen else { return }

        let angle = Double.random(in: 0...(2 * .pi))
        let dist  = CGFloat.random(in: 20...wanderRadius)
        var target = CGPoint(
            x: originalPosition.x + cos(angle) * dist,
            y: originalPosition.y + sin(angle) * dist
        )

        // Clamp to hard bounds if set — prevents drifting onto interactive
        // triggers (stairs, doors) or outside the host room.
        if let bounds = wanderBounds {
            target.x = max(bounds.minX, min(bounds.maxX, target.x))
            target.y = max(bounds.minY, min(bounds.maxY, target.y))
        }

        let move = SKAction.move(to: target, duration: 2.5)
        move.timingMode = .easeInEaseOut
        run(move, withKey: "gnome_wander_move")
    }

    // MARK: - BaseNPC Hooks
    override func onFreeze() {
        stopWandering()
        removeAction(forKey: "gnome_wander_move")
    }

    override func onUnfreeze() {
        let resume = SKAction.sequence([
            SKAction.wait(forDuration: 1.0),
            SKAction.run { [weak self] in self?.startWandering() }
        ])
        run(resume, withKey: "gnome_resume_wander")
    }

    // MARK: - Time Context
    override func currentTimeContext() -> TimeContext {
        return TimeManager.shared.currentPhase == .night ? .night : .day
    }

    // MARK: - Dialogue Hook (Hardcoded Lore)
    /// Gnomes don't pull from npc_dialogue.json. Override `showDialogue`
    /// in the future to present hardcoded lore inline. For now, it falls
    /// through to BaseNPC (which will no-op because `dialogueCharacterId`
    /// won't resolve to a NPCData entry in DialogueService).
    ///
    /// When hardcoded dialogue gets wired up, replace the body of this
    /// method with a direct call into a gnome-specific presenter.
    override func showDialogue() {
        Log.debug(.dialogue, "Gnome \(gnomeType.displayName) tapped — hardcoded lore not yet implemented")
        // Intentional no-op for now. Do NOT call super.showDialogue() —
        // we don't want it hitting DialogueService with placeholder data.
    }
}
