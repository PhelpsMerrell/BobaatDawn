//
//  ForestNPCEntity.swift
//  BobaAtDawn
//
//  Forest-scene NPC with simple wandering behaviour.
//  Extends BaseNPC so it shares visual + dialogue with ShopNPC.
//

import SpriteKit

class ForestNPCEntity: BaseNPC {

    // MARK: - Wandering
    private let wanderRadius: CGFloat = 100.0
    private let wanderInterval: TimeInterval = 3.0
    private let originalPosition: CGPoint

    // MARK: - Network Control
    /// When true, local wandering is stopped and positions come from the
    /// host via `applyNetworkPosition`. Set by the guest when receiving
    /// forest NPC sync in the same room as the host.
    private(set) var isNetworkControlled: Bool = false
    private var networkTargetPosition: CGPoint = .zero

    // MARK: - Init
    init(npcData: NPCData, at position: CGPoint) {
        self.originalPosition = position

        let animal = npcData.animalType ?? .fox

        super.init(npcData: npcData, animalType: animal, at: position)

        // Slightly larger emoji for forest (more prominent outdoors)
        emojiLabel.fontSize = 50

        startWandering()
        Log.info(.forest, "Spawned \(npcData.name) (\(npcData.emoji)) at \(position)")
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Movement (SKAction-based — no Timer, no physics)

    private func startWandering() {
        guard !isFrozen else { return }
        guard !isNetworkControlled else { return }

        let sequence = SKAction.sequence([
            SKAction.wait(forDuration: wanderInterval, withRange: 1.0),
            SKAction.run { [weak self] in self?.wander() }
        ])
        run(SKAction.repeatForever(sequence), withKey: "wander_loop")
    }

    private func stopWandering() {
        removeAction(forKey: "wander_loop")
        removeAction(forKey: "wander_move")
    }

    private func wander() {
        guard !isFrozen else { return }
        guard !isNetworkControlled else { return }

        let angle = Double.random(in: 0...(2 * .pi))
        let dist  = CGFloat.random(in: 30...wanderRadius)
        let target = CGPoint(x: originalPosition.x + cos(angle) * dist,
                             y: originalPosition.y + sin(angle) * dist)

        let move = SKAction.move(to: target, duration: 2.0)
        move.timingMode = .easeInEaseOut
        run(move, withKey: "wander_move")
    }

    // MARK: - BaseNPC Hooks

    override func onFreeze() {
        stopWandering()
        removeAction(forKey: "wander_move")
    }

    override func onUnfreeze() {
        // Don't resume local wandering if positions are being driven by
        // the host via network sync.
        guard !isNetworkControlled else { return }
        
        // Resume after a brief pause
        let resume = SKAction.sequence([
            SKAction.wait(forDuration: 1.0),
            SKAction.run { [weak self] in self?.startWandering() }
        ])
        run(resume, withKey: "resume_wander")
    }

    // MARK: - Time Context (FIXED — was hardcoded to .day)

    override func currentTimeContext() -> TimeContext {
        // Reads from the global time manager so forest NPCs reveal
        // hidden dialogue at night, matching the design pillar.
        return TimeManager.shared.currentPhase == .night ? .night : .day
    }

    // MARK: - Legacy Compatibility Aliases
    // These let existing code (NPCResidentManager, ForestScene) keep compiling
    // while we migrate call-sites. TODO: remove once migration is done.

    var npcId: String { npcData.id }

    // MARK: - Network Control Methods

    /// Switch this NPC to network-controlled mode. Stops local wandering
    /// and positions will be driven by `applyNetworkPosition` calls from
    /// the multiplayer sync handler.
    func setNetworkControlled(_ controlled: Bool) {
        guard controlled != isNetworkControlled else { return }
        isNetworkControlled = controlled
        if controlled {
            stopWandering()
        } else {
            startWandering()
        }
    }

    /// Lerp toward the host-broadcast position. Called every frame (or
    /// every sync tick) by the guest's multiplayer handler.
    func applyNetworkPosition(_ target: CGPoint, lerp factor: CGFloat = 0.2) {
        networkTargetPosition = target
        let dx = target.x - position.x
        let dy = target.y - position.y
        position = CGPoint(
            x: position.x + dx * factor,
            y: position.y + dy * factor
        )
    }
}
