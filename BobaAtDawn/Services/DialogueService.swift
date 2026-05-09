//
//  DialogueService.swift
//  BobaAtDawn
//
//  Service for managing NPC dialogue and character interactions.
//  Works with any DialoguePresenter (BaseNPC, ShopNPC, ForestNPCEntity).
//
//  Schema-v2 / multiplayer parity changes:
//    - DialogueShownMessage now carries `mood` and `sceneType`
//    - showRemoteDialogue is gated by sceneType (only renders if local
//      scene matches the broadcast)
//    - When a player taps a followup pill, that pill is highlighted +
//      the chosen text broadcast to the remote player as a final-text
//      bubble (so they see "what their partner said")
//    - On startup, NPC↔NPC relationship rows are seeded from JSON stance
//      overlap (idempotent — no-op on subsequent boots)
//

import SpriteKit
import Foundation

// MARK: - Active Dialogue Bundle

/// Per-NPC bookkeeping for one open dialogue bubble. Replaces the old
/// single-slot `activeBubble` / `activeAnchorNode` / `activeBubbleIsLocal`
/// trio. Indexed in DialogueService by NPC id so multiple NPCs can carry
/// on conversations with the player simultaneously.
private final class ActiveDialogueBundle {
    let bubble: DialogueBubble
    weak var anchor: SKNode?
    /// True when WE started this bubble (vs. it being painted from a
    /// remote peer's broadcast). Only locally-started bubbles auto-dismiss
    /// on distance — remote ones follow the partner's `dialogueDismissed`.
    let isLocal: Bool

    init(bubble: DialogueBubble, anchor: SKNode?, isLocal: Bool) {
        self.bubble = bubble
        self.anchor = anchor
        self.isLocal = isLocal
    }
}

// MARK: - Dialogue Service
class DialogueService {
    static let shared = DialogueService()

    private var npcDatabase: NPCDatabase?

    /// Open dialogue bubbles, keyed by NPC id. Multiple may be active at
    /// once — one per NPC the player has tapped.
    private var activeBubbles: [String: ActiveDialogueBundle] = [:]

    /// World-space distance at which a forgotten dialogue auto-dismisses.
    /// Roughly two grid "screens" — generous enough that idle wandering
    /// near the NPC won't kill the bubble, but tight enough that walking
    /// to the front door definitely does.
    private static let autoDismissDistance: CGFloat = 700

    /// Flag to prevent re-broadcasting when a dialogue action was triggered
    /// by a network message. Set true before local action, reset after.
    private var suppressNetworkBroadcast: Bool = false

    private init() {
        loadNPCData()
    }

    // MARK: - Data Loading
    private func loadNPCData() {
        guard let url = Bundle.main.url(forResource: "npc_dialogue", withExtension: "json") else {
            Log.error(.dialogue, "Could not find npc_dialogue.json")
            return
        }
        do {
            let data = try Data(contentsOf: url)
            npcDatabase = try JSONDecoder().decode(NPCDatabase.self, from: data)
            Log.info(.dialogue, "Loaded \(npcDatabase?.npcs.count ?? 0) NPCs (schema v\(npcDatabase?.schemaVersion ?? 1)) with \(npcDatabase?.opinionTopics.count ?? 0) opinion topics")

            // Seed pairwise NPC relationship rows from JSON stance overlap.
            // Idempotent — skips if rows already exist for n*(n-1) pairs.
            if let db = npcDatabase {
                SaveService.shared.seedRelationshipsIfNeeded(db)
            }
        } catch {
            Log.error(.dialogue, "Failed to load NPC dialogue data: \(error)")
        }
    }

    // MARK: - NPC Access
    func getAllNPCs() -> [NPCData] {
        npcDatabase?.npcs ?? []
    }

    func getNPC(byId id: String) -> NPCData? {
        npcDatabase?.npcs.first { $0.id == id }
    }

    func getRandomNPCs(count: Int) -> [NPCData] {
        Array(getAllNPCs().shuffled().prefix(count))
    }

    /// Public access to the global topic list — used by the conversation
    /// service when picking a topic seed two NPCs both have a stance on.
    func getOpinionTopics() -> [OpinionTopic] {
        npcDatabase?.opinionTopics ?? []
    }

    // MARK: - Scene Type Helper
    /// Build a sceneType string for outgoing dialogue messages, mirroring
    /// the convention used by PlayerPositionMessage.
    static func sceneTypeKey(for scene: SKScene?) -> String {
        guard let scene = scene else { return "shop" }
        if let forest = scene as? ForestScene {
            return "forest_\(forest.currentRoom)"
        }
        // Use the class name as a fallback so the receiving side can match.
        let className = String(describing: type(of: scene))
        switch className {
        case "GameScene":        return "shop"
        case "CaveScene":        return "cave"
        case "BigOakTreeScene":  return "big_oak"
        default:                  return className
        }
    }

    // MARK: - Show Dialogue (unified — works with any DialoguePresenter)
    func showDialogue(for presenter: DialoguePresenter, in scene: SKScene, timeContext: TimeContext) {
        guard let charId = presenter.dialogueCharacterId,
              let npcData = getNPC(byId: charId) else {
            Log.error(.dialogue, "No dialogue data for character: \(presenter.dialogueCharacterId ?? "nil")")
            return
        }

        // Replace this NPC's existing bubble (if any) without disturbing others.
        dismissDialogue(forNPCID: charId)

        presenter.freeze()

        let text = npcData.getRandomDialogue(isNight: timeContext.isNight)

        let bubble = DialogueBubble(
            text: text,
            speakerName: npcData.name,
            position: presenter.position,
            npcID: charId
        )

        scene.addChild(bubble)
        activeBubbles[charId] = ActiveDialogueBundle(
            bubble: bubble,
            anchor: presenter as? SKNode,
            isLocal: true
        )
        Log.info(.dialogue, "\(npcData.name): \(text)")

        // No network broadcast for legacy JSON path: it's only used as a
        // fallback when no NPCResident exists for this character (rare).
        // The new host-authoritative streaming path is what gets synced;
        // this is an offline-style backup. If both players hit it they'll
        // each render their own line locally, which is fine.
    }

    // MARK: - Custom Dialogue (ritual farewells)
    func showCustomDialogue(for presenter: DialoguePresenter, in scene: SKScene, customLines: [String]) {
        guard let charId = presenter.dialogueCharacterId,
              let npcData = getNPC(byId: charId) else {
            Log.error(.dialogue, "No dialogue data for NPC: \(presenter.dialogueCharacterId ?? "nil")")
            return
        }

        dismissDialogue(forNPCID: charId)

        presenter.freeze()
        let text = customLines.randomElement() ?? "Farewell..."

        let bubble = DialogueBubble(
            text: text,
            speakerName: npcData.name,
            position: presenter.position,
            npcID: charId,
            showResponseButtons: false
        )

        scene.addChild(bubble)
        activeBubbles[charId] = ActiveDialogueBundle(
            bubble: bubble,
            anchor: presenter as? SKNode,
            isLocal: true
        )
        Log.info(.dialogue, "\(npcData.name) (liberation): \(text)")
    }

    // MARK: - Static Dialogue (single line, no streaming, no followups)

    /// Render a one-shot bubble for a presenter. Used by short, finite
    /// systems like the gnome conversation service that don't need the
    /// full streaming/followup pipeline.
    ///
    /// Anchors directly to `presenter` so the auto-dismiss-on-distance
    /// path works for any DialoguePresenter — including gnomes. Earlier
    /// callers routed through `showRemoteDialogue`, which set the anchor
    /// by enumerating `"npc_*"` scene children. Gnome nodes are named
    /// `"gnome_*"`, so that lookup quietly returned nil and the bubble
    /// was killed on the next frame.
    func showStaticDialogue(
        for presenter: DialoguePresenter,
        speakerName: String,
        text: String,
        mood: String?,
        in scene: SKScene
    ) {
        let charId = presenter.dialogueCharacterId ?? speakerName

        // Replace this presenter's bubble (if any) without disturbing
        // unrelated open dialogues.
        dismissDialogue(forNPCID: charId)

        let bubble = DialogueBubble(
            text: text,
            speakerName: speakerName,
            position: presenter.position,
            npcID: charId,
            showResponseButtons: false   // terminal mode — no buttons
        )
        if let mood = mood, !mood.isEmpty {
            bubble.setMood(mood)
        }
        scene.addChild(bubble)

        // Anchor explicitly to the presenter (works for both BaseNPC
        // and GnomeNPC). isLocal=true so the auto-dismiss-on-distance
        // path still applies.
        let anchor = presenter as? SKNode
        activeBubbles[charId] = ActiveDialogueBundle(
            bubble: bubble, anchor: anchor, isLocal: true
        )
        Log.info(.dialogue, "[Static] \(speakerName)\(mood.map { " (\($0))" } ?? ""): \(text)")
    }

    // MARK: - Streaming LLM Dialogue (Host-Authoritative, Parallel Multi-NPC)

    /// Per-NPC followup pills that are pending pill-tap. Stored only on
    /// the host while the player is choosing kind vs blunt. Cleared once
    /// either pill is selected. Allows a remote pill-tap to map back to
    /// the right `LLMTone` even though the network message only carries
    /// the chosen text.
    private var pendingFollowups: [String: [DialogueFollowup]] = [:]

    /// Public entry point used by `BaseNPC.showDialogue`. Decides whether
    /// to handle the open locally (host or solo) or send a request to the
    /// host (guest).
    func requestDialogueOpen(
        for presenter: DialoguePresenter,
        in scene: SKScene,
        timeContext: TimeContext,
        resident: NPCResident,
        memory: NPCMemory?
    ) {
        let charId = presenter.dialogueCharacterId ?? resident.npcData.id

        // Solo or host: drive the dialogue locally.
        if !MultiplayerService.shared.isConnected || MultiplayerService.shared.isHost {
            hostStartDialogue(
                presenter: presenter, scene: scene,
                timeContext: timeContext,
                resident: resident, memory: memory,
                npcID: charId
            )
            return
        }

        // Guest: send an open-request to host. Bubble is opened on the
        // host's `dialogueOpened` broadcast — not locally — so both
        // players see the exact same anchor and timing.
        presenter.freeze()
        MultiplayerService.shared.send(
            type: .dialogueOpenRequest,
            payload: DialogueOpenRequestMessage(
                npcID: charId,
                sceneType: DialogueService.sceneTypeKey(for: scene)
            )
        )
    }

    /// Host-side dialogue open. Creates the bubble locally, broadcasts
    /// `dialogueOpened` to the guest, then drives the LLM stream and
    /// broadcasts incremental deltas. Called both for the host's own
    /// taps and in response to a guest's `dialogueOpenRequest`.
    func hostStartDialogue(
        presenter: DialoguePresenter,
        scene: SKScene,
        timeContext: TimeContext,
        resident: NPCResident,
        memory: NPCMemory?,
        npcID: String
    ) {
        let npcData = resident.npcData

        // Replace this NPC's existing bubble if any (e.g. rapid re-tap).
        dismissDialogue(forNPCID: npcID)
        presenter.freeze()

        let bubble = DialogueBubble(
            text: "...",
            speakerName: npcData.name,
            position: presenter.position,
            npcID: npcID,
            mode: .streamingLLM
        )
        scene.addChild(bubble)
        activeBubbles[npcID] = ActiveDialogueBundle(
            bubble: bubble,
            anchor: presenter as? SKNode,
            isLocal: true
        )

        // Tell the guest to open a matching empty bubble. They'll listen
        // for `dialogueLineDelta` to fill it in.
        if MultiplayerService.shared.isConnected {
            MultiplayerService.shared.send(
                type: .dialogueOpened,
                payload: DialogueOpenedMessage(
                    npcID: npcID,
                    speakerName: npcData.name,
                    position: CodablePoint(presenter.position),
                    sceneType: DialogueService.sceneTypeKey(for: scene)
                )
            )
        }

        // Prefer prewarmed entry, else live stream, else JSON fallback.
        let stream: AsyncThrowingStream<DialogueStreamUpdate, Error>?
        if let cached = LLMDialogueService.shared.consumePrewarmed(
            for: npcID, isNight: timeContext.isNight
        ) {
            Log.debug(.dialogue, "[Prewarm hit] \(npcData.name)")
            stream = cached
        } else {
            stream = LLMDialogueService.shared.streamInitialLine(
                for: resident, memory: memory, timeContext: timeContext
            )
        }

        guard let stream = stream else {
            // No LLM available — fall back to one JSON line WITH followup
            // pills so the satisfaction loop still works on iPad without
            // Apple Intelligence. Renders the same kind/blunt pair the
            // LLM path would have produced, sourced from `tap_followups`
            // in the NPC JSON.
            let text = npcData.getRandomDialogue(isNight: timeContext.isNight)
            bubble.setText(text)
            broadcastLineDelta(npcID: npcID, partialText: text, mood: nil)
            self.installJSONFallbackFollowups(
                bubble: bubble, npcID: npcID, npcData: npcData
            )
            Log.info(.dialogue, "[Fallback JSON+pills] \(npcData.name): \(text)")
            return
        }

        Task { @MainActor [weak self, weak bubble] in
            guard let self = self, let bubble = bubble else { return }
            var lastBroadcastText = ""
            var lastBroadcastMood: String? = nil
            var lastBroadcastTime: TimeInterval = 0
            let throttleInterval: TimeInterval = 0.10  // ~10 deltas/sec
            var finalFollowups: [DialogueFollowup] = []
            do {
                for try await update in stream {
                    if let line = update.line {
                        bubble.setText(line)
                        // Throttled broadcast: only when text changed AND
                        // 100ms have passed (or it's the final line).
                        let now = Date().timeIntervalSinceReferenceDate
                        let textChanged = line != lastBroadcastText
                        let moodChanged = update.mood != nil && update.mood != lastBroadcastMood
                        let dueByTime = (now - lastBroadcastTime) >= throttleInterval
                        if textChanged && (dueByTime || moodChanged) {
                            lastBroadcastText = line
                            if update.mood != nil { lastBroadcastMood = update.mood }
                            lastBroadcastTime = now
                            self.broadcastLineDelta(
                                npcID: npcID, partialText: line, mood: update.mood
                            )
                        }
                    }
                    if let mood = update.mood {
                        bubble.setMood(mood)
                    }
                    if let followups = update.followups, !followups.isEmpty {
                        finalFollowups = followups
                        bubble.setFollowups(followups) { [weak self] tone, text in
                            self?.handleFollowupTapLocal(
                                tone: tone, playerSaid: text,
                                npcID: npcID, npcName: npcData.name
                            )
                        }
                    }
                    if update.isComplete { break }
                }
                // Force one final delta so the guest's bubble shows the
                // exact same text we ended on, even if the throttle
                // dropped the last token-batch.
                if !lastBroadcastText.isEmpty {
                    self.broadcastLineDelta(
                        npcID: npcID, partialText: lastBroadcastText,
                        mood: lastBroadcastMood
                    )
                }
                // Followups: stash for pill-tap routing + broadcast to guest.
                if !finalFollowups.isEmpty {
                    self.pendingFollowups[npcID] = finalFollowups
                    let kind = finalFollowups.first(where: { $0.tone == .kind })?.text ?? ""
                    let blunt = finalFollowups.first(where: { $0.tone == .blunt })?.text ?? ""
                    if MultiplayerService.shared.isConnected {
                        MultiplayerService.shared.send(
                            type: .dialogueFollowupsReady,
                            payload: DialogueFollowupsReadyMessage(
                                npcID: npcID, kindText: kind, bluntText: blunt
                            )
                        )
                    }
                }
                Log.info(.dialogue, "[LLM] \(npcData.name): \(lastBroadcastText)")
            } catch {
                // Stream failed mid-flight — fall back to JSON line + pills
                // so the player still gets a usable satisfaction loop.
                let text = npcData.getRandomDialogue(isNight: timeContext.isNight)
                bubble.setText(text)
                self.broadcastLineDelta(npcID: npcID, partialText: text, mood: nil)
                self.installJSONFallbackFollowups(
                    bubble: bubble, npcID: npcID, npcData: npcData
                )
                Log.warn(.dialogue, "[LLM failed → JSON+pills] \(npcData.name): \(text)")
            }
        }
    }

    /// Send one streaming-delta update to the guest. Cumulative-text style
    /// so out-of-order delivery is harmless — the next delta supersedes.
    private func broadcastLineDelta(npcID: String, partialText: String, mood: String?) {
        guard MultiplayerService.shared.isConnected else { return }
        MultiplayerService.shared.send(
            type: .dialogueLineDelta,
            payload: DialogueLineDeltaMessage(
                npcID: npcID, partialText: partialText, mood: mood
            )
        )
    }

    /// Local pill-tap handler installed by `hostStartDialogue` on the
    /// bubble. Equivalent to the host receiving its own pill-tap. Records
    /// satisfaction, broadcasts the choice (so guest sees "P1 said X"),
    /// confirms the visual selection, and runs turn-2 reply on host.
    private func handleFollowupTapLocal(
        tone: LLMTone, playerSaid: String,
        npcID: String, npcName: String
    ) {
        // Record + broadcast satisfaction effect.
        SaveService.shared.recordNPCInteraction(npcID, responseType: tone.responseType)
        if MultiplayerService.shared.isConnected {
            MultiplayerService.shared.send(
                type: .npcInteraction,
                payload: NPCInteractionMessage(npcID: npcID, responseType: tone.responseType.rawValue)
            )
            // Broadcast the chosen pill so the guest sees a brief
            // "P1 said X" cue before turn-2 streams.
            MultiplayerService.shared.send(
                type: .dialogueFollowupChosen,
                payload: DialogueFollowupChosenMessage(
                    npcID: npcID, chosenText: playerSaid, tone: tone.rawValue
                )
            )
        }
        if let bubble = activeBubbles[npcID]?.bubble {
            bubble.confirmFollowupChoice(text: playerSaid, tone: tone)
            bubble.run(SKAction.wait(forDuration: 0.45)) { [weak self] in
                self?.hostStreamTurn2Reply(
                    tone: tone, playerSaid: playerSaid,
                    npcID: npcID, npcName: npcName
                )
            }
        } else {
            // Bubble vanished mid-pill (rare). Still run turn-2 so guest
            // sees a closing line; we just won't render it locally.
            hostStreamTurn2Reply(
                tone: tone, playerSaid: playerSaid,
                npcID: npcID, npcName: npcName
            )
        }
        pendingFollowups.removeValue(forKey: npcID)
    }

    // MARK: - JSON Fallback Pills

    /// Install kind/blunt followup pills sourced from the NPC's JSON
    /// `tap_followups` block, used when the LLM is unavailable
    /// (iPad without Apple Intelligence, model cold-start, mid-stream
    /// error). Mirrors the path the LLM stream would take when it emits
    /// `update.followups`: stash for routing, broadcast to guest,
    /// install the same pill-tap callback that records satisfaction
    /// and runs turn-2 reply.
    private func installJSONFallbackFollowups(
        bubble: DialogueBubble,
        npcID: String,
        npcData: NPCData
    ) {
        let kindLine  = npcData.getRandomKindFollowup()
        let bluntLine = npcData.getRandomBluntFollowup()
        let followups: [DialogueFollowup] = [
            DialogueFollowup(text: kindLine,  tone: .kind),
            DialogueFollowup(text: bluntLine, tone: .blunt)
        ]
        let npcName = npcData.name
        bubble.setFollowups(followups) { [weak self] tone, text in
            self?.handleFollowupTapLocal(
                tone: tone, playerSaid: text,
                npcID: npcID, npcName: npcName
            )
        }
        pendingFollowups[npcID] = followups
        if MultiplayerService.shared.isConnected {
            MultiplayerService.shared.send(
                type: .dialogueFollowupsReady,
                payload: DialogueFollowupsReadyMessage(
                    npcID: npcID, kindText: kindLine, bluntText: bluntLine
                )
            )
        }
    }

    /// Host-side handler for `dialogueFollowupChosen` arriving from the
    /// guest. Confirms the visual on the host's bubble, drives turn-2.
    func applyRemoteFollowupChosen(npcID: String, chosenText: String, toneRaw: String) {
        let tone = LLMTone.from(toneRaw)
        // Reflect satisfaction (the guest already broadcast .npcInteraction).
        if let bubble = activeBubbles[npcID]?.bubble {
            bubble.confirmFollowupChoice(text: chosenText, tone: tone)
        }
        // Brief pause then run turn-2 so both players see the same beat.
        let npcName = getNPC(byId: npcID)?.name ?? npcID
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
            self?.hostStreamTurn2Reply(
                tone: tone, playerSaid: chosenText,
                npcID: npcID, npcName: npcName
            )
        }
        pendingFollowups.removeValue(forKey: npcID)
    }

    /// Host-only: stream turn-2 reply. Updates the local bubble live and
    /// broadcasts deltas to the guest. Auto-dismisses both sides after
    /// the reading beat.
    private func hostStreamTurn2Reply(
        tone: LLMTone, playerSaid: String,
        npcID: String, npcName: String
    ) {
        let bubble = activeBubbles[npcID]?.bubble
        bubble?.setText("...")
        bubble?.enterTerminalMode()

        guard let stream = LLMDialogueService.shared.streamReply(
            forNPCID: npcID, playerSaid: playerSaid, tone: tone
        ) else {
            // No turn-2 — dismiss after a beat.
            (bubble ?? SKNode()).run(SKAction.sequence([
                SKAction.wait(forDuration: 1.2),
                SKAction.run { [weak self] in self?.dismissDialogue(forNPCID: npcID) }
            ]))
            return
        }

        Task { @MainActor [weak self, weak bubble] in
            guard let self = self else { return }
            var lastBroadcastText = ""
            var lastBroadcastMood: String? = nil
            var lastBroadcastTime: TimeInterval = 0
            let throttleInterval: TimeInterval = 0.10
            do {
                for try await update in stream {
                    if let line = update.line {
                        bubble?.setText(line)
                        let now = Date().timeIntervalSinceReferenceDate
                        let textChanged = line != lastBroadcastText
                        let moodChanged = update.mood != nil && update.mood != lastBroadcastMood
                        let dueByTime = (now - lastBroadcastTime) >= throttleInterval
                        if textChanged && (dueByTime || moodChanged) {
                            lastBroadcastText = line
                            if update.mood != nil { lastBroadcastMood = update.mood }
                            lastBroadcastTime = now
                            self.broadcastLineDelta(
                                npcID: npcID, partialText: line, mood: update.mood
                            )
                        }
                    }
                    if let mood = update.mood {
                        bubble?.setMood(mood)
                    }
                    if update.isComplete { break }
                }
                if !lastBroadcastText.isEmpty {
                    self.broadcastLineDelta(
                        npcID: npcID, partialText: lastBroadcastText,
                        mood: lastBroadcastMood
                    )
                    Log.info(.dialogue, "[LLM reply] \(npcName): \(lastBroadcastText)")
                }
                // Dismiss after a reading beat. Use a dispatch timer
                // rather than SKAction.run — inside @MainActor Tasks the
                // compiler picks the async overload of SKNode.run and
                // complains about missing await.
                DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
                    self?.dismissDialogue(forNPCID: npcID)
                }
            } catch {
                Log.warn(.dialogue, "[LLM reply failed] \(error)")
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
                    self?.dismissDialogue(forNPCID: npcID)
                }
            }
        }
    }

    // MARK: - Dismiss

    /// Dismiss every open dialogue bubble. Used on scene transitions.
    func dismissAllDialogues() {
        // Snapshot keys so we can mutate `activeBubbles` while iterating.
        let keys = Array(activeBubbles.keys)
        for npcID in keys {
            dismissDialogue(forNPCID: npcID)
        }
    }

    /// Backwards-compatible name. Keeps existing callers working without
    /// scattering `dismissAllDialogues()` everywhere. Same behavior.
    func dismissDialogue() {
        dismissAllDialogues()
    }

    /// Dismiss the bubble for one specific NPC. Other NPCs' bubbles are
    /// untouched. This is what room/scene transitions and the per-bubble
    /// auto-dismiss path call.
    func dismissDialogue(forNPCID npcID: String) {
        guard let bundle = activeBubbles.removeValue(forKey: npcID) else { return }

        let bubbleScene = bundle.bubble.scene
        bundle.bubble.removeFromParent()

        // Drop per-NPC bookkeeping.
        LLMDialogueService.shared.endSession(forNPCID: npcID)
        pendingFollowups.removeValue(forKey: npcID)

        // Unfreeze just this NPC / gnome if we can find it.
        // Try the anchor first (cheap, exact). The anchor is stored
        // weakly so it may already be gone; fall back to a scene
        // enumeration for both BaseNPC and GnomeNPC names if so.
        var unfrozeViaAnchor = false
        if let presenter = bundle.anchor as? DialoguePresenter {
            presenter.unfreeze()
            unfrozeViaAnchor = true
        }
        if !unfrozeViaAnchor, let scene = bubbleScene {
            var found = false
            scene.enumerateChildNodes(withName: "npc_*") { node, stop in
                if let npc = node as? BaseNPC,
                   npc.dialogueCharacterId == npcID {
                    npc.unfreeze()
                    found = true
                    stop.pointee = true
                }
            }
            if !found {
                // Gnomes live under "gnome_*" and aren't BaseNPCs.
                scene.enumerateChildNodes(withName: "gnome_*") { node, stop in
                    if let gnome = node as? GnomeNPC,
                       gnome.agent.identity.id == npcID {
                        gnome.unfreeze()
                        stop.pointee = true
                    }
                }
            }
        }

        // Re-warm so the next tap is also instant.
        LLMDialogueService.shared.requestPrewarm(forNPCID: npcID)

        // Per-NPC dismiss broadcast. Either side may originate dismissal
        // (host running turn-2 timer, either player tapping the bubble),
        // and the receiver knows exactly which bubble to close.
        if !suppressNetworkBroadcast && MultiplayerService.shared.isConnected {
            MultiplayerService.shared.send(
                type: .dialogueDismissed,
                payload: DialogueDismissedMessage(npcID: npcID)
            )
        }
    }

    func isDialogueActive() -> Bool {
        !activeBubbles.isEmpty
    }

    /// True when this specific NPC has an open bubble. Used by
    /// `BaseNPC.touchesBegan` to gate per-NPC re-taps without blocking
    /// taps on other NPCs.
    func isDialogueActive(forNPCID npcID: String) -> Bool {
        activeBubbles[npcID] != nil
    }

    /// Called each frame by `BaseGameScene.update` so the service can
    /// auto-dismiss "forgotten" dialogues. Per-bubble checks now — each
    /// open bubble is evaluated independently, so the player walking
    /// away from one NPC doesn't kill the others.
    ///
    /// Locally-anchored bubbles (whether host or guest started them) get
    /// auto-dismissed on distance/scene mismatch. The dismissal sends a
    /// per-NPC `dialogueDismissed` so the partner closes their copy too.
    func updateForPlayerPosition(_ playerPosition: CGPoint) {
        guard !activeBubbles.isEmpty else { return }

        // Snapshot to allow mutation during iteration.
        let snapshot = activeBubbles
        for (npcID, bundle) in snapshot {
            // Anchor went away or moved to a different scene — dismiss.
            guard let anchor = bundle.anchor,
                  let anchorScene = anchor.scene,
                  anchorScene === bundle.bubble.scene else {
                Log.debug(.dialogue, "Auto-dismissing dialogue for \(npcID) — anchor gone or scene changed")
                dismissDialogue(forNPCID: npcID)
                continue
            }

            let dx = playerPosition.x - anchor.position.x
            let dy = playerPosition.y - anchor.position.y
            let distance = hypot(dx, dy)
            if distance > Self.autoDismissDistance {
                Log.debug(.dialogue, "Auto-dismissing dialogue for \(npcID) — player walked away (\(Int(distance))pt)")
                dismissDialogue(forNPCID: npcID)
            }
        }
    }

    // MARK: - Network Dialogue (Host-Authoritative Streaming)

    /// Host received an open-request from the guest. Validate and start
    /// the dialogue locally; the rest is the same broadcast pipeline as
    /// when the host taps an NPC themself.
    func hostHandleOpenRequest(_ msg: DialogueOpenRequestMessage, in scene: SKScene) {
        // Scene gate: the requesting player must be in our scene.
        let myScene = DialogueService.sceneTypeKey(for: scene)
        guard msg.sceneType == myScene else {
            Log.debug(.dialogue, "[Host] Ignoring open-request for \(msg.npcID) — scene mismatch (\(msg.sceneType) vs \(myScene))")
            return
        }
        // Find the matching local NPC node so we have a presenter.
        var found: BaseNPC?
        scene.enumerateChildNodes(withName: "npc_*") { node, stop in
            if let npc = node as? BaseNPC,
               npc.dialogueCharacterId == msg.npcID {
                found = npc
                stop.pointee = true
            }
        }
        guard let presenter = found else {
            Log.debug(.dialogue, "[Host] Ignoring open-request for \(msg.npcID) — NPC not in scene")
            return
        }
        guard let resident = NPCResidentManager.shared.findResident(byID: msg.npcID) else {
            Log.debug(.dialogue, "[Host] Ignoring open-request — no resident for \(msg.npcID)")
            return
        }
        let memory = SaveService.shared.getNPCMemory(msg.npcID)
        let isNight = (TimeManager.shared.currentPhase == .night)
        let timeContext: TimeContext = isNight ? .night : .day
        hostStartDialogue(
            presenter: presenter, scene: scene,
            timeContext: timeContext,
            resident: resident, memory: memory,
            npcID: msg.npcID
        )
    }

    /// Either side: `dialogueOpened` arrived. The guest creates a fresh
    /// streaming bubble; the host typically already has one open and
    /// no-ops (the host emitted this message in the first place). Bubble
    /// created here is anchored to the local NPC node — not to the host's
    /// position — so it visually follows our copy of the NPC.
    func applyDialogueOpened(_ msg: DialogueOpenedMessage, in scene: SKScene) {
        guard msg.sceneType == DialogueService.sceneTypeKey(for: scene) else { return }
        // Already have a bubble for this NPC? No-op (host case).
        if activeBubbles[msg.npcID] != nil { return }

        suppressNetworkBroadcast = true
        defer { suppressNetworkBroadcast = false }

        let bubble = DialogueBubble(
            text: "...",
            speakerName: msg.speakerName,
            position: msg.position.cgPoint,
            npcID: msg.npcID,
            mode: .streamingLLM
        )
        scene.addChild(bubble)

        // Anchor to the local NPC node if present so the bubble follows it.
        var anchor: SKNode? = nil
        scene.enumerateChildNodes(withName: "npc_*") { node, stop in
            if let npc = node as? BaseNPC,
               npc.dialogueCharacterId == msg.npcID {
                npc.freeze()
                anchor = npc
                stop.pointee = true
            }
        }
        // isLocal=true so updateForPlayerPosition prunes it when we
        // walk away — same as a host-started bubble. The host bubble's
        // dismissal will broadcast a dialogueDismissed that closes the
        // partner's copy too.
        activeBubbles[msg.npcID] = ActiveDialogueBundle(
            bubble: bubble, anchor: anchor, isLocal: true
        )
        Log.info(.dialogue, "[Network] dialogueOpened for \(msg.speakerName)")
    }

    /// Either side: `dialogueLineDelta` arrived. Apply to the bubble.
    /// Cumulative-text — just overwrite. Mood updates the emoji slot.
    func applyDialogueLineDelta(_ msg: DialogueLineDeltaMessage) {
        guard let bundle = activeBubbles[msg.npcID] else { return }
        bundle.bubble.setText(msg.partialText)
        if let mood = msg.mood, !mood.isEmpty {
            bundle.bubble.setMood(mood)
        }
    }

    /// Guest side: `dialogueFollowupsReady` arrived. Render the kind/blunt
    /// pills on our bubble and wire pill-tap to broadcast the choice back
    /// to the host (which the host will route to turn-2 reply).
    func applyDialogueFollowupsReady(_ msg: DialogueFollowupsReadyMessage, in scene: SKScene) {
        guard let bundle = activeBubbles[msg.npcID] else { return }
        var followups: [DialogueFollowup] = []
        if !msg.kindText.isEmpty {
            followups.append(DialogueFollowup(text: msg.kindText, tone: .kind))
        }
        if !msg.bluntText.isEmpty {
            followups.append(DialogueFollowup(text: msg.bluntText, tone: .blunt))
        }
        guard !followups.isEmpty else { return }
        // Stash so a guest-side pill-tap can use the same routing.
        pendingFollowups[msg.npcID] = followups

        let npcID = msg.npcID
        bundle.bubble.setFollowups(followups) { [weak self] tone, text in
            self?.handleGuestFollowupTap(
                tone: tone, playerSaid: text,
                npcID: npcID
            )
        }
    }

    /// Guest pressed a pill. Record satisfaction locally (so both saves
    /// agree), broadcast `npcInteraction` + `dialogueFollowupChosen`,
    /// confirm visual selection on guest's bubble. Host's
    /// `applyRemoteFollowupChosen` will run turn-2 and stream deltas.
    private func handleGuestFollowupTap(
        tone: LLMTone, playerSaid: String, npcID: String
    ) {
        SaveService.shared.recordNPCInteraction(npcID, responseType: tone.responseType)
        if MultiplayerService.shared.isConnected {
            MultiplayerService.shared.send(
                type: .npcInteraction,
                payload: NPCInteractionMessage(npcID: npcID, responseType: tone.responseType.rawValue)
            )
            MultiplayerService.shared.send(
                type: .dialogueFollowupChosen,
                payload: DialogueFollowupChosenMessage(
                    npcID: npcID, chosenText: playerSaid, tone: tone.rawValue
                )
            )
        }
        if let bubble = activeBubbles[npcID]?.bubble {
            bubble.confirmFollowupChoice(text: playerSaid, tone: tone)
        }
        pendingFollowups.removeValue(forKey: npcID)
    }

    /// Show the remote player's pill choice as a brief "they said X" beat.
    func showRemoteFollowupChoice(npcID: String, chosenText: String, tone: String, in scene: SKScene) {
        guard let bubble = activeBubbles[npcID]?.bubble else { return }
        bubble.showRemotePlayerChoice(text: chosenText, toneRaw: tone)
    }

    /// Either side: `dialogueDismissed` arrived. If `npcID` is provided,
    /// dismiss only that bubble; otherwise (legacy back-compat) flush all.
    func dismissRemoteDialogue(forNPCID npcID: String? = nil) {
        suppressNetworkBroadcast = true
        defer { suppressNetworkBroadcast = false }
        if let npcID = npcID {
            dismissDialogue(forNPCID: npcID)
        } else {
            dismissAllDialogues()
        }
    }

    /// Legacy entry point for showing a remote bubble — kept for
    /// callsites that haven't moved to the streaming protocol yet (e.g.
    /// liberation farewells go through the JSON dialogueShown channel).
    /// New host-authoritative streaming uses `applyDialogueOpened` +
    /// `applyDialogueLineDelta` instead.
    func showRemoteDialogue(npcID: String, speakerName: String, text: String,
                            mood: String?, at position: CGPoint, in scene: SKScene) {
        suppressNetworkBroadcast = true
        // Replace just this NPC's existing bubble (if any) without
        // disturbing local bubbles for other NPCs.
        dismissDialogue(forNPCID: npcID)

        let bubble = DialogueBubble(
            text: text,
            speakerName: speakerName,
            position: position,
            npcID: npcID,
            showResponseButtons: false
        )
        if let mood = mood, !mood.isEmpty {
            bubble.setMood(mood)
        }
        scene.addChild(bubble)

        var anchor: SKNode? = nil
        scene.enumerateChildNodes(withName: "npc_*") { node, stop in
            if let npc = node as? BaseNPC,
               npc.dialogueCharacterId == npcID {
                npc.freeze()
                anchor = npc
                stop.pointee = true
            }
        }
        activeBubbles[npcID] = ActiveDialogueBundle(
            bubble: bubble, anchor: anchor, isLocal: false
        )
        suppressNetworkBroadcast = false
        Log.info(.dialogue, "[Remote legacy] \(speakerName)\(mood.map { " (\($0))" } ?? ""): \(text)")
    }

    // MARK: - NPC Conversation Bubble (NPC ↔ NPC)

    /// Render one line of an NPC↔NPC conversation as a small bubble above
    /// `speakerNode`. Doesn't replace the activeBubble (which is reserved
    /// for player↔NPC). Auto-fades after `lifetime`.
    @discardableResult
    func showConversationLine(
        speakerNode: SKNode,
        speakerName: String,
        text: String,
        mood: String?,
        in scene: SKScene,
        lifetime: TimeInterval = 6.5
    ) -> SKNode {
        let bubble = ConversationLineBubble(
            text: text,
            speakerName: speakerName,
            mood: mood,
            position: speakerNode.position
        )
        scene.addChild(bubble)
        bubble.run(SKAction.sequence([
            SKAction.wait(forDuration: lifetime),
            SKAction.fadeOut(withDuration: 0.4),
            SKAction.removeFromParent()
        ]))
        return bubble
    }
}

// MARK: - Speech Bubble Component
class DialogueBubble: SKNode {

    // MARK: - Mode
    enum BubbleMode {
        case legacyJSON      // Original 3-emoji buttons (❌😊😠). Used by JSON dialogue.
        case streamingLLM    // Mutable text/mood/followup buttons. Used by LLM dialogue.
        case terminal        // Text only, no buttons. Liberation farewells, remote bubbles, turn-2 replies.
    }

    // MARK: - Children
    private let bubbleBackground: SKShapeNode
    private let textLabel: SKLabelNode
    private let nameLabel: SKLabelNode
    private let moodLabel: SKLabelNode      // Emoji slot to right of name (LLM mood)
    private let responseButtons: SKNode     // Legacy emoji buttons
    private let followupButtons: SKNode     // LLM-generated followup pills

    private let npcID: String
    private var mode: BubbleMode
    private var followupCount: Int = 0
    private var followupTapHandler: ((LLMTone, String) -> Void)?

    // MARK: - Constants
    private static let bubbleWidth: CGFloat = 320
    private static let baseHeight: CGFloat = 120
    private static let legacyButtonsExtraHeight: CGFloat = 40    // matches original 160
    private static let buttonRowHeight: CGFloat = 36

    // MARK: - Designated Init
    init(text: String, speakerName: String, position: CGPoint, npcID: String, mode: BubbleMode) {
        self.npcID = npcID
        self.mode = mode

        let initialHeight = DialogueBubble.heightFor(mode: mode, followupCount: 0)
        let initialSize = CGSize(width: DialogueBubble.bubbleWidth, height: initialHeight)

        bubbleBackground = SKShapeNode()
        bubbleBackground.path = DialogueBubble.makePath(size: initialSize)
        bubbleBackground.fillColor = SKColor.white.withAlphaComponent(0.95)
        bubbleBackground.strokeColor = SKColor.black.withAlphaComponent(0.7)
        bubbleBackground.lineWidth = 2
        bubbleBackground.name = "dialogue_bubble"

        nameLabel = SKLabelNode(text: speakerName)
        nameLabel.fontName = "Arial-Bold"
        nameLabel.fontSize = 14
        nameLabel.fontColor = SKColor.darkGray
        nameLabel.horizontalAlignmentMode = .center
        nameLabel.verticalAlignmentMode = .center

        moodLabel = SKLabelNode(text: "")
        moodLabel.fontName = "Arial"
        moodLabel.fontSize = 16
        moodLabel.horizontalAlignmentMode = .left
        moodLabel.verticalAlignmentMode = .center

        textLabel = SKLabelNode(text: text)
        textLabel.fontName = "Arial"
        textLabel.fontSize = 12
        textLabel.fontColor = SKColor.black
        textLabel.horizontalAlignmentMode = .center
        textLabel.verticalAlignmentMode = .center
        textLabel.numberOfLines = 4
        textLabel.preferredMaxLayoutWidth = initialSize.width - 20

        responseButtons = SKNode()
        followupButtons = SKNode()

        super.init()

        self.position = CGPoint(x: position.x, y: position.y + 100)
        self.zPosition = ZLayers.dialogueUI

        addChild(bubbleBackground)
        addChild(nameLabel)
        addChild(moodLabel)
        addChild(textLabel)
        addChild(responseButtons)
        addChild(followupButtons)

        if mode == .legacyJSON {
            setupLegacyResponseButtons()
        }

        layoutContents()

        isUserInteractionEnabled = true

        alpha = 0; setScale(0.5)
        run(SKAction.group([
            SKAction.fadeIn(withDuration: 0.3),
            SKAction.scale(to: 1.0, duration: 0.3)
        ]))
    }

    /// Backwards-compatible convenience init for legacy JSON / liberation /
    /// remote bubbles. Maps `showResponseButtons` onto the new `mode` enum.
    convenience init(text: String, speakerName: String, position: CGPoint,
                     npcID: String, showResponseButtons: Bool = true) {
        self.init(text: text, speakerName: speakerName, position: position, npcID: npcID,
                  mode: showResponseButtons ? .legacyJSON : .terminal)
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Public Mutators (used by streaming dialogue path)

    /// Update the displayed text. Safe to call repeatedly during streaming.
    func setText(_ text: String) {
        textLabel.text = text
    }

    /// Set the mood emoji shown next to the speaker's name.
    func setMood(_ moodKey: String) {
        moodLabel.text = DialogueBubble.emojiForMood(moodKey)
        // Reposition since name label may have shifted.
        layoutContents()
    }

    /// Replace the followup buttons with LLM-generated options. Resizes the
    /// bubble vertically to fit. Tap callback fires with the chosen tone+text.
    func setFollowups(_ followups: [DialogueFollowup],
                      onTap: @escaping (LLMTone, String) -> Void) {
        followupButtons.removeAllChildren()
        followupTapHandler = onTap
        followupCount = min(followups.count, 2)

        for (i, fu) in followups.prefix(2).enumerated() {
            followupButtons.addChild(makeFollowupButton(text: fu.text, tone: fu.tone, index: i))
        }

        resizeBubble()
        layoutContents()
    }

    /// Visually confirm which followup the local player just tapped.
    /// Highlights the chosen pill, dims the others, and disables further
    /// taps. Used for the "selected pill stays on screen" beat before
    /// turn-2 reply streams.
    func confirmFollowupChoice(text: String, tone: LLMTone) {
        followupTapHandler = nil
        for child in followupButtons.children {
            guard let userInfo = child.userData,
                  let pillText = userInfo["text"] as? String else {
                child.alpha = 0.25
                continue
            }
            if pillText == text {
                // Chosen — pulse + bold tint
                if let bg = child.children.compactMap({ $0 as? SKShapeNode }).first {
                    bg.strokeColor = SKColor.black
                    bg.lineWidth = 2.5
                    bg.fillColor = bg.fillColor.brighter(by: 1.15)
                }
                child.run(SKAction.sequence([
                    SKAction.scale(to: 1.05, duration: 0.10),
                    SKAction.scale(to: 1.0,  duration: 0.10)
                ]))
            } else {
                // Unchosen — fade
                child.run(SKAction.fadeAlpha(to: 0.30, duration: 0.20))
            }
        }
    }

    /// Show the remote player's pill choice as a small ephemeral label
    /// above the bubble. Auto-fades after a beat.
    func showRemotePlayerChoice(text: String, toneRaw: String) {
        let tone = LLMTone.from(toneRaw)
        let label = SKLabelNode(text: "P2: \(text)")
        label.fontName = "Arial-Bold"
        label.fontSize = 11
        label.fontColor = SKColor.darkGray
        label.horizontalAlignmentMode = .center
        label.verticalAlignmentMode = .center

        let height = DialogueBubble.heightFor(mode: mode, followupCount: followupCount)
        let pillSize = CGSize(width: 280, height: 24)
        let bg = SKShapeNode(rectOf: pillSize, cornerRadius: 10)
        bg.fillColor = colorForTone(tone)
        bg.strokeColor = SKColor.darkGray
        bg.lineWidth = 1

        let container = SKNode()
        container.zPosition = 10
        container.position = CGPoint(x: 0, y: height/2 + 20)
        container.addChild(bg)
        container.addChild(label)
        container.alpha = 0
        addChild(container)

        container.run(SKAction.sequence([
            SKAction.fadeIn(withDuration: 0.2),
            SKAction.wait(forDuration: 1.4),
            SKAction.fadeOut(withDuration: 0.4),
            SKAction.removeFromParent()
        ]))
    }

    /// Strip all interactive buttons (used for turn-2 reply or fallback).
    /// Tap-bubble-to-dismiss still works.
    func enterTerminalMode() {
        mode = .terminal
        followupCount = 0
        followupButtons.removeAllChildren()
        responseButtons.removeAllChildren()
        followupTapHandler = nil
        resizeBubble()
        layoutContents()
    }

    // MARK: - Layout

    private func resizeBubble() {
        let height = DialogueBubble.heightFor(mode: mode, followupCount: followupCount)
        let size = CGSize(width: DialogueBubble.bubbleWidth, height: height)
        bubbleBackground.path = DialogueBubble.makePath(size: size)
        textLabel.preferredMaxLayoutWidth = size.width - 20
    }

    private func layoutContents() {
        let height = DialogueBubble.heightFor(mode: mode, followupCount: followupCount)
        let halfH = height / 2

        switch mode {
        case .legacyJSON:
            // Match the original layout exactly.
            nameLabel.position = CGPoint(x: 0, y: 50)
            textLabel.position = CGPoint(x: 0, y: 15)
            textLabel.numberOfLines = 3
        case .terminal:
            // Match the original "showResponseButtons:false" layout.
            nameLabel.position = CGPoint(x: 0, y: 35)
            textLabel.position = CGPoint(x: 0, y: 0)
            textLabel.numberOfLines = 4
        case .streamingLLM:
            // Name pinned near top; text centered in the area between name and followups.
            nameLabel.position = CGPoint(x: 0, y: halfH - 22)
            let buttonsBlock = CGFloat(followupCount) * DialogueBubble.buttonRowHeight
                              + (followupCount > 0 ? 4 : 0)
            let areaTop = nameLabel.position.y - 18
            let areaBottom = -halfH + buttonsBlock + 6
            textLabel.position = CGPoint(x: 0, y: (areaTop + areaBottom) / 2)
            textLabel.numberOfLines = 4
        }

        // Mood emoji floats just to the right of the name label.
        let nameWidth = nameLabel.frame.width
        moodLabel.position = CGPoint(x: nameWidth / 2 + 10, y: nameLabel.position.y)

        // Stack followup pills from the bottom upward.
        let firstBtnCenterY = -halfH + DialogueBubble.buttonRowHeight / 2 + 6
        for (i, child) in followupButtons.children.enumerated() {
            let row = followupCount - 1 - i   // index 0 displayed on top
            child.position = CGPoint(x: 0, y: firstBtnCenterY + CGFloat(row) * DialogueBubble.buttonRowHeight)
        }
    }

    private static func heightFor(mode: BubbleMode, followupCount: Int) -> CGFloat {
        switch mode {
        case .legacyJSON:   return baseHeight + legacyButtonsExtraHeight
        case .terminal:     return baseHeight
        case .streamingLLM: return baseHeight + CGFloat(followupCount) * buttonRowHeight
        }
    }

    private static func makePath(size: CGSize) -> CGPath {
        let rect = CGRect(x: -size.width / 2, y: -size.height / 2,
                          width: size.width, height: size.height)
        return CGPath(roundedRect: rect, cornerWidth: 15, cornerHeight: 15, transform: nil)
    }

    // MARK: - Button Construction

    private func setupLegacyResponseButtons() {
        let spacing: CGFloat = 90
        let y: CGFloat = -45
        responseButtons.addChild(createLegacyButton(emoji: "❌", responseType: .dismiss,
                                                     position: CGPoint(x: -spacing, y: y)))
        responseButtons.addChild(createLegacyButton(emoji: "😊", responseType: .nice,
                                                     position: CGPoint(x: 0, y: y)))
        responseButtons.addChild(createLegacyButton(emoji: "😠", responseType: .mean,
                                                     position: CGPoint(x: spacing, y: y)))
    }

    private func createLegacyButton(emoji: String, responseType: NPCResponseType,
                                    position: CGPoint) -> SKNode {
        let container = SKNode()
        container.position = position

        let bg = SKShapeNode(circleOfRadius: 20)
        bg.fillColor = SKColor.lightGray.withAlphaComponent(0.3)
        bg.strokeColor = SKColor.gray
        bg.lineWidth = 1

        let label = SKLabelNode(text: emoji)
        label.fontSize = 24
        label.fontName = "Arial"
        label.horizontalAlignmentMode = .center
        label.verticalAlignmentMode = .center

        container.addChild(bg)
        container.addChild(label)
        container.name = "response_\(responseType.rawValue)"
        return container
    }

    private func makeFollowupButton(text: String, tone: LLMTone, index: Int) -> SKNode {
        let container = SKNode()
        let pillSize = CGSize(width: 280, height: 28)

        let bg = SKShapeNode(rectOf: pillSize, cornerRadius: 12)
        bg.fillColor = colorForTone(tone)
        bg.strokeColor = SKColor.darkGray
        bg.lineWidth = 1

        let label = SKLabelNode(text: text)
        label.fontName = "Arial"
        label.fontSize = 12
        label.fontColor = SKColor.black
        label.horizontalAlignmentMode = .center
        label.verticalAlignmentMode = .center
        label.preferredMaxLayoutWidth = pillSize.width - 16
        label.numberOfLines = 1

        container.addChild(bg)
        container.addChild(label)
        container.name = "followup_\(index)_\(tone.rawValue)"

        // Stash text + tone on the node so the touch handler can recover it.
        let userInfo = NSMutableDictionary()
        userInfo["text"] = text
        userInfo["tone"] = tone.rawValue
        container.userData = userInfo

        return container
    }

    private func colorForTone(_ tone: LLMTone) -> SKColor {
        switch tone {
        case .kind:    return SKColor(red: 0.85, green: 0.95, blue: 0.85, alpha: 0.9) // soft green
        case .neutral: return SKColor(red: 0.92, green: 0.92, blue: 0.92, alpha: 0.9) // soft gray
        case .blunt:   return SKColor(red: 0.95, green: 0.85, blue: 0.85, alpha: 0.9) // soft red
        }
    }

    // MARK: - Mood → Emoji

    private static func emojiForMood(_ key: String) -> String {
        switch key.lowercased() {
        case "delighted": return "😍"
        case "happy":     return "😊"
        case "neutral":   return "😐"
        case "wistful":   return "🥺"
        case "anxious":   return "😟"
        case "upset":     return "😠"
        case "weary":     return "😔"
        default:          return ""
        }
    }

    // MARK: - Touch Handling

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let location = touch.location(in: self)
        let touched = atPoint(location)

        // Walk up the tree to find a named container with response_* / followup_*.
        var node: SKNode? = touched
        while let n = node, n !== self {
            if let name = n.name {
                if name.hasPrefix("followup_") {
                    handleFollowupHit(n)
                    return
                }
                if name.hasPrefix("response_") {
                    let raw = String(name.dropFirst("response_".count))
                    if let type = NPCResponseType(rawValue: raw) {
                        handleLegacyResponse(type)
                        return
                    }
                }
            }
            node = n.parent
        }

        // Tap on bubble background → dismiss THIS NPC's bubble only.
        DialogueService.shared.dismissDialogue(forNPCID: npcID)
    }

    private func handleFollowupHit(_ node: SKNode) {
        guard let handler = followupTapHandler,
              let text = node.userData?["text"] as? String,
              let toneRaw = node.userData?["tone"] as? String else {
            DialogueService.shared.dismissDialogue(forNPCID: npcID)
            return
        }
        let tone = LLMTone.from(toneRaw)

        node.run(SKAction.sequence([
            SKAction.scale(to: 0.95, duration: 0.08),
            SKAction.scale(to: 1.0, duration: 0.08)
        ]))

        Log.debug(.dialogue, "Player chose followup '\(text)' (\(tone.rawValue)) for \(npcID)")
        handler(tone, text)
    }

    private func handleLegacyResponse(_ type: NPCResponseType) {
        SaveService.shared.recordNPCInteraction(npcID, responseType: type)

        // Broadcast NPC interaction to other player
        MultiplayerService.shared.send(type: .npcInteraction, payload: NPCInteractionMessage(
            npcID: npcID, responseType: type.rawValue
        ))

        if let btn = responseButtons.childNode(withName: "response_\(type.rawValue)") {
            btn.run(SKAction.sequence([
                SKAction.scale(to: 0.8, duration: 0.1),
                SKAction.scale(to: 1.0, duration: 0.1)
            ]))
        }

        run(SKAction.sequence([
            SKAction.wait(forDuration: 0.3),
            SKAction.run { [npcID] in DialogueService.shared.dismissDialogue(forNPCID: npcID) }
        ]))

        Log.debug(.dialogue, "Player responded '\(type.rawValue)' to \(npcID)")
    }
}

// MARK: - Conversation Line Bubble (NPC ↔ NPC)

/// Lightweight read-only bubble used to display a single line of an
/// NPC↔NPC conversation. Smaller than DialogueBubble, no buttons,
/// auto-fades after its parent action. Tappable so the player can
/// interrupt by tapping a participant — but the tap is forwarded
/// through to the underlying NPC by NOT consuming touches here.
final class ConversationLineBubble: SKNode {
    init(text: String, speakerName: String, mood: String?, position: CGPoint) {
        super.init()

        let width: CGFloat = 220
        let height: CGFloat = 70

        let bg = SKShapeNode(rectOf: CGSize(width: width, height: height), cornerRadius: 12)
        bg.fillColor = SKColor.white.withAlphaComponent(0.92)
        bg.strokeColor = SKColor.darkGray.withAlphaComponent(0.7)
        bg.lineWidth = 1.5
        addChild(bg)

        let nameLabel = SKLabelNode(text: speakerName + (mood.flatMap { ConversationLineBubble.moodEmoji($0) }.map { " \($0)" } ?? ""))
        nameLabel.fontName = "Arial-Bold"
        nameLabel.fontSize = 11
        nameLabel.fontColor = SKColor.darkGray
        nameLabel.horizontalAlignmentMode = .center
        nameLabel.position = CGPoint(x: 0, y: height/2 - 14)
        addChild(nameLabel)

        let textLabel = SKLabelNode(text: text)
        textLabel.fontName = "Arial"
        textLabel.fontSize = 11
        textLabel.fontColor = SKColor.black
        textLabel.horizontalAlignmentMode = .center
        textLabel.verticalAlignmentMode = .center
        textLabel.numberOfLines = 3
        textLabel.preferredMaxLayoutWidth = width - 16
        textLabel.position = CGPoint(x: 0, y: -4)
        addChild(textLabel)

        self.position = CGPoint(x: position.x, y: position.y + 70)
        self.zPosition = ZLayers.dialogueUI - 1   // sits below player↔NPC bubbles
        self.name = "npc_conversation_bubble"
        self.isUserInteractionEnabled = false     // taps fall through to NPCs
        self.alpha = 0
        run(SKAction.fadeIn(withDuration: 0.2))
    }

    required init?(coder aDecoder: NSCoder) { fatalError() }

    private static func moodEmoji(_ key: String) -> String? {
        switch key.lowercased() {
        case "delighted": return "😍"
        case "happy":     return "😊"
        case "neutral":   return "😐"
        case "wistful":   return "🥺"
        case "anxious":   return "😟"
        case "upset":     return "😠"
        case "weary":     return "😔"
        default:          return nil
        }
    }
}

// MARK: - SKColor helper (small)

private extension SKColor {
    /// Multiply each RGB component by `factor`, clamped. Used to pop the
    /// chosen-pill background. Falls back to self if components can't be
    /// extracted.
    func brighter(by factor: CGFloat) -> SKColor {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard self.getRed(&r, green: &g, blue: &b, alpha: &a) else { return self }
        return SKColor(red: min(1, r * factor),
                       green: min(1, g * factor),
                       blue: min(1, b * factor),
                       alpha: a)
    }
}
