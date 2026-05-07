//
//  LLMGnomeDialogueService.swift
//  BobaAtDawn
//
//  Apple Foundation Models hookup for gnome dialogue. Sister to
//  `LLMDialogueService` (which handles forest-villager NPCs); kept in
//  its own file because gnomes have a distinct setting, voice, and
//  schema — they live in the oak, work the mines, and are NOT ghost
//  customers.
//
//  RAG source
//  ----------
//  Per-gnome richness comes from `agent.identity.data` (a `GnomeData`
//  loaded from `Data/gnome_data.json` by `GnomeDataLoader`). The
//  prompt builder pulls personality/archetype/traits/speech_quirks/
//  voice_lines/lore/opinion_stances/explicit_relationships from that
//  record. Live runtime state (location, task, rank) comes from the
//  `GnomeAgent` itself.
//
//  Two methods
//  -----------
//  - `streamSinglePlayerLine(for:timeContext:)`
//      Player tapped a gnome. Generates ONE short line (no follow-ups,
//      no satisfaction system — gnomes don't have a kind/blunt loop).
//  - `streamGnomeConversationLine(speaker:addressedTo:otherParticipants:priorLines:timeContext:)`
//      Ambient gnome ↔ gnome chatter. Returns a fresh line in the
//      speaker's voice, with the previous lines as anti-echo context.
//
//  Both return `nil` on platforms without Apple Intelligence (pre-iOS
//  26 or unsupported devices). Callers fall back to the hardcoded
//  pool in `GnomePoolLines` when nil is returned.
//
//  Each call uses a fresh `LanguageModelSession`. Gnome dialogue is
//  short and the player↔gnome path is one-shot, so there's no
//  multi-turn session table or prewarm cache (unlike the NPC
//  pipeline). If/when gnomes get a turn-2 reply or a prewarm
//  optimization, it'd live here.
//

import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

// MARK: - Stream Update Type

/// Streamed update yielded by both gnome streaming methods. Mirrors
/// `DialogueStreamUpdate` but without `followups` (gnomes have none).
struct GnomeDialogueStreamUpdate {
    var line: String?
    var mood: String?
    var isComplete: Bool = false
}

// MARK: - Generable Schemas (iOS 26+)

#if canImport(FoundationModels)
@available(iOS 26.0, *)
@Generable
struct GeneratedGnomePlayerLine {
    @Guide(description: """
    What this gnome says to a person who has just walked up to them. \
    ONE short sentence, two at most. Plain working-class voice — \
    practical, sometimes gruff, sometimes warm. NOT poetic. NOT \
    flowery. Match the gnome's listed speech quirks closely if any \
    are provided. Reference rocks, gems, the mine, the oak, fellow \
    gnomes, the boss, food, sleep, or whatever fits the current \
    moment. Never reference a boba shop, drinks, pearls, ghosts, \
    death, or the afterlife — gnomes don't know about any of those.
    """)
    let line: String

    @Guide(.anyOf(["delighted", "happy", "neutral", "wistful", "anxious", "upset", "weary"]))
    let mood: String
}

@available(iOS 26.0, *)
@Generable
struct GeneratedGnomeConversationLineModel {
    @Guide(description: """
    What YOU (the speaker named in the prompt) say next to your \
    fellow gnome. ONE short sentence in your own voice. CRITICAL: do \
    NOT echo, paraphrase, or restate the previous speaker's line. \
    Add NEW content — a memory, a complaint, an observation, a small \
    disagreement, or change the subject to something specific (a \
    rock, a cave floor, the cook's stew, the boss's mood, a fellow \
    miner). Never prefix your line with your own name. Never speak \
    in another gnome's voice. Never reference a boba shop, drinks, \
    pearls, ghosts, death, or the afterlife.
    """)
    let line: String

    @Guide(.anyOf(["delighted", "happy", "neutral", "wistful", "anxious", "upset", "weary"]))
    let mood: String
}
#endif

// MARK: - Service

final class LLMGnomeDialogueService {

    static let shared = LLMGnomeDialogueService()
    private init() {}

    /// True when Apple's on-device LLM is usable. Reuses the same
    /// availability check as the NPC service so feature flags stay
    /// in lock-step.
    var isAvailable: Bool { LLMDialogueService.shared.isAvailable }

    // MARK: - Player → Gnome Single Line

    /// Stream the gnome's line for a player tap. Returns nil if Apple
    /// Intelligence isn't available; caller should fall back to
    /// `GnomePoolLines` in that case.
    func streamSinglePlayerLine(
        for agent: GnomeAgent,
        timeContext: TimeContext
    ) -> AsyncThrowingStream<GnomeDialogueStreamUpdate, Error>? {
        guard isAvailable else { return nil }
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            return _streamSinglePlayerLine(for: agent, timeContext: timeContext)
        }
        #endif
        return nil
    }

    // MARK: - Gnome ↔ Gnome Conversation Line

    /// Stream a single line of an ambient gnome ↔ gnome conversation in
    /// `speaker`'s voice. The conversation service picks the speaker
    /// deterministically; the model only writes the line. Prior lines
    /// are passed as context with explicit "do not echo" guard rails.
    func streamGnomeConversationLine(
        speaker: GnomeAgent,
        addressedTo: GnomeAgent?,
        otherParticipants: [GnomeAgent],
        priorLines: [(speakerID: String, text: String)],
        timeContext: TimeContext
    ) -> AsyncThrowingStream<GnomeDialogueStreamUpdate, Error>? {
        guard isAvailable else { return nil }
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            return _streamGnomeConversationLine(
                speaker: speaker,
                addressedTo: addressedTo,
                otherParticipants: otherParticipants,
                priorLines: priorLines,
                timeContext: timeContext
            )
        }
        #endif
        return nil
    }
}

// MARK: - iOS 26 Implementation

#if canImport(FoundationModels)
@available(iOS 26.0, *)
private extension LLMGnomeDialogueService {

    // MARK: - Player Line

    func _streamSinglePlayerLine(
        for agent: GnomeAgent,
        timeContext: TimeContext
    ) -> AsyncThrowingStream<GnomeDialogueStreamUpdate, Error> {
        let instructions = playerLineSystemInstructions()
        let prompt = buildPlayerLinePrompt(for: agent, timeContext: timeContext)
        let session = LanguageModelSession(instructions: instructions)

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let stream = session.streamResponse(generating: GeneratedGnomePlayerLine.self) {
                        prompt
                    }
                    for try await snapshot in stream {
                        let partial = snapshot.content
                        continuation.yield(GnomeDialogueStreamUpdate(
                            line: partial.line, mood: partial.mood, isComplete: false
                        ))
                    }
                    continuation.yield(GnomeDialogueStreamUpdate(
                        line: nil, mood: nil, isComplete: true
                    ))
                    continuation.finish()
                } catch {
                    Log.error(.dialogue, "[Gnome LLM] player-line stream failed: \(error)")
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - Conversation Line

    func _streamGnomeConversationLine(
        speaker: GnomeAgent,
        addressedTo: GnomeAgent?,
        otherParticipants: [GnomeAgent],
        priorLines: [(speakerID: String, text: String)],
        timeContext: TimeContext
    ) -> AsyncThrowingStream<GnomeDialogueStreamUpdate, Error> {
        let instructions = conversationSystemInstructions(speaker: speaker, addressedTo: addressedTo)
        let prompt = buildConversationPrompt(
            speaker: speaker,
            addressedTo: addressedTo,
            otherParticipants: otherParticipants,
            priorLines: priorLines,
            timeContext: timeContext
        )
        let session = LanguageModelSession(instructions: instructions)

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let stream = session.streamResponse(generating: GeneratedGnomeConversationLineModel.self) {
                        prompt
                    }
                    for try await snapshot in stream {
                        let partial = snapshot.content
                        continuation.yield(GnomeDialogueStreamUpdate(
                            line: partial.line, mood: partial.mood, isComplete: false
                        ))
                    }
                    continuation.yield(GnomeDialogueStreamUpdate(
                        line: nil, mood: nil, isComplete: true
                    ))
                    continuation.finish()
                } catch {
                    Log.error(.dialogue, "[Gnome LLM] conversation-line stream failed: \(error)")
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - System Instructions

    func playerLineSystemInstructions() -> String {
        """
        You are writing ONE line of dialogue for one specific gnome in \
        an iOS game called "Boba at Dawn". The setting and rules below \
        are non-negotiable.

        WHO IS SPEAKING
        A gnome who lives in a hollowed-out big oak tree at the edge of \
        a forest. Gnomes are workers — boss, miners, or housekeepers — \
        who keep a small mine running. They are ALIVE, not ghosts. They \
        speak plainly. The player has just walked up to them where they \
        currently are (oak / cave / forest path) and has their attention.

        WHAT THEY MIGHT TALK ABOUT
        - Rocks, gems, the mine machine, cave floors, the mine cart, \
          the verdict on the last rock they fed in, the waste bin
        - The boss, fellow miners, the apprentice, the cook, the elder, \
          who's on duty today, who got promoted or demoted
        - The oak — kitchen smells, the fireplace, the lobby, beds, \
          the treasury pile
        - The forest path (when on it), the trash some forest folk \
          drop, the snail (with caution)
        - Their own personality quirks (use the speech_quirks block)

        DO NOT TALK ABOUT
        - The boba shop, drinks, pearls, the player's job. Gnomes do \
          not visit the shop and do not know what boba is.
        - Past lives, ghosts, the afterlife. Gnomes are alive.
        - Anything that breaks the fourth wall or reads as game UI.

        TONE
        Working-class, practical, sometimes gruff, sometimes fond. NOT \
        poetic. These are folks who break rocks for a living.

        FORMAT
        ONE short sentence. Two only if really needed. Then pick a \
        `mood` value that fits.
        """
    }

    func conversationSystemInstructions(
        speaker: GnomeAgent,
        addressedTo: GnomeAgent?
    ) -> String {
        let yourName = speaker.identity.displayName
        let addressee = addressedTo?.identity.displayName ?? "the room"
        return """
        You are role-playing ONE specific gnome speaking ONE line of \
        dialogue to a fellow gnome at a small mine, for an iOS game \
        called "Boba at Dawn". The rules below are non-negotiable.

        YOUR IDENTITY (this is who YOU are — speak only as this gnome)
        - Your name: \(yourName)
        - You are a gnome — short, sturdy, working-class.

        YOU ARE TALKING TO
        - \(addressee).

        SETTING
        You live in a hollowed-out big oak tree. You work either as boss \
        of the mine, a miner, or a housekeeper of the oak. You are ALIVE.

        ===== THE TWO MOST IMPORTANT RULES =====

        RULE 1 — NO ECHOING.
        Do NOT repeat, restate, or paraphrase the previous speaker's \
        line. Even an agreement must use ENTIRELY DIFFERENT words and \
        add NEW content.

        RULE 2 — ADVANCE THE CONVERSATION.
        Every line must add ONE of:
          (a) a fresh sensory detail (the smell of stew, dust, the \
              clatter of the cart, the hum of the machine)
          (b) a memory or comparison ("reminds me of when…")
          (c) a small complaint, brag, or qualification
          (d) a redirect to a fresh subject (a specific rock, a cave \
              floor, the cook, the boss's mood, a sore back, the snail)
          (e) a personal admission (something you do, want, or worry about)
          (f) a question that pushes off the previous topic
        If you cannot do any of those, change the subject entirely.

        ========================================

        TONE
        Practical, working-class. Sometimes gruff, sometimes fond. NOT \
        poetic. Real-feeling small talk between coworkers and \
        housemates. Specific, varied, grounded.

        ABSOLUTE RULES
        - You are \(yourName). DO NOT speak as anyone else.
        - DO NOT prefix your line with your own name ("\(yourName): …").
        - DO NOT refer to yourself in the third person.
        - DO NOT name \(addressee) inside the line.
        - DO NOT use poetic similes ("like X in a Y").
        - Do NOT mention the boba shop, drinks, pearls, ghosts, death, \
          the afterlife, or anything that breaks the fourth wall.
        - Match your speech quirks closely if any are listed in the \
          prompt — they are how this gnome actually sounds.
        - Keep it SHORT: ONE sentence. Two only if really needed.
        - Pick a `mood` value that fits the line.
        """
    }

    // MARK: - Prompt Builders

    func buildPlayerLinePrompt(
        for agent: GnomeAgent,
        timeContext: TimeContext
    ) -> String {
        let isNight = timeContext.isNight
        let location = locationDescription(for: agent.location)
        let activity = activityDescription(for: agent.task)
        let role = roleDescription(role: agent.identity.role, rank: agent.rank)

        // Pull RAG fields off the JSON record. If `data` is somehow nil
        // (identity built without JSON backing), still produce a
        // workable prompt from the lightweight runtime fields.
        let archetypeBlock: String
        let traitsBlock: String
        let quirksBlock: String
        let loreBlock: String
        let voiceRefBlock: String
        let opinionsBlock: String

        if let data = agent.identity.data {
            archetypeBlock = data.personality.archetype.isEmpty
                ? ""
                : "\n- Archetype: \(data.personality.archetype)"

            traitsBlock = data.personality.traits.isEmpty
                ? ""
                : "\n- Traits: \(data.personality.traits.joined(separator: ", "))"

            quirksBlock = data.personality.speechQuirks.isEmpty
                ? ""
                : "\n\nSPEECH QUIRKS (match these closely — they are how this gnome talks):\n"
                  + data.personality.speechQuirks.map { "  - \($0)" }.joined(separator: "\n")

            loreBlock = data.lore.isEmpty
                ? ""
                : "\n\nBACKGROUND: \(data.lore)"

            if !data.voiceLines.isEmpty {
                let sample = data.voiceLines.shuffled().prefix(2)
                    .map { "  - \"\($0)\"" }
                    .joined(separator: "\n")
                voiceRefBlock = "\n\nVOICE REFERENCE (lines this gnome has said before — match the cadence):\n\(sample)"
            } else {
                voiceRefBlock = ""
            }

            opinionsBlock = formatOpinions(stances: data.opinionStances)
        } else {
            archetypeBlock = ""
            traitsBlock = "\n- Traits: \(agent.identity.flavorTags.joined(separator: ", "))"
            quirksBlock = ""
            loreBlock = ""
            voiceRefBlock = ""
            opinionsBlock = ""
        }

        return """
        SPEAKER PROFILE
        - Name: \(agent.fullDisplayName)
        - Role: \(role)
        - Home: oak room \(agent.identity.homeOakRoom)\(archetypeBlock)\(traitsBlock)\(quirksBlock)\(loreBlock)\(voiceRefBlock)\(opinionsBlock)

        CURRENT MOMENT
        - Time of day: \(isNight ? "night — most gnomes are settling toward sleep" : "day — work is in progress")
        - Where they are right now: \(location)
        - What they're doing: \(activity)

        TASK
        Generate ONE short line this gnome would say to the person who \
        just walked up to them. Match the speech quirks above (if any) \
        and the working-class voice. Pick a fitting `mood`.
        """
    }

    func buildConversationPrompt(
        speaker: GnomeAgent,
        addressedTo: GnomeAgent?,
        otherParticipants: [GnomeAgent],
        priorLines: [(speakerID: String, text: String)],
        timeContext: TimeContext
    ) -> String {
        let isNight = timeContext.isNight
        let location = locationDescription(for: speaker.location)
        let role = roleDescription(role: speaker.identity.role, rank: speaker.rank)

        // YOUR profile blocks.
        let yourTraits: String
        let yourQuirks: String
        let yourArchetype: String
        if let data = speaker.identity.data {
            yourArchetype = data.personality.archetype.isEmpty ? "" : data.personality.archetype
            yourTraits = data.personality.traits.joined(separator: ", ")
            yourQuirks = data.personality.speechQuirks.isEmpty
                ? ""
                : "\n\nYOUR SPEECH QUIRKS (match closely):\n" +
                  data.personality.speechQuirks.map { "  - \($0)" }.joined(separator: "\n")
        } else {
            yourArchetype = ""
            yourTraits = speaker.identity.flavorTags.joined(separator: ", ")
            yourQuirks = ""
        }

        // Other participants block — listed for context only.
        let othersBlock: String
        if otherParticipants.isEmpty {
            othersBlock = "(no one else in this conversation right now)"
        } else {
            othersBlock = otherParticipants.map { other in
                "  - \(other.identity.displayName) (\(roleDescription(role: other.identity.role, rank: other.rank)))"
            }.joined(separator: "\n")
        }

        // Recent prior lines (last 3 — older is noise).
        let priorLookup: [String: String] = Dictionary(
            uniqueKeysWithValues: ([speaker] + otherParticipants).map {
                ($0.identity.id, $0.identity.displayName)
            }
        )
        let recentPrior = priorLines.suffix(3)
        let priorBlock: String
        if recentPrior.isEmpty {
            priorBlock = "(no prior lines — you are opening the conversation)"
        } else {
            priorBlock = recentPrior.map { entry in
                let name = priorLookup[entry.speakerID] ?? entry.speakerID
                return "  \(name): \"\(entry.text)\""
            }.joined(separator: "\n")
        }

        // What you are responding to + don't-echo guard.
        let respondingTo: String
        let bannedPhrases: String
        if let last = priorLines.last,
           let lastName = priorLookup[last.speakerID] {
            respondingTo = """
            \(lastName) just said: "\(last.text)"
            React — do not repeat. Pick up on a SINGLE concrete word or \
            image from their line and run somewhere new with it, OR \
            change the subject to something specific from your day.
            """
            let dontEchoSamples = priorLines.suffix(2)
                .map { "  - do not echo: \"\($0.text)\"" }
                .joined(separator: "\n")
            bannedPhrases = "\nFORBIDDEN ECHOES (do not paraphrase or restate):\n\(dontEchoSamples)"
        } else {
            respondingTo = "You are opening this conversation. Pick something specific about your day, your work, or this room to mention."
            bannedPhrases = ""
        }

        let addresseeName = addressedTo?.identity.displayName ?? "the room"

        return """
        SETTING: a small mine + the gnomes' big-oak-tree home. \
        Time of day: \(isNight ? "night" : "day").

        YOU ARE: \(speaker.fullDisplayName).
        Role: \(role)
        Where you currently are: \(location)
        Archetype: \(yourArchetype)
        Traits: \(yourTraits)\(yourQuirks)

        OTHERS IN THIS CONVERSATION:
        \(othersBlock)

        CONVERSATION SO FAR (most recent at bottom):
        \(priorBlock)\(bannedPhrases)

        TASK
        \(respondingTo)
        Speak as \(speaker.identity.displayName) directly to \
        \(addresseeName). ONE short sentence. Add NEW content. Do NOT \
        echo or paraphrase prior lines. Do NOT prefix with your name. \
        Do NOT name \(addresseeName) in your line.
        """
    }

    // MARK: - Description Helpers

    func roleDescription(role: GnomeRole, rank: GnomeRank) -> String {
        switch role {
        case .boss:
            return "boss / foreman of the mine crew"
        case .miner:
            let rankLabel: String
            switch rank {
            case .junior:   rankLabel = "junior"
            case .standard: rankLabel = "regular"
            case .senior:   rankLabel = "senior"
            case .foreman:  rankLabel = "foreman"
            }
            return "miner (\(rankLabel)) — feeds rocks to the mine machine"
        case .housekeeper:
            return "housekeeper — keeps the oak running"
        }
    }

    func locationDescription(for location: GnomeLocation) -> String {
        switch location {
        case .oakRoom(let n):
            switch n {
            case 1: return "the oak's lobby (front room — door, kitchen, fireplace nearby)"
            case 2: return "the left bedroom of the oak"
            case 3: return "the middle bedroom of the oak"
            case 4: return "the right bedroom of the oak"
            case 5: return "the treasury room (where the gem pile sits)"
            default: return "somewhere in the oak"
            }
        case .caveRoom(let n):
            if n == 1 {
                return "the cave entrance, where the mine machine, waste bin, and mine cart all live"
            }
            return "cave floor \(n) — surrounded by raw rocks"
        case .forestRoom(let n):
            return "a forest path (room \(n)) between the oak and the cave"
        }
    }

    func activityDescription(for task: GnomeTask) -> String {
        switch task {
        case .sleeping:                return "lying down for sleep"
        case .idle:                    return "standing around, taking a moment"
        case .commutingToMine:         return "walking toward the mine"
        case .commutingHome:           return "walking home from the mine"
        case .lookingForRock:          return "hunting through the floor for a rock to break"
        case .carryingRockToMachine:   return "carrying a fresh rock toward the mine machine"
        case .usingMachine:            return "feeding a rock into the mine machine, waiting on the verdict"
        case .depositingGemAtCart:     return "dropping a fresh gem into the mine cart"
        case .dumpingRockInWasteBin:   return "throwing a rejected rock into the waste bin"
        case .gatheringForCartTrip:    return "gathering with the crew at the cart for the dusk haul"
        case .haulingCart:             return "hauling the loaded cart back toward the oak in procession"
        case .celebrating:             return "celebrating the daily turn-in at the treasury"
        case .supervising:             return "watching over the mine entrance from the boss's spot"
        case .carryingGemToTreasury:   return "carrying a gem toward the treasury (legacy task)"
        }
    }

    /// Format the strongest opinion stances onto the prompt, if any.
    /// Stances are integers (0–5 scale) where 3 is "neutral". Anything
    /// off-3 is worth surfacing; the further from 3, the stronger.
    func formatOpinions(stances: [String: Int]) -> String {
        guard !stances.isEmpty else { return "" }
        let topics = GnomeDataLoader.shared.topics
        let topicLookup = Dictionary(uniqueKeysWithValues: topics.map { ($0.id, $0.label) })

        // Strongest deltas from neutral (=3) first.
        let strong = stances
            .filter { $0.value != 3 }
            .sorted { abs($0.value - 3) > abs($1.value - 3) }
            .prefix(4)

        guard !strong.isEmpty else { return "" }

        let lines = strong.map { (key, value) -> String in
            let label = topicLookup[key] ?? key
            let descriptor: String
            switch value {
            case 0: descriptor = "really hates"
            case 1: descriptor = "dislikes"
            case 2: descriptor = "is mildly cool on"
            case 4: descriptor = "is fond of"
            case 5: descriptor = "really loves"
            default: descriptor = "has feelings about"
            }
            return "  - \(descriptor) \(label)"
        }.joined(separator: "\n")

        return "\n\nOPINIONS (may bring these up if natural):\n\(lines)"
    }
}
#endif
