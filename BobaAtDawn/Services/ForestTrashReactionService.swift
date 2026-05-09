//
//  ForestTrashReactionService.swift
//  BobaAtDawn
//
//  Reactive trash pickup for forest NPCs. When trash is dropped at an
//  NPC's home house (by a hostile neighbor), the homeowner notices it
//  next time they walk past, picks it up with an annoyed remark, and
//  throws it out. The trash item is deleted from the world — this is
//  the design's trash sink that bounds forest clutter.
//
//  Detection rules
//  ---------------
//  An NPC reacts if ALL of these are true:
//    1. They are in their own home room (`forestNPC` exists, the scene
//       is showing their home room).
//    2. They are within ~80pt of their own house anchor.
//    3. There is uncollected trash in the WorldItemRegistry within
//       ~70pt of the NPC's current position.
//    4. They are not currently mid-reaction (cooldown).
//    5. They are not frozen (in dialogue).
//    6. The trash item has not already been claimed by another NPC's
//       in-flight reaction this session.
//
//  Reaction flow
//  -------------
//  1. NPC freezes (stops wandering).
//  2. LLM generates an annoyed line. Falls back to the static pool on
//     unavailability or stream failure.
//  3. Bubble renders over the NPC.
//  4. Trash is removed from WorldItemRegistry, broadcast as cleaned,
//     visual fades out.
//  5. Cooldown applied so the same NPC doesn't immediately re-trigger
//     on a second piece of trash. Their next reaction is gated on a
//     short delay so they get back to wandering first.
//
//  Multiplayer
//  -----------
//  Host-authoritative. The host runs the entire reaction (line + sink
//  + broadcast). The guest sees the result via the existing
//  `trashCleaned` broadcast plus the dialogue broadcast layer.
//
//  Cooldown / dedup
//  ----------------
//  Per-NPC cooldowns prevent thrashing if the player drops more trash
//  on the same lawn. A separate `claimedTrashIDs` set prevents two
//  NPCs from racing to react to the same item (rare but possible if
//  two NPCs share a house slot or one is just passing through).
//

import SpriteKit
import Foundation

final class ForestTrashReactionService {

    static let shared = ForestTrashReactionService()
    private init() {}

    // MARK: - Tunables

    /// How close the NPC must be to their own house to be considered
    /// "home" for reaction purposes. Bigger than the wander radius so
    /// the NPC doesn't have to be standing exactly on the door.
    private let nearHouseDistance: CGFloat = 80

    /// How close the NPC must be to a trash item to react to it.
    private let nearTrashDistance: CGFloat = 70

    /// How long after a reaction before the same NPC can react again.
    /// Keeps a barrage of trash from triggering 5 reactions in a row.
    private let perNPCCooldown: TimeInterval = 25.0

    // MARK: - State

    /// Per-NPC cooldown timestamps. NPC reacts again only after
    /// CACurrentMediaTime() exceeds the stored value.
    private var cooldowns: [String: TimeInterval] = [:]

    /// Trash item IDs that another NPC has already claimed for an
    /// in-flight reaction this session. Cleared when the reaction
    /// completes (either way — line generated or fell back).
    private var claimedTrashIDs: Set<String> = []

    /// Per-frame guard so a long-running reaction doesn't fire its own
    /// retrigger before resolving. Maps NPC id → bool.
    private var inFlightReactions: Set<String> = []

    // MARK: - Public Tick

    /// Called from `ForestScene.updateSpecificContent`. Cheap when
    /// nothing to do.
    func tick(in scene: ForestScene, room: Int) {
        guard !MultiplayerService.shared.isGuest else { return }
        guard !DialogueService.shared.isDialogueActive() else { return }

        let now = CACurrentMediaTime()

        // Pull all forest NPCs currently in this scene.
        let npcs = scene.children.compactMap { $0 as? ForestNPCEntity }
        guard !npcs.isEmpty else { return }

        // Trash items registered in this room.
        let trashItems = WorldItemRegistry.shared.items(of: .trash, at: .forestRoom(room))
        guard !trashItems.isEmpty else { return }

        for npc in npcs {
            let npcID = npc.npcData.id
            // Cooldown check.
            if let until = cooldowns[npcID], until > now { continue }
            // Already mid-reaction.
            if inFlightReactions.contains(npcID) { continue }
            // Frozen (in dialogue).
            if npc.isFrozen { continue }
            // Wrong room.
            guard npc.npcData.homeRoom == room else { continue }

            // Resolve this NPC's home anchor in scene coords.
            guard let resident = NPCResidentManager.shared.findResident(byID: npcID) else { continue }
            let homePos = housePosition(in: scene, houseSlot: resident.homeHouse)

            // Must be near home.
            let homeOffset = hypot(npc.position.x - homePos.x, npc.position.y - homePos.y)
            guard homeOffset <= nearHouseDistance else { continue }

            // Find a nearby unclaimed trash item.
            guard let trashTarget = pickReactionTarget(
                npc: npc,
                items: trashItems
            ) else { continue }

            // Claim and react.
            claimedTrashIDs.insert(trashTarget.id)
            inFlightReactions.insert(npcID)
            triggerReaction(
                npc: npc,
                resident: resident,
                trashItem: trashTarget,
                in: scene,
                room: room
            )
        }
    }

    // MARK: - Target Selection

    /// Find the nearest unclaimed trash within range.
    private func pickReactionTarget(
        npc: ForestNPCEntity,
        items: [WorldItem]
    ) -> WorldItem? {
        let candidates = items
            .filter { !claimedTrashIDs.contains($0.id) }
            .map { item -> (item: WorldItem, distance: CGFloat) in
                let dx = item.position.x - npc.position.x
                let dy = item.position.y - npc.position.y
                return (item, hypot(dx, dy))
            }
            .filter { $0.distance <= nearTrashDistance }
            .sorted { $0.distance < $1.distance }
        return candidates.first?.item
    }

    // MARK: - Reaction Execution

    private func triggerReaction(
        npc: ForestNPCEntity,
        resident: NPCResident,
        trashItem: WorldItem,
        in scene: ForestScene,
        room: Int
    ) {
        let npcID = npc.npcData.id

        // Freeze so the NPC stops wandering during the bubble.
        npc.freeze()

        // Find the trash node in the scene so we can animate its
        // removal alongside the bubble. Match by registry ID stored in
        // userData.
        let trashNode = scene.children
            .compactMap { $0 as? Trash }
            .first { ($0.userData?["worldItemID"] as? String) == trashItem.id }

        // Show a placeholder bubble immediately while we wait on the
        // LLM. This makes the reaction feel responsive even if the
        // model is slow or absent.
        renderReactionBubble(
            npc: npc,
            resident: resident,
            text: "...",
            mood: "upset",
            in: scene
        )

        let timeContext: TimeContext = TimeManager.shared.currentPhase == .night ? .night : .day

        // Stream the LLM line. On unavailability, fall back to pool.
        if let stream = LLMDialogueService.shared.streamTrashReactionLine(
            for: resident,
            timeContext: timeContext
        ) {
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                var finalLine = ""
                var finalMood = "upset"
                do {
                    for try await update in stream {
                        if let l = update.line { finalLine = l }
                        if let m = update.mood { finalMood = m }
                        if update.isComplete { break }
                    }
                } catch {
                    Log.warn(.dialogue, "[TrashReaction] stream failed: \(error)")
                }
                let cleaned = finalLine.trimmingCharacters(in: .whitespacesAndNewlines)
                let lineToShow = cleaned.isEmpty
                    ? Self.fallbackPool.randomElement() ?? "Not again."
                    : cleaned
                self.finalizeReaction(
                    npc: npc,
                    resident: resident,
                    line: lineToShow,
                    mood: finalMood,
                    trashItem: trashItem,
                    trashNode: trashNode,
                    in: scene,
                    room: room
                )
            }
        } else {
            let line = Self.fallbackPool.randomElement() ?? "Not again."
            finalizeReaction(
                npc: npc,
                resident: resident,
                line: line,
                mood: "upset",
                trashItem: trashItem,
                trashNode: trashNode,
                in: scene,
                room: room
            )
        }
    }

    /// Render the final bubble, remove the trash, broadcast, and clean
    /// up reaction state. Idempotent if called twice (defensive).
    private func finalizeReaction(
        npc: ForestNPCEntity,
        resident: NPCResident,
        line: String,
        mood: String,
        trashItem: WorldItem,
        trashNode: Trash?,
        in scene: ForestScene,
        room: Int
    ) {
        let npcID = npc.npcData.id

        // Render the actual bubble.
        renderReactionBubble(
            npc: npc,
            resident: resident,
            text: line,
            mood: mood,
            in: scene
        )

        // Remove trash from registry.
        WorldItemRegistry.shared.remove(id: trashItem.id)

        // Animate the trash sprite out, if present.
        if let node = trashNode {
            node.pickUp { }
        }

        // Broadcast removal so the guest's scene clears the visual too.
        if MultiplayerService.shared.isConnected {
            MultiplayerService.shared.send(
                type: .trashCleaned,
                payload: TrashCleanedMessage(
                    position: trashItem.position,
                    location: "forest_room_\(room)"
                )
            )
        }

        // Chronicle hook — counts as a tidy.
        DailyChronicleLedger.shared.recordTrashCleaned(
            location: "forest room \(room)"
        )

        // Schedule unfreeze + cooldown release after the bubble has
        // had time to read. Same duration the dialogue service uses.
        let now = CACurrentMediaTime()
        cooldowns[npcID] = now + perNPCCooldown
        claimedTrashIDs.remove(trashItem.id)
        inFlightReactions.remove(npcID)

        // Don't manually unfreeze — DialogueService's normal dismissal
        // pipeline does that on its bubble timeout. The freeze persists
        // until the bubble closes, then the NPC resumes wandering.
        // (See BaseNPC.unfreeze + onUnfreeze.)
        Log.info(.dialogue, "[TrashReaction] \(resident.npcData.name) reacted to trash at home")
    }

    /// Show the reaction line over the NPC. Uses the static dialogue
    /// rendering path so it gates correctly against player taps.
    private func renderReactionBubble(
        npc: ForestNPCEntity,
        resident: NPCResident,
        text: String,
        mood: String,
        in scene: ForestScene
    ) {
        DialogueService.shared.showStaticDialogue(
            for: npc,
            speakerName: resident.npcData.name,
            text: text,
            mood: mood,
            in: scene
        )
    }

    // MARK: - House Position

    /// Resolve a house's world position for a given slot. Mirrors the
    /// layout used by NPCResidentManager.spawnForestNPC. Falls back to
    /// the residentManager's house grid if the scene doesn't expose
    /// the anchor directly — we don't know whether the anchors are
    /// authored in the .sks for every room, so derive from the same
    /// fixed grid coords.
    private func housePosition(in scene: ForestScene, houseSlot: Int) -> CGPoint {
        let housePositions: [GridCoordinate] = [
            GridCoordinate(x: 8, y: 16),
            GridCoordinate(x: 24, y: 16),
            GridCoordinate(x: 8, y: 8),
            GridCoordinate(x: 24, y: 8)
        ]
        let idx = max(0, min(3, houseSlot - 1))
        return scene.gridService.gridToWorld(housePositions[idx])
    }

    // MARK: - Daily Reset

    /// Clear all cooldowns and claimed trash. Called at dawn when
    /// every NPC's plan rerolls — old reactions shouldn't carry over.
    func resetForDawn() {
        cooldowns.removeAll()
        claimedTrashIDs.removeAll()
        inFlightReactions.removeAll()
    }

    // MARK: - Fallback Pool

    /// Used whenever the LLM is unavailable, errors mid-stream, or
    /// returns an empty line. Annoyed-but-not-furious register —
    /// these are people who've found trash on their lawn, not active
    /// rage. The bubble system will tag a "upset" mood emoji either
    /// way.
    static let fallbackPool: [String] = [
        "Oh, for goodness' sake. Not again.",
        "Honestly. Some neighbors.",
        "Right. Of course it's on my doorstep.",
        "I'll just clean this up myself, then.",
        "Some people. Honestly.",
        "Charming. Truly charming.",
        "Lovely. Wonderful. My favorite.",
        "I know exactly who left this here.",
        "Every. Single. Day.",
        "If only I had a guess. I do have a guess.",
        "Picking up after grown adults again, am I?",
        "Right where I was going to step. Of course."
    ]
}
