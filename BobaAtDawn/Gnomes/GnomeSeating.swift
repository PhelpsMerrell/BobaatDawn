//
//  GnomeSeating.swift
//  BobaAtDawn
//
//  Manages the "everyone at dining tables" portion of dawn breakfast
//  and dusk dinner. Encapsulates:
//    1. Seat assignment (random shuffle each meal).
//    2. Cook cycle: serve → deliver → check → return, ~5s per loop.
//    3. Cook reaction bubbles: LLM-batched, with hardcoded fallback.
//    4. Table show/hide timing.
//    5. Lookups so GnomeManager can ask "where should this gnome stand
//       during the meal?" and "what should the cook do this frame?"
//
//  Single-instance, host-authoritative. Nothing here cares about
//  multiplayer — `GnomeManager.broadcastFullState` already snapshots
//  task + position every 0.5s, so the cook cycle replicates for free
//  on the guest. The reaction bubbles render via DialogueService which
//  has its own remote-broadcast path.
//
//  Graceful degradation
//  --------------------
//  If `BigOakTreeScene.availableDiningSeats()` returns empty (no
//  anchors authored yet in the .sks), `assignSeats(forMeal:)` simply
//  returns false and GnomeManager keeps using the old free-mingle
//  positioning. The cook cycle no-ops too. No assertions, no crashes
//  \u2014 the system just sleeps until the SKS is updated.
//

import SpriteKit
import Foundation

// MARK: - Meal Identity

enum GnomeMeal: String {
    case breakfast
    case dinner
}

// MARK: - Cook Cycle Sub-State

private enum CookCyclePhase {
    case serving        // ~1s standing at the cook station
    case delivering     // ~2s walking to the target table
    case checking       // ~2s standing at the table while a reaction fires
}

// MARK: - GnomeSeating

final class GnomeSeating {

    static let shared = GnomeSeating()
    private init() {}

    // MARK: - Tunables

    /// Cook cycle pacing. Sum is the round-trip time per table visit.
    /// 1 + 2 + 2 = 5 seconds, "busy chef" pace.
    private let cookServeDuration: TimeInterval = 1.0
    private let cookDeliverDuration: TimeInterval = 2.0
    private let cookCheckDuration: TimeInterval = 2.0

    /// How many reaction lines to keep cached at a time. The cache
    /// refills via a single LLM call when it dips below this.
    private let reactionBatchSize: Int = 3

    // MARK: - Per-Meal State

    /// Reaction line cache. Refilled via the LLM whenever depleted.
    /// When the LLM is unavailable the cache stays empty and the
    /// fallback pool (below) is used instead.
    private var reactionCache: [String] = []
    /// True while an LLM batch is in flight, to avoid redundant
    /// concurrent refills.
    private var reactionRefillInFlight: Bool = false

    /// Cook cycle bookkeeping.
    private var cookPhase: CookCyclePhase = .serving
    private var cookPhaseStartedAt: TimeInterval = 0
    /// Tables visited recently so we don't repeat. Cleared when the
    /// list of remaining tables runs dry.
    private var cookRecentTables: Set<Int> = []
    /// Whether a meal is currently active; gates `tickCook` from
    /// running outside of meal time.
    private var mealInProgress: Bool = false
    private var currentMeal: GnomeMeal = .breakfast

    // MARK: - Static Reaction Pool (fallback)

    /// Used when the LLM is unavailable, returns nothing, or returns
    /// only too-long lines. Deliberately specific to a working-class
    /// gnome cook setting.
    static let staticReactionPool: [String] = [
        "This is incredible, Cook.",
        "Best stew yet.",
        "You've outdone yourself.",
        "My compliments.",
        "Mm. Mm-mm-mm.",
        "Bread's perfect today.",
        "Bowl's already empty. Sorry.",
        "Save me seconds, would you?",
        "Salt's just right.",
        "I needed this.",
        "Plate me again, Cook.",
        "Warms the bones, this."
    ]

    // MARK: - Public Lifecycle

    /// Begin a meal beat. Assigns seats, hides/shows tables, kicks the
    /// cook cycle, and prewarms the reaction cache.
    ///
    /// Returns true on success, false if no seats were authored in
    /// the .sks (caller should fall back to free-mingle behavior).
    @discardableResult
    func beginMeal(
        _ meal: GnomeMeal,
        agents: [GnomeAgent],
        oakScene: BigOakTreeScene?,
        now: TimeInterval
    ) -> Bool {
        guard let scene = oakScene else {
            Log.info(.npc, "[Seating] beginMeal(\(meal.rawValue)) skipped: no oak scene yet")
            return false
        }

        // Show tables.
        scene.setDiningTablesVisible(true)

        // Try to assign seats. If no anchors yet, bail and let the
        // caller fall back to free-mingle.
        guard assignSeats(forMeal: meal, agents: agents, oakScene: scene) else {
            Log.info(.npc, "[Seating] beginMeal(\(meal.rawValue)) skipped: no seat anchors authored")
            return false
        }

        mealInProgress = true
        currentMeal = meal
        cookPhase = .serving
        cookPhaseStartedAt = now
        cookRecentTables.removeAll()

        // Wipe any stale cache from a prior meal and prewarm a fresh batch.
        reactionCache.removeAll()
        refillReactionCacheIfNeeded(agents: agents)

        Log.info(.npc, "[Seating] beginMeal(\(meal.rawValue)) — seats assigned, cook cycle started")
        return true
    }

    /// End a meal beat. Clears seat assignments and stops the cook
    /// cycle. Dining tables stay visible as permanent lobby props.
    /// Does NOT restore agent positions \u2014 the caller
    /// (GnomeManager) is responsible for setting the next task.
    func endMeal(
        agents: [GnomeAgent],
        oakScene: BigOakTreeScene?
    ) {
        mealInProgress = false
        for agent in agents {
            agent.currentSeatAnchor = nil
            agent.cookTargetTableIndex = nil
            agent.cookTargetSeatedAgentID = nil
        }
        oakScene?.setDiningTablesVisible(true)
        Log.info(.npc, "[Seating] endMeal — seats cleared, tables remain visible")
    }

    /// Preserve the permanent lobby tables during cleanup beats.
    /// Doesn't touch agent state.
    func hideTables(oakScene: BigOakTreeScene?) {
        oakScene?.setDiningTablesVisible(true)
    }

    /// True while a meal is active (for GnomeManager to gate cook tick).
    var isMealActive: Bool { mealInProgress }

    // MARK: - Seat Assignment

    /// Shuffle seat assignments for the given meal. Cook is excluded
    /// (she stands at her station). Gnomes that don't get a seat
    /// (fewer seats than gnomes) end up with `currentSeatAnchor = nil`
    /// and the caller falls back to a free-mingle position for them.
    ///
    /// Returns false if no seats are authored at all (so the caller
    /// can fall back to the legacy mingle path entirely).
    @discardableResult
    private func assignSeats(
        forMeal meal: GnomeMeal,
        agents: [GnomeAgent],
        oakScene: BigOakTreeScene
    ) -> Bool {
        let seats = oakScene.availableDiningSeats()
        guard !seats.isEmpty else { return false }

        let cookID = GnomeRoster.kitchenCook.id
        let diners = agents.filter { $0.identity.id != cookID }
        let shuffledSeats = seats.shuffled()
        let shuffledDiners = diners.shuffled()

        // Clear all assignments first so anyone who doesn't get a seat
        // ends up nil rather than carrying a stale value from last meal.
        for agent in agents {
            agent.currentSeatAnchor = nil
        }

        for (i, agent) in shuffledDiners.enumerated() {
            guard i < shuffledSeats.count else { break }
            agent.currentSeatAnchor = shuffledSeats[i].anchor
        }

        let seated = shuffledDiners.prefix(shuffledSeats.count).count
        let standing = max(0, diners.count - shuffledSeats.count)
        Log.info(.npc, "[Seating] \(meal.rawValue): seated=\(seated) standing=\(standing) totalSeats=\(seats.count)")
        return true
    }

    // MARK: - Position Lookup

    /// World-space position where this agent should be during a meal.
    /// - Cook: returns the cook station (or the cook's current cycle
    ///   target if mid-cycle).
    /// - Other gnomes: returns their seat anchor's position, or a
    ///   fallback free-mingle position if they didn't get a seat.
    func mealPosition(
        for agent: GnomeAgent,
        oakScene: BigOakTreeScene?,
        fallbackMinglePosition: CGPoint
    ) -> CGPoint {
        let cookID = GnomeRoster.kitchenCook.id
        if agent.identity.id == cookID {
            return oakScene?.cookStationPosition() ?? fallbackMinglePosition
        }
        guard let anchor = agent.currentSeatAnchor,
              let parsed = BigOakTreeScene.parseSeatAnchor(anchor),
              let scene = oakScene,
              let p = scene.diningSeatPosition(tableIndex: parsed.table, seatIndex: parsed.seat) else {
            return fallbackMinglePosition
        }
        return p
    }

    /// World-space position where the cook should be standing right
    /// now, derived from the current cook cycle phase. Falls back to
    /// the cook station if the cycle data is incomplete.
    func cookCurrentPosition(
        cook: GnomeAgent,
        oakScene: BigOakTreeScene?,
        fallbackMinglePosition: CGPoint
    ) -> CGPoint {
        guard let scene = oakScene else { return fallbackMinglePosition }

        switch cookPhase {
        case .serving:
            return scene.cookStationPosition() ?? fallbackMinglePosition
        case .delivering, .checking:
            if let table = cook.cookTargetTableIndex,
               let p = scene.diningTablePosition(tableIndex: table) {
                return p
            }
            return scene.cookStationPosition() ?? fallbackMinglePosition
        }
    }

    // MARK: - Cook Cycle Tick

    /// Advance the cook cycle one frame. Updates `cook.task` so the
    /// state propagates over the multiplayer snapshot, picks new
    /// table targets, and fires reaction bubbles when checking.
    ///
    /// Should be called from `GnomeManager.update` only when the cook
    /// is at the lobby AND a meal is in progress. The function is a
    /// safe no-op when those preconditions aren't met.
    func tickCook(
        cook: GnomeAgent,
        agents: [GnomeAgent],
        oakScene: BigOakTreeScene?,
        now: TimeInterval
    ) {
        guard mealInProgress else { return }
        guard let scene = oakScene else { return }

        let elapsedInPhase = now - cookPhaseStartedAt

        switch cookPhase {
        case .serving:
            cook.task = .cookServingFromStation
            if elapsedInPhase >= cookServeDuration {
                guard let nextTable = pickNextTable(scene: scene) else {
                    // No tables to visit — stay serving until the cycle
                    // can find one. (Edge case: 0 tables in scene.)
                    cookPhaseStartedAt = now
                    return
                }
                cook.cookTargetTableIndex = nextTable
                cook.cookTargetSeatedAgentID = pickSeatedAgentAtTable(
                    nextTable, agents: agents
                )
                cookPhase = .delivering
                cookPhaseStartedAt = now
                cook.task = .cookDeliveringToTable
            }

        case .delivering:
            cook.task = .cookDeliveringToTable
            if elapsedInPhase >= cookDeliverDuration {
                cookPhase = .checking
                cookPhaseStartedAt = now
                cook.task = .cookCheckingOnTable
                fireReactionBubble(
                    cook: cook,
                    agents: agents,
                    oakScene: scene
                )
            }

        case .checking:
            cook.task = .cookCheckingOnTable
            if elapsedInPhase >= cookCheckDuration {
                // Cycle back to the station.
                cook.cookTargetTableIndex = nil
                cook.cookTargetSeatedAgentID = nil
                cookPhase = .serving
                cookPhaseStartedAt = now
                cook.task = .cookServingFromStation
            }
        }
    }

    // MARK: - Reaction Bubbles

    /// Fire a reaction bubble over a seated gnome at the cook's
    /// current target table. Pulls a line from the cache first; if
    /// the cache is empty, uses the static fallback pool. Triggers a
    /// cache refill in the background when running low.
    private func fireReactionBubble(
        cook: GnomeAgent,
        agents: [GnomeAgent],
        oakScene: BigOakTreeScene
    ) {
        guard let seatedAgentID = cook.cookTargetSeatedAgentID,
              let seatedAgent = agents.first(where: { $0.identity.id == seatedAgentID }),
              let presenter = seatedAgent.sceneNode else {
            // No visual to anchor the bubble to — silently skip.
            return
        }

        // Don't clobber any in-flight dialogue (player tap on this
        // gnome, ambient gnome conversation, etc.). The reaction is a
        // non-essential flavor beat.
        if DialogueService.shared.isDialogueActive(forNPCID: seatedAgent.identity.id) {
            return
        }

        let line = popReactionLine() ?? Self.staticReactionPool.randomElement() ?? "Mm."
        let mood = "delighted"
        DialogueService.shared.showStaticDialogue(
            for: presenter,
            speakerName: seatedAgent.fullDisplayName,
            text: line,
            mood: mood,
            in: oakScene
        )

        // Trigger a refill if cache is running low.
        refillReactionCacheIfNeeded(agents: agents)
    }

    /// Pop the next cached LLM line, or return nil if cache is empty.
    private func popReactionLine() -> String? {
        guard !reactionCache.isEmpty else { return nil }
        return reactionCache.removeFirst()
    }

    /// Kick off an async LLM batch refill if (a) the cache is below
    /// `reactionBatchSize`, (b) no refill is already in flight, and
    /// (c) Apple Intelligence is available. No-op otherwise.
    private func refillReactionCacheIfNeeded(agents: [GnomeAgent]) {
        guard reactionCache.count < reactionBatchSize else { return }
        guard !reactionRefillInFlight else { return }
        guard LLMGnomeDialogueService.shared.isAvailable else { return }
        guard let cook = agents.first(where: { $0.identity.id == GnomeRoster.kitchenCook.id }) else {
            return
        }

        // Sample a few seated gnomes to give the prompt some flavor.
        let seatedSample = agents.filter { $0.currentSeatAnchor != nil }
        let timeContext: TimeContext = (currentMeal == .dinner) ? .night : .day
        let mealKey = currentMeal.rawValue

        reactionRefillInFlight = true
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            let lines = await LLMGnomeDialogueService.shared.streamCookReactionBatch(
                seatedSample: seatedSample,
                cook: cook,
                meal: mealKey,
                timeContext: timeContext
            )
            self.reactionCache.append(contentsOf: lines)
            self.reactionRefillInFlight = false
            if lines.isEmpty {
                Log.debug(.dialogue, "[Seating] cook reaction batch returned 0 lines (will use static pool)")
            } else {
                Log.debug(.dialogue, "[Seating] cook reaction batch refilled with \(lines.count) lines")
            }
        }
    }

    // MARK: - Helpers

    /// Pick a table index the cook hasn't visited recently. Cycles
    /// through the available tables; resets the recent-set when all
    /// of them have been hit.
    private func pickNextTable(scene: BigOakTreeScene) -> Int? {
        // Build the list of tables that actually have at least one
        // authored seat. We don't want the cook to walk to an empty
        // anchor.
        let tableCount = BigOakTreeScene.diningTableCount
        var liveTables: [Int] = []
        for t in 1...tableCount {
            let hasSeat = (1...BigOakTreeScene.seatsPerTable).contains { s in
                scene.diningSeatPosition(tableIndex: t, seatIndex: s) != nil
            }
            if hasSeat { liveTables.append(t) }
        }
        guard !liveTables.isEmpty else { return nil }

        // Filter out recents; reset the recent set if we'd be left
        // with nothing.
        let candidates = liveTables.filter { !cookRecentTables.contains($0) }
        let pool = candidates.isEmpty ? liveTables : candidates
        if candidates.isEmpty {
            cookRecentTables.removeAll()
        }

        let pick = pool.randomElement()
        if let pick = pick {
            cookRecentTables.insert(pick)
        }
        return pick
    }

    /// Pick a seated gnome at the given table, or nil if none seated.
    private func pickSeatedAgentAtTable(_ tableIndex: Int, agents: [GnomeAgent]) -> String? {
        let here = agents.filter { agent in
            guard let anchor = agent.currentSeatAnchor,
                  let parsed = BigOakTreeScene.parseSeatAnchor(anchor) else {
                return false
            }
            return parsed.table == tableIndex
        }
        return here.randomElement()?.identity.id
    }
}
