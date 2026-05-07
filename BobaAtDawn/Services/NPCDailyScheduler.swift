//
//  NPCDailyScheduler.swift
//  BobaAtDawn
//
//  Picks each NPC's three activities for the day at dawn, then drives
//  the activities throughout the day and reports completion back to
//  NPCResidentManager.
//
//  Activity rules
//  --------------
//  Each NPC gets exactly 3 activity slots per day:
//    Slot 1: ALWAYS .visitShop (the design pillar — every NPC visits
//            the shop at least once a day).
//    Slots 2-3: picked from the eligible pool.
//
//  The pool:
//    .forageAndTrade        — always eligible. Walk forest, pick up an
//                              item, take it to the broker, get a gem.
//                              Implementation lives in Phase 3.
//    .visitFriend           — eligible iff this NPC has at least one
//                              other NPC with relationship score ≥ +25.
//                              Pick weighted toward the highest score.
//    .dropTrashAtEnemy      — eligible iff this NPC has at least one
//                              other NPC with relationship score ≤ -45.
//                              Pick weighted toward the lowest score.
//    .gatherCaveMushrooms   — eligible iff this NPC's `the_cave` stance
//                              is .likes or .loves. By design, that's a
//                              rare 1-2 NPCs out of the roster.
//
//  Reactive trash pickup is NOT a planned activity — it happens
//  automatically when an NPC encounters trash at their own house
//  during any movement. See `reactToTrashIfNeeded` in Phase 3.
//
//  Eligibility fallbacks: if filtering leaves the NPC with fewer than 2
//  options for slots 2-3, the planner backfills with .forageAndTrade
//  (always available). Slots are NEVER duplicates — you only do each
//  activity at most once per day.
//
//  Persistence: plans are NOT persisted. They are re-rolled at every
//  dawn rollover, including after a save/load. This keeps the system
//  simple and means a save → restore mid-day will reroll the plan,
//  losing partial progress — acceptable because the activities are
//  short and the player isn't tracking them explicitly anyway.
//
//  Multiplayer: plans live on the host. The host marks activities done
//  and the existing visitShop → maintainShopPopulation flow already
//  triggers correctly on both sides. Other activities don't yet have
//  visible side effects that need syncing (Phase 3 will introduce the
//  broker trade, which gets its own broadcast).
//

import Foundation

// MARK: - Activity Enum

/// One of the things an NPC might do during their day.
enum NPCDailyActivity: String, Codable, CaseIterable {
    case visitShop
    case forageAndTrade
    case visitFriend
    case dropTrashAtEnemy
    case gatherCaveMushrooms

    /// Human-readable label for debug logs.
    var debugLabel: String {
        switch self {
        case .visitShop:           return "visit_shop"
        case .forageAndTrade:      return "forage_and_trade"
        case .visitFriend:         return "visit_friend"
        case .dropTrashAtEnemy:    return "drop_trash_at_enemy"
        case .gatherCaveMushrooms: return "gather_cave_mushrooms"
        }
    }
}

// MARK: - Daily Plan

/// Per-NPC plan for today. Holds the chosen activities, the targets
/// resolved at planning time (so a friend visit goes to the same
/// friend even if the relationship score drifts mid-day), and a set
/// of completion markers.
struct NPCDailyPlan {
    /// The chosen activities, in order. Always has exactly 3 entries
    /// post-rolling, with the first always being .visitShop.
    var activities: [NPCDailyActivity]

    /// For .visitFriend, the resolved friend's npcID. Nil if not in plan.
    var visitFriendTargetID: String?

    /// For .dropTrashAtEnemy, the resolved enemy's npcID. Nil if not in plan.
    var dropTrashTargetID: String?

    /// Completion markers, keyed by activity rawValue.
    var completed: Set<NPCDailyActivity>

    /// True when every activity in the plan has been marked complete.
    var isFullyComplete: Bool {
        completed.count >= activities.count
    }

    /// Whether a specific activity is in this plan.
    func includes(_ activity: NPCDailyActivity) -> Bool {
        activities.contains(activity)
    }

    /// Whether a specific activity is in this plan AND not yet done.
    func isPending(_ activity: NPCDailyActivity) -> Bool {
        includes(activity) && !completed.contains(activity)
    }

    static var empty: NPCDailyPlan {
        NPCDailyPlan(
            activities: [],
            visitFriendTargetID: nil,
            dropTrashTargetID: nil,
            completed: []
        )
    }
}

// MARK: - Scheduler Service

final class NPCDailyScheduler {

    static let shared = NPCDailyScheduler()
    private init() {}

    // MARK: - Public Entry Points

    /// Roll a fresh plan for every resident at dawn. Idempotent for
    /// a given dayCount — calling it twice on the same day re-rolls,
    /// which is acceptable (and what happens after a save → restore).
    /// Logs every plan for visibility while the system is being built.
    func rollPlansForAllResidents(dayCount: Int) {
        guard !MultiplayerService.shared.isGuest else {
            Log.debug(.resident, "[Scheduler] Guest — skipping plan roll, host owns this")
            return
        }

        let residents = NPCResidentManager.shared.getAllResidents()
        var rolled = 0
        for resident in residents {
            // Skip liberated NPCs — they're gone.
            if SaveService.shared.isNPCLiberated(resident.npcData.id) { continue }

            let plan = rollPlan(for: resident)
            resident.dailyPlan = plan
            rolled += 1
            logPlan(plan, for: resident)
        }
        Log.info(.resident, "[Scheduler] Day \(dayCount): rolled plans for \(rolled) residents")
    }

    /// Mark a specific activity as done for the named NPC. Called
    /// by execution code (or the existing shop population maintenance
    /// loop) when an activity is observed to have happened.
    func markActivityComplete(_ activity: NPCDailyActivity, npcID: String) {
        guard let resident = NPCResidentManager.shared.findResident(byID: npcID) else { return }
        guard resident.dailyPlan.includes(activity) else { return }
        guard !resident.dailyPlan.completed.contains(activity) else { return }
        resident.dailyPlan.completed.insert(activity)
        Log.debug(.resident, "[Scheduler] \(resident.npcData.name) finished \(activity.debugLabel)")
    }

    /// Convenience: query the next pending activity in plan order.
    /// Returns nil if every planned activity is complete.
    func nextPendingActivity(for resident: NPCResident) -> NPCDailyActivity? {
        for activity in resident.dailyPlan.activities {
            if !resident.dailyPlan.completed.contains(activity) { return activity }
        }
        return nil
    }

    /// Convenience: query the resolved target NPC ID for a planned
    /// social activity. Returns nil for non-social activities or when
    /// no target was resolved at planning time.
    func targetID(for activity: NPCDailyActivity, in plan: NPCDailyPlan) -> String? {
        switch activity {
        case .visitFriend:      return plan.visitFriendTargetID
        case .dropTrashAtEnemy: return plan.dropTrashTargetID
        default:                return nil
        }
    }

    // MARK: - Plan Rolling

    /// Pure function over a resident: pick today's activities and
    /// resolve their targets. Does not mutate state.
    private func rollPlan(for resident: NPCResident) -> NPCDailyPlan {
        // Slot 1: always visit shop.
        var activities: [NPCDailyActivity] = [.visitShop]

        // Determine eligibility for each pool option.
        let friendCandidates = friendlyTargets(for: resident)
        let enemyCandidates  = hostileTargets(for: resident)
        let likesCaves       = doesNPCLikeCaves(resident)

        var pool: [NPCDailyActivity] = [.forageAndTrade]
        if !friendCandidates.isEmpty { pool.append(.visitFriend) }
        if !enemyCandidates.isEmpty  { pool.append(.dropTrashAtEnemy) }
        if likesCaves                { pool.append(.gatherCaveMushrooms) }

        // Pick 2 from the pool, no duplicates.
        var pickedSlot2: NPCDailyActivity = .forageAndTrade
        var pickedSlot3: NPCDailyActivity = .forageAndTrade

        if pool.count >= 2 {
            let shuffled = pool.shuffled()
            pickedSlot2 = shuffled[0]
            pickedSlot3 = shuffled[1]
        } else if pool.count == 1 {
            pickedSlot2 = pool[0]
            // Slot 3 falls back to forage if pool is too thin.
            // .forageAndTrade is the safe always-available default.
            pickedSlot3 = .forageAndTrade
        }

        // Edge case: shuffled gave us two of the same (only possible if
        // the pool had a duplicate, which it doesn't — but defend
        // against future changes).
        if pickedSlot2 == pickedSlot3 {
            pickedSlot3 = .forageAndTrade
        }

        activities.append(pickedSlot2)
        activities.append(pickedSlot3)

        // Resolve targets where applicable.
        var visitFriendTargetID: String? = nil
        var dropTrashTargetID: String? = nil

        if activities.contains(.visitFriend),
           let friend = pickWeighted(friendCandidates) {
            visitFriendTargetID = friend.npcID
        }
        if activities.contains(.dropTrashAtEnemy),
           let enemy = pickWeighted(enemyCandidates) {
            dropTrashTargetID = enemy.npcID
        }

        return NPCDailyPlan(
            activities: activities,
            visitFriendTargetID: visitFriendTargetID,
            dropTrashTargetID: dropTrashTargetID,
            completed: []
        )
    }

    // MARK: - Eligibility Helpers

    /// Friend candidates: relationships of `resident` toward others
    /// where score ≥ friendly threshold (+25). Returns (npcID, score).
    private func friendlyTargets(for resident: NPCResident) -> [(npcID: String, score: Int)] {
        let rows = SaveService.shared.relationshipsOf(resident.npcData.id)
        return rows
            .filter { $0.score >= HostilityThreshold.friendly }
            .map { ($0.towardNPCID, $0.score) }
    }

    /// Enemy candidates: relationships where score ≤ hostile threshold
    /// (-45). Returns (npcID, score) sorted naturally for inspection.
    private func hostileTargets(for resident: NPCResident) -> [(npcID: String, score: Int)] {
        let rows = SaveService.shared.relationshipsOf(resident.npcData.id)
        return rows
            .filter { $0.score <= HostilityThreshold.hostile }
            .map { ($0.towardNPCID, $0.score) }
    }

    /// True if this NPC's `the_cave` stance is .likes or .loves.
    /// In current JSON this is Finn Fox and BB James Pufferfish only.
    private func doesNPCLikeCaves(_ resident: NPCResident) -> Bool {
        let stance = resident.npcData.opinionStances["the_cave"] ?? .unaware
        switch stance {
        case .loves, .likes: return true
        default:             return false
        }
    }

    /// Weighted random pick from a (npcID, score) list. Candidates with
    /// more extreme scores (further from 0) get higher weight — i.e.
    /// closest friend or most-hated enemy gets visited most often, but
    /// not exclusively.
    private func pickWeighted(
        _ candidates: [(npcID: String, score: Int)]
    ) -> (npcID: String, score: Int)? {
        guard !candidates.isEmpty else { return nil }
        if candidates.count == 1 { return candidates[0] }

        // Weight each candidate by abs(score). Add a small base so a
        // score of 0 (shouldn't happen at threshold but defend) doesn't
        // collapse the weight to zero.
        let weights = candidates.map { Double(abs($0.score)) + 1.0 }
        let total = weights.reduce(0, +)
        guard total > 0 else { return candidates.randomElement() }

        let roll = Double.random(in: 0..<total)
        var running = 0.0
        for (i, w) in weights.enumerated() {
            running += w
            if roll < running { return candidates[i] }
        }
        return candidates.last
    }

    // MARK: - Logging

    private func logPlan(_ plan: NPCDailyPlan, for resident: NPCResident) {
        let parts = plan.activities.enumerated().map { (i, a) -> String in
            switch a {
            case .visitFriend:
                let friend = plan.visitFriendTargetID
                    .map { NPCResidentManager.shared.findResident(byID: $0)?.npcData.name ?? $0 } ?? "?"
                return "\(i+1):\(a.debugLabel)(\(friend))"
            case .dropTrashAtEnemy:
                let enemy = plan.dropTrashTargetID
                    .map { NPCResidentManager.shared.findResident(byID: $0)?.npcData.name ?? $0 } ?? "?"
                return "\(i+1):\(a.debugLabel)(\(enemy))"
            default:
                return "\(i+1):\(a.debugLabel)"
            }
        }
        Log.debug(.resident, "[Scheduler] \(resident.npcData.name): \(parts.joined(separator: ", "))")
    }
}
