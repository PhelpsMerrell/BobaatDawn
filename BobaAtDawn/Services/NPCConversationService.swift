//
//  NPCConversationService.swift
//  BobaAtDawn
//
//  Drives ambient NPC ↔ NPC conversations in the shop.
//
//  Architecture
//  ------------
//  - Host-authoritative. The host picks the participants, picks the topic,
//    and runs the LLM streaming loop. Each finalized line is broadcast as
//    a `npcConversationLine` message; the guest just renders.
//  - Pairings are weighted by:
//      • participants' talkativeness (fixed per NPC)
//      • how much they share opinion-wise (close & friendly bond more)
//      • boredom — a per-NPC chat cooldown so the same pair doesn't loop
//  - Conversations are 3..6 lines long. The first speaker is chosen by the
//    pairing logic; subsequent speakers are chosen by the LLM.
//  - Each line carries a `ConversationInteraction` tag which is applied to
//    EVERY pair within the participant set (speaker → each listener) so a
//    3-way conversation moves all pair scores together.
//  - Tapping any participant (player↔NPC dialogue) interrupts immediately
//    and applies a final `awkwardSilence` to slightly cool the room. This
//    is how the player can "break up a fight."
//

import SpriteKit
import Foundation

// MARK: - Conversation State

private enum ConversationState {
    case idle
    case running(id: String, participants: [String], started: TimeInterval, linesPlayed: Int)
}

// MARK: - Service

final class NPCConversationService {

    static let shared = NPCConversationService()

    // MARK: - Tunables

    /// How often the host considers starting a new conversation when one
    /// isn't already running. Real seconds.
    private let scanIntervalSeconds: TimeInterval = 22.0

    /// After a conversation ends, both participants go on cooldown for
    /// this many seconds before being eligible again.
    private let perNPCCooldownSeconds: TimeInterval = 90.0

    /// Conversation length cap. The LLM may close earlier via isClosing.
    private let maxLinesPerConversation = 6
    private let minLinesPerConversation = 3

    /// Beat between lines so the player can read each one before the
    /// next renders.
    private let secondsBetweenLines: TimeInterval = 3.0

    /// 3-way conversations only fire when at least this many NPCs are
    /// in the shop. 4-way needs even more.
    private let threeWayMinShopNPCs = 4
    private let fourWayMinShopNPCs  = 5

    // MARK: - State

    private var state: ConversationState = .idle
    private var lastScanAt: TimeInterval = 0

    /// Per-NPC chat cooldown. Maps NPC id → earliest CACurrentMediaTime
    /// at which they're eligible again.
    private var cooldowns: [String: TimeInterval] = [:]

    /// Live conversation bookkeeping (host side).
    private var currentParticipants: [NPCData] = []
    /// Live ShopNPC node references for the participants. Kept as weak
    /// box to avoid retaining nodes that have left the scene mid-convo.
    private var currentParticipantNodes: [WeakShopNPC] = []
    private var currentTopic: OpinionTopic?
    private var currentLines: [(speakerID: String, text: String)] = []
    private var currentInteractions: [(speakerID: String, listenerID: String, interaction: ConversationInteraction)] = []
    private var currentConversationID: String = ""
    private weak var currentScene: SKScene?
    /// Active streaming Task for the current line, if any. Cancelled on
    /// player interruption to avoid pumping more lines into a dismissed
    /// conversation.
    private var currentLineTask: Task<Void, Never>?

    private init() {}

    // MARK: - Public Entry Points

    /// Called every frame from GameScene's update loop. Cheap unless a
    /// scan is due. Only hosts (or solo) actually consider firing.
    func tick(deltaTime: TimeInterval, in scene: SKScene, npcs: [ShopNPC], timeContext: TimeContext) {
        // Only the authoritative side runs the scheduler. Guests render
        // remote lines via handleRemoteLine.
        guard !MultiplayerService.shared.isGuest else { return }

        // Bail if a player↔NPC dialogue is open — don't talk over it.
        if DialogueService.shared.isDialogueActive() { return }

        // If something is running, no scheduling needed; the line task
        // drives itself.
        if case .running = state { return }

        // Throttle scans.
        let now = CACurrentMediaTime()
        if now - lastScanAt < scanIntervalSeconds { return }
        lastScanAt = now

        scheduleConversationIfPossible(in: scene, npcs: npcs, timeContext: timeContext)
    }

    /// Player tapped an NPC participating in a live conversation. Cuts
    /// the conversation short, applies a small `awkwardSilence` to the
    /// room, and broadcasts the end.
    func interruptByPlayer() {
        guard case .running(let id, let parts, _, _) = state else { return }
        Log.info(.dialogue, "[NPC convo] Player interrupted \(id)")

        // Add an awkwardSilence between every pair so opinions cool a notch.
        let pairs = orderedPairs(in: parts)
        var addedInteractions: [NPCConversationEndedMessage.Entry] = []
        for (a, b) in pairs {
            currentInteractions.append((speakerID: a, listenerID: b, interaction: .awkwardSilence))
            addedInteractions.append(.init(speaker: a, listener: b, interaction: ConversationInteraction.awkwardSilence.rawValue))
        }

        finalizeConversation(interruptedByPlayer: true, extraInteractions: addedInteractions)
    }

    // MARK: - Remote Rendering (guest side)

    /// Render a line broadcast by the host. Guest doesn't run any LLM
    /// or scheduler — just shows the bubble and freezes the speaker.
    func handleRemoteLine(_ msg: NPCConversationLineMessage, in scene: SKScene) {
        guard let speakerNode = findShopNPCNode(npcID: msg.speakerNPCID, in: scene)
            ?? findForestNPCNode(npcID: msg.speakerNPCID, in: scene) else {
            // Speaker isn't on stage in our scene — just drop the line.
            return
        }

        // Briefly freeze the speaker so they look like they're talking.
        // Hold the freeze long enough that they don't visually unfreeze
        // between lines (host emits a line every secondsBetweenLines=3.0).
        if let baseNPC = speakerNode as? BaseNPC {
            baseNPC.freeze()
            baseNPC.run(SKAction.wait(forDuration: 3.5)) { [weak baseNPC] in
                baseNPC?.unfreeze()
            }
        }

        DialogueService.shared.showConversationLine(
            speakerNode: speakerNode,
            speakerName: msg.speakerName,
            text: msg.text,
            mood: msg.mood,
            in: scene
        )
    }

    /// Apply the host's final interaction list locally so guest's
    /// SaveService relationship rows track. Idempotent enough — applying
    /// twice on the same conversationID is harmless if the host already
    /// applied them on the host side, since both sides have their own
    /// SwiftData stores.
    func handleRemoteEnd(_ msg: NPCConversationEndedMessage) {
        // Only the guest applies these; the host has already applied them
        // line-by-line as it generated.
        guard MultiplayerService.shared.isGuest else { return }
        for entry in msg.interactions {
            guard let interaction = ConversationInteraction(rawValue: entry.interaction) else { continue }
            SaveService.shared.applyConversationInteraction(
                speaker: entry.speaker,
                listener: entry.listener,
                interaction: interaction,
                incrementConversationCount: false
            )
        }
        // Bump conversation counts once per pair on the guest side too.
        let pairs = orderedPairs(in: msg.participants)
        for (a, b) in pairs {
            if let row = SaveService.shared.getRelationship(of: a, toward: b) {
                row.conversationCount += 1
            }
        }
    }

    // MARK: - Scheduling (Host)

    private func scheduleConversationIfPossible(
        in scene: SKScene,
        npcs: [ShopNPC],
        timeContext: TimeContext
    ) {
        // Only NPCs in `wandering` or `sitting` (i.e. not entering /
        // leaving / drinking / ritual) are good candidates.
        let candidates = npcs.filter { isConversational($0) }
        guard candidates.count >= 2 else { return }

        // Filter out NPCs on cooldown.
        let now = CACurrentMediaTime()
        let eligible = candidates.filter { (cooldowns[$0.npcData.id] ?? 0) <= now }
        guard eligible.count >= 2 else { return }

        // Decide group size based on shop population.
        let maxGroup: Int
        if eligible.count >= fourWayMinShopNPCs {
            maxGroup = 4
        } else if eligible.count >= threeWayMinShopNPCs {
            maxGroup = 3
        } else {
            maxGroup = 2
        }

        // Roll a base chance scaled by average talkativeness across
        // eligible NPCs. Skittish-shop = quieter shop.
        let avgTalk = eligible.map { CGFloat($0.npcData.talkativeness) }.reduce(0, +)
                      / CGFloat(eligible.count)
        let fireChance = 0.35 + (avgTalk - 0.5) * 0.4    // 0.15 .. 0.55-ish
        guard CGFloat.random(in: 0...1) < fireChance else { return }

        // Pick first speaker weighted by talkativeness.
        guard let first = pickWeightedByTalkativeness(eligible) else { return }

        // Pick a partner that maximally fits with `first`. Score each
        // candidate by relationship + topic overlap + a touch of randomness.
        let groupSize = Int.random(in: 2...maxGroup)
        let group = pickGroup(starting: first, from: eligible, groupSize: groupSize)
        guard group.count >= 2 else { return }

        // Resolve NPCData for each, plus pick a topic both/all share.
        let datas = group.map { $0.npcData }
        let topics = DialogueService.shared.getOpinionTopics()
        let sharedTopics = topics.filter { topic in
            datas.allSatisfy { ($0.opinionStances[topic.id] ?? .unaware).isVoiced }
        }
        let topic = sharedTopics.randomElement()

        startConversation(
            participants: group,
            participantData: datas,
            topic: topic,
            in: scene,
            timeContext: timeContext
        )
    }

    private func isConversational(_ npc: ShopNPC) -> Bool {
        switch npc.currentState {
        case .wandering, .sitting:  return !npc.isCurrentlyInRitual()
        default:                    return false
        }
    }

    private func pickWeightedByTalkativeness(_ pool: [ShopNPC]) -> ShopNPC? {
        let weights = pool.map { max(0.05, CGFloat($0.npcData.talkativeness)) }
        let total = weights.reduce(0, +)
        guard total > 0 else { return pool.randomElement() }
        let r = CGFloat.random(in: 0...total)
        var acc: CGFloat = 0
        for (i, w) in weights.enumerated() {
            acc += w
            if r <= acc { return pool[i] }
        }
        return pool.last
    }

    /// Pick `groupSize` NPCs starting from `first`. Subsequent members are
    /// chosen by a score that prefers relationship strength (positive or
    /// strongly negative — beef makes for spicy convos too) and topic
    /// overlap.
    private func pickGroup(starting first: ShopNPC, from pool: [ShopNPC], groupSize: Int) -> [ShopNPC] {
        var result: [ShopNPC] = [first]
        var remaining = pool.filter { $0 !== first }

        while result.count < groupSize, !remaining.isEmpty {
            let scored: [(ShopNPC, CGFloat)] = remaining.map { cand in
                let score = pairingScore(cand, against: result)
                return (cand, score)
            }
            // Soft-weighted pick (no hard greedy max — keeps it varied).
            let total = scored.map { max(0.01, $0.1) }.reduce(0, +)
            let r = CGFloat.random(in: 0...total)
            var acc: CGFloat = 0
            var picked: ShopNPC = scored[0].0
            for (cand, w) in scored {
                acc += max(0.01, w)
                if r <= acc { picked = cand; break }
            }
            result.append(picked)
            remaining.removeAll { $0 === picked }
        }
        return result
    }

    /// Higher scores are more likely to be picked into the group with
    /// `existing`. Strong opinions (in either direction) score high
    /// because both friendly and hostile interactions are good drama.
    private func pairingScore(_ candidate: ShopNPC, against existing: [ShopNPC]) -> CGFloat {
        var score: CGFloat = 1.0
        for ex in existing {
            let aID = candidate.npcData.id
            let bID = ex.npcData.id

            // Relationship strength contributes |score| up to ~1.0 on each side.
            if let rowAtoB = SaveService.shared.getRelationship(of: aID, toward: bID) {
                score += min(1.5, CGFloat(abs(rowAtoB.score)) / 60.0)
                // Avoidant pairs are far less likely to randomly chat
                // unless the player's brought them together — knock score down.
                if rowAtoB.isAvoidant && !rowAtoB.isHostile {
                    score *= 0.5
                }
            }

            // Talkativeness: louder pair = higher chance.
            score += CGFloat(candidate.npcData.talkativeness + ex.npcData.talkativeness) * 0.5
        }
        return score
    }

    // MARK: - Running a Conversation (Host)

    private func startConversation(
        participants: [ShopNPC],
        participantData: [NPCData],
        topic: OpinionTopic?,
        in scene: SKScene,
        timeContext: TimeContext
    ) {
        let id = UUID().uuidString.prefix(8).lowercased()
        currentConversationID = String(id)
        currentParticipants = participantData
        currentParticipantNodes = participants.map { WeakShopNPC($0) }
        currentTopic = topic
        currentLines = []
        currentInteractions = []
        currentScene = scene
        state = .running(
            id: currentConversationID,
            participants: participantData.map { $0.id },
            started: CACurrentMediaTime(),
            linesPlayed: 0
        )

        let names = participantData.map { $0.name }.joined(separator: ", ")
        let topicLabel = topic?.label ?? "(open small talk)"
        Log.info(.dialogue, "[NPC convo \(currentConversationID)] starting: \(names) on '\(topicLabel)' — gathering")

        // Gather everyone into a huddle, THEN freeze and start lines.
        gatherParticipants(participants) { [weak self] in
            guard let self = self else { return }
            // Mid-conversation might have been interrupted while we were
            // walking — only proceed if we're still in `running` state with
            // zero lines played.
            guard case .running(_, _, _, let lineCount) = self.state, lineCount == 0 else {
                Log.debug(.dialogue, "[NPC convo \(self.currentConversationID)] gather completed but state moved on — skipping freeze/start")
                return
            }

            // Freeze everyone in place now that they've huddled. They
            // also stay frozen so they don't drift mid-conversation.
            for p in participants { p.freeze() }

            // Make participants face roughly toward the huddle center for
            // a tiny readability win. Done AFTER freeze() so the freeze
            // emphasis-scale doesn't clobber the mirror flip.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                self?.faceParticipantsTowardCenter(participants)
            }

            self.runNextLine(timeContext: timeContext)
        }
    }

    // MARK: - Gathering (huddle)

    /// Compute a huddle anchor (the participant centroid, biased toward
    /// the most-talkative member to act as the "social center") and ring
    /// positions around it. Dispatch each participant a `gatherTo`. Fire
    /// the completion when all have arrived OR the safety timeout elapses.
    private func gatherParticipants(
        _ participants: [ShopNPC],
        completion: @escaping () -> Void
    ) {
        guard !participants.isEmpty else { completion(); return }

        // Anchor: bias toward the most-talkative NPC's current position.
        // They're the natural focal point of the huddle.
        let anchorNPC = participants.max(by: { $0.npcData.talkativeness < $1.npcData.talkativeness })
            ?? participants[0]
        let centroid = participants.reduce(CGPoint.zero) { acc, npc in
            CGPoint(x: acc.x + npc.position.x, y: acc.y + npc.position.y)
        }
        let avg = CGPoint(
            x: centroid.x / CGFloat(participants.count),
            y: centroid.y / CGFloat(participants.count)
        )
        // 60/40 mix toward the anchor's position so the huddle forms
        // around the loudest one rather than purely at the geometric mean.
        let huddleCenter = CGPoint(
            x: avg.x * 0.4 + anchorNPC.position.x * 0.6,
            y: avg.y * 0.4 + anchorNPC.position.y * 0.6
        )

        // Ring positions for the non-anchor members. Spaced evenly around
        // the center, radius ~ 1 grid cell of separation. The anchor
        // stays roughly where they are (just snaps to nearest cell).
        let nonAnchors = participants.filter { $0 !== anchorNPC }
        let ringRadius: CGFloat = huddleRingRadius
        let count = max(1, nonAnchors.count)
        let ringPositions: [CGPoint] = (0..<count).map { i in
            let angle = (2 * CGFloat.pi) * (CGFloat(i) / CGFloat(count))
                       + CGFloat.random(in: -0.2...0.2) // slight jitter
            return CGPoint(
                x: huddleCenter.x + cos(angle) * ringRadius,
                y: huddleCenter.y + sin(angle) * ringRadius
            )
        }

        // Dispatch moves. Use an arrival-counter; complete when everyone
        // arrives OR the safety timeout fires — whichever first.
        let total = participants.count
        var arrived = 0
        var alreadyCompleted = false
        let conversationIDAtStart = currentConversationID
        let fire = { [weak self] in
            guard !alreadyCompleted else { return }
            // Bail if the conversation was interrupted/changed during gather.
            guard let self = self,
                  self.currentConversationID == conversationIDAtStart else {
                alreadyCompleted = true
                completion()
                return
            }
            alreadyCompleted = true
            completion()
        }

        // Anchor itself: snap to its current cell (no real walking needed).
        // We still call gatherTo so isGathering gets set and movement
        // controller stops any pending wander.
        anchorNPC.gatherTo(worldPoint: anchorNPC.position) {
            arrived += 1
            if arrived >= total { fire() }
        }

        for (i, npc) in nonAnchors.enumerated() {
            let target = ringPositions[i]
            npc.gatherTo(worldPoint: target) {
                arrived += 1
                if arrived >= total { fire() }
            }
        }

        // Safety timeout: don't let a wedged NPC hold up the whole
        // conversation forever.
        DispatchQueue.main.asyncAfter(deadline: .now() + huddleTimeoutSeconds) {
            fire()
        }
    }

    /// Cosmetic: orient each participant slightly toward the huddle
    /// center. Cheap, just rotates the sprite a little. No-op if NPC
    /// has no rotatable visual (skips silently).
    private func faceParticipantsTowardCenter(_ participants: [ShopNPC]) {
        guard participants.count > 1 else { return }
        let centroid = participants.reduce(CGPoint.zero) { acc, npc in
            CGPoint(x: acc.x + npc.position.x, y: acc.y + npc.position.y)
        }
        let center = CGPoint(
            x: centroid.x / CGFloat(participants.count),
            y: centroid.y / CGFloat(participants.count)
        )
        for npc in participants {
            // Mirror via xScale: face left if center is to our left,
            // right otherwise. Cheap and reads correctly for the emoji
            // sprites BaseNPC uses.
            let facingLeft = center.x < npc.position.x
            let absScale = abs(npc.emojiLabel.xScale)
            npc.emojiLabel.xScale = facingLeft ? -absScale : absScale
        }
    }

    /// Spacing between participants in the huddle ring (world points).
    private let huddleRingRadius: CGFloat = 56.0
    /// Hard cap on gather time so a stuck NPC can't wedge the conversation.
    private let huddleTimeoutSeconds: TimeInterval = 4.0

    private func runNextLine(timeContext: TimeContext) {
        guard case .running(_, _, _, let lineCount) = state else { return }
        guard let scene = currentScene else { return }

        // Stop early if cap hit.
        if lineCount >= maxLinesPerConversation {
            finalizeConversation(interruptedByPlayer: false, extraInteractions: [])
            return
        }

        // ---- Deterministic speaker selection (no LLM involvement) ----
        //
        // The previous design let the LLM pick the speakerID, which led to
        // it answering itself or attributing a line to one NPC while writing
        // it in another's voice. Instead, we pick the speaker here:
        //   - Opening line  : pick by talkativeness from the participant pool.
        //   - Otherwise     : pick anyone EXCEPT whoever spoke the last line.
        //                     Weighted by talkativeness + relationship pull
        //                     toward the previous speaker (so close friends
        //                     and active grudges respond more readily).
        let lastSpeakerID = currentLines.last?.speakerID
        let speaker = pickNextSpeaker(lastSpeakerID: lastSpeakerID)
        let addressedTo: NPCData? = {
            guard let lastID = lastSpeakerID,
                  lastID != speaker.id else { return nil }
            return currentParticipants.first { $0.id == lastID }
        }()
        let otherParticipants = currentParticipants.filter { $0.id != speaker.id }

        // Build the LLM prompt context.
        let relSummaries = buildRelationshipSummaries(among: currentParticipants)
        let priorLines = currentLines
        let priorLookup: [String: String] = Dictionary(
            uniqueKeysWithValues: currentParticipants.map { ($0.id, $0.name) }
        )

        guard let stream = LLMDialogueService.shared.streamConversationLine(
            speaker: speaker,
            addressedTo: addressedTo,
            otherParticipants: otherParticipants,
            topic: currentTopic,
            priorLines: priorLines,
            priorLineLookup: priorLookup,
            relationshipSummaries: relSummaries,
            timeContext: timeContext
        ) else {
            // No LLM available — fall back to a single canned line and stop.
            playFallbackLine(speaker: speaker, timeContext: timeContext)
            finalizeConversation(interruptedByPlayer: false, extraInteractions: [])
            return
        }

        currentLineTask = Task { @MainActor [weak self] in
            guard let self = self else { return }
            var finalLine: String = ""
            var finalMood: String? = nil
            var finalInteractionRaw: String? = nil
            var isClosingFinal = false

            do {
                for try await update in stream {
                    if let l = update.line { finalLine = l }
                    if let m = update.mood { finalMood = m }
                    if let i = update.interaction { finalInteractionRaw = i }
                    isClosingFinal = update.isClosing
                    if update.isComplete { break }
                }
            } catch {
                Log.warn(.dialogue, "[NPC convo] line stream failed: \(error). Falling back.")
                self.playFallbackLine(speaker: speaker, timeContext: timeContext)
                self.finalizeConversation(interruptedByPlayer: false, extraInteractions: [])
                return
            }

            // Strip any "Name:" prefix the model may slip in despite
            // instructions, and clean stray quote-wrapping.
            let cleaned = Self.cleanLine(finalLine, speakerName: speaker.name)
            guard !cleaned.isEmpty else {
                self.finalizeConversation(interruptedByPlayer: false, extraInteractions: [])
                return
            }

            // Post-flight echo guard. Foundation Models on a small device
            // sometimes parrots the previous line near-verbatim. If this
            // line is too similar to ANY of the last 2 lines, swap it for
            // a topic-shifting fallback so the conversation moves forward
            // instead of looping.
            let echoLimit = priorLines.suffix(2)
            let echoesPrior = echoLimit.contains { Self.linesAreSimilar($0.text, cleaned) }
            let lineToCommit: String
            let interactionToUse: String?
            let moodToUse: String?
            if echoesPrior {
                let topicShift = Self.topicShiftFallback(
                    speaker: speaker,
                    isNight: timeContext.isNight
                )
                Log.warn(.dialogue, "[NPC convo \(self.currentConversationID)] \(speaker.name) echoed prior line — substituting topic shift: \(topicShift)")
                lineToCommit = topicShift
                interactionToUse = ConversationInteraction.smallTalk.rawValue
                moodToUse = "neutral"
            } else {
                lineToCommit = cleaned
                interactionToUse = finalInteractionRaw
                moodToUse = finalMood
            }

            self.commitLine(
                speaker: speaker,
                text: lineToCommit,
                mood: moodToUse,
                interactionRaw: interactionToUse,
                isClosing: isClosingFinal,
                in: scene,
                timeContext: timeContext
            )
        }
    }

    /// Choose the next speaker. Excludes `lastSpeakerID` so a single NPC
    /// can't stack two lines in a row. Weighted by talkativeness and —
    /// when there's a `lastSpeakerID` — by how much each candidate would
    /// be moved to respond (close friends and active grudges weigh more).
    private func pickNextSpeaker(lastSpeakerID: String?) -> NPCData {
        let pool: [NPCData]
        if let last = lastSpeakerID {
            pool = currentParticipants.filter { $0.id != last }
        } else {
            pool = currentParticipants
        }
        guard !pool.isEmpty else {
            // Fallback (shouldn't happen with >=2 participants).
            return currentParticipants.randomElement() ?? currentParticipants[0]
        }

        // Only one option (2-way mid-conversation): strict alternation.
        if pool.count == 1 { return pool[0] }

        // Otherwise weight by talkativeness + (if there's a previous
        // speaker) relationship pull toward them.
        let weights: [CGFloat] = pool.map { cand in
            var w = max(0.05, CGFloat(cand.talkativeness))
            if let lastID = lastSpeakerID,
               let row = SaveService.shared.getRelationship(of: cand.id, toward: lastID) {
                // Strong feelings (either direction) make them speak up.
                w += min(1.5, CGFloat(abs(row.score)) / 50.0)
            }
            return w
        }
        let total = weights.reduce(0, +)
        let r = CGFloat.random(in: 0...total)
        var acc: CGFloat = 0
        for (i, w) in weights.enumerated() {
            acc += w
            if r <= acc { return pool[i] }
        }
        return pool.last ?? pool[0]
    }

    /// Defensive cleanup on what the LLM returned. Strips a leading
    /// "Name:" prefix and outer quotes if present — cosmetic safety net
    /// in case the model ignores the "don't prefix" instruction.
    private static func cleanLine(_ raw: String, speakerName: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        // Strip wrapping quotes if the model wrapped the whole thing.
        if s.hasPrefix("\"") && s.hasSuffix("\"") && s.count > 1 {
            s = String(s.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
        }

        // Strip a leading "Name:" or "Name -" prefix.
        let lower = s.lowercased()
        let nameLower = speakerName.lowercased()
        let prefixes = ["\(nameLower):", "\(nameLower) -", "\(nameLower) —", "\(nameLower) –"]
        for p in prefixes where lower.hasPrefix(p) {
            s = String(s.dropFirst(p.count)).trimmingCharacters(in: .whitespaces)
            break
        }
        return s
    }

    /// Token-overlap similarity check. Two lines are "similar" if they
    /// share more than 60% of their non-trivial words. Catches both
    /// verbatim echoes and light paraphrases like
    ///   A: "Like pearls in a cup, or stepping stones in a river."
    ///   B: "Pearls like stepping stones in a river."
    private static func linesAreSimilar(_ a: String, _ b: String) -> Bool {
        let stop: Set<String> = [
            "a", "an", "the", "and", "or", "of", "in", "on", "at", "to",
            "is", "it", "its", "as", "like", "with", "this", "that", "i",
            "my", "you", "your", "so", "but", "just", "for", "are", "was",
            "be", "yes", "oh", "well", "some", "any", "have", "had"
        ]
        func tokens(_ s: String) -> Set<String> {
            let cleaned = s.lowercased().unicodeScalars.map { scalar -> Swift.Character in
                let c = Swift.Character(String(scalar))
                if c.isLetter || c == " " { return c }
                return " "
            }
            let words = String(cleaned).split(separator: " ").map(String.init)
            return Set(words.filter { $0.count > 2 && !stop.contains($0) })
        }
        let ta = tokens(a)
        let tb = tokens(b)
        guard !ta.isEmpty, !tb.isEmpty else { return false }
        let intersect = ta.intersection(tb).count
        let smaller = min(ta.count, tb.count)
        guard smaller > 0 else { return false }
        let overlap = Double(intersect) / Double(smaller)
        return overlap > 0.6
    }

    /// Pre-baked topic-shifting lines used when the LLM produces an echo.
    /// They explicitly steer AWAY from boba imagery toward something
    /// concrete — the path, the cabin, the weather, a neighbor — to
    /// jolt the conversation out of a loop. Day vs night for atmosphere.
    private static func topicShiftFallback(speaker: NPCData, isNight: Bool) -> String {
        let day = [
            "Did you take the loop trail today, or the ridge?",
            "My porch creaked something awful this morning.",
            "The wind smelled like rain about an hour ago.",
            "I keep meaning to fix that gate behind my cabin.",
            "There's a stump near the creek I've been watching all week.",
            "The light through the trees hits different this time of year.",
            "Have you been past the deeper woods lately?",
            "My kettle's been whistling weird. I think it's tired.",
            "Saw three crows on the same branch this morning. Felt like an omen.",
            "I almost tripped on a root I swear wasn't there yesterday."
        ]
        let night = [
            "The path back home felt longer tonight.",
            "I latched my shutters twice before I came over.",
            "Did you hear that owl earlier, the one to the west?",
            "Something rustled near the gnome path. Probably nothing.",
            "My candles kept guttering even with the door shut.",
            "The trees felt strange tonight. Couldn't tell you why.",
            "I almost turned around halfway here.",
            "There's a quiet that settles in past dusk that I don't love.",
            "I thought I heard footsteps behind me on the way over.",
            "The lanterns up the path were swinging without any wind."
        ]
        let pool = isNight ? night : day
        return pool.randomElement() ?? pool[0]
    }

    /// Apply a finalized line — render bubble locally, broadcast to remote,
    /// move opinion scores, then schedule the next line (or finalize).
    private func commitLine(
        speaker: NPCData,
        text: String,
        mood: String?,
        interactionRaw: String?,
        isClosing: Bool,
        in scene: SKScene,
        timeContext: TimeContext
    ) {
        guard case .running(let id, let parts, let started, let lineCount) = state else { return }

        // Bump line count.
        state = .running(id: id, participants: parts, started: started, linesPlayed: lineCount + 1)
        currentLines.append((speakerID: speaker.id, text: text))

        // Apply opinion deltas: speaker → each listener.
        let interaction = ConversationInteraction(rawValue: interactionRaw ?? "")
            ?? .smallTalk
        for listener in currentParticipants where listener.id != speaker.id {
            SaveService.shared.applyConversationInteraction(
                speaker: speaker.id,
                listener: listener.id,
                interaction: interaction,
                incrementConversationCount: false
            )
            currentInteractions.append((speakerID: speaker.id, listenerID: listener.id, interaction: interaction))
        }

        // Render locally.
        if let speakerNode = findShopNPCNode(npcID: speaker.id, in: scene)
            ?? findForestNPCNode(npcID: speaker.id, in: scene) {
            DialogueService.shared.showConversationLine(
                speakerNode: speakerNode,
                speakerName: speaker.name,
                text: text,
                mood: mood,
                in: scene
            )
        }

        // Broadcast to guest.
        if MultiplayerService.shared.isHost && MultiplayerService.shared.isConnected {
            let speakerNode = findShopNPCNode(npcID: speaker.id, in: scene)
                ?? findForestNPCNode(npcID: speaker.id, in: scene)
            let pos = speakerNode?.position ?? .zero
            MultiplayerService.shared.send(
                type: .npcConversationLine,
                payload: NPCConversationLineMessage(
                    conversationID: currentConversationID,
                    speakerNPCID: speaker.id,
                    speakerName: speaker.name,
                    listenerNPCIDs: currentParticipants.filter { $0.id != speaker.id }.map { $0.id },
                    text: text,
                    mood: mood,
                    position: CodablePoint(pos),
                    sceneType: DialogueService.sceneTypeKey(for: scene),
                    isClosing: isClosing
                )
            )
        }

        Log.info(.dialogue, "[NPC convo \(currentConversationID)] \(speaker.name): \(text) [\(interaction.rawValue)]")

        // Decide what's next.
        let played = lineCount + 1
        let earlyExit = isClosing && played >= minLinesPerConversation
        let hardCap = played >= maxLinesPerConversation
        if earlyExit || hardCap {
            // Wait a beat so the bubble is readable, then finalize.
            DispatchQueue.main.asyncAfter(deadline: .now() + secondsBetweenLines) { [weak self] in
                self?.finalizeConversation(interruptedByPlayer: false, extraInteractions: [])
            }
        } else {
            // Schedule next line.
            DispatchQueue.main.asyncAfter(deadline: .now() + secondsBetweenLines) { [weak self] in
                self?.runNextLine(timeContext: timeContext)
            }
        }
    }

    /// Fallback when the LLM is unavailable — play one canned line from
    /// the chosen speaker and end. Better than nothing.
    private func playFallbackLine(speaker: NPCData, timeContext: TimeContext) {
        guard let scene = currentScene else { return }
        let text = speaker.getRandomDialogue(isNight: timeContext.isNight)
        if let speakerNode = findShopNPCNode(npcID: speaker.id, in: scene)
            ?? findForestNPCNode(npcID: speaker.id, in: scene) {
            DialogueService.shared.showConversationLine(
                speakerNode: speakerNode,
                speakerName: speaker.name,
                text: text,
                mood: nil,
                in: scene
            )
        }
        Log.info(.dialogue, "[NPC convo \(currentConversationID)] [Fallback JSON] \(speaker.name): \(text)")
    }

    // MARK: - Finalization

    private func finalizeConversation(
        interruptedByPlayer: Bool,
        extraInteractions: [NPCConversationEndedMessage.Entry]
    ) {
        guard case .running(let id, let parts, _, _) = state else { return }

        // Cancel any in-flight line stream so it can't pump after the end.
        currentLineTask?.cancel()
        currentLineTask = nil

        // Bump the conversation count once per pair (already applied
        // line-deltas; this is the once-per-conversation tick).
        let pairs = orderedPairs(in: parts)
        for (a, b) in pairs {
            if let row = SaveService.shared.getRelationship(of: a, toward: b) {
                row.conversationCount += 1
            }
        }

        // Set per-NPC cooldowns.
        let until = CACurrentMediaTime() + perNPCCooldownSeconds
        for npcID in parts { cooldowns[npcID] = until }

        // Clear the gather-lock on every participant node and unfreeze
        // them. Both must happen so the state machine resumes cleanly.
        for box in currentParticipantNodes {
            guard let npc = box.ref else { continue }
            npc.clearGathering()
            npc.unfreeze()
        }

        // Belt-and-suspenders: also unfreeze any matching NPCs in the
        // scene by name lookup, in case our weak refs have gone stale
        // (e.g. NPC left the shop mid-conversation).
        if let scene = currentScene {
            scene.enumerateChildNodes(withName: "npc_*") { node, _ in
                if let npc = node as? BaseNPC,
                   parts.contains(npc.npcData.id) {
                    npc.unfreeze()
                }
            }
        }

        // Broadcast end.
        if MultiplayerService.shared.isHost && MultiplayerService.shared.isConnected {
            let allEntries = currentInteractions.map {
                NPCConversationEndedMessage.Entry(
                    speaker: $0.speakerID,
                    listener: $0.listenerID,
                    interaction: $0.interaction.rawValue
                )
            } + extraInteractions
            MultiplayerService.shared.send(
                type: .npcConversationEnded,
                payload: NPCConversationEndedMessage(
                    conversationID: id,
                    participants: parts,
                    interactions: allEntries,
                    interruptedByPlayer: interruptedByPlayer
                )
            )
        }

        Log.info(.dialogue, "[NPC convo \(id)] ended (interruptedByPlayer=\(interruptedByPlayer), lines=\(currentLines.count))")

        // Reset.
        state = .idle
        currentParticipants = []
        currentParticipantNodes = []
        currentTopic = nil
        currentLines = []
        currentInteractions = []
        currentConversationID = ""
        currentScene = nil
    }

    // MARK: - Helpers

    /// Build a short list of human-readable relationship hints for the
    /// LLM prompt. Includes only notable scores so we don't drown the
    /// model in 12 boring rows.
    private func buildRelationshipSummaries(among participants: [NPCData]) -> [String] {
        var out: [String] = []
        for a in participants {
            for b in participants where a.id != b.id {
                guard let row = SaveService.shared.getRelationship(of: a.id, toward: b.id) else { continue }
                if row.isClose {
                    out.append("\(a.name) is close with \(b.name) (\(row.score))")
                } else if row.isFriendly {
                    out.append("\(a.name) likes \(b.name) (\(row.score))")
                } else if row.isHostile {
                    out.append("\(a.name) is hostile toward \(b.name) (\(row.score))")
                } else if row.isAvoidant {
                    out.append("\(a.name) is wary of \(b.name) (\(row.score))")
                }
            }
        }
        return out
    }

    /// All ordered (a, b) pairs in `npcIDs` where a != b. Used to bump
    /// per-pair conversation counts and to layer awkward-silence
    /// penalties across the whole group on player interruption.
    private func orderedPairs(in npcIDs: [String]) -> [(String, String)] {
        var pairs: [(String, String)] = []
        for a in npcIDs {
            for b in npcIDs where a != b {
                pairs.append((a, b))
            }
        }
        return pairs
    }

    private func findShopNPCNode(npcID: String, in scene: SKScene) -> SKNode? {
        var hit: SKNode?
        scene.enumerateChildNodes(withName: "npc_*") { node, stop in
            if let npc = node as? BaseNPC, npc.npcData.id == npcID {
                hit = npc
                stop.pointee = true
            }
        }
        return hit
    }

    private func findForestNPCNode(npcID: String, in scene: SKScene) -> SKNode? {
        return scene.children.compactMap { $0 as? ForestNPCEntity }
                              .first(where: { $0.npcData.id == npcID })
    }
}

// MARK: - Weak ShopNPC Box

/// Tiny weak-ref wrapper so the conversation service can hold the live
/// ShopNPC nodes for `clearGathering()` and friends without retaining
/// them past their scene lifetime.
private final class WeakShopNPC {
    weak var ref: ShopNPC?
    init(_ npc: ShopNPC) { self.ref = npc }
}
