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
}
