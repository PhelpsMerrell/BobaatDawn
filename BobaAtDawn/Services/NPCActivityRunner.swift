//
//  NPCActivityRunner.swift
//  BobaAtDawn
//
//  Drives NPC daily activities. Pulls each resident's plan from
//  `NPCDailyScheduler`, picks the next pending activity, and walks
//  the resident through a small state machine — out to the activity
//  target, "doing the thing" for a beat, then home.
//
//  Modeled after `ForestTrashReactionService` and the gnome state
//  machine. Service-style: singleton, `tick(now:)` called by
//  NPCResidentManager.update once per frame on host (and solo). On
//  guest the runner does nothing — host-authoritative.
//
//  TRUE POSITION MODEL
//  --------------------
//  Each NPC has exactly one logical location (`resident.status`) at
//  any given moment. The runner moves them between locations as
//  activities progress. Visual nodes (`ForestNPCEntity`, `ShopNPC`)
//  are spawned/despawned by `NPCResidentManager` based on whether
//  the player's current scene matches the NPC's logical location.
//  Net effect: the NPC is in exactly one place, and that place is
//  consistent with where they would be if they had walked there.
//
//  MULTI-LEG ACTIVITIES
//  --------------------
//  Activities can have multiple legs. Each leg is a "walk to a
//  location, do something there" pair. The step machine is:
//
//      .idle
//        → .walkingToTarget(eta)   // status flips to leg target
//        → .atTarget(eta)          // arrival side-effect runs
//        → if more legs → bump currentLeg, .walkingToTarget(eta)
//          else        → .walkingHome(eta)
//        → .walkingHome completes  → completeActivity
//
//  Most activities have a single leg (`currentLeg == 0` throughout).
//  `.forageAndTrade` has two legs:
//      leg 0 — walk to a forest room with a forageable, pick it up
//      leg 1 — walk to oak lobby, hand item to broker for a gem
//
//  ACTIVITIES THE RUNNER SKIPS
//  ----------------------------
//  `.visitShop` is NOT driven by the runner. The existing
//  `maintainShopPopulation` loop handles shop arrivals, and
//  `moveResidentToShop` calls `markActivityComplete(.visitShop, ...)`
//  itself. The runner respects this — when picking the next pending
//  activity, it skips visitShop entirely.
//
//  END-OF-DAY CLEANUP
//  ------------------
//  At dusk/night/dawn, `NPCResidentManager` calls
//  `cancelAllActivities()` here. Half-finished activities reset
//  cleanly: the resident's status normalizes to `.atHome`, any
//  carried ingredient is dropped (forfeit — they didn't make it
//  back to the broker in time), and the runner's bookkeeping is
//  cleared.
//

import Foundation
import CoreGraphics
import QuartzCore

// MARK: - Activity Step (sub-state)

/// Where in an activity's current leg the resident is.
enum NPCActivityStep: Equatable {
    /// Not running an activity (or about to begin one — runner will
    /// transition to `.walkingToTarget` on the next tick).
    case idle

    /// Transiting to the leg's target location. Status is already
    /// set to the target (teleport model — see file header).
    case walkingToTarget(completionTime: TimeInterval)

    /// At the leg's target location, performing its beat.
    case atTarget(completionTime: TimeInterval)

    /// Returning home from the activity (final leg only).
    case walkingHome(completionTime: TimeInterval)
}

// MARK: - Activity Runner

final class NPCActivityRunner {

    static let shared = NPCActivityRunner()
    private init() {}

    // MARK: - Tuning Constants

    private enum Tuning {
        /// Time to walk between forest rooms during an activity.
        static let walkToForestTarget: TimeInterval = 8.0
        /// Time to walk from forest into the oak lobby.
        static let walkToOakLobby: TimeInterval = 14.0
        /// Time to walk into the cave.
        static let walkToCave: TimeInterval = 12.0
        /// Time spent picking up a forageable.
        static let atForageTarget: TimeInterval = 5.0
        /// Time spent at the broker desk for a trade.
        static let atBroker: TimeInterval = 4.0
        /// Time spent visiting a friend.
        static let atFriend: TimeInterval = 25.0
        /// Time spent in the cave gathering mushrooms.
        static let atCave: TimeInterval = 8.0
        /// Time to walk home from the final activity target.
        static let walkHome: TimeInterval = 8.0

        /// Minimum gap between activities for the same NPC.
        static let minRestBetweenActivities: TimeInterval = 4.0
    }

    /// Per-NPC last-completed timestamp so the rest gap is honored.
    private var lastActivityCompletedAt: [String: TimeInterval] = [:]

    // MARK: - Public API

    /// Called every frame by `NPCResidentManager.update`. No-op on
    /// guest. No-op outside the day phase.
    func tick(now: TimeInterval) {
        guard !MultiplayerService.shared.isGuest else { return }
        guard NPCResidentManager.shared.currentTimePhase == .day else { return }

        for resident in NPCResidentManager.shared.getAllResidents() {
            tickResident(resident, now: now)
        }
    }

    /// Reset every resident's activity state. Called at dusk/night/dawn
    /// so half-finished activities don't leak across phases. Also
    /// normalizes mid-activity statuses back to `.atHome` so NPCs are
    /// home for the night, and drops any carried ingredient (forfeit).
    func cancelAllActivities() {
        for resident in NPCResidentManager.shared.getAllResidents() {
            if let activity = resident.currentActivity {
                if let drop = resident.carriedIngredient {
                    Log.debug(.resident, "[ActivityRunner] \(resident.npcData.name) forfeited carried \(drop.displayName) (cancelled mid-\(activity.debugLabel))")
                } else {
                    Log.debug(.resident, "[ActivityRunner] Cancelling \(resident.npcData.name)'s \(activity.debugLabel)")
                }
            }
            resident.currentActivity = nil
            resident.currentStep = .idle
            resident.stepStartedAt = 0
            resident.currentLeg = 0
            resident.carriedIngredient = nil
            resident.targetForageSpawnID = nil
            resident.targetCaveSpawnID = nil
            resident.targetCaveRoom = nil

            // Normalize status. Anyone NOT in shop and NOT at home
            // gets sent back to their cabin so the night state is
            // clean. (Shop NPCs are handled by sendAllShopNPCsHome.)
            switch resident.status {
            case .atHome, .inShop:
                break
            case .traveling, .inForestRoom, .inOakLobby, .inCaveRoom, .atFriendHouse:
                let priorLocation = resident.status.displayName
                resident.forestNPC?.removeFromParent()
                resident.forestNPC = nil
                resident.status = .atHome(room: resident.npcData.homeRoom)
                Log.debug(.resident, "[ActivityRunner] \(resident.npcData.name) sent home from \(priorLocation)")
            }
        }
        lastActivityCompletedAt.removeAll()
    }

    // MARK: - Per-Resident Tick

    private func tickResident(_ resident: NPCResident, now: TimeInterval) {
        if SaveService.shared.isNPCLiberated(resident.npcData.id) { return }
        if case .inShop = resident.status { return }

        guard let activity = resident.currentActivity else {
            tryStartNextActivity(resident, now: now)
            return
        }

        switch resident.currentStep {
        case .idle:
            beginWalkToTarget(resident, activity: activity, now: now)
        case .walkingToTarget(let completionTime):
            if now >= completionTime { beginAtTarget(resident, activity: activity, now: now) }
        case .atTarget(let completionTime):
            if now >= completionTime { advanceAfterAtTarget(resident, activity: activity, now: now) }
        case .walkingHome(let completionTime):
            if now >= completionTime { completeActivity(resident, activity: activity, now: now) }
        }
    }

    // MARK: - Activity Selection

    private func tryStartNextActivity(_ resident: NPCResident, now: TimeInterval) {
        if let last = lastActivityCompletedAt[resident.npcData.id],
           now - last < Tuning.minRestBetweenActivities {
            return
        }

        guard let next = NPCDailyScheduler.shared.nextPendingActivity(for: resident) else {
            return
        }

        // visitShop is owned by maintainShopPopulation, not this runner.
        if next == .visitShop { return }

        guard case .atHome = resident.status else { return }

        resident.currentActivity = next
        resident.currentStep = .idle
        resident.stepStartedAt = now
        resident.currentLeg = 0
        resident.carriedIngredient = nil
        resident.targetForageSpawnID = nil
        resident.targetCaveSpawnID = nil
        resident.targetCaveRoom = nil
        Log.info(.resident, "[ActivityRunner] \(resident.npcData.name) starting \(next.debugLabel)")
    }

    // MARK: - Step Transitions

    /// Begin walking to the current leg's target. Resolves which
    /// location to head to and how long it should take based on
    /// `(activity, currentLeg)`. If the leg can't be set up (e.g. no
    /// foragable available anywhere), abort cleanly.
    private func beginWalkToTarget(
        _ resident: NPCResident,
        activity: NPCDailyActivity,
        now: TimeInterval
    ) {
        guard let leg = setupLeg(resident: resident, activity: activity, leg: resident.currentLeg, now: now) else {
            // Setup failed — abort to walk-home.
            beginWalkHome(resident, activity: activity, now: now)
            return
        }

        // Despawn current forest visual; we're moving.
        resident.forestNPC?.removeFromParent()
        resident.forestNPC = nil

        resident.status = leg.targetStatus
        resident.currentStep = .walkingToTarget(completionTime: now + leg.walkDuration)
        resident.stepStartedAt = now
        Log.debug(.resident, "[ActivityRunner] \(resident.npcData.name) → \(leg.targetStatus.displayName) (leg \(resident.currentLeg))")

        refreshForestVisualIfNeeded(for: resident)
    }

    /// Arrival side-effect: pick up the forageable, hand to broker, etc.
    /// Then schedule the at-target beat.
    private func beginAtTarget(
        _ resident: NPCResident,
        activity: NPCDailyActivity,
        now: TimeInterval
    ) {
        let beat = runAtTargetSideEffect(resident: resident, activity: activity, leg: resident.currentLeg, now: now)
        resident.currentStep = .atTarget(completionTime: now + beat)
        resident.stepStartedAt = now
        Log.debug(.resident, "[ActivityRunner] \(resident.npcData.name) at \(resident.status.displayName) for \(Int(beat))s")
    }

    /// After the at-target beat finishes, decide if there are more
    /// legs (advance to next walkingToTarget) or this is the last
    /// leg (transition to walkingHome).
    private func advanceAfterAtTarget(
        _ resident: NPCResident,
        activity: NPCDailyActivity,
        now: TimeInterval
    ) {
        let nextLeg = resident.currentLeg + 1
        if hasLeg(activity: activity, leg: nextLeg, resident: resident) {
            resident.currentLeg = nextLeg
            beginWalkToTarget(resident, activity: activity, now: now)
        } else {
            beginWalkHome(resident, activity: activity, now: now)
        }
    }

    /// Walking back to the home cabin.
    private func beginWalkHome(
        _ resident: NPCResident,
        activity: NPCDailyActivity,
        now: TimeInterval
    ) {
        resident.forestNPC?.removeFromParent()
        resident.forestNPC = nil

        // Status flips to home forest room for the walk so the player
        // sees them passing through their home room.
        resident.status = .inForestRoom(resident.npcData.homeRoom)
        resident.currentStep = .walkingHome(completionTime: now + Tuning.walkHome)
        resident.stepStartedAt = now
        Log.debug(.resident, "[ActivityRunner] \(resident.npcData.name) walking home")

        refreshForestVisualIfNeeded(for: resident)
    }

    /// Walk-home complete. Mark the activity done, return resident to
    /// `.atHome`, refresh visual.
    private func completeActivity(
        _ resident: NPCResident,
        activity: NPCDailyActivity,
        now: TimeInterval
    ) {
        let homeRoom = resident.npcData.homeRoom

        resident.forestNPC?.removeFromParent()
        resident.forestNPC = nil

        resident.status = .atHome(room: homeRoom)
        resident.currentActivity = nil
        resident.currentStep = .idle
        resident.stepStartedAt = 0
        resident.currentLeg = 0
        resident.carriedIngredient = nil
        resident.targetForageSpawnID = nil
        resident.targetCaveSpawnID = nil
        resident.targetCaveRoom = nil
        lastActivityCompletedAt[resident.npcData.id] = now

        NPCDailyScheduler.shared.markActivityComplete(activity, npcID: resident.npcData.id)
        Log.info(.resident, "[ActivityRunner] \(resident.npcData.name) finished \(activity.debugLabel)")

        refreshForestVisualIfNeeded(for: resident)
    }

    // MARK: - Leg Resolution

    /// Setup data for a single leg of an activity.
    private struct LegSetup {
        let targetStatus: ResidentStatus
        let walkDuration: TimeInterval
    }

    /// Return setup data for the requested leg, or nil if the leg
    /// can't be set up (e.g. no forageable available, friend not
    /// found). A nil return aborts the activity to walk-home.
    private func setupLeg(
        resident: NPCResident,
        activity: NPCDailyActivity,
        leg: Int,
        now: TimeInterval
    ) -> LegSetup? {
        switch activity {
        case .forageAndTrade:
            switch leg {
            case 0:
                // Pick a forest room with a tradeable spawn we can
                // commit to. Snapshot the spawn id so the NPC stays
                // locked onto this specific spawn even if others get
                // collected concurrently.
                guard let pick = pickForageTarget(for: resident) else {
                    Log.info(.resident, "[ActivityRunner] \(resident.npcData.name) found no foragables today — aborting forageAndTrade")
                    return nil
                }
                resident.targetForageSpawnID = pick.spawnID
                return LegSetup(
                    targetStatus: .inForestRoom(pick.room),
                    walkDuration: Tuning.walkToForestTarget
                )
            case 1:
                // Trade leg — walk to oak lobby. Skip if we somehow
                // arrived here without an ingredient (forage failed
                // mid-leg).
                guard resident.carriedIngredient != nil else {
                    Log.debug(.resident, "[ActivityRunner] \(resident.npcData.name) reached trade leg without ingredient — aborting")
                    return nil
                }
                return LegSetup(
                    targetStatus: .inOakLobby,
                    walkDuration: Tuning.walkToOakLobby
                )
            default:
                return nil
            }

        case .visitFriend:
            guard leg == 0,
                  let friendID = resident.dailyPlan.visitFriendTargetID,
                  let friend = NPCResidentManager.shared.findResident(byID: friendID) else {
                Log.warn(.resident, "[ActivityRunner] \(resident.npcData.name) has visitFriend but no resolved target — aborting")
                return nil
            }
            return LegSetup(
                targetStatus: .atFriendHouse(npcID: friendID, room: friend.npcData.homeRoom),
                walkDuration: Tuning.walkToForestTarget
            )

        case .gatherCaveMushrooms:
            // Single leg — pick a cave room with a mushroom spawn.
            // Mushrooms spawn one-per-cave-room daily (rooms 2..4),
            // but if the player or another NPC took it already we
            // gracefully abort.
            guard leg == 0 else { return nil }
            guard let pick = pickCaveMushroomTarget() else {
                Log.info(.resident, "[ActivityRunner] \(resident.npcData.name) found no cave mushrooms today — aborting")
                return nil
            }
            resident.targetCaveSpawnID = pick.spawnID
            resident.targetCaveRoom = pick.room
            return LegSetup(
                targetStatus: .inCaveRoom(pick.room),
                walkDuration: Tuning.walkToCave
            )

        case .dropTrashAtEnemy:
            // Removed from the scheduler pool — should never reach here.
            Log.warn(.resident, "[ActivityRunner] dropTrashAtEnemy reached runner — should be reactive only")
            return nil

        case .visitShop:
            // Skipped at selection time.
            return nil
        }
    }

    /// Whether the activity has another leg after `leg`. Used by
    /// `advanceAfterAtTarget` to decide between continuing and going
    /// home.
    private func hasLeg(activity: NPCDailyActivity, leg: Int, resident: NPCResident) -> Bool {
        switch activity {
        case .forageAndTrade:
            // Leg 1 (trade) is only valid if leg 0 actually produced
            // an ingredient.
            return leg == 1 && resident.carriedIngredient != nil
        case .visitFriend, .gatherCaveMushrooms:
            return false  // single-leg activities
        case .dropTrashAtEnemy, .visitShop:
            return false
        }
    }

    // MARK: - At-Target Side Effects

    /// Run the side effect for arriving at a leg's target. Returns
    /// the duration the NPC should wait there (the at-target beat).
    private func runAtTargetSideEffect(
        resident: NPCResident,
        activity: NPCDailyActivity,
        leg: Int,
        now: TimeInterval
    ) -> TimeInterval {
        switch activity {
        case .forageAndTrade:
            switch leg {
            case 0:
                // Forage pickup.
                if let id = resident.targetForageSpawnID,
                   let spawn = ForagingManager.shared.spawn(withID: id),
                   !spawn.isCollected {
                    let success = ForagingManager.shared.collect(spawnID: id)
                    if success {
                        resident.carriedIngredient = spawn.ingredient
                        Log.info(.resident, "[ActivityRunner] \(resident.npcData.name) foraged \(spawn.ingredient.displayName) in \(spawn.location.stringKey)")
                        // Local visual cleanup if the player is
                        // currently watching the forage room.
                        NPCResidentManager.shared.removeForageNodeIfVisible(
                            spawnID: id,
                            in: spawn.location
                        )
                        // Broadcast collection so the guest's active
                        // forest scene removes the spawn node and the
                        // guest's ForagingManager marks the spawn
                        // collected too. Host-only branch — we already
                        // gated tick() on isHost above.
                        MultiplayerService.shared.send(
                            type: .itemForaged,
                            payload: ItemForagedMessage(
                                spawnID: id,
                                locationKey: spawn.location.stringKey
                            )
                        )
                    } else {
                        Log.debug(.resident, "[ActivityRunner] \(resident.npcData.name) tried to collect \(id) but it was already gone")
                    }
                } else {
                    // Spawn vanished while we were walking. No
                    // ingredient — `hasLeg` will see no carriedIngredient
                    // and skip the trade leg, sending us home.
                    Log.debug(.resident, "[ActivityRunner] \(resident.npcData.name)'s target spawn \(resident.targetForageSpawnID ?? "?") was gone on arrival")
                }
                return Tuning.atForageTarget
            case 1:
                // Trade with the broker.
                if let item = resident.carriedIngredient {
                    let traded = GnomeManager.shared.brokerReceiveTrade(item: item)
                    if traded {
                        Log.info(.resident, "[ActivityRunner] \(resident.npcData.name) traded \(item.displayName) to broker")
                    } else {
                        // Broker unavailable / box full / out of gems.
                        // Discard the ingredient — NPC walks home empty.
                        Log.info(.resident, "[ActivityRunner] \(resident.npcData.name) couldn't trade \(item.displayName) (broker unavailable) — discarding")
                    }
                    resident.carriedIngredient = nil
                }
                return Tuning.atBroker
            default:
                return 1.0
            }

        case .visitFriend:
            // Apply a small one-shot relationship bump in both
            // directions, modeled as `.gossipShared` (+2/+2). Visiting
            // a friend reinforces the bond — not as much as a real
            // conversation, but more than passive proximity.
            // (Wrapped in a guard for the friend ID; if the resolution
            // failed earlier we still spend the dwell time but skip
            // the bump.)
            if leg == 0,
               let friendID = resident.dailyPlan.visitFriendTargetID {
                SaveService.shared.applyConversationInteraction(
                    speaker: resident.npcData.id,
                    listener: friendID,
                    interaction: .gossipShared,
                    incrementConversationCount: false
                )
                Log.info(.resident, "[ActivityRunner] \(resident.npcData.name) visited friend \(friendID) — +2/+2 bond")
            }
            // 3c-3 still uses dwell time as the visible "hanging out"
            // beat. The relationship change happens once on arrival.
            return Tuning.atFriend

        case .gatherCaveMushrooms:
            // Pick up the committed mushroom spawn, if it's still there.
            if let id = resident.targetCaveSpawnID,
               let spawn = ForagingManager.shared.spawn(withID: id),
               !spawn.isCollected {
                let success = ForagingManager.shared.collect(spawnID: id)
                if success {
                    Log.info(.resident, "[ActivityRunner] \(resident.npcData.name) gathered \(spawn.ingredient.displayName) in \(spawn.location.stringKey)")
                    // Deposit the mushroom in the pantry. The NPC is
                    // taking it home and the cook will use it at the
                    // next meal. If the pantry is full and the new
                    // ingredient is novel, store() returns false and
                    // we just log it (the NPC "ate it" — no other
                    // bookkeeping; mushrooms aren't tracked on NPCs).
                    if spawn.ingredient.isPantryDepositable {
                        let stored = StorageRegistry.shared.store(
                            ingredient: spawn.ingredient.rawValue,
                            in: "pantry"
                        )
                        if !stored {
                            Log.info(.resident, "[ActivityRunner] \(resident.npcData.name)'s mushroom didn't fit in the pantry — discarded")
                        }
                    }
                    // Broadcast collection to the guest. Cave rooms
                    // aren't currently visible-room-cleaned because
                    // `removeForageNodeIfVisible` only checks forest
                    // rooms; cave scenes will pick up the change on
                    // re-entry.
                    MultiplayerService.shared.send(
                        type: .itemForaged,
                        payload: ItemForagedMessage(
                            spawnID: id,
                            locationKey: spawn.location.stringKey
                        )
                    )
                } else {
                    Log.debug(.resident, "[ActivityRunner] \(resident.npcData.name) tried to gather \(id) but it was already gone")
                }
            } else {
                Log.debug(.resident, "[ActivityRunner] \(resident.npcData.name)'s cave spawn \(resident.targetCaveSpawnID ?? "?") was gone on arrival")
            }
            return Tuning.atCave

        case .dropTrashAtEnemy, .visitShop:
            return 1.0
        }
    }

    // MARK: - Forage Target Selection

    /// A picked forage target: which spawn, which room.
    private struct ForagePick {
        let spawnID: String
        let room: Int
    }

    /// Find a forest room with a tradeable forageable (matcha,
    /// strawberry, or mushroom — anything `isPantryDepositable`).
    /// Prefer rooms other than the resident's home room for variety.
    /// Returns nil if no tradeable spawns exist anywhere in the forest.
    ///
    /// Rocks and gems are excluded — those are work items, not
    /// broker-tradeable.
    private func pickForageTarget(for resident: NPCResident) -> ForagePick? {
        let here = resident.npcData.homeRoom

        // Build a list of (room, eligible spawns) across all forest rooms.
        var candidates: [(room: Int, spawns: [ForageSpawn])] = []
        for room in 1...5 {
            let roomSpawns = ForagingManager.shared.spawnsFor(.forestRoom(room))
                .filter { $0.ingredient.isPantryDepositable }
            if !roomSpawns.isEmpty {
                candidates.append((room: room, spawns: roomSpawns))
            }
        }
        guard !candidates.isEmpty else { return nil }

        // Prefer non-home rooms first; fall back to home if needed.
        let preferred = candidates.filter { $0.room != here }
        let pool = preferred.isEmpty ? candidates : preferred

        guard let chosen = pool.randomElement(),
              let spawn = chosen.spawns.randomElement() else { return nil }

        return ForagePick(spawnID: spawn.spawnID, room: chosen.room)
    }

    /// Find a cave room (2..4) that still has a mushroom spawn today.
    /// Returns nil if every mushroom is already collected.
    private func pickCaveMushroomTarget() -> ForagePick? {
        for room in [2, 3, 4] {
            let mushrooms = ForagingManager.shared.spawnsFor(.caveRoom(room))
                .filter { $0.ingredient == .mushroom }
            if let pick = mushrooms.randomElement() {
                return ForagePick(spawnID: pick.spawnID, room: room)
            }
        }
        return nil
    }

    // MARK: - Visual Refresh

    private func refreshForestVisualIfNeeded(for resident: NPCResident) {
        guard let forestRoom = resident.status.visibleForestRoom else { return }
        NPCResidentManager.shared.refreshForestVisualIfPlayerInRoom(resident, room: forestRoom)
    }
}
