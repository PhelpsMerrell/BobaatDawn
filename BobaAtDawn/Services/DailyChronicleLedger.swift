//
//  DailyChronicleLedger.swift
//  BobaAtDawn
//
//  Host-only (and solo) event collector. Every interesting world event
//  during the day calls one of the record... methods. At dawn the host
//  snapshots the ledger, hands the snapshot to DailyChronicleService,
//  and resets for the new day.
//
//  All record... methods are no-ops on guest. This keeps event sourcing
//  simple — call them everywhere, and they only "stick" on the
//  authoritative side. The host receives guest-originated events
//  (drink served, storage deposit, etc.) via existing multiplayer
//  message handlers, which call the same SaveService / Registry
//  mutators that fire ledger hooks. Net effect: every event lands in
//  the ledger exactly once on the host.
//

import Foundation

final class DailyChronicleLedger {
    static let shared = DailyChronicleLedger()

    /// Live event list for the current day. Cleared on `reset()`.
    private(set) var events: [LedgerEvent] = []

    /// Pairs (ofID-towardID-threshold-direction) we've already logged
    /// for this day, to avoid spamming the ledger with score yo-yos.
    private var loggedThresholdCrossings: Set<String> = []

    private init() {}

    // MARK: - Gating

    /// Returns true on the side that should be recording.
    /// Solo and host both record. Guest never records.
    private var shouldRecord: Bool {
        !MultiplayerService.shared.isGuest
    }

    // MARK: - Day Lifecycle

    /// Snapshot the current day's events.
    func snapshot() -> [LedgerEvent] {
        events
    }

    /// Wipe the ledger for the new day.
    func reset() {
        events.removeAll()
        loggedThresholdCrossings.removeAll()
    }

    // MARK: - Recording

    func recordDrinkServed(npcID: String, npcName: String) {
        guard shouldRecord else { return }
        var e = LedgerEvent(kind: .drinkServed, timestamp: Date())
        e.npcID = npcID
        e.npcName = npcName
        events.append(e)
    }

    func recordGemDeposited(byGnomeID: String?, byGnomeName: String?) {
        guard shouldRecord else { return }
        var e = LedgerEvent(kind: .gemDeposited, timestamp: Date())
        e.gnomeID = byGnomeID
        e.gnomeName = byGnomeName
        events.append(e)
    }

    func recordIngredientForaged(name: String) {
        guard shouldRecord else { return }
        var e = LedgerEvent(kind: .ingredientForaged, timestamp: Date())
        e.ingredient = name
        events.append(e)
    }

    func recordIngredientDeposited(name: String, container: String) {
        guard shouldRecord else { return }
        var e = LedgerEvent(kind: .ingredientDeposited, timestamp: Date())
        e.ingredient = name
        e.container = container
        events.append(e)
    }

    func recordIngredientRetrieved(name: String, container: String) {
        guard shouldRecord else { return }
        var e = LedgerEvent(kind: .ingredientRetrieved, timestamp: Date())
        e.ingredient = name
        e.container = container
        events.append(e)
    }

    func recordTrashSpawned(location: String) {
        guard shouldRecord else { return }
        var e = LedgerEvent(kind: .trashSpawned, timestamp: Date())
        e.location = location
        events.append(e)
    }

    func recordTrashCleaned(location: String) {
        guard shouldRecord else { return }
        var e = LedgerEvent(kind: .trashCleaned, timestamp: Date())
        e.location = location
        events.append(e)
    }

    func recordNPCArrivedShop(npcID: String, npcName: String) {
        guard shouldRecord else { return }
        var e = LedgerEvent(kind: .npcArrivedShop, timestamp: Date())
        e.npcID = npcID
        e.npcName = npcName
        events.append(e)
    }

    func recordNPCLiberated(npcID: String, npcName: String, divine: Bool) {
        guard shouldRecord else { return }
        var e = LedgerEvent(kind: .npcLiberated, timestamp: Date())
        e.npcID = npcID
        e.npcName = npcName
        e.liberationKind = divine ? "divine" : "hellish"
        events.append(e)
    }

    func recordGnomeRankChanged(
        gnomeID: String,
        gnomeName: String,
        newRank: String,
        bossLine: String?,
        isPromotion: Bool
    ) {
        guard shouldRecord else { return }
        var e = LedgerEvent(kind: .gnomeRankChanged, timestamp: Date())
        e.gnomeID = gnomeID
        e.gnomeName = gnomeName
        e.newRank = newRank
        e.bossLine = bossLine
        e.rankChangeIsPromotion = isPromotion
        events.append(e)
    }

    /// Detect threshold crossings between `before` and `after`. Logs at
    /// most one crossing per (ordered-pair, threshold, direction) per day.
    func recordPossibleThresholdCrossings(
        ofID: String,
        towardID: String,
        before: Int,
        after: Int
    ) {
        guard shouldRecord else { return }
        guard before != after else { return }

        let goingUp = after > before
        let crossings = Self.detectCrossings(before: before, after: after)
        guard !crossings.isEmpty else { return }

        let ofName = SaveService.shared.getNPCMemory(ofID)?.name
            ?? DialogueService.shared.getNPC(byId: ofID)?.name
            ?? ofID
        let towardName = SaveService.shared.getNPCMemory(towardID)?.name
            ?? DialogueService.shared.getNPC(byId: towardID)?.name
            ?? towardID

        for threshold in crossings {
            let direction = goingUp ? "up" : "down"
            let dedupeKey = "\(ofID)__\(towardID)__\(threshold)__\(direction)"
            guard !loggedThresholdCrossings.contains(dedupeKey) else { continue }
            loggedThresholdCrossings.insert(dedupeKey)

            var e = LedgerEvent(kind: .opinionThresholdCrossed, timestamp: Date())
            e.pairOfID = ofID
            e.pairOfName = ofName
            e.pairTowardID = towardID
            e.pairTowardName = towardName
            e.threshold = threshold
            e.crossingDirection = direction
            events.append(e)
        }
    }

    /// Returns the names of threshold lines crossed between `before` and `after`.
    private static func detectCrossings(before: Int, after: Int) -> [String] {
        let lines: [(name: String, value: Int)] = [
            ("hostile",  HostilityThreshold.hostile),
            ("avoidant", HostilityThreshold.avoidant),
            ("friendly", HostilityThreshold.friendly),
            ("close",    HostilityThreshold.close)
        ]
        var crossed: [String] = []
        for line in lines {
            let beforeSide = before >= line.value
            let afterSide = after >= line.value
            if beforeSide != afterSide {
                crossed.append(line.name)
            }
        }
        return crossed
    }
}
