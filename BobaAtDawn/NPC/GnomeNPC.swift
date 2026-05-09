//
//  GnomeNPC.swift
//  BobaAtDawn
//
//  Visual representation of a gnome inside a scene. The persistent
//  state (location, task, carried item, rank) lives in `GnomeAgent`,
//  managed by `GnomeManager`. This node is spawned and despawned by
//  the manager as the player enters/leaves scenes.
//
//  Tap dialogue is handled here — see `showDialogue()` — and routed
//  through `GnomeConversationService` for LLM-backed lore.
//
//  Visual movement modes:
//    * `gnomeWanderTo(_)`        — short, clamped, pause-y in-room drift
//                                  (used for sleeping/idle/supervising).
//    * `gnomeTraverse(from:to:)` — long continuous walk for cross-room
//                                  commute and carrying-rock/gem states.
//                                  Driven by GnomeManager when it spawns
//                                  a visual mid-commute.
//

import SpriteKit

@objc(GnomeNPC)
class GnomeNPC: SKNode {

    // MARK: - Identity
    let agent: GnomeAgent

    /// Visual sprite — grayscale gnome.png tinted per-gnome.
    private let spriteNode: SKSpriteNode

    /// Small badge above the gnome showing what they're carrying (rock/gem).
    private let carriedBadge: SKLabelNode

    /// Optional rank pip (worker > senior > foreman).
    private let rankBadge: SKLabelNode

    /// Hard wander bounds (room rectangle in scene coordinates) — keeps
    /// the visual from drifting onto stairs or doors.
    private let wanderBounds: CGRect

    /// Fast or slow visual chatter cooldown is tracked on the manager.
    private(set) var isFrozen: Bool = false
    var isTraversing: Bool { action(forKey: GnomeNPC.traverseKey) != nil }
    var isWandering: Bool { action(forKey: GnomeNPC.wanderKey) != nil }

    // MARK: - Action Keys
    private static let wanderKey = "gnome_wander_move"
    private static let traverseKey = "gnome_traverse_move"
    private static let bobKey = "gnome_walk_bob"

    // MARK: - Visual Constants
    static let spriteSize = CGSize(width: 48, height: 56)

    // MARK: - Rainbow Palette

    /// Roster ids that get a hue tint, in JSON order. Cached on first
    /// access. The two "plain" gnomes (boss_thork and kitchen_cook)
    /// are excluded so they keep their unstyled sprite. Built from
    /// `GnomeDataLoader.shared` rather than a hardcoded list so the
    /// JSON file remains the single source of truth for gnome order.
    private static let coloredIDs: [String] = {
        let plain: Set<String> = ["gnome_boss_thork", "gnome_kitchen_cook"]
        return GnomeDataLoader.shared.all
            .map { $0.id }
            .filter { !plain.contains($0) }
    }()

    /// Returns the tint color for a gnome ID, or nil for plain (no tint).
    /// bossThork (foreman) and kitchenCook are plain. The remaining
    /// gnomes are spread evenly across the hue wheel in roster order.
    static func gnomeColor(for id: String) -> UIColor? {
        guard let index = coloredIDs.firstIndex(of: id) else { return nil }
        let hue = CGFloat(index) / CGFloat(coloredIDs.count)
        return UIColor(hue: hue, saturation: 0.85, brightness: 0.95, alpha: 1.0)
    }

    // MARK: - Init

    init(agent: GnomeAgent, at position: CGPoint, wanderBounds: CGRect) {
        self.agent = agent
        self.wanderBounds = wanderBounds
        self.spriteNode = SKSpriteNode(
            texture: SKTexture(imageNamed: "gnome"),
            size: GnomeNPC.spriteSize
        )
        self.carriedBadge = SKLabelNode(text: "")
        self.rankBadge = SKLabelNode(text: "")

        super.init()

        spriteNode.anchorPoint = CGPoint(x: 0.5, y: 0.0)
        spriteNode.zPosition = 1
        if let tint = GnomeNPC.gnomeColor(for: agent.identity.id) {
            spriteNode.color = tint
            spriteNode.colorBlendFactor = 0.55
        }
        addChild(spriteNode)

        carriedBadge.fontSize = 22
        carriedBadge.fontName = "Arial"
        carriedBadge.horizontalAlignmentMode = .center
        carriedBadge.verticalAlignmentMode = .center
        carriedBadge.position = CGPoint(x: 18, y: 22)
        carriedBadge.zPosition = 2
        carriedBadge.alpha = 0
        addChild(carriedBadge)

        rankBadge.fontSize = 14
        rankBadge.fontName = "AvenirNext-Bold"
        rankBadge.fontColor = SKColor(red: 0.95, green: 0.85, blue: 0.4, alpha: 1.0)
        rankBadge.horizontalAlignmentMode = .center
        rankBadge.verticalAlignmentMode = .top
        rankBadge.position = CGPoint(x: 0, y: -22)
        rankBadge.zPosition = 2
        addChild(rankBadge)

        self.position = position
        self.zPosition = ZLayers.npcs
        self.name = "gnome_\(agent.identity.id)"
        self.isUserInteractionEnabled = true

        refreshVisualBadges()

        Log.info(.npc, "Gnome visual spawned: \(agent.identity.displayName) at \(position)")

        // Register with the gnome LLM prewarmer so a dialogue can be
        // cached ahead of time. Mirrors the BaseNPC ↔ LLMDialogueService
        // pattern. The gnome service ignores the call when Apple
        // Intelligence isn't available, so this is safe everywhere.
        LLMGnomeDialogueService.shared.registerAgent(agent)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented — GnomeNPC is spawned in code")
    }

    // MARK: - Scene Lifecycle (Prewarm Hookup)

    /// Unregister from the gnome LLM prewarmer when this visual leaves
    /// its scene. Pairs with the init-time `registerAgent` call so the
    /// prewarm cache stays scoped to gnomes the player can actually see.
    override func removeFromParent() {
        LLMGnomeDialogueService.shared.unregisterAgent(gnomeID: agent.identity.id)
        super.removeFromParent()
    }

    // MARK: - Public API for GnomeManager

    /// Update the carried-badge and rank-badge based on the current
    /// agent state. Called whenever agent.carried or agent.rank may
    /// have changed.
    func refreshVisualBadges() {
        // Carried badge
        if let carried = agent.carried {
            switch carried {
            case .rock:        carriedBadge.text = "\u{1FAA8}" // 🪨
            case .gem:         carriedBadge.text = "\u{1F48E}" // 💎
            case .brokerBox:   carriedBadge.text = "\u{1F4E6}" // 📦
            case .gemHandful:  carriedBadge.text = "\u{1F48E}" // 💎
            }
            carriedBadge.run(SKAction.fadeAlpha(to: 1.0, duration: 0.2))
        } else {
            carriedBadge.run(SKAction.fadeAlpha(to: 0.0, duration: 0.2))
        }

        // Rank badge — only for boss/miners
        switch agent.identity.role {
        case .boss:
            rankBadge.text = "\u{2605}"
        case .miner:
            switch agent.rank {
            case .junior:   rankBadge.text = ""
            case .standard: rankBadge.text = "\u{00B7}"
            case .senior:   rankBadge.text = "\u{00B7}\u{00B7}"
            case .foreman:  rankBadge.text = "\u{2605}"
            }
        case .housekeeper, .npcBroker, .treasurer:
            rankBadge.text = ""
        }
    }

    /// Move toward `target` smoothly. Used for in-room idle drift —
    /// short, clamped to wander bounds, with the bob walk cycle.
    /// Replaces any active traversal action.
    func gnomeWanderTo(_ target: CGPoint) {
        guard !isFrozen else { return }
        let clamped = CGPoint(
            x: max(wanderBounds.minX, min(wanderBounds.maxX, target.x)),
            y: max(wanderBounds.minY, min(wanderBounds.maxY, target.y))
        )
        // Cancel any in-flight traversal — wander wins.
        removeAction(forKey: GnomeNPC.traverseKey)
        removeAction(forKey: GnomeNPC.wanderKey)
        let move = SKAction.move(to: clamped, duration: 1.8)
        move.timingMode = .easeInEaseOut
        run(move, withKey: GnomeNPC.wanderKey)
        startBobIfNeeded()
    }

    /// Walk continuously from `from` to `to` over `duration` seconds.
    /// Used by GnomeManager during commute / carrying states so the
    /// gnome appears to be physically traversing the room. Bypasses
    /// `wanderBounds` (caller is responsible for sane endpoints).
    /// Replaces any active wander action.
    func gnomeTraverse(from: CGPoint, to: CGPoint, duration: TimeInterval) {
        guard !isFrozen else { return }
        position = from
        removeAction(forKey: GnomeNPC.wanderKey)
        removeAction(forKey: GnomeNPC.traverseKey)
        let move = SKAction.move(to: to, duration: max(0.1, duration))
        // Linear timing — purposeful walk, not the easy-in-out drift.
        move.timingMode = .linear
        run(move, withKey: GnomeNPC.traverseKey)
        startBobIfNeeded()
    }

    /// Stand still at `point`. Used for "at the machine" / "at the bin"
    /// / "at the treasury pile" beats. Cancels any active movement.
    func gnomeStandAt(_ point: CGPoint) {
        removeAction(forKey: GnomeNPC.wanderKey)
        removeAction(forKey: GnomeNPC.traverseKey)
        position = point
        stopBob()
    }

    /// Subtle vertical bob to suggest walking. Re-runs are no-ops thanks
    /// to the action key.
    private func startBobIfNeeded() {
        guard spriteNode.action(forKey: GnomeNPC.bobKey) == nil else { return }
        let up = SKAction.moveBy(x: 0, y: 3, duration: 0.18)
        let down = SKAction.moveBy(x: 0, y: -3, duration: 0.18)
        up.timingMode = .easeOut
        down.timingMode = .easeIn
        let bob = SKAction.repeatForever(SKAction.sequence([up, down]))
        spriteNode.run(bob, withKey: GnomeNPC.bobKey)
    }

    private func stopBob() {
        spriteNode.removeAction(forKey: GnomeNPC.bobKey)
        // Settle the sprite back to baseline so it doesn't sit offset.
        spriteNode.run(SKAction.move(to: .zero, duration: 0.1))
    }

    // MARK: - Freeze / Unfreeze (Dialogue)

    func freeze() {
        isFrozen = true
        removeAction(forKey: GnomeNPC.wanderKey)
        removeAction(forKey: GnomeNPC.traverseKey)
        stopBob()
        let emphasize = SKAction.scale(to: 1.1, duration: 0.2)
        spriteNode.run(emphasize, withKey: "freeze_scale")
    }

    func unfreeze() {
        isFrozen = false
        let normalize = SKAction.scale(to: 1.0, duration: 0.2)
        spriteNode.run(normalize, withKey: "freeze_scale")
    }

    // MARK: - Touch → Dialogue

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        // Player tapped this gnome — open hardcoded/LLM dialogue via
        // GnomeConversationService.
        guard !DialogueService.shared.isDialogueActive() else {
            Log.debug(.dialogue, "Ignoring gnome tap — dialogue already active")
            return
        }
        guard !isFrozen else {
            // If a gnome ↔ gnome convo is happening, tap interrupts it.
            GnomeConversationService.shared.interruptByPlayer()
            return
        }
        showDialogue()
    }

    func showDialogue() {
        freeze()
        guard let scene = scene else { return }
        GnomeConversationService.shared.showPlayerDialogue(
            for: agent,
            in: scene,
            timeContext: TimeManager.shared.currentPhase == .night ? .night : .day
        )
    }
}

// MARK: - DialoguePresenter Conformance

/// Lightweight DialoguePresenter so GnomeConversationService can wire
/// into the existing DialogueService bubble plumbing if desired.
extension GnomeNPC: DialoguePresenter {
    var dialogueCharacterId: String? { agent.identity.id }
}
