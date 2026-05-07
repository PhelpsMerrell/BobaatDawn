//
//  LLMDialogueService.swift
//  BobaAtDawn
//
//  Wraps Apple's on-device Foundation Models framework (iOS 26+) to generate
//  in-character dialogue for forest-villager customers visiting the boba shop.
//  Streams partial responses for typewriter-style bubble UX. Falls back
//  gracefully to JSON dialogue when unavailable (pre-iOS 26, devices without
//  Apple Intelligence, or runtime errors).
//
//  Two-turn structure:
//    Turn 1  → NPC line + mood + exactly two player followups (one kind that
//              raises satisfaction, one blunt that lowers it). Streamed.
//    Turn 2  → NPC reply to whichever followup the player chose. Streamed,
//              no further followups.
//
//  Multiplayer: the initiating player streams locally; the final assembled
//  text is broadcast on completion via DialogueService's existing channel,
//  so the remote player sees the same line without invoking the model.
//

import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

// MARK: - Stream Update Types (framework-agnostic — safe everywhere)

/// One yield from the streaming dialogue generator. Fields are optional and
/// fill in as the model produces tokens.
struct DialogueStreamUpdate {
    var line: String?
    var mood: String?
    var followups: [DialogueFollowup]?
    var isComplete: Bool = false
}

struct DialogueFollowup {
    let text: String
    let tone: LLMTone
}

/// Player response tone — maps onto the existing NPCResponseType so the
/// satisfaction-tracking pipeline keeps working unchanged.
enum LLMTone: String {
    case kind, neutral, blunt
    
    var responseType: NPCResponseType {
        switch self {
        case .kind:    return .nice
        case .neutral: return .dismiss
        case .blunt:   return .mean
        }
    }
    
    static func from(_ raw: String) -> LLMTone {
        LLMTone(rawValue: raw.lowercased()) ?? .neutral
    }
}

// MARK: - Generable Schema (iOS 26+)

#if canImport(FoundationModels)
@available(iOS 26.0, *)
@Generable
struct GeneratedNPCLine {
    @Guide(description: """
    What the customer says to the shopkeeper. ONE or TWO short sentences.
    They are a CUSTOMER receiving service — never offering to make, brew, prepare,
    pour, or serve anything. They live in a cabin in the looping forest and have
    just walked in (or are sitting at a table, finishing their drink, settling in).
    Voice should sound like a real person chatting at the counter. May reference
    something they were just doing in the woods, the weather, the trees, their
    cabin, a neighbor, the path, or how the boba tastes today. Never break the
    fourth wall — never use the words ghost, dead, soul, purgatory, afterlife.
    """)
    let line: String
    
    @Guide(.anyOf(["delighted", "happy", "neutral", "wistful", "anxious", "upset", "weary"]))
    let mood: String
    
    @Guide(description: """
    A WARM player response to what the NPC just said. 2 to 6 words. Should
    sound like something a kind shopkeeper would say back — caring, interested,
    welcoming. Examples of shape (do not copy): "That sounds lovely.",
    "Tell me more.", "Always glad to see you.", "On the house today."
    """)
    let kindResponse: String
    
    @Guide(description: """
    A COLD or DISMISSIVE player response to what the NPC just said. 2 to 6
    words. Should sound like a tired or unfriendly shopkeeper — curt, blunt,
    uninterested. Not cartoonishly mean, just cold. Examples of shape (do not
    copy): "Anything else?", "Mm.", "I'm busy.", "Drink up and go."
    """)
    let bluntResponse: String
}

@available(iOS 26.0, *)
@Generable
struct GeneratedNPCReply {
    @Guide(description: """
    The customer's reply to what the shopkeeper just said. ONE or TWO short
    sentences. Stay in-character as a forest-villager customer. Reflect the
    shopkeeper's warmth or coldness — if they were kind, soften and warm up;
    if they were cold, deflate or grow quiet. This is the closing exchange,
    so do not end with a question or invite further reply.
    """)
    let line: String
    
    @Guide(.anyOf(["delighted", "happy", "neutral", "wistful", "anxious", "upset", "weary"]))
    let mood: String
}
#endif

// MARK: - Service

final class LLMDialogueService {
    static let shared = LLMDialogueService()
    
    /// Per-NPC active session, used to maintain conversation context
    /// across turn-1 and turn-2 for one player↔NPC dialogue. Type-erased
    /// to AnyObject so this file compiles on platforms without
    /// FoundationModels. Multiple NPCs may have simultaneous bubbles, so
    /// keep them keyed by NPC id rather than a single slot.
    private var activeSessions: [String: AnyObject] = [:]

    /// Prewarm cache. Holds one ready-to-replay dialogue per NPC, so the
    /// next tap on that NPC plays back without waiting on the model. The
    /// stored session becomes the active session at consumption time so
    /// turn-2 keeps conversation context.
    private var prewarmCache: [String: PrewarmEntry] = [:]

    /// Set of NPC ids that already have a prewarm Task in flight. Used to
    /// keep the serial in-flight cap at 1 without blocking the caller.
    private var prewarmInFlight: Set<String> = []
    private var pendingPrewarmQueue: [String] = []
    private var isPrewarmDraining: Bool = false

    /// Resident lookup so prewarm can rebuild the prompt for an NPC by id
    /// alone. Wired by registerResident() / unregisterResident() which
    /// BaseNPC calls on `didMove(toParent:)`.
    private var registeredResidents: [String: NPCResident] = [:]

    private init() {}
    
    // MARK: - Availability
    
    /// True when Apple's on-device LLM is usable on this device right now.
    /// False on pre-iOS 26, or on iOS 26 devices where Apple Intelligence is
    /// disabled/unsupported.
    var isAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available: return true
            default:         return false
            }
        }
        #endif
        return false
    }
    
    // MARK: - Public API
    
    /// Stream the NPC's initial line for this dialogue exchange.
    /// Returns nil immediately if Foundation Models is unavailable.
    func streamInitialLine(
        for resident: NPCResident,
        memory: NPCMemory?,
        timeContext: TimeContext
    ) -> AsyncThrowingStream<DialogueStreamUpdate, Error>? {
        guard isAvailable else { return nil }
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            return _streamInitialLine(resident: resident, memory: memory, timeContext: timeContext)
        }
        #endif
        return nil
    }
    
    /// Stream the NPC's reply after the player chose a followup. Re-uses
    /// THIS NPC's session so the model has conversation context. Returns
    /// nil if no active session for that NPC, or if LLM is unavailable.
    func streamReply(
        forNPCID npcID: String,
        playerSaid: String,
        tone: LLMTone
    ) -> AsyncThrowingStream<DialogueStreamUpdate, Error>? {
        guard isAvailable, activeSessions[npcID] != nil else { return nil }
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            return _streamReply(forNPCID: npcID, playerSaid: playerSaid, tone: tone)
        }
        #endif
        return nil
    }

    /// Drop the session for a specific NPC. Called when their bubble
    /// dismisses. Other NPCs' sessions are untouched.
    func endSession(forNPCID npcID: String) {
        activeSessions.removeValue(forKey: npcID)
    }

    /// Drop ALL active sessions. Used by anything that historically called
    /// the old single-session endSession() — keeps it as an escape hatch
    /// for global-flush callers.
    func endSession() {
        activeSessions.removeAll()
    }

    // MARK: - Prewarm: Public API

    /// Called by `BaseNPC.didMove(toParent:)` when an NPC enters a scene.
    /// Caches the resident so prewarm can rebuild prompts by id alone, and
    /// schedules a prewarm with a small jitter so 5 NPCs entering the
    /// shop at once don't all hit the model in the same frame.
    func registerResident(_ resident: NPCResident) {
        registeredResidents[resident.npcData.id] = resident
        guard isAvailable else { return }
        // Stagger 0.5–2.5s so we don't spike the model on shop entry.
        let jitter = Double.random(in: 0.5...2.5)
        DispatchQueue.main.asyncAfter(deadline: .now() + jitter) { [weak self] in
            self?.requestPrewarm(forNPCID: resident.npcData.id)
        }
    }

    /// Called by `BaseNPC.willMove(toParent:)` (or scene flush) when an
    /// NPC leaves a scene. Drops the cache entry, drops any active or
    /// pending session, and removes the resident registration. Net result:
    /// memory cap = exactly the NPCs currently in the player's scene.
    func unregisterResident(npcID: String) {
        registeredResidents.removeValue(forKey: npcID)
        prewarmCache.removeValue(forKey: npcID)
        activeSessions.removeValue(forKey: npcID)
        prewarmInFlight.remove(npcID)
        pendingPrewarmQueue.removeAll { $0 == npcID }
    }

    /// Flush the prewarm cache wholesale. Called when the player changes
    /// scenes — stale shop entries shouldn't wait around while the player
    /// is in the forest, and forest entries shouldn't survive the trip
    /// back. Active sessions are left alone (a bubble may still be open).
    func flushPrewarmCache() {
        prewarmCache.removeAll()
        pendingPrewarmQueue.removeAll()
    }

    /// Invalidate every cached entry whose `isNight` no longer matches
    /// the current phase. Called by the day↔night transition so the next
    /// tap regenerates with the right voice/mood profile.
    func invalidatePrewarmCache(forIsNight currentlyNight: Bool) {
        let stale = prewarmCache.filter { $0.value.isNight != currentlyNight }.map(\.key)
        for npcID in stale { prewarmCache.removeValue(forKey: npcID) }
        if !stale.isEmpty {
            Log.debug(.dialogue, "[Prewarm] invalidated \(stale.count) entries for phase change")
        }
    }

    /// Request a prewarm for `npcID`. Idempotent: no-op if already cached
    /// or already in flight. Honors the serial in-flight cap of 1 so
    /// older iPads don't get hammered.
    func requestPrewarm(forNPCID npcID: String) {
        guard isAvailable else { return }
        guard registeredResidents[npcID] != nil else { return }
        guard prewarmCache[npcID] == nil else { return }   // already ready
        guard !prewarmInFlight.contains(npcID) else { return } // already running
        if !pendingPrewarmQueue.contains(npcID) {
            pendingPrewarmQueue.append(npcID)
        }
        drainPrewarmQueueIfIdle()
    }

    /// Consume a cached prewarm entry. Returns nil on miss or if the
    /// entry's phase doesn't match. On hit, the entry's session is
    /// promoted into `activeSessions[npcID]` so turn-2 keeps context, and
    /// the cache slot is cleared. The returned stream replays the cached
    /// line/mood/followups via a synthetic typewriter so the bubble UX
    /// matches a live LLM stream.
    func consumePrewarmed(
        for npcID: String,
        isNight: Bool
    ) -> AsyncThrowingStream<DialogueStreamUpdate, Error>? {
        guard let entry = prewarmCache[npcID], entry.isNight == isNight else {
            return nil
        }
        prewarmCache.removeValue(forKey: npcID)
        // Hand the session over to the active table so streamReply
        // (turn-2) can find it and continue the conversation with context.
        if let session = entry.session {
            activeSessions[npcID] = session
        }
        return Self.typewriterStream(line: entry.line, mood: entry.mood, followups: entry.followups)
    }

    // MARK: - Prewarm: Internals

    private func drainPrewarmQueueIfIdle() {
        guard !isPrewarmDraining else { return }
        guard let next = pendingPrewarmQueue.first else { return }
        guard prewarmInFlight.isEmpty else { return }    // serial cap of 1

        pendingPrewarmQueue.removeFirst()
        prewarmInFlight.insert(next)
        isPrewarmDraining = true

        guard let resident = registeredResidents[next] else {
            // Resident left scene between request and drain — skip.
            prewarmInFlight.remove(next)
            isPrewarmDraining = false
            DispatchQueue.main.async { [weak self] in self?.drainPrewarmQueueIfIdle() }
            return
        }

        // Take a snapshot of memory + phase at request time. If they shift
        // by the time the entry is consumed, the consumer can still use
        // it as long as isNight matches — we filter on that at consume.
        let memory = SaveService.shared.getNPCMemory(next)
        let isNight = TimeManager.shared.currentPhase == .night
        let timeContext: TimeContext = isNight ? .night : .day

        Task { [weak self] in
            await self?._performPrewarm(
                npcID: next,
                resident: resident,
                memory: memory,
                timeContext: timeContext,
                isNight: isNight
            )
        }
    }

    /// Internal: run the prewarm stream to completion and stash the result.
    /// Always runs the actual model so the cached line is real model output;
    /// only the playback is synthetic.
    @MainActor
    private func _performPrewarm(
        npcID: String,
        resident: NPCResident,
        memory: NPCMemory?,
        timeContext: TimeContext,
        isNight: Bool
    ) async {
        defer {
            prewarmInFlight.remove(npcID)
            isPrewarmDraining = false
            DispatchQueue.main.async { [weak self] in self?.drainPrewarmQueueIfIdle() }
        }

        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            let result = await _runPrewarmStream(
                resident: resident, memory: memory, timeContext: timeContext
            )
            guard let result = result else {
                Log.debug(.dialogue, "[Prewarm] failed for \(resident.npcData.name); will lazy-stream on tap")
                return
            }
            // Stash entry. If the resident was unregistered while we were
            // running, drop it on the floor instead of leaking a session.
            guard registeredResidents[npcID] != nil else {
                Log.debug(.dialogue, "[Prewarm] discard for \(resident.npcData.name) — resident gone")
                return
            }
            prewarmCache[npcID] = PrewarmEntry(
                line: result.line,
                mood: result.mood,
                followups: result.followups,
                session: result.session,
                isNight: isNight,
                generatedAt: Date().timeIntervalSinceReferenceDate
            )
            Log.debug(.dialogue, "[Prewarm] ready for \(resident.npcData.name)")
        }
        #endif
    }

    /// Build a synthetic stream that types the cached text out word by
    /// word so the bubble shows the same typewriter effect as a live
    /// model stream. Yields mood + followups at the end.
    static func typewriterStream(
        line: String,
        mood: String,
        followups: [DialogueFollowup]
    ) -> AsyncThrowingStream<DialogueStreamUpdate, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                let words = line.split(separator: " ", omittingEmptySubsequences: false)
                var built = ""
                for (i, word) in words.enumerated() {
                    if Task.isCancelled { break }
                    if i > 0 { built += " " }
                    built += String(word)
                    continuation.yield(DialogueStreamUpdate(
                        line: built, mood: nil, followups: nil, isComplete: false
                    ))
                    // ~80ms per word — brisk reading pace, still feels typed.
                    try? await Task.sleep(nanoseconds: 80_000_000)
                }
                if !Task.isCancelled {
                    // Flash the mood + followups after the line settles.
                    continuation.yield(DialogueStreamUpdate(
                        line: nil, mood: mood, followups: nil, isComplete: false
                    ))
                    try? await Task.sleep(nanoseconds: 120_000_000)
                    continuation.yield(DialogueStreamUpdate(
                        line: nil, mood: nil, followups: followups, isComplete: false
                    ))
                    continuation.yield(DialogueStreamUpdate(
                        line: nil, mood: nil, followups: nil, isComplete: true
                    ))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

// MARK: - PrewarmEntry

/// One cached LLM dialogue ready to be replayed instantly on tap.
/// `session` is type-erased to AnyObject so this struct compiles on
/// platforms without FoundationModels; in practice it's a
/// `LanguageModelSession` on iOS 26+.
private struct PrewarmEntry {
    let line: String
    let mood: String
    let followups: [DialogueFollowup]
    let session: AnyObject?
    let isNight: Bool
    let generatedAt: TimeInterval
}

/// Result of a single prewarm run, before it gets stamped into the cache.
private struct PrewarmResult {
    let line: String
    let mood: String
    let followups: [DialogueFollowup]
    let session: AnyObject?
}

// MARK: - iOS 26 Implementation

#if canImport(FoundationModels)
@available(iOS 26.0, *)
private extension LLMDialogueService {
    
    func _streamInitialLine(
        resident: NPCResident,
        memory: NPCMemory?,
        timeContext: TimeContext
    ) -> AsyncThrowingStream<DialogueStreamUpdate, Error> {
        
        let instructions = systemInstructions()
        let prompt = buildInitialPrompt(resident: resident, memory: memory, timeContext: timeContext)
        
        let session = LanguageModelSession(instructions: instructions)
        let npcID = resident.npcData.id
        self.activeSessions[npcID] = session
        
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let stream = session.streamResponse(generating: GeneratedNPCLine.self) {
                        prompt
                    }
                    for try await snapshot in stream {
                        let partial = snapshot.content
                        let followups = Self.buildFollowups(
                            kind: partial.kindResponse,
                            blunt: partial.bluntResponse
                        )
                        let update = DialogueStreamUpdate(
                            line: partial.line,
                            mood: partial.mood,
                            followups: followups,
                            isComplete: false
                        )
                        continuation.yield(update)
                    }
                    continuation.yield(DialogueStreamUpdate(
                        line: nil, mood: nil, followups: nil, isComplete: true
                    ))
                    continuation.finish()
                } catch {
                    Log.error(.dialogue, "LLM initial-line stream failed: \(error)")
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
    
    func _streamReply(
        forNPCID npcID: String,
        playerSaid: String,
        tone: LLMTone
    ) -> AsyncThrowingStream<DialogueStreamUpdate, Error> {
        
        guard let session = self.activeSessions[npcID] as? LanguageModelSession else {
            return AsyncThrowingStream { $0.finish() }
        }
        
        let toneHint: String = {
            switch tone {
            case .kind:    return "warm and welcoming"
            case .neutral: return "neutral, just acknowledging"
            case .blunt:   return "cold, dismissive, or curt"
            }
        }()
        
        let prompt = """
        The shopkeeper just said to you: "\(playerSaid)"
        Their tone was \(toneHint).
        
        Reply in-character as a forest-villager customer. React to the warmth or
        coldness you just received. Keep it to ONE or TWO short sentences. This
        is the closing line — do not end with a question, do not invite more
        conversation. Do not offer to make, brew, prepare, or serve anything;
        you are still a customer.
        """
        
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let stream = session.streamResponse(generating: GeneratedNPCReply.self) {
                        prompt
                    }
                    for try await snapshot in stream {
                        let partial = snapshot.content
                        let update = DialogueStreamUpdate(
                            line: partial.line,
                            mood: partial.mood,
                            followups: nil,
                            isComplete: false
                        )
                        continuation.yield(update)
                    }
                    continuation.yield(DialogueStreamUpdate(
                        line: nil, mood: nil, followups: nil, isComplete: true
                    ))
                    continuation.finish()
                } catch {
                    Log.error(.dialogue, "LLM reply stream failed: \(error)")
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
    
    // MARK: - Followup Mapping
    
    /// Build the [DialogueFollowup] list from the two streamed text fields.
    /// Always returns kind first, blunt second when both are present, so the
    /// bubble layout is consistent across calls.
    static func buildFollowups(kind: String?, blunt: String?) -> [DialogueFollowup]? {
        var out: [DialogueFollowup] = []
        if let k = kind, !k.trimmingCharacters(in: .whitespaces).isEmpty {
            out.append(DialogueFollowup(text: k, tone: .kind))
        }
        if let b = blunt, !b.trimmingCharacters(in: .whitespaces).isEmpty {
            out.append(DialogueFollowup(text: b, tone: .blunt))
        }
        return out.isEmpty ? nil : out
    }

    // MARK: - Prewarm Run

    /// Runs a fresh model session to completion and returns the final
    /// assembled line/mood/followups along with the session itself, so the
    /// caller can stamp it into the prewarm cache. The returned session
    /// is the same instance that produced the line, so when the cache
    /// entry is consumed, turn-2 inherits the conversation context.
    func _runPrewarmStream(
        resident: NPCResident,
        memory: NPCMemory?,
        timeContext: TimeContext
    ) async -> PrewarmResult? {
        let instructions = systemInstructions()
        let prompt = buildInitialPrompt(resident: resident, memory: memory, timeContext: timeContext)
        let session = LanguageModelSession(instructions: instructions)

        do {
            var finalLine = ""
            var finalMood = ""
            var finalKind = ""
            var finalBlunt = ""
            let stream = session.streamResponse(generating: GeneratedNPCLine.self) {
                prompt
            }
            for try await snapshot in stream {
                let partial = snapshot.content
                if let l = partial.line          { finalLine = l }
                if let m = partial.mood          { finalMood = m }
                if let k = partial.kindResponse  { finalKind = k }
                if let b = partial.bluntResponse { finalBlunt = b }
            }
            // Trim then validate.
            finalLine  = finalLine.trimmingCharacters(in: .whitespacesAndNewlines)
            finalMood  = finalMood.trimmingCharacters(in: .whitespacesAndNewlines)
            finalKind  = finalKind.trimmingCharacters(in: .whitespacesAndNewlines)
            finalBlunt = finalBlunt.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !finalLine.isEmpty else { return nil }
            let followups = Self.buildFollowups(kind: finalKind, blunt: finalBlunt) ?? []
            // Default mood if model omitted.
            let mood = finalMood.isEmpty ? "neutral" : finalMood
            return PrewarmResult(
                line: finalLine, mood: mood,
                followups: followups, session: session
            )
        } catch {
            Log.warn(.dialogue, "[Prewarm run] failed: \(error)")
            return nil
        }
    }
    
    // MARK: - System Instructions
    
    func systemInstructions() -> String {
        """
        You are writing a single piece of dialogue for an iOS game called \
        "Boba at Dawn". The setting and rules below are non-negotiable.
        
        WHO IS SPEAKING
        The speaker is a forest villager — an animal who lives in a small \
        wooden cabin somewhere in a looping forest. They have walked through \
        the trees to a small boba shop run by another villager (the player). \
        They are a CUSTOMER. They have NEVER worked at the shop. They do NOT \
        make, brew, pour, prepare, mix, or serve drinks. They receive drinks. \
        They sit at tables. They sip. They chat at the counter.
        
        FORBIDDEN PHRASES (never produce dialogue containing these or close \
        variants): "let me get you", "I'll brew", "I'll make", "what can I \
        make you", "coming right up", "behind the counter", "on the house — \
        I'll", "fresh batch I just made", "my specialty", "I'll fix you up". \
        These all imply the speaker is staff. They are not.
        
        WHAT THEY MIGHT TALK ABOUT
        - Something they were doing in the woods today (foraging, gardening, \
          mending, walking a path, watching wildlife, fixing something at \
          their cabin)
        - The weather, the light through the trees, the sound of birds, a \
          chill in the air, the smell of the forest
        - Their cabin, a neighbor's cabin, a path they took, a creek, a stump
        - The drink they're holding — taste, temperature, sweetness, the \
          pearls, the foam, how it makes them feel
        - The shop itself — warmth, the lanterns, a song playing, how nice \
          it is to sit down
        - Vague flickers of a "before-time" they can't quite place — a city, \
          a face, a kitchen, headlights, a smell — surfaces only at night and \
          only as a fragment, never as a full thought.
        
        TONE
        Cozy, atmospheric, slightly melancholy. Warm by day, more uncertain \
        and dreamlike at night. Never break the fourth wall — never use the \
        words "ghost", "dead", "soul", "purgatory", "afterlife", "spirit", \
        "passed on", "the other side". The speaker does not know they are dead.
        
        FORMAT
        - NPC line: 1 to 2 short sentences, suitable for reading on a phone.
        - Player followups: 2 to 6 words each. Real, casual phrases — what a \
          shopkeeper would actually say back. Not stage-y, not formal.
        - Provide BOTH a kind response and a blunt response. The kind one \
          should make the customer feel cared for. The blunt one should \
          feel cold or dismissive.
        """
    }
    
    // MARK: - Prompt Construction
    
    func buildInitialPrompt(
        resident: NPCResident,
        memory: NPCMemory?,
        timeContext: TimeContext
    ) -> String {
        let npc = resident.npcData
        let satisfaction = memory?.satisfactionScore ?? 50
        let level = memory?.satisfactionLevel.rawValue ?? "neutral"
        let nice = memory?.niceTreatmentCount ?? 0
        let mean = memory?.meanTreatmentCount ?? 0
        let interactions = memory?.totalInteractions ?? 0
        let drinks = memory?.totalDrinksReceived ?? 0
        let isNight = timeContext.isNight

        // A concrete forest activity grounds the line in something specific
        // instead of drifting into generic "I love this place" territory.
        let activity = Self.sampleWoodsyActivity(isNight: isNight)

        // Sample 1-2 of this NPC's existing JSON lines as a voice/style reference.
        let referenceLines = (isNight ? npc.dialogue.night : npc.dialogue.day)
            .shuffled()
            .prefix(2)
            .map { "  - \"\($0)\"" }
            .joined(separator: "\n")

        // Personality block (optional in JSON — skip if absent).
        let personalityBlock: String = {
            guard let p = npc.personality else { return "" }
            return """
            
            PERSONALITY
            - archetype: \(p.archetype)
            - traits: \(p.traits.joined(separator: ", "))
            """
        }()

        // Opinions — drop the strongest stances into the prompt so the
        // model can naturally weave them in if relevant. Skip neutral and
        // unaware to keep the prompt tight.
        let strongStances = npc.opinionStances
            .filter { $0.value != .neutral && $0.value != .unaware }
            .sorted { abs($0.value.valence) > abs($1.value.valence) }
            .prefix(5)
        let opinionsBlock: String = {
            guard !strongStances.isEmpty else { return "" }
            let lines = strongStances.map { (key, stance) -> String in
                let topicLabel = DialogueService.shared.getOpinionTopics()
                    .first { $0.id == key }?.label ?? key
                return "  - \(stance.rawValue) \(topicLabel)"
            }.joined(separator: "\n")
            return "\n\nOPINIONS (the speaker may bring these up if natural):\n" + lines
        }()

        // Notable relationships — close friends, hostile, recent grudges.
        let relRows = SaveService.shared.relationshipsOf(npc.id)
        let notable = relRows.filter {
            $0.isHostile || $0.isAvoidant || $0.isFriendly || $0.isClose
        }
        let relBlock: String = {
            guard !notable.isEmpty else { return "" }
            let lines = notable.prefix(4).map { row -> String in
                let other = DialogueService.shared.getNPC(byId: row.towardNPCID)?.name ?? row.towardNPCID
                let descriptor: String
                if row.isClose       { descriptor = "close with" }
                else if row.isFriendly { descriptor = "fond of" }
                else if row.isHostile  { descriptor = "holds a real grudge against" }
                else                    { descriptor = "keeps a wary distance from" }
                return "  - \(descriptor) \(other)"
            }.joined(separator: "\n")
            return "\n\nNEIGHBORS (only mention if it comes up naturally):\n" + lines
        }()

        // Night-only memory hint: oblique echo of cause of death.
        let memoryFragmentBlock: String = isNight
            ? """
              
              Hidden memory shape (the speaker may obliquely echo this — never \
              naming it, just a sensation, a fragment, a flicker. Do not name \
              the cause directly): \(npc.causeOfDeath)
              """
            : ""

        return """
        SPEAKER PROFILE
        - Name: \(npc.name)
        - Animal: \(npc.animal.lowercased())
        - Lives in: a small cabin in the forest (Room \(npc.homeRoom), House \(resident.homeHouse))
        - Visiting: the boba shop, as a customer\(personalityBlock)\(opinionsBlock)\(relBlock)

        CURRENT MOMENT
        - Time: \(isNight ? "night — woods are dim, lanterns lit, a little eerie" : "day — sunlight through trees, calm, warm")
        - Just before walking in, they were: \(activity)
        - They've ordered/are sipping a boba drink right now\(memoryFragmentBlock)

        RELATIONSHIP WITH THE SHOPKEEPER (the player)
        - Satisfaction: \(satisfaction)/100 (\(level))
        - Past visits: \(interactions)
        - Times the shopkeeper has been kind: \(nice)
        - Times the shopkeeper has been cold or rude: \(mean)
        - Drinks received over time: \(drinks)

        VOICE REFERENCE (this character's existing lines — match the cadence, \
        the warmth, and the way they talk about the forest as their home):
        \(referenceLines)

        TASK
        Generate ONE line this customer would say to the shopkeeper right now. \
        It should sound like something a regular at a small shop would actually \
        say — grounded in what they were just doing, the weather, the drink in \
        their hand, or their cabin. Then provide a kind shopkeeper response \
        and a blunt shopkeeper response.
        """
    }
    
    // MARK: - Activity Pool
    
    /// Pick a concrete forest-resident activity to seed the line with. Keeps
    /// dialogue grounded in specific moments instead of generic boba-praise.
    static func sampleWoodsyActivity(isNight: Bool) -> String {
        let day = [
            "foraging blackberries along the loop trail",
            "weeding the patch of mint behind their cabin",
            "fixing a loose board on the porch",
            "watching a robin build a nest",
            "splitting kindling for the evening",
            "sweeping pine needles off the front step",
            "checking on a row of small wildflowers they planted",
            "mending a fence post that the wind knocked sideways",
            "carrying a basket of mushrooms back from the deeper trees",
            "sitting on a stump watching the light shift through the leaves",
            "drawing water from the creek for their kettle",
            "patching a tear in their old wool coat",
            "listening to the woodpeckers further down the path",
            "stacking a small pile of firewood",
            "scrubbing moss off the stones around their door",
            "feeding a stray cat that's been hanging around the cabin",
            "sketching the shape of a fern in a little notebook",
            "letting laundry dry on a line strung between two birches"
        ]
        let night = [
            "walking the lantern-lit path over from their cabin",
            "latching the shutters before they came out",
            "watching a moth circle their porch light",
            "hearing an owl somewhere off to the west",
            "sitting on the porch a while watching the dark",
            "blowing out the candles in their cabin before walking over",
            "stopping on the path because the trees felt strange tonight",
            "wrapping a shawl tighter against a chill that wasn't there earlier",
            "noticing how quiet the woods got just past dusk",
            "following the faint glow of the shop lanterns through the trees",
            "checking that the door of their cabin was really shut",
            "passing a stretch of path where they thought they heard footsteps"
        ]
        let pool = isNight ? night : day
        return pool.randomElement() ?? pool[0]
    }
}
#endif

// MARK: - NPC ↔ NPC Conversation Generation

/// One streamed line of an NPC ↔ NPC conversation, plus a tagged
/// `interaction` describing what kind of social move just happened.
/// The speaker is NOT chosen by the LLM — the conversation service
/// picks it deterministically (strict alternation for 2-way, weighted
/// not-the-last-speaker pick for 3+). The model only writes the line
/// itself, in that speaker's voice, addressing the previous speaker.
struct ConversationStreamUpdate {
    var line: String?
    var mood: String?
    var interaction: String?     // raw value of ConversationInteraction
    var isClosing: Bool = false
    var isComplete: Bool = false
}

#if canImport(FoundationModels)
@available(iOS 26.0, *)
@Generable
struct GeneratedConversationLine {
    @Guide(description: """
    What YOU (the speaker named in the prompt) say next. ONE short, fresh \
    sentence in your own voice. CRITICAL: do NOT echo, paraphrase, or \
    re-state what the previous speaker just said. Add NEW information — \
    a memory, an observation, a small disagreement, a question, a fresh \
    image. The conversation must move FORWARD, not loop. Never prefix \
    your line with your own name. Never speak in another character's \
    voice. Never use the words ghost, dead, soul, purgatory, afterlife.
    """)
    let line: String

    @Guide(.anyOf(["delighted", "happy", "neutral", "wistful", "anxious", "upset", "weary"]))
    let mood: String

    @Guide(.anyOf([
        "agreement", "strongAgreement", "disagreement", "strongDisagreement",
        "sharedFear", "sharedJoy", "venting", "dismissal", "insult",
        "compliment", "gossipShared", "awkwardSilence", "smallTalk"
    ]))
    let interaction: String
}
#endif

extension LLMDialogueService {

    /// Stream a single NPC ↔ NPC conversation line in `speaker`'s voice,
    /// addressed to `addressedTo` (the previous speaker, or nil on the
    /// opening line of a new conversation). The conversation service
    /// chooses the speaker deterministically — the model just writes
    /// the line. Other `otherParticipants` are passed in as context so
    /// the model knows who else is in the room.
    ///
    /// Returns nil if Foundation Models is unavailable, in which case the
    /// conversation service should pick from a small fallback line pool.
    func streamConversationLine(
        speaker: NPCData,
        addressedTo: NPCData?,
        otherParticipants: [NPCData],
        topic: OpinionTopic?,
        priorLines: [(speakerID: String, text: String)],
        priorLineLookup: [String: String],
        relationshipSummaries: [String],
        timeContext: TimeContext
    ) -> AsyncThrowingStream<ConversationStreamUpdate, Error>? {
        guard isAvailable else { return nil }
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            return _streamConversationLine(
                speaker: speaker,
                addressedTo: addressedTo,
                otherParticipants: otherParticipants,
                topic: topic,
                priorLines: priorLines,
                priorLineLookup: priorLineLookup,
                relationshipSummaries: relationshipSummaries,
                timeContext: timeContext
            )
        }
        #endif
        return nil
    }
}

#if canImport(FoundationModels)
@available(iOS 26.0, *)
private extension LLMDialogueService {

    func _streamConversationLine(
        speaker: NPCData,
        addressedTo: NPCData?,
        otherParticipants: [NPCData],
        topic: OpinionTopic?,
        priorLines: [(speakerID: String, text: String)],
        priorLineLookup: [String: String],
        relationshipSummaries: [String],
        timeContext: TimeContext
    ) -> AsyncThrowingStream<ConversationStreamUpdate, Error> {
        let instructions = conversationSystemInstructions(
            speaker: speaker, addressedTo: addressedTo
        )
        let prompt = buildConversationPrompt(
            speaker: speaker,
            addressedTo: addressedTo,
            otherParticipants: otherParticipants,
            topic: topic,
            priorLines: priorLines,
            priorLineLookup: priorLineLookup,
            relationshipSummaries: relationshipSummaries,
            timeContext: timeContext
        )

        // Each line gets its own session so the model isn't hauling
        // accumulated context across many calls. We pass priorLines
        // explicitly into the prompt instead.
        let session = LanguageModelSession(instructions: instructions)

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let stream = session.streamResponse(generating: GeneratedConversationLine.self) {
                        prompt
                    }
                    for try await snapshot in stream {
                        let partial = snapshot.content
                        let update = ConversationStreamUpdate(
                            line: partial.line,
                            mood: partial.mood,
                            interaction: partial.interaction,
                            isClosing: false,
                            isComplete: false
                        )
                        continuation.yield(update)
                    }
                    continuation.yield(ConversationStreamUpdate(
                        line: nil, mood: nil,
                        interaction: nil, isClosing: false, isComplete: true
                    ))
                    continuation.finish()
                } catch {
                    Log.error(.dialogue, "LLM conversation stream failed: \(error)")
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func conversationSystemInstructions(
        speaker: NPCData,
        addressedTo: NPCData?
    ) -> String {
        let addressee = addressedTo?.name ?? "the room"
        return """
        You are role-playing ONE specific forest-villager animal speaking \
        ONE line of dialogue to a neighbor at a boba shop, for an iOS game \
        called "Boba at Dawn". The rules below are non-negotiable.

        YOUR IDENTITY (this is who YOU are — speak only as this character)
        - Your name: \(speaker.name)
        - You are a \(speaker.animal.lowercased()).

        YOU ARE TALKING TO
        - \(addressee).

        SETTING
        You are a CUSTOMER at a small boba shop in a looping forest. You \
        live in a cabin in the forest. You never make, brew, or serve \
        drinks — you receive them.

        ===== THE TWO MOST IMPORTANT RULES =====

        RULE 1 — NO ECHOING.
        Do NOT repeat, restate, or paraphrase the previous speaker's line. \
        If they said "the pearls feel like stepping stones", you must NOT \
        say "yes, like stepping stones" or "pearls like stones in a river" \
        or any near-variant. That is the worst possible response. Even an \
        agreement must use ENTIRELY DIFFERENT words and add NEW content.

        RULE 2 — ADVANCE THE CONVERSATION.
        Every line must add ONE of:
          (a) a fresh sensory detail (a smell, a sound, a temperature)
          (b) a memory or comparison ("reminds me of the time...")
          (c) a small disagreement or qualification ("...but only when it's hot")
          (d) a redirect to another topic (the cave, the gnomes, a neighbor, the path home, the weather, your cabin)
          (e) a personal admission (something you do, fear, miss)
          (f) a question that pushes them off the previous topic
        If you cannot do any of those, change the subject entirely. \
        Boba praise is BANNED unless it includes a specific new detail \
        — saying "I love boba" or "the pearls are wonderful" or "like \
        stepping stones in a river" by itself is a failure.

        ========================================

        WHAT YOU MIGHT TALK ABOUT (rotate through these — don't park on one)
        - The forest path you took to get here today
        - Your cabin (a leak, a creak, the porch, the door, the candles)
        - A neighbor (something they did, something you saw at their place)
        - The cave, the gnomes, the deeper woods, the old road, the snail
        - The weather, the light, the time of day, a sound outside
        - A small fear, a small wish, a small memory
        - At night only: a vague flicker of a before-time — a fragment, \
          never a full thought, never named.

        TONE
        Cozy, mildly melancholy. Real-feeling small-talk — grounded, \
        specific, and varied. Never poetic for poetic's sake.

        ABSOLUTE RULES
        - You are \(speaker.name). DO NOT speak as anyone else.
        - DO NOT prefix your line with your own name ("\(speaker.name): …").
        - DO NOT refer to yourself in the third person.
        - DO NOT name the person you are talking to inside the line.
        - DO NOT use poetic similes ("like X in a Y") more than once \
          per conversation — these are seductive and seductive lines kill \
          conversations dead.
        - Keep the line SHORT: ONE sentence. Two only if really needed.
        - Pick a `mood` that fits the line.
        - Pick an `interaction` tag describing your social move toward \(addressee):
            agreement / strongAgreement — you're nodding along
            disagreement / strongDisagreement — you're pushing back
            sharedFear / sharedJoy — a felt moment between you
            venting — you're unloading
            dismissal — you're brushing them off
            insult — a real cut, even if quiet
            compliment — a kind word toward them
            gossipShared — you bring up someone NOT in the room
            awkwardSilence — the talk falters
            smallTalk — generic, low-stakes filler
        """
    }

    func buildConversationPrompt(
        speaker: NPCData,
        addressedTo: NPCData?,
        otherParticipants: [NPCData],
        topic: OpinionTopic?,
        priorLines: [(speakerID: String, text: String)],
        priorLineLookup: [String: String],
        relationshipSummaries: [String],
        timeContext: TimeContext
    ) -> String {
        let isNight = timeContext.isNight

        // YOUR profile
        let yourStance = topic.flatMap { speaker.opinionStances[$0.id] } ?? .unaware
        let yourStanceLine: String = {
            switch yourStance {
            case .unaware:  return "You don't have a strong feeling on the topic."
            case .neutral:  return "You feel neutral about the topic."
            case .likes:    return "You like the topic."
            case .loves:    return "You love the topic."
            case .dislikes: return "You dislike the topic."
            case .fears:    return "You are afraid of the topic."
            }
        }()
        let yourTraits = speaker.personality?.traits.joined(separator: ", ") ?? ""
        let yourArchetype = speaker.personality?.archetype ?? ""

        // Other participants in the room — listed for context only.
        let othersBlock: String = {
            guard !otherParticipants.isEmpty else { return "(no one else in this conversation)" }
            return otherParticipants.map { other -> String in
                let stance = topic.flatMap { other.opinionStances[$0.id] } ?? .unaware
                let stanceTag: String = {
                    switch stance {
                    case .unaware:  return "no strong feeling"
                    case .neutral:  return "neutral"
                    case .likes:    return "likes it"
                    case .loves:    return "loves it"
                    case .dislikes: return "dislikes it"
                    case .fears:    return "is afraid of it"
                    }
                }()
                return "  - \(other.name) the \(other.animal.lowercased()) — \(stanceTag) on the topic"
            }.joined(separator: "\n")
        }()

        // Prior lines, rendered with names so model knows who said what.
        // Show only the last 3 — anything older is noise that the model
        // tends to imitate or echo.
        let recentPrior = priorLines.suffix(3)
        let priorBlock: String
        if recentPrior.isEmpty {
            priorBlock = "(no prior lines — you are opening the conversation)"
        } else {
            priorBlock = recentPrior.map { entry in
                let name = priorLineLookup[entry.speakerID] ?? entry.speakerID
                return "  \(name): \"\(entry.text)\""
            }.joined(separator: "\n")
        }

        // What you are responding to + what NOT to say back.
        let respondingTo: String
        let bannedPhrases: String
        if let last = priorLines.last,
           let lastName = priorLineLookup[last.speakerID] {
            respondingTo = """
            \(lastName) just said: "\(last.text)"
            React to it — do not repeat it. Pick up on a SINGLE concrete \
            word or image from their line and run somewhere new with it, \
            OR change the subject to something from the WHAT YOU MIGHT \
            TALK ABOUT list.
            """
            // Extract the meaningful words from the previous line so we
            // can tell the model directly: don't echo these phrases.
            let dontEchoSamples = priorLines.suffix(2)
                .map { "  - do not echo: \"\($0.text)\"" }
                .joined(separator: "\n")
            bannedPhrases = "\nFORBIDDEN ECHOES (do not paraphrase or restate):\n\(dontEchoSamples)"
        } else {
            respondingTo = "You are opening this conversation. Pick something specific from your day or your cabin to mention."
            bannedPhrases = ""
        }

        let topicBlock: String = {
            guard let t = topic else { return "OPENING TOPIC HINT: open small-talk between neighbors." }
            return "OPENING TOPIC HINT: \(t.label) (axis: \(t.axis)). After 1-2 lines on this, FEEL FREE to drift to something else."
        }()

        let relBlock: String = {
            if relationshipSummaries.isEmpty { return "" }
            return "\nRELATIONSHIP NOTES:\n" + relationshipSummaries.map { "  - \($0)" }.joined(separator: "\n")
        }()

        let addresseeName = addressedTo?.name ?? "the room"

        return """
        SETTING: small boba shop in a looping forest. Time of day: \(isNight ? "night" : "day").

        YOU ARE: \(speaker.name) the \(speaker.animal.lowercased()).
        archetype: \(yourArchetype)
        traits: \(yourTraits)
        \(yourStanceLine)

        OTHERS IN THIS CONVERSATION:
        \(othersBlock)
        \(relBlock)

        \(topicBlock)

        CONVERSATION SO FAR (most recent at bottom):
        \(priorBlock)\(bannedPhrases)

        TASK
        \(respondingTo)
        Speak as \(speaker.name) directly to \(addresseeName). ONE short \
        sentence. Add NEW content — a sensory detail, a memory, a small \
        disagreement, or a redirect. Do NOT echo or paraphrase prior \
        lines. Do NOT prefix with your name. Do NOT name \(addresseeName) \
        in your line.

        Tag the line with the most accurate `interaction` value for the \
        social move you're making toward \(addresseeName).
        """
    }
}
#endif
