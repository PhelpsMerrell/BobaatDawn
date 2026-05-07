//
//  GnomeConversationService.swift
//  BobaAtDawn
//
//  Drives ambient gnome ↔ gnome chatter and player ↔ gnome dialogue.
//  Sister to NPCConversationService but with a fully separate prompt
//  and LLM service (LLMGnomeDialogueService) so gnome lines feel
//  distinct from the forest-villager NPCs.
//
//  Architecture mirrors NPCConversationService:
//  - Host-authoritative scheduling.
//  - Each line is broadcast to the guest as a `gnomeConversationLine`.
//  - Player tap on a participating gnome interrupts (`interruptByPlayer`).
//
//  The service is lighter on machinery than its NPC sibling — gnomes
//  don't have pairwise opinion-score rows or satisfaction tracking.
//  Their voice instead comes from the JSON-backed `GnomeData`
//  (personality, traits, speech_quirks, lore, voice_lines) reachable
//  via `agent.identity.data`, which `LLMGnomeDialogueService` splices
//  into prompts as RAG context.
//
//  Eligibility: conversations only fire among gnomes who are visibly
//  not actively working — sleeping, idle, supervising, hauling the
//  cart, or celebrating. Anyone commuting, looking, carrying, using
//  the machine, or dumping is excluded so the simulation visibly
//  keeps moving when the player is watching.
//
//  LLM fallback: every LLM call falls back to a hardcoded pool in
//  `GnomePoolLines` whenever the model is unavailable, errors mid-
//  stream, or returns an empty line. The pools are deliberately
//  specific to mining/rocks/oak so the fallback voice still sounds
//  right.
//

import SpriteKit
import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

// MARK: - Conversation State

private enum GnomeConvoState {
    case idle
    case running(id: String, participantIDs: [String], startedAt: TimeInterval, linesPlayed: Int)
}

// MARK: - Service

final class GnomeConversationService {

    static let shared = GnomeConversationService()

    // MARK: - Tunables

    /// How often (real seconds) the host scans for a new conversation
    /// when none is running. Slower than the NPC version because gnomes
    /// chat in pairs near each other, not as part of a busy shop crowd.
    private let scanInterval: TimeInterval = 10.0

    /// After a conversation ends, both gnomes go on cooldown.
    private let perGnomeCooldown: TimeInterval = 90.0

    /// Conversation length cap.
    private let maxLines = 4
    private let minLines = 2

    /// Beat between lines.
    private let secondsBetweenLines: TimeInterval = 4.5

    // MARK: - State

    private var state: GnomeConvoState = .idle
    private var lastScanAt: TimeInterval = 0

    /// Per-gnome chat cooldown — id → eligible-again-time.
    private var cooldowns: [String: TimeInterval] = [:]

    /// Live conversation bookkeeping (host).
    private var currentParticipants: [GnomeAgent] = []
    private var currentLines: [(speakerID: String, text: String)] = []
    private var currentConversationID: String = ""
    private var currentLineTask: Task<Void, Never>?
    private weak var currentScene: SKScene?

    private init() {}

    // MARK: - Entry: Per-frame Tick

    /// Called from CaveScene + BigOakTreeScene + ForestScene `update`. Cheap
    /// when nothing's happening. Solo/host only — guests render lines
    /// from incoming network messages.
    func tick(in scene: SKScene, agents: [GnomeAgent]) {
        guard !MultiplayerService.shared.isGuest else { return }
        if DialogueService.shared.isDialogueActive() { return }
        if case .running = state { return }

        let now = CACurrentMediaTime()
        if now - lastScanAt < scanInterval { return }
        lastScanAt = now

        scheduleConversationIfPossible(in: scene, agents: agents)
    }

    /// Called by the player tapping a participating gnome — interrupts
    /// the current conversation immediately.
    func interruptByPlayer() {
        guard case .running(let id, let parts, _, _) = state else { return }
        Log.info(.dialogue, "[Gnome convo] Player interrupted \(id)")
        currentLineTask?.cancel()
        currentLineTask = nil

        // Apply cooldowns + clear state.
        let now = CACurrentMediaTime()
        for pid in parts {
            cooldowns[pid] = now + perGnomeCooldown
        }
        // Unfreeze any participants we have nodes for.
        for agent in currentParticipants {
            agent.sceneNode?.unfreeze()
        }
        currentParticipants.removeAll()
        currentLines.removeAll()
        currentConversationID = ""
        state = .idle

        // Tell the guest to clear too.
        if MultiplayerService.shared.isHost,
           MultiplayerService.shared.isConnected {
            MultiplayerService.shared.send(
                type: .gnomeConversationEnded,
                payload: GnomeConversationEndedMessage(
                    conversationID: id,
                    participants: parts,
                    interruptedByPlayer: true
                )
            )
        }
    }

    // MARK: - Player → Gnome Dialogue

    /// Player tapped a single gnome. Streams a fresh LLM line (using
    /// the gnome's JSON-backed personality as RAG) and renders it via
    /// the existing DialogueService bubble. Falls back to a hardcoded
    /// pool line when Apple Intelligence isn't available, when the
    /// stream errors out, or when the model returns an empty line.
    ///
    /// The bubble is created up front with a "..." placeholder so the
    /// player gets immediate feedback (and so `isDialogueActive()` is
    /// true while the model is thinking — preventing rapid re-taps on
    /// other gnomes from queuing up parallel streams).
    func showPlayerDialogue(
        for agent: GnomeAgent,
        in scene: SKScene,
        timeContext: TimeContext
    ) {
        // Boss daily promotion/demotion line takes priority — pre-baked,
        // render it immediately and skip the LLM.
        if agent.identity.role == .boss,
           let bossLine = GnomeManager.shared.todaysBossLine {
            renderPlayerDialogue(for: agent, text: bossLine, mood: "delighted", in: scene)
            return
        }

        // Try the LLM. If unavailable on this device, render a pool
        // line synchronously and we're done.
        guard let stream = LLMGnomeDialogueService.shared.streamSinglePlayerLine(
            for: agent, timeContext: timeContext
        ) else {
            let line = fallbackLine(for: agent, timeContext: timeContext)
            renderPlayerDialogue(for: agent, text: line, mood: "neutral", in: scene)
            return
        }

        // Show a placeholder bubble immediately. This (a) signals to the
        // player that their tap registered, (b) makes
        // `isDialogueActive()` return true so a second rapid tap on
        // another gnome is gated, and (c) reserves the bubble slot for
        // this gnome id — `showStaticDialogue` re-renders the same slot
        // when the stream completes.
        renderPlayerDialogue(for: agent, text: "...", mood: "neutral", in: scene)

        // Collect the stream, then re-render the bubble with the final
        // line. If the stream errors or comes back empty, swap in a
        // pool line so the player isn't left staring at the placeholder.
        Task { @MainActor [weak self] in
            var finalLine = ""
            var finalMood = "neutral"
            do {
                for try await update in stream {
                    if let l = update.line { finalLine = l }
                    if let m = update.mood { finalMood = m }
                    if update.isComplete { break }
                }
            } catch {
                Log.warn(.dialogue, "[Gnome convo] player-line stream failed: \(error)")
            }
            let cleaned = finalLine.trimmingCharacters(in: .whitespacesAndNewlines)
            let lineToShow: String
            let moodToShow: String
            if cleaned.isEmpty {
                lineToShow = self?.fallbackLine(for: agent, timeContext: timeContext) ?? "..."
                moodToShow = "neutral"
            } else {
                lineToShow = cleaned
                moodToShow = finalMood
            }
            // Bail if the gnome left the scene during the wait, or the
            // placeholder bubble has already been auto-dismissed (player
            // walked away, scene change, etc.).
            guard agent.sceneNode != nil else { return }
            guard DialogueService.shared.isDialogueActive(forNPCID: agent.identity.id) else { return }
            self?.renderPlayerDialogue(for: agent, text: lineToShow, mood: moodToShow, in: scene)
        }
    }

    /// Render (or replace) the bubble for a player → gnome tap. The
    /// DialogueService keys bubbles by NPC id, so calling this twice in
    /// a row swaps the displayed text in place — that's how the
    /// streaming path replaces "..." with the final LLM line.
    private func renderPlayerDialogue(
        for agent: GnomeAgent,
        text: String,
        mood: String,
        in scene: SKScene
    ) {
        guard let presenter = agent.sceneNode else { return }
        DialogueService.shared.showStaticDialogue(
            for: presenter,
            speakerName: agent.fullDisplayName,
            text: text,
            mood: mood,
            in: scene
        )
    }

    // MARK: - Scheduling Conversations

    private func scheduleConversationIfPossible(in scene: SKScene, agents: [GnomeAgent]) {
        let now = CACurrentMediaTime()

        // Only consider gnomes that are visible (have a scene node), share
        // the same logical room, and are not on cooldown. CRITICALLY: only
        // gnomes whose task is "at rest" — sleeping, idle, or supervising —
        // are eligible. Anyone in a working/walking state stays moving so
        // the simulation looks alive when the player is watching.
        let eligible = agents.filter { agent in
            guard agent.sceneNode != nil else { return false }
            if let until = cooldowns[agent.identity.id], until > now { return false }

            // Commuters who are staged in the oak with a future start time
            // are effectively "gathering up" before they head out, so let
            // them chat during that visible pause.
            if agent.task == .commutingToMine,
               case .oakRoom = agent.location,
               agent.taskStartedAt > now {
                return true
            }

            switch agent.task {
            case .sleeping, .idle, .supervising,
                 .haulingCart, .celebrating:
                // Resting, parading, or celebrating — chat away.
                return true
            case .commutingToMine, .commutingHome,
                 .lookingForRock,
                 .carryingRockToMachine, .carryingGemToTreasury,
                 .depositingGemAtCart, .dumpingRockInWasteBin,
                 .gatheringForCartTrip, .usingMachine:
                return false
            }
        }

        guard eligible.count >= 2 else { return }

        // Group by location and pick a 2-gnome pair from a populated room.
        let byLocation = Dictionary(grouping: eligible, by: { $0.location })
        let groups = byLocation.values.filter { $0.count >= 2 }
        guard let group = groups.randomElement() else { return }
        let pair = Array(group.shuffled().prefix(2))

        startConversation(participants: pair, in: scene)
    }

    private func startConversation(participants: [GnomeAgent], in scene: SKScene) {
        let id = UUID().uuidString
        currentConversationID = id
        currentParticipants = participants
        currentLines.removeAll()
        currentScene = scene

        // Freeze all participants so they don't wander mid-line.
        for agent in participants {
            agent.sceneNode?.freeze()
        }

        let now = CACurrentMediaTime()
        state = .running(id: id, participantIDs: participants.map { $0.identity.id },
                         startedAt: now, linesPlayed: 0)

        Log.info(.dialogue, "[Gnome convo] Starting \(id) with \(participants.map { $0.identity.displayName }.joined(separator: ", "))")

        // Kick off line 0.
        playNextLine()
    }

    private func playNextLine() {
        guard case .running(let id, _, _, let played) = state else { return }
        guard played < maxLines else {
            endConversation()
            return
        }
        guard let scene = currentScene else { return }

        // Speaker rotation: strict alternation between the two participants.
        let speaker = currentParticipants[played % currentParticipants.count]
        let listener = currentParticipants[(played + 1) % currentParticipants.count]

        let timeContext: TimeContext = TimeManager.shared.currentPhase == .night ? .night : .day

        // Try the LLM first. On unavailability, fall back to a pool
        // line and commit it immediately. The same pool path is used as
        // the safety net inside the streaming Task below.
        guard let stream = LLMGnomeDialogueService.shared.streamGnomeConversationLine(
            speaker: speaker,
            addressedTo: listener,
            otherParticipants: currentParticipants.filter { $0.identity.id != speaker.identity.id },
            priorLines: currentLines,
            timeContext: timeContext
        ) else {
            let lineText = generateGnomeChatterLine(
                speaker: speaker,
                listener: listener,
                priorLines: currentLines,
                timeContext: timeContext
            )
            commitConversationLine(
                speaker: speaker, text: lineText, mood: "neutral",
                in: scene, timeContext: timeContext
            )
            return
        }

        // LLM in flight. Replace any pending sleep/scheduling task with
        // the streaming task so `interruptByPlayer` cancels the right
        // thing if the player taps mid-stream.
        currentLineTask?.cancel()
        let conversationIDAtStart = id
        currentLineTask = Task { @MainActor [weak self] in
            guard let self = self else { return }
            var finalLine = ""
            var finalMood = "neutral"
            do {
                for try await update in stream {
                    if Task.isCancelled { return }
                    if let l = update.line { finalLine = l }
                    if let m = update.mood { finalMood = m }
                    if update.isComplete { break }
                }
            } catch {
                Log.warn(.dialogue, "[Gnome convo] line stream failed: \(error)")
            }

            // Bail if the conversation was interrupted/ended while we
            // were streaming.
            guard case .running(let curID, _, _, _) = self.state,
                  curID == conversationIDAtStart else {
                return
            }

            let cleaned = finalLine.trimmingCharacters(in: .whitespacesAndNewlines)
            let lineToCommit: String
            let moodToCommit: String
            if cleaned.isEmpty {
                // Empty / failed → pool fallback so the conversation
                // keeps flowing instead of dropping a line.
                lineToCommit = self.generateGnomeChatterLine(
                    speaker: speaker, listener: listener,
                    priorLines: self.currentLines, timeContext: timeContext
                )
                moodToCommit = "neutral"
            } else {
                lineToCommit = cleaned
                moodToCommit = finalMood
            }
            self.commitConversationLine(
                speaker: speaker, text: lineToCommit, mood: moodToCommit,
                in: scene, timeContext: timeContext
            )
        }
    }

    /// Apply a finalized conversation line: render the bubble locally,
    /// broadcast to guest, bump the line count, then schedule the next
    /// line (or end on cap). Shared by both the LLM-success path and
    /// the pool-fallback path so the multiplayer/state-machine plumbing
    /// only lives in one place.
    private func commitConversationLine(
        speaker: GnomeAgent,
        text: String,
        mood: String,
        in scene: SKScene,
        timeContext: TimeContext
    ) {
        guard case .running(let id, let parts, let started, let played) = state else { return }

        currentLines.append((speakerID: speaker.identity.id, text: text))

        renderLineLocally(speaker: speaker, text: text, mood: mood, in: scene)
        if MultiplayerService.shared.isHost,
           MultiplayerService.shared.isConnected {
            MultiplayerService.shared.send(
                type: .gnomeConversationLine,
                payload: GnomeConversationLineMessage(
                    conversationID: id,
                    speakerGnomeID: speaker.identity.id,
                    speakerName: speaker.fullDisplayName,
                    listenerGnomeIDs: currentParticipants
                        .filter { $0.identity.id != speaker.identity.id }
                        .map { $0.identity.id },
                    text: text,
                    mood: mood,
                    position: CodablePoint(speaker.sceneNode?.position ?? .zero),
                    sceneType: DialogueService.sceneTypeKey(for: scene),
                    isClosing: played + 1 >= maxLines
                )
            )
        }

        state = .running(id: id, participantIDs: parts, startedAt: started, linesPlayed: played + 1)

        // Schedule the next line beat (or end on cap). Reuses the
        // currentLineTask slot — `interruptByPlayer` cancels this if
        // the player taps in.
        currentLineTask?.cancel()
        let nextDelay = secondsBetweenLines
        currentLineTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(nextDelay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await MainActor.run { self?.playNextLine() }
        }
    }

    private func renderLineLocally(speaker: GnomeAgent, text: String, mood: String, in scene: SKScene) {
        guard let presenter = speaker.sceneNode else { return }
        DialogueService.shared.showStaticDialogue(
            for: presenter,
            speakerName: speaker.fullDisplayName,
            text: text,
            mood: mood,
            in: scene
        )
    }

    private func endConversation() {
        guard case .running(let id, let parts, _, _) = state else { return }
        let now = CACurrentMediaTime()
        for pid in parts {
            cooldowns[pid] = now + perGnomeCooldown
        }
        for agent in currentParticipants {
            agent.sceneNode?.unfreeze()
        }
        if MultiplayerService.shared.isHost,
           MultiplayerService.shared.isConnected {
            MultiplayerService.shared.send(
                type: .gnomeConversationEnded,
                payload: GnomeConversationEndedMessage(
                    conversationID: id,
                    participants: parts,
                    interruptedByPlayer: false
                )
            )
        }
        DialogueService.shared.dismissDialogue()
        currentParticipants.removeAll()
        currentLines.removeAll()
        currentConversationID = ""
        state = .idle
        Log.info(.dialogue, "[Gnome convo] Ended \(id)")
    }

    // MARK: - Remote Line Handler (Guest-Side)

    /// Apply a line broadcast from the host. Renders locally over the
    /// matching gnome's visual if we have one in this scene.
    func handleRemoteLine(_ msg: GnomeConversationLineMessage, in scene: SKScene) {
        guard let agent = GnomeManager.shared.agent(byID: msg.speakerGnomeID) else { return }
        guard let node = agent.sceneNode else { return }
        DialogueService.shared.showStaticDialogue(
            for: node,
            speakerName: msg.speakerName,
            text: msg.text,
            mood: msg.mood,
            in: scene
        )
    }

    func handleRemoteEnd(_ msg: GnomeConversationEndedMessage) {
        DialogueService.shared.dismissDialogue()
    }

    // MARK: - Line Generation (Hardcoded Pool — Fallback Only)
    //
    // Used whenever the LLM is unavailable (pre-iOS 26 / unsupported
    // device), errors mid-stream, or returns an empty line. The pools
    // are deliberately specific to mining/rocks/oak so the fallback
    // voice still feels in-character. Once the LLM RAG path is fully
    // tuned, these can shrink — but they should never disappear:
    // they're what keeps the conversation flowing on devices without
    // Apple Intelligence.

    private func generateGnomeChatterLine(
        speaker: GnomeAgent,
        listener: GnomeAgent,
        priorLines: [(speakerID: String, text: String)],
        timeContext: TimeContext
    ) -> String {
        // Avoid repeats — collect the recent line text and re-roll if a
        // pick collides (up to 3 tries).
        let recent = Set(priorLines.suffix(3).map { $0.text })
        for _ in 0..<3 {
            let pick = pickPoolLine(speaker: speaker, listener: listener, timeContext: timeContext)
            if !recent.contains(pick) { return pick }
        }
        return pickPoolLine(speaker: speaker, listener: listener, timeContext: timeContext)
    }

    private func pickPoolLine(
        speaker: GnomeAgent,
        listener: GnomeAgent,
        timeContext: TimeContext
    ) -> String {
        // Boss-flavored lines win when the boss is the speaker.
        if speaker.identity.role == .boss {
            return GnomePoolLines.bossLines.randomElement() ?? "Pick up the pace."
        }

        // Housekeeper-flavored lines — they don't see rocks all day.
        if speaker.identity.role == .housekeeper {
            let pool = (timeContext == .night)
                ? GnomePoolLines.housekeeperNight
                : GnomePoolLines.housekeeperDay
            return pool.randomElement() ?? "Mm."
        }

        // Miner pool — switches by location: oak (resting), cave (working), forest (transit).
        switch speaker.location {
        case .caveRoom:
            return GnomePoolLines.minerInCave.randomElement() ?? "This rock has a face."
        case .oakRoom:
            return GnomePoolLines.minerAtHome.randomElement() ?? "Long shift today."
        case .forestRoom:
            return GnomePoolLines.minerInTransit.randomElement() ?? "Almost there."
        }
    }

    private func fallbackLine(for agent: GnomeAgent, timeContext: TimeContext) -> String {
        switch agent.identity.role {
        case .boss:
            return GnomePoolLines.bossLines.randomElement() ?? "Stay sharp."
        case .miner:
            return (timeContext == .night
                    ? GnomePoolLines.minerAtHome.randomElement()
                    : GnomePoolLines.minerInCave.randomElement())
                ?? "Rocks today, rocks tomorrow."
        case .housekeeper:
            return (timeContext == .night
                    ? GnomePoolLines.housekeeperNight.randomElement()
                    : GnomePoolLines.housekeeperDay.randomElement())
                ?? "Mind the floor — fresh polished."
        }
    }
}

// MARK: - Hardcoded Line Pools

private enum GnomePoolLines {

    // Boss — gruff, fair, occasionally fond
    static let bossLines: [String] = [
        "Pick up the pace, you lot.",
        "Good rock today. Real good rock.",
        "Don't drop it. Don't you DARE drop it.",
        "Machine's in a mood. Be patient.",
        "I want fifty by sundown. Or close.",
        "Whoever found that one — solid work.",
        "Easy on the new ones. Show 'em the technique.",
        "Reds happen. Don't take it personal.",
        "You earn your gem, the gem earns you.",
        "Keep your head down and your hands moving."
    ]

    // Miner lines while in cave (working)
    static let minerInCave: [String] = [
        "This one's heavy. Heavy means good, sometimes.",
        "Smell that? That's wet stone. Best smell.",
        "I named this one. Don't tell Thork.",
        "Three reds in a row. THREE.",
        "I love a rock with character.",
        "The deeper floors hum, you ever notice?",
        "Pip dropped one again. Bless him.",
        "Foreman watched me on that last green. Saw me.",
        "Going up. My back's going up too.",
        "Quiet down there today. Almost peaceful.",
        "Fenn keeps counting them. He counts EVERYTHING.",
        "Nice and round, this one. Round ones go green more, you'll see.",
        "Gritty floor today. Mind your boots.",
        "I've got a feeling about the next rock.",
        "Hold this for a sec — I dropped my pick.",
        "There's a vein on the third floor. Real proper vein."
    ]

    // Miner lines at home (oak — resting / sleeping)
    static let minerAtHome: [String] = [
        "Bones are tired. Bones are happy.",
        "That stew tonight was something else.",
        "Long shift. Worth it. I think.",
        "I keep gem dust in my beard. On purpose.",
        "Tomorrow I'm aiming for ten greens.",
        "Couch is good. Couch is real good.",
        "Boss looked at me twice today. Means something.",
        "I dreamed of a giant rock last night.",
        "Hearth's warm. Anyone got a blanket?",
        "Pip's already asleep, snoring like a saw.",
        "Cook saved me a heel of bread. Don't tell.",
        "Rest day tomorrow? I forget."
    ]

    // Miner lines in transit (forest rooms)
    static let minerInTransit: [String] = [
        "Almost to the oak. Smell the smoke?",
        "This path's longer when you're carrying.",
        "Watch the roots. Watch the roots.",
        "Every day, this same walk. Every day.",
        "I like this stretch. Birds.",
        "Rain coming. I can feel it.",
        "One foot. Other foot. Repeat.",
        "Boss said don't dawdle. So I'm not.",
        "Treasury, here we come.",
        "Hand cramping. Worth it though."
    ]

    // Housekeeper day
    static let housekeeperDay: [String] = [
        "Fresh polish on the lobby floor — mind your boots.",
        "Bread's rising. Don't slam the door.",
        "I swept this morning. Twice.",
        "Greeter's at the door again. Always at the door.",
        "Stew's on for whoever's home tonight.",
        "Treasury's looking healthy this week.",
        "Whose mug is this? Always whose mug.",
        "I patched the curtain in the middle bedroom.",
        "Hearth needs another log. Always another log.",
        "Quiet morning. Suspicious."
    ]

    // Housekeeper night
    static let housekeeperNight: [String] = [
        "Miners back. Stew warm. Good night.",
        "I'll bank the fire low.",
        "Lock the door. Yes, properly. Yes, both bolts.",
        "Pip's already snoring. Bless him.",
        "Gems up there glow funny in the dark.",
        "Heard something outside. Probably the wind.",
        "Rest is rest. Don't waste it talking.",
        "Boss is up late again. Counting things."
    ]
}

// MARK: - DialogueService Static-Bubble Convenience
//
// `showStaticDialogue(for:speakerName:text:mood:in:)` lives directly on
// DialogueService now — see DialogueService.swift. The earlier extension
// here forwarded to `showRemoteDialogue`, which used a `"npc_*"` scene
// enumeration to set the dialogue anchor. Gnome nodes are named
// `"gnome_*"`, so that lookup quietly returned nil and the bubble was
// auto-dismissed on the next frame by the distance-check tick. The
// new impl anchors directly to the presenter, fixing tap-a-gnome dialog.
