//
//  GnomeManager.swift
//  BobaAtDawn
//
//  Singleton orchestrator for the 18-gnome simulation. Mirrors the
//  pattern of NPCResidentManager — agents persist across scenes, the
//  manager ticks every frame and runs each agent's task state machine,
//  and scenes ask the manager for "who's logically in this room right
//  now" so they can spawn matching GnomeNPC visuals.
//
//  DAILY LOOP (post-cart rework)
//  -----------------------------
//  Dawn: breakfast and mingling in the oak, then the mine crew hauls
//        the empty cart back to the cave together.
//  Day:  STRICTLY cave-bound. Miners cycle through floors 2/3/4 picking
//        up rocks; rocks go to the machine in the entrance; on a green
//        verdict the miner walks the gem to the in-cave MINE CART (also
//        in the entrance) which accumulates the day's haul. On a red
//        verdict the rock goes to the waste bin. NPC↔gnome forest/oak
//        traffic is removed during the day.
//  Dusk: cart procession. All active miners + boss converge on cave
//        entrance, then march in lockstep with the cart along
//        cave_1 → forest_2 → forest_3 → forest_4 → oak_1 → oak_5
//        (treasury). On arrival, the cart's full load is dumped into
//        the treasury in one celebratory beat.
//  Night: gnomes scatter to bedrooms and sleep. Cart stays parked in
//         the oak until the dawn return procession.
//
//  HOST AUTHORITY
//  --------------
//  In multiplayer the host runs the simulation and broadcasts a full
//  snapshot every ~0.5s via `gnomeStateSync` (now also carries cart
//  state). The guest applies snapshots verbatim. Treasury count is
//  broadcast either as part of the snapshot (normal updates) or via a
//  dedicated TreasuryUpdateMessage for instantaneous deposits.
//
//  PERSISTENCE
//  -----------
//  At every dawn rollover and on disconnect the manager dumps its full
//  state via `exportSaveData()` for SaveService. On boot it consumes
//  whatever SaveService loads. Cart count + cart room are persisted
//  too, so a mid-procession reconnect resumes cleanly.
//
//  VISUAL CHOREOGRAPHY
//  -------------------
//  Each task drives a specific visual movement:
//    - commutingToMine → continuous traversal across each room.
//    - lookingForRock → active wander with a target near rock spawns.
//    - usingMachine / depositingGemAtCart / dumpingRockInWasteBin →
//      walk to + stand at the relevant fixture in cave entrance.
//    - gatheringForCartTrip → walk up the cave to room 1, idle near cart.
//    - haulingCart → group march in lockstep with the cart, no per-
//      agent jitter (so the parade reads cleanly).
//    - celebrating → stand near treasury with raised emoji until the
//      celebration timeout, then scatter to bedrooms.
//    - sleeping / idle / supervising → small in-room drift.
//
//  TRAFFIC DENSITY
//  ---------------
//  Per-agent jitter desynchronizes the cycle so the cave feels populated
//  rather than scheduled. Each agent has a personal speed multiplier
//  derived from their id; combined with randomized post-deposit pauses,
//  no two miners ever take the same time to complete a round trip.
//  During `.haulingCart` the multiplier is bypassed so the procession
//  stays in lockstep.
//

import SpriteKit
import Foundation

// MARK: - Daily Timing Constants
//
// These are deliberately short so the player sees a continuous flow of
// gnomes throughout the day. These timings are intentionally very mellow
// so the procession reads clearly and the player has time to notice
// chatter, handoffs, and repeated work loops.
private enum GnomeTiming {
    /// Time spent crossing a single forest room while in transit.
    /// Also the duration of the visual traversal animation.
    static let transitPerForestRoom: TimeInterval = 24.0

    /// Time spent walking down stairs from one cave floor to the next.
    /// Also the duration of the vertical traversal animation.
    static let transitPerCaveFloor: TimeInterval = 15.5

    /// How long a miner spends hunting for a rock in a cave floor before
    /// actually picking one up. Long-ish on purpose — it's how the cave
    /// reads as "populated" rather than "a corridor people pass through".
    static let rockHuntDuration: TimeInterval = 22.0

    /// Time at the machine before verdict.
    static let machineUseDuration: TimeInterval = 10.0

    /// Time at the waste bin to drop a rejected rock.
    static let wasteDumpDuration: TimeInterval = 7.0

    /// Time at the treasury pile to deposit a gem.
    static let treasuryDepositDuration: TimeInterval = 8.0

    /// Time the gnome spends standing at the cart depositing a gem.
    static let cartDepositDuration: TimeInterval = 5.0

    /// Dawn is split into two equal beats: breakfast/mingling in the
    /// oak, then the shared walk back to the cave with the cart.
    static let dawnBreakfastDuration: TimeInterval = GameConfig.Time.dawnDuration / 2.0
    static let dawnReturnTravelDuration: TimeInterval = GameConfig.Time.dawnDuration / 2.0

    /// Dusk is split into four explicit one-minute beats:
    /// prep in the mines, travel to the oak, treasury turn-in, then
    /// dinner/mingling before bed.
    static let duskMinePrepDuration: TimeInterval = 60.0
    static let duskCartTravelDuration: TimeInterval = 60.0
    static let duskTreasuryDuration: TimeInterval = 60.0
    static let duskDinnerDuration: TimeInterval = 60.0

    /// The cart route crosses five room segments:
    /// cave_1 → forest_2 → forest_3 → forest_4 → oak_1 → oak_5.
    /// Travel minute divided evenly across them.
    static let processionRoomDuration: TimeInterval = duskCartTravelDuration / 5.0

    /// Dawn return route crosses four segments:
    /// oak_1 → forest_4 → forest_3 → forest_2 → cave_1.
    static let dawnReturnRoomDuration: TimeInterval = dawnReturnTravelDuration / 4.0

    /// Wander tick interval inside a single room.
    static let wanderInterval: TimeInterval = 24.0

    /// How often (real seconds) the host broadcasts gnome state.
    static let stateSyncInterval: TimeInterval = 0.5

    /// Random pause after arriving home / at treasury before heading
    /// back out — keeps cycles desynced so traffic is continuous.
    static let postArrivalPauseRange: ClosedRange<TimeInterval> = 5.0...14.0

    /// Offscreen drift speed for home / supervisory motion.
    static let idleWalkSpeed: CGFloat = 18

    /// Offscreen walk speed while a miner is actively searching a floor.
    static let huntWalkSpeed: CGFloat = 26

    /// Offscreen approach speed for targets like the machine, bin, or pile.
    static let taskWalkSpeed: CGFloat = 28
}

// MARK: - Geometry Constants (room layout)

private enum GnomeGeometry {
    // Forest rooms run horizontally. Outbound (oak→cave) walks right→left;
    // inbound (cave→oak) walks left→right. Stable lanes keep the traffic
    // reading as a procession instead of a scatter plot.
    static let forestEdgeX: CGFloat = 720
    static let forestOutboundBaseY: CGFloat = -120
    static let forestInboundBaseY: CGFloat = 120
    static let forestLaneCount = 4
    static let forestLaneSpacing: CGFloat = 22
    static let forestLaneWobble: CGFloat = 7

    // Cave rooms are vertical. Stairs up at top (+Y), stairs down at
    // bottom (-Y). Descending: enter top, exit bottom. Ascending: enter
    // bottom, exit top. Stable X lanes make the mine traffic easier to read.
    static let caveEdgeY: CGFloat = 360
    static let caveLaneCount = 5
    static let caveLaneSpacing: CGFloat = 70
    static let caveLaneWobble: CGFloat = 10

    // Oak rooms — gnomes enter/exit through the lobby. Use a shallow
    // jittered box so they don't all stack at one anchor.
    static let oakXJitter: ClosedRange<CGFloat> = -220...220
    static let oakYJitter: ClosedRange<CGFloat> = -110...110
}

// MARK: - Travel Direction

/// Whether an agent in a commute/carrying state is moving toward the
/// mines (outbound) or toward the oak (inbound). Used to decide which
/// edge of a forest room they enter from.
private enum GnomeTravelDirection {
    case outbound  // oak → cave (delivering self / coming to work)
    case inbound   // cave → oak (returning home / delivering gem)
    case neutral   // not in a directional task
}

// MARK: - Gnome Manager

final class GnomeManager {

    static let shared = GnomeManager()

    // MARK: - Agents
    private(set) var agents: [GnomeAgent] = []

    // MARK: - Treasury
    private(set) var treasuryGemCount: Int = 0
    private var pendingResetCelebration: Bool = false

    // MARK: - Mine Cart
    /// Gems currently sitting in the cart. Accumulates throughout the
    /// day as miners feed the machine and deposit greens. Drained to
    /// zero (and dumped into the treasury) when the cart arrives at
    /// the oak treasury at dusk.
    private(set) var cartGemCount: Int = 0
    /// Logical room the cart is in.
    private(set) var cartLocation: GnomeLocation = .caveRoom(1)
    /// Cart's interpolated position within the current room
    /// (scene-space). Updated each frame during procession.
    private(set) var cartPosition: CGPoint = .zero
    /// Cart lifecycle state.
    private(set) var cartState: MineCartState = .idle
    /// Time at which `cartState` last changed — drives procession
    /// timing and celebration timeout.
    private var cartTaskStartedAt: TimeInterval = 0
    /// Absolute time at which the current dusk window ends.
    private var cartDuskEndsAt: TimeInterval = 0
    /// Absolute time at which the dinner/mingling minute begins.
    private var cartDinnerStartsAt: TimeInterval = 0
    /// Planned duration of the treasury turn-in beat.
    private var cartTreasuryTurnInDuration: TimeInterval = 0
    /// Per-room duration for the current procession segment.
    private var cartCurrentRoomDuration: TimeInterval = GnomeTiming.processionRoomDuration
    /// Currently-attached cart visual (weak — the scene parents it).
    private weak var cartVisual: MineCart?

    // MARK: - Dawn Timing
    /// Whether the dawn cart return procession is already in flight.
    private var dawnReturnStarted: Bool = false

    // MARK: - Day Tracking
    private(set) var currentDayCount: Int = -1
    /// Optional so the *first* call to `handleTimePhaseChange` always
    /// runs, regardless of which phase the game starts in.
    private var lastKnownPhase: TimePhase? = nil

    // MARK: - Scene References
    private weak var oakScene: BigOakTreeScene?
    private weak var caveScene: CaveScene?
    private weak var forestScene: ForestScene?

    // MARK: - Promotion / Demotion
    private(set) var todaysRankChangeID: String?
    private(set) var todaysRankChangeIsPromotion: Bool = true
    private(set) var todaysBossLine: String?

    // MARK: - Sync Timing
    private var stateSyncAccumulator: TimeInterval = 0

    // MARK: - Init

    private init() {
        let now = CACurrentMediaTime()
        agents = GnomeRoster.all.map { GnomeAgent(identity: $0, startTime: now) }

        for agent in agents {
            agent.task = .sleeping
            agent.location = .oakRoom(agent.identity.homeOakRoom)
            agent.position = restingPosition(for: agent.location, agent: agent)
            agent.wanderTarget = agent.position
            agent.hasRealPosition = true
        }
    }

    func resetForNewGame() {
        let now = CACurrentMediaTime()

        despawnAllVisibleGnomes()
        despawnCartVisualNode()
        clearCartDuskTiming()
        clearDawnTiming()

        pendingResetCelebration = false
        treasuryGemCount = 0
        cartGemCount = 0
        cartLocation = .caveRoom(1)
        cartPosition = cartRestingPosition(in: cartLocation)
        cartState = .idle
        cartTaskStartedAt = 0
        cartDuskEndsAt = 0
        cartDinnerStartsAt = 0
        cartTreasuryTurnInDuration = 0
        cartCurrentRoomDuration = GnomeTiming.processionRoomDuration
        dawnReturnStarted = false
        currentDayCount = -1
        lastKnownPhase = nil
        todaysRankChangeID = nil
        todaysRankChangeIsPromotion = true
        todaysBossLine = nil
        stateSyncAccumulator = 0

        for agent in agents {
            agent.rank = agent.identity.initialRank
            agent.location = .oakRoom(agent.identity.homeOakRoom)
            agent.task = agent.identity.role.livesInOak ? .idle : .sleeping
            agent.carried = nil
            agent.taskStartedAt = now
            agent.position = restingPosition(for: agent.location, agent: agent)
            agent.hasRealPosition = true
            agent.wanderTarget = agent.position
            agent.nextWanderAt = 0
            agent.sceneNode?.removeFromParent()
            agent.sceneNode = nil
            agent.carriedRockSpawnID = nil
            agent.workingCaveFloor = nil
            agent.gemsDeliveredToday = 0
            agent.isOnMineDutyToday = !agent.identity.role.livesInOak
        }

        oakScene?.updateTreasuryPileIfPresent(count: 0, didReset: true)
        Log.info(.npc, "[Gnomes] Reset for a fresh game")
    }

    // MARK: - Scene Registration

    func registerOakScene(_ scene: BigOakTreeScene) { oakScene = scene }
    func registerCaveScene(_ scene: CaveScene) { caveScene = scene }
    func registerForestScene(_ scene: ForestScene) { forestScene = scene }

    /// If the player enters the oak during dawn phase 1 after the meal
    /// would normally have started, recover the breakfast seating state
    /// now that the seat anchors are finally available.
    func ensureOakBreakfastIfNeeded(now: TimeInterval = CACurrentMediaTime()) {
        guard oakScene != nil else { return }
        guard TimeManager.shared.currentPhase == .dawn else { return }
        guard TimeManager.shared.phaseProgress < 0.5 else { return }
        guard !dawnReturnStarted else { return }
        guard !GnomeSeating.shared.isMealActive else { return }
        stageDawnBreakfast(now: now)
    }

    // MARK: - Public API: Scene Spawning Hooks

    func spawnVisibleGnomes(inOakRoom oakRoom: OakRoom, container: SKNode, scene: BigOakTreeScene) {
        let wantLocation = GnomeLocation.oakRoom(oakRoom.rawValue)
        let agentsHere = agents.filter { $0.location == wantLocation }
        for agent in agentsHere {
            spawnVisual(for: agent, in: scene, fallbackContainer: container)
        }
        logVisibleDuskSpawn(scope: "oak_\(oakRoom.rawValue)", agentsHere: agentsHere)
        Log.info(.npc, "Oak room \(oakRoom.debugName): spawned \(agentsHere.count) gnome visuals")
    }

    func spawnVisibleGnomes(inCaveRoom caveRoom: CaveRoom, scene: CaveScene) {
        let wantLocation = GnomeLocation.caveRoom(caveRoom.rawValue)
        let agentsHere = agents.filter { $0.location == wantLocation }
        for agent in agentsHere {
            spawnVisual(for: agent, in: scene, fallbackContainer: nil)
        }
        logVisibleDuskSpawn(scope: "cave_\(caveRoom.rawValue)", agentsHere: agentsHere)
        Log.info(.npc, "Cave room \(caveRoom.debugName): spawned \(agentsHere.count) gnome visuals")
    }

    func spawnVisibleGnomes(inForestRoom forestRoom: Int, scene: ForestScene) {
        let wantLocation = GnomeLocation.forestRoom(forestRoom)
        let agentsHere = agents.filter { $0.location == wantLocation }
        for agent in agentsHere {
            spawnVisual(for: agent, in: scene, fallbackContainer: nil)
        }
        logVisibleDuskSpawn(scope: "forest_\(forestRoom)", agentsHere: agentsHere)
        if !agentsHere.isEmpty {
            Log.info(.npc, "Forest room \(forestRoom): spawned \(agentsHere.count) gnomes in transit")
        }
    }

    func despawnAllVisibleGnomes() {
        for agent in agents {
            agent.sceneNode?.removeFromParent()
            agent.sceneNode = nil
        }
    }

    // MARK: - Time Phase Handling

    /// Drives the daily cycle. Dawn = breakfast in the oak, then a
    /// shared cart return to the cave for the mine crew.
    /// Dusk/night = either kick off the cart procession (if there are
    /// gems on the cart) or send everyone straight home (if nothing
    /// was mined). The cart-aware handling lives in `handleDuskOrNight`.
    ///
    /// First call always runs (lastKnownPhase is nil at boot) so the
    /// gnomes pick up the correct state for the current phase even if
    /// the game starts mid-day.
    func handleTimePhaseChange(_ newPhase: TimePhase, dayCount: Int) {
        if let last = lastKnownPhase, last == newPhase { return }
        let oldPhase = lastKnownPhase
        lastKnownPhase = newPhase
        Log.info(.npc, "[Gnomes] Phase \(oldPhase?.displayName ?? "nil") → \(newPhase.displayName) (day \(dayCount))")

        switch newPhase {
        case .dawn:
            handleDawnRollover(dayCount: dayCount, includeBreakfast: true)
        case .day:
            if oldPhase == .dawn {
                launchMineShiftImmediately(now: CACurrentMediaTime())
                clearDawnTiming()
            }
            // Boot path or first-day-after-fresh-boot: ensure mining
            // is in progress so the player sees gnomes immediately.
            if oldPhase == nil {
                handleDawnRollover(dayCount: dayCount, includeBreakfast: false)
            }
        case .dusk, .night:
            clearDawnTiming()
            handleDuskOrNight(now: CACurrentMediaTime())
        }
    }

    private func handleDawnRollover(dayCount: Int, includeBreakfast: Bool) {
        currentDayCount = dayCount

        for agent in agents { agent.gemsDeliveredToday = 0 }
        todaysRankChangeID = nil
        todaysBossLine = nil

        // Dawn starts with the empty cart still in the oak. The mine
        // crew brings it back with them during the second half.
        let now = CACurrentMediaTime()
        cartGemCount = 0
        cartLocation = .oakRoom(1)
        cartState = .resting
        cartPosition = cartRestingPosition(in: cartLocation)
        cartTaskStartedAt = now
        clearCartDuskTiming()
        clearDawnTiming()
        // Drop the visual; whichever scene is active will respawn it
        // on its next setupCurrentRoom() pass.
        cartVisual?.removeFromParent()
        cartVisual = nil

        rotateMineDuty(dayCount: dayCount)

        // Stable miner ordering keeps cave-floor assignments consistent.
        let activeMiners = orderedTransitAgents(
            from: agents.filter { $0.identity.role == .miner && $0.isOnMineDutyToday },
            salt: "dawn_\(dayCount)"
        )

        for agent in agents {
            agent.carried = nil
            agent.carriedRockSpawnID = nil
            if agent.identity.role == .miner {
                let floorPicks: [Int] = [2, 3, 4]
                let idx = activeMiners.firstIndex(where: { $0.identity.id == agent.identity.id }) ?? 0
                agent.workingCaveFloor = agent.isOnMineDutyToday ? floorPicks[idx % floorPicks.count] : nil
            } else {
                agent.workingCaveFloor = nil
            }
        }

        if includeBreakfast {
            stageDawnBreakfast(now: now)
        } else {
            launchMineShiftImmediately(now: now)
        }

        rollDailyRankChange(dayCount: dayCount)

        if MultiplayerService.shared.isHost {
            let msg = GnomeRosterRefreshMessage(
                promotedID: todaysRankChangeIsPromotion ? todaysRankChangeID : nil,
                demotedID: todaysRankChangeIsPromotion ? nil : todaysRankChangeID,
                newRank: todaysRankChangeID.flatMap { id in
                    agents.first(where: { $0.identity.id == id })?.rank.rawValue
                },
                bossLine: todaysBossLine,
                dayCount: dayCount
            )
            MultiplayerService.shared.send(type: .gnomeRosterRefresh, payload: msg)
        }
    }

    private func stageDawnBreakfast(now: TimeInterval) {
        cartLocation = .oakRoom(1)
        cartState = .resting
        cartPosition = cartRestingPosition(in: cartLocation)
        cartTaskStartedAt = now
        despawnCartVisualNode()
        spawnCartVisualIfCurrentRoomMatches(newLocation: cartLocation)
        cartVisual?.setCount(0, animated: false)
        cartVisual?.stopRolling()

        // Try to seat everyone at dining tables. Falls back gracefully
        // (returns false) if the SKS doesn't have seat anchors yet, in
        // which case we drop through to the legacy free-mingle path.
        let seated = GnomeSeating.shared.beginMeal(
            .breakfast, agents: agents, oakScene: oakScene, now: now
        )

        for agent in agents {
            // Cook gets the cookServingFromStation task; everyone else
            // gets .dining when seated, .idle otherwise (back-compat).
            let isCook = agent.identity.id == GnomeRoster.kitchenCook.id
            let target: CGPoint
            if seated {
                target = GnomeSeating.shared.mealPosition(
                    for: agent,
                    oakScene: oakScene,
                    fallbackMinglePosition: dinnerMinglePosition(for: agent)
                )
                agent.task = isCook ? .cookServingFromStation : .dining
            } else {
                target = dinnerMinglePosition(for: agent)
                agent.task = .idle
            }
            agent.taskStartedAt = now
            agent.location = .oakRoom(1)
            agent.position = target
            agent.wanderTarget = target
            agent.hasRealPosition = true
            agent.sceneNode?.removeFromParent()
            agent.sceneNode = nil
            respawnVisualIfRoomVisible(agent: agent)
        }

        Log.info(.npc, "[Gnomes][Dawn] phase 1/2 started: breakfast seating (\(Int(GnomeTiming.dawnBreakfastDuration))s)")
        logDawnSnapshot("breakfast seating started")
    }

    private func launchMineShiftImmediately(now: TimeInterval) {
        cartGemCount = 0
        cartLocation = .caveRoom(1)
        cartState = .idle
        cartPosition = cartRestingPosition(in: cartLocation)
        cartTaskStartedAt = now
        despawnCartVisualNode()
        spawnCartVisualIfCurrentRoomMatches(newLocation: cartLocation)
        cartVisual?.setCount(0, animated: false)
        cartVisual?.stopRolling()

        for agent in agents {
            switch agent.identity.role {
            case .boss:
                if agent.isOnMineDutyToday {
                    agent.task = .supervising
                    agent.location = .caveRoom(1)
                    agent.position = restingPosition(for: agent.location, agent: agent)
                    agent.wanderTarget = agent.position
                } else {
                    agent.task = .idle
                    agent.location = .oakRoom(agent.identity.homeOakRoom)
                    agent.position = restingPosition(for: agent.location, agent: agent)
                    agent.wanderTarget = agent.position
                }
            case .miner:
                if agent.isOnMineDutyToday {
                    let targetFloor = agent.workingCaveFloor ?? 2
                    agent.task = .lookingForRock
                    agent.location = .caveRoom(targetFloor)
                    agent.position = restingPosition(for: agent.location, agent: agent)
                    agent.wanderTarget = nil
                } else {
                    agent.task = .idle
                    agent.location = .oakRoom(agent.identity.homeOakRoom)
                    agent.position = restingPosition(for: agent.location, agent: agent)
                    agent.wanderTarget = agent.position
                }
            case .housekeeper, .npcBroker, .treasurer:
                agent.task = .idle
                agent.location = .oakRoom(agent.identity.homeOakRoom)
                agent.position = restingPosition(for: agent.location, agent: agent)
                agent.wanderTarget = agent.position
            }
            agent.taskStartedAt = now
            agent.hasRealPosition = true
            agent.sceneNode?.removeFromParent()
            agent.sceneNode = nil
            respawnVisualIfRoomVisible(agent: agent)
        }
    }

    /// Drives the daily cycle. Dawn is handled separately; dusk/night
    /// either launches the treasury procession or sends everyone home.
    /// Dusk/night = either kick off the cart procession (if there are
    /// gems to haul) or send everyone home directly (if nothing was
    /// mined). The current time-phase tick is idempotent — it only
    /// triggers `beginCartProcession` / `forceAllHomeDirectly` when
    /// `cartState == .idle`, so a dusk → night transition mid-procession
    /// doesn't restart anything.
    private func handleDuskOrNight(now: TimeInterval) {
        guard cartState == .idle else {
            // Procession or celebration in flight — leave it alone.
            return
        }
        if cartGemCount > 0 {
            beginDuskGathering(now: now)
        } else {
            forceAllHomeDirectly(now: now)
        }
    }

    /// Send everyone home immediately, no procession. Used when the
    /// cart is empty at dusk (nothing was mined) or as a fallback if
    /// the procession can't proceed for some reason. Identical to the
    /// pre-cart `recallEveryoneHome` behavior.
    private func forceAllHomeDirectly(now: TimeInterval) {
        clearCartDuskTiming()
        let recallCrew = orderedTransitAgents(
            from: agents.filter { !$0.identity.role.livesInOak },
            salt: "dusk_\(max(0, currentDayCount))"
        )
        for agent in agents {
            // Lobby crew (housekeepers + broker + treasurer) stay where
            // they are, just go idle/sleeping.
            if agent.identity.role.livesInOak {
                agent.task = .idle
                agent.taskStartedAt = now
                agent.wanderTarget = restingPosition(for: agent.location, agent: agent)
                continue
            }
            // Already in oak — go to sleep.
            if case .oakRoom = agent.location {
                agent.task = .sleeping
                agent.taskStartedAt = now
                agent.wanderTarget = restingPosition(for: agent.location, agent: agent)
                continue
            }
            // Drop carried items — nothing makes it home tonight.
            agent.carried = nil
            agent.carriedRockSpawnID = nil
            agent.wanderTarget = nil
            agent.task = .commutingHome
            agent.taskStartedAt = now + recallDelay(for: agent, orderedCrew: recallCrew)
            agent.sceneNode?.refreshVisualBadges()
        }
        Log.info(.npc, "[Gnomes] Dusk — cart empty, sending everyone straight home")
    }

    /// Dusk procession kickoff. Set every active miner + boss to
    /// `.gatheringForCartTrip`; once they're all in the cave entrance
    /// (or after a timeout) the procession actually begins.
    private func beginDuskGathering(now: TimeInterval) {
        configureCartDuskTiming(now: now)
        cartState = .gathering
        cartTaskStartedAt = now

        for agent in agents {
            if agent.identity.role.livesInOak {
                // Oak gnomes are already preparing supper while the
                // miners gather the cart. Keep them in the lobby so
                // the player can actually find them during dusk.
                agent.location = .oakRoom(1)
                let prepTarget = dinnerMinglePosition(for: agent)
                agent.task = .idle
                agent.taskStartedAt = now
                agent.position = prepTarget
                agent.wanderTarget = prepTarget
                agent.hasRealPosition = true
                agent.sceneNode?.removeFromParent()
                agent.sceneNode = nil
                respawnVisualIfRoomVisible(agent: agent)
                continue
            }
            // If they're carrying a gem mid-trip, count it toward the
            // cart immediately (the procession will deliver it).
            if agent.carried == .gem {
                cartGemCount += 1
            }
            // Rocks just disappear at dusk — no time to refine.
            agent.carried = nil
            agent.carriedRockSpawnID = nil
            agent.wanderTarget = nil
            agent.task = .gatheringForCartTrip
            agent.taskStartedAt = now
            agent.sceneNode?.refreshVisualBadges()
        }
        cartVisual?.setCount(cartGemCount, animated: false)
        Log.info(.npc, "[Gnomes] Dusk — cart procession gathering (\(cartGemCount) gems on the cart)")
        Log.info(.npc, "[Gnomes][Dusk] phase 1/4 started: mine prep (60s)")
        logDuskSnapshot("mine prep started")
    }

    // MARK: - Daily Rotation

    private func rotateMineDuty(dayCount: Int) {
        if let boss = agents.first(where: { $0.identity.role == .boss }) {
            boss.isOnMineDutyToday = true
        }
        let miners = agents.filter { $0.identity.role == .miner }
        for miner in miners {
            miner.isOnMineDutyToday = true
        }
        for hk in agents where hk.identity.role.livesInOak {
            hk.isOnMineDutyToday = false
        }
    }

    private func rollDailyRankChange(dayCount: Int) {
        let miners = agents.filter { $0.identity.role == .miner }
        guard !miners.isEmpty else { return }

        let preferPromotion = (dayCount % 2 == 0)

        if preferPromotion {
            let eligible = miners.filter { $0.rank != .foreman }
            guard let candidate = eligible.randomElement() else { return }
            candidate.rank = GnomeRank(rawValue: candidate.rank.rawValue + 1) ?? .foreman
            todaysRankChangeIsPromotion = true
            todaysRankChangeID = candidate.identity.id
            todaysBossLine = "\(candidate.identity.displayName) — you're \(candidate.rank.title) now. Don't make me regret it."
            Log.info(.npc, "[Gnomes] PROMOTION: \(candidate.identity.displayName) → \(candidate.rank.title)")
            DailyChronicleLedger.shared.recordGnomeRankChanged(
                gnomeID: candidate.identity.id,
                gnomeName: candidate.identity.displayName,
                newRank: candidate.rank.title,
                bossLine: todaysBossLine,
                isPromotion: true
            )
        } else {
            let eligible = miners.filter { $0.rank != .junior }
            guard let candidate = eligible.randomElement() else { return }
            candidate.rank = GnomeRank(rawValue: candidate.rank.rawValue - 1) ?? .junior
            todaysRankChangeIsPromotion = false
            todaysRankChangeID = candidate.identity.id
            todaysBossLine = "\(candidate.identity.displayName), I'm bumping you back to \(candidate.rank.title). Sharpen up."
            Log.info(.npc, "[Gnomes] DEMOTION: \(candidate.identity.displayName) → \(candidate.rank.title)")
            DailyChronicleLedger.shared.recordGnomeRankChanged(
                gnomeID: candidate.identity.id,
                gnomeName: candidate.identity.displayName,
                newRank: candidate.rank.title,
                bossLine: todaysBossLine,
                isPromotion: false
            )
        }
    }

    // MARK: - Per-agent speed jitter
    //
    // Each agent walks at slightly different pace so the round-trip
    // cycles never sync up. Multiplier is in [0.85, 1.15] derived from
    // a stable hash of the gnome id so it's the same across launches
    // and across host/guest.

    private func stableHash(_ string: String) -> UInt64 {
        var hash: UInt64 = 1469598103934665603
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 1099511628211
        }
        return hash
    }

    private func stableUnitValue(for key: String) -> Double {
        Double(stableHash(key) & 0xFFFF) / 65535.0
    }

    private func stableSignedOffset(for key: String, magnitude: CGFloat) -> CGFloat {
        let unit = CGFloat(stableUnitValue(for: key))
        return (unit - 0.5) * 2 * magnitude
    }

    private func orderedTransitAgents(from agents: [GnomeAgent], salt: String) -> [GnomeAgent] {
        agents.sorted {
            stableHash("\(salt)|\($0.identity.id)") < stableHash("\(salt)|\($1.identity.id)")
        }
    }

    private func departureDelay(for agent: GnomeAgent, orderedCrew: [GnomeAgent]) -> TimeInterval {
        guard let idx = orderedCrew.firstIndex(where: { $0.identity.id == agent.identity.id }) else {
            return 0
        }
        let wobble = stableUnitValue(for: "departure_\(agent.identity.id)") * 0.9
        return TimeInterval(idx) * 2.1 + wobble
    }

    private func recallDelay(for agent: GnomeAgent, orderedCrew: [GnomeAgent]) -> TimeInterval {
        guard let idx = orderedCrew.firstIndex(where: { $0.identity.id == agent.identity.id }) else {
            return 0
        }
        let wobble = stableUnitValue(for: "recall_\(agent.identity.id)") * 0.5
        return TimeInterval(idx) * 0.65 + wobble
    }

    private func laneOffset(slot: Int, count: Int, spacing: CGFloat) -> CGFloat {
        (CGFloat(slot) - CGFloat(count - 1) / 2) * spacing
    }

    private func laneSlot(for agent: GnomeAgent, salt: String, count: Int) -> Int {
        Int(stableHash("\(agent.identity.id)|\(salt)") % UInt64(max(1, count)))
    }

    private func forestLaneY(for room: Int, agent: GnomeAgent, direction: GnomeTravelDirection) -> CGFloat {
        let salt = "forest_\(room)_\(direction == .outbound ? "out" : "in")"
        let slot = laneSlot(for: agent, salt: salt, count: GnomeGeometry.forestLaneCount)
        let base = (direction == .outbound)
            ? GnomeGeometry.forestOutboundBaseY
            : GnomeGeometry.forestInboundBaseY
        return base
            + laneOffset(slot: slot,
                         count: GnomeGeometry.forestLaneCount,
                         spacing: GnomeGeometry.forestLaneSpacing)
            + stableSignedOffset(for: "\(salt)_wiggle", magnitude: GnomeGeometry.forestLaneWobble)
    }

    private func caveLaneX(for room: Int, agent: GnomeAgent, direction: GnomeTravelDirection) -> CGFloat {
        let salt = "cave_\(room)_\(direction == .outbound ? "down" : "up")"
        let slot = laneSlot(for: agent, salt: salt, count: GnomeGeometry.caveLaneCount)
        return laneOffset(slot: slot,
                          count: GnomeGeometry.caveLaneCount,
                          spacing: GnomeGeometry.caveLaneSpacing)
            + stableSignedOffset(for: "\(salt)_wiggle", magnitude: GnomeGeometry.caveLaneWobble)
    }

    private func oakRestPosition(for room: Int, agent: GnomeAgent) -> CGPoint {
        switch room {
        case 1:
            return CGPoint(
                x: stableSignedOffset(for: "oak_lobby_rest_x_\(agent.identity.id)", magnitude: 180),
                y: stableSignedOffset(for: "oak_lobby_rest_y_\(agent.identity.id)", magnitude: 90)
            )
        case 2:
            return CGPoint(
                x: -180 + stableSignedOffset(for: "oak_left_rest_x_\(agent.identity.id)", magnitude: 55),
                y: 55 + stableSignedOffset(for: "oak_left_rest_y_\(agent.identity.id)", magnitude: 60)
            )
        case 3:
            return CGPoint(
                x: stableSignedOffset(for: "oak_middle_rest_x_\(agent.identity.id)", magnitude: 60),
                y: 55 + stableSignedOffset(for: "oak_middle_rest_y_\(agent.identity.id)", magnitude: 60)
            )
        case 4:
            return CGPoint(
                x: 180 + stableSignedOffset(for: "oak_right_rest_x_\(agent.identity.id)", magnitude: 55),
                y: 55 + stableSignedOffset(for: "oak_right_rest_y_\(agent.identity.id)", magnitude: 60)
            )
        case 5:
            return CGPoint(
                x: 95 + stableSignedOffset(for: "oak_treasury_rest_x_\(agent.identity.id)", magnitude: 35),
                y: 90 + stableSignedOffset(for: "oak_treasury_rest_y_\(agent.identity.id)", magnitude: 25)
            )
        default:
            return .zero
        }
    }

    private func oakLobbyInteriorPosition(for agent: GnomeAgent) -> CGPoint {
        CGPoint(
            x: 70 + stableSignedOffset(for: "oak_lobby_center_x_\(agent.identity.id)", magnitude: 60),
            y: -40 + stableSignedOffset(for: "oak_lobby_center_y_\(agent.identity.id)", magnitude: 30)
        )
    }

    private func oakLobbyDoorPosition(for agent: GnomeAgent) -> CGPoint {
        CGPoint(
            x: 455,
            y: -55 + stableSignedOffset(for: "oak_lobby_door_y_\(agent.identity.id)", magnitude: 28)
        )
    }

    private func oakBedroomStairPosition(for room: Int, agent: GnomeAgent) -> CGPoint {
        let xBase: CGFloat
        switch room {
        case 2: xBase = -120
        case 3: xBase = 0
        case 4: xBase = 120
        default: xBase = 0
        }
        return CGPoint(
            x: xBase + stableSignedOffset(for: "oak_bedroom_stair_x_\(room)_\(agent.identity.id)", magnitude: 26),
            y: -180 + stableSignedOffset(for: "oak_bedroom_stair_y_\(room)_\(agent.identity.id)", magnitude: 18)
        )
    }

    private func oakTreasuryStairPosition(for agent: GnomeAgent) -> CGPoint {
        CGPoint(
            x: -235 + stableSignedOffset(for: "oak_treasury_stair_x_\(agent.identity.id)", magnitude: 24),
            y: -150 + stableSignedOffset(for: "oak_treasury_stair_y_\(agent.identity.id)", magnitude: 20)
        )
    }

    private func oakDirectionalEndpoints(
        for room: Int,
        agent: GnomeAgent,
        direction: GnomeTravelDirection
    ) -> (entry: CGPoint, exit: CGPoint)? {
        switch room {
        case 1:
            switch direction {
            case .outbound:
                return (oakLobbyInteriorPosition(for: agent), oakLobbyDoorPosition(for: agent))
            case .inbound:
                return (oakLobbyDoorPosition(for: agent), oakLobbyInteriorPosition(for: agent))
            case .neutral:
                return nil
            }
        case 2, 3, 4:
            let rest = oakRestPosition(for: room, agent: agent)
            let stair = oakBedroomStairPosition(for: room, agent: agent)
            switch direction {
            case .outbound:
                return (rest, stair)
            case .inbound:
                return (stair, rest)
            case .neutral:
                return nil
            }
        case 5:
            let pile = oakRestPosition(for: room, agent: agent)
            let stair = oakTreasuryStairPosition(for: agent)
            switch direction {
            case .outbound:
                return (pile, stair)
            case .inbound:
                return (stair, pile)
            case .neutral:
                return nil
            }
        default:
            return nil
        }
    }

    private func restingPosition(for location: GnomeLocation, agent: GnomeAgent) -> CGPoint {
        switch location {
        case .forestRoom(let room):
            let sign: CGFloat = stableUnitValue(for: "forest_idle_side_\(agent.identity.id)") < 0.5 ? -1 : 1
            return CGPoint(x: sign * (GnomeGeometry.forestEdgeX - 200),
                           y: stableSignedOffset(for: "forest_idle_y_\(room)_\(agent.identity.id)", magnitude: 170))
        case .caveRoom(let room):
            return CGPoint(x: stableSignedOffset(for: "cave_idle_x_\(room)_\(agent.identity.id)", magnitude: 170),
                           y: stableSignedOffset(for: "cave_idle_y_\(room)_\(agent.identity.id)", magnitude: 130))
        case .oakRoom(let room):
            return oakRestPosition(for: room, agent: agent)
        }
    }

    private func interpolate(from: CGPoint, to: CGPoint, progress: CGFloat) -> CGPoint {
        CGPoint(
            x: from.x + (to.x - from.x) * progress,
            y: from.y + (to.y - from.y) * progress
        )
    }

    private func machineTargetPosition() -> CGPoint {
        if let scene = caveScene,
           scene.currentCaveRoom == .entrance,
           let machine = scene.roomContainer(for: .entrance)?.namedChild(MineMachine.nodeName, as: SKNode.self) {
            return scene.convert(.zero, from: machine)
        }
        return CGPoint(x: -120, y: 0)
    }

    private func wasteBinTargetPosition() -> CGPoint {
        if let scene = caveScene,
           scene.currentCaveRoom == .entrance,
           let bin = scene.roomContainer(for: .entrance)?.namedChild(WasteBin.nodeName, as: SKNode.self) {
            return scene.convert(.zero, from: bin)
        }
        return CGPoint(x: 120, y: 0)
    }

    private func updateTransitPositionIfHidden(agent: GnomeAgent, elapsed: TimeInterval) {
        guard agent.sceneNode == nil else { return }
        guard let exit = exitPosition(for: agent.location, agent: agent) else { return }
        let entry = entryPosition(for: agent.location, agent: agent)
        let total = roomDuration(for: agent, location: agent.location)
        let progress = min(1.0, max(0.0, elapsed / max(0.001, total)))
        agent.position = interpolate(from: entry, to: exit, progress: CGFloat(progress))
        agent.hasRealPosition = true
    }

    private func moveHiddenAgent(
        _ agent: GnomeAgent,
        toward target: CGPoint,
        deltaTime: TimeInterval,
        speed: CGFloat
    ) {
        guard agent.sceneNode == nil else { return }
        if !agent.hasRealPosition {
            agent.position = restingPosition(for: agent.location, agent: agent)
            agent.hasRealPosition = true
        }
        let dx = target.x - agent.position.x
        let dy = target.y - agent.position.y
        let distance = hypot(dx, dy)
        guard distance > 0.001 else {
            agent.position = target
            return
        }
        let step = min(distance, speed * CGFloat(max(0.0, deltaTime)))
        let scale = step / distance
        agent.position = CGPoint(x: agent.position.x + dx * scale,
                                 y: agent.position.y + dy * scale)
    }

    private func advanceHiddenWanderIfNeeded(
        _ agent: GnomeAgent,
        deltaTime: TimeInterval,
        fallback: CGPoint,
        speed: CGFloat
    ) {
        let target = clamp(agent.wanderTarget ?? fallback, to: agent.location)
        agent.wanderTarget = target
        moveHiddenAgent(agent, toward: target, deltaTime: deltaTime, speed: speed)
    }

    private func remainingTraversalDuration(
        from current: CGPoint,
        entry: CGPoint,
        exit: CGPoint,
        totalDuration: TimeInterval
    ) -> TimeInterval {
        let fullDistance = max(0.001, hypot(exit.x - entry.x, exit.y - entry.y))
        let remainingDistance = hypot(exit.x - current.x, exit.y - current.y)
        return max(0.4, totalDuration * Double(remainingDistance / fullDistance))
    }

    private func ensureVisibleTraversal(agent: GnomeAgent, now: TimeInterval) {
        guard let node = agent.sceneNode, !node.isFrozen else { return }
        guard !node.isTraversing else { return }
        startTraversalForCurrentTask(agent: agent, now: now)
    }

    private func speedMultiplier(for agent: GnomeAgent) -> Double {
        // Map the low 10 bits to [0, 1023], then to [-1.0, 1.0] roughly.
        let scaled = Double(stableHash(agent.identity.id) & 0x3FF) / 1023.0  // 0...1
        let jitter = (scaled - 0.5) * 0.30          // -0.15...+0.15
        return 1.0 + jitter
    }

    /// Effective room transit duration for this agent — base × jitter.
    private func roomDuration(for agent: GnomeAgent, location: GnomeLocation) -> TimeInterval {
        if agent.task == .gatheringForCartTrip {
            // The first dusk minute is a strict one-minute prep beat,
            // so gathering runs on fixed timing instead of per-agent
            // jitter. Five room hops max to reach cave_1 => 12s each.
            return GnomeTiming.duskMinePrepDuration / 5.0
        }

        let base: TimeInterval
        switch location {
        case .forestRoom: base = GnomeTiming.transitPerForestRoom
        case .caveRoom:   base = GnomeTiming.transitPerCaveFloor
        case .oakRoom:    base = GnomeTiming.transitPerForestRoom
        }
        return base * speedMultiplier(for: agent)
    }

    // MARK: - Update Loop

    func update(deltaTime: TimeInterval) {
        guard !MultiplayerService.shared.isGuest else { return }

        let now = CACurrentMediaTime()
        tickDawnState(now: now)
        tickDiningForMeal(now: now)
        for agent in agents {
            advanceAgent(agent, now: now, deltaTime: deltaTime)
            updateVisualPosition(for: agent)
        }
        tickCartState(now: now)
        tickCookForMeal(now: now)

        stateSyncAccumulator += deltaTime
        if MultiplayerService.shared.isHost,
           MultiplayerService.shared.isConnected,
           stateSyncAccumulator >= GnomeTiming.stateSyncInterval {
            stateSyncAccumulator = 0
            broadcastFullState()
        }
    }

    // MARK: - State Machine

    private func advanceAgent(_ agent: GnomeAgent, now: TimeInterval, deltaTime: TimeInterval) {
        let elapsed = now - agent.taskStartedAt

        switch agent.task {
        case .sleeping, .idle:
            tickWander(agent, now: now)
            advanceHiddenWanderIfNeeded(
                agent,
                deltaTime: deltaTime,
                fallback: restingPosition(for: agent.location, agent: agent),
                speed: GnomeTiming.idleWalkSpeed
            )

        case .commutingToMine:
            advanceCommuteToMine(agent, elapsed: elapsed, now: now, deltaTime: deltaTime)

        case .lookingForRock:
            advanceLookingForRock(agent, elapsed: elapsed, now: now, deltaTime: deltaTime)

        case .carryingRockToMachine:
            advanceCarryingRockToMachine(agent, elapsed: elapsed, now: now, deltaTime: deltaTime)

        case .usingMachine:
            advanceUsingMachine(agent, elapsed: elapsed, now: now, deltaTime: deltaTime)

        case .carryingGemToTreasury:
            // LEGACY — only reachable from a save migration before we
            // had cart deposits. Treat it as if it were the new task.
            agent.task = .depositingGemAtCart
            agent.taskStartedAt = now
            advanceDepositingGemAtCart(agent, elapsed: 0, now: now, deltaTime: deltaTime)

        case .depositingGemAtCart:
            advanceDepositingGemAtCart(agent, elapsed: elapsed, now: now, deltaTime: deltaTime)

        case .dumpingRockInWasteBin:
            advanceDumpingRockInWasteBin(agent, elapsed: elapsed, now: now, deltaTime: deltaTime)

        case .commutingHome:
            advanceCommuteHome(agent, elapsed: elapsed, now: now, deltaTime: deltaTime)

        case .gatheringForCartTrip:
            advanceGatheringForCartTrip(agent, elapsed: elapsed, now: now, deltaTime: deltaTime)

        case .haulingCart:
            advanceHaulingCart(agent, elapsed: elapsed, now: now, deltaTime: deltaTime)

        case .celebrating:
            advanceCelebrating(agent, elapsed: elapsed, now: now, deltaTime: deltaTime)

        case .supervising:
            tickWander(agent, now: now)
            advanceHiddenWanderIfNeeded(
                agent,
                deltaTime: deltaTime,
                fallback: restingPosition(for: agent.location, agent: agent),
                speed: GnomeTiming.idleWalkSpeed
            )

        case .dining,
             .cookServingFromStation,
             .cookDeliveringToTable,
             .cookCheckingOnTable,
             .tidyingTables:
            // Meal-time and cleanup tasks. Position is owned by
            // GnomeSeating (mealPosition / cookCurrentPosition). The
            // per-frame movement is just a gentle drift toward the
            // current wanderTarget, which gets refreshed each meal
            // beat. The cook's task transitions and reaction bubbles
            // are driven by `tickCookForMeal` below; everyone else
            // just stays put.
            advanceHiddenWanderIfNeeded(
                agent,
                deltaTime: deltaTime,
                fallback: restingPosition(for: agent.location, agent: agent),
                speed: GnomeTiming.idleWalkSpeed
            )
        }
    }

    // MARK: - Commute Logic

    private func advanceCommuteToMine(
        _ agent: GnomeAgent,
        elapsed: TimeInterval,
        now: TimeInterval,
        deltaTime: TimeInterval
    ) {
        // Don't start moving until the staggered taskStartedAt has actually arrived.
        // (handleDawnRollover sets it to a future time.)
        if elapsed < 0 {
            advanceHiddenWanderIfNeeded(
                agent,
                deltaTime: deltaTime,
                fallback: restingPosition(for: agent.location, agent: agent),
                speed: GnomeTiming.idleWalkSpeed
            )
            return
        }

        updateTransitPositionIfHidden(agent: agent, elapsed: elapsed)
        ensureVisibleTraversal(agent: agent, now: now)

        switch agent.location {
        case .oakRoom(let room):
            if elapsed >= roomDuration(for: agent, location: agent.location) {
                if room == 1 {
                    hop(agent, to: .forestRoom(4), now: now)
                } else {
                    hop(agent, to: .oakRoom(1), now: now)
                }
            }

        case .forestRoom(let n):
            if elapsed >= roomDuration(for: agent, location: agent.location) {
                if n > 2 {
                    hop(agent, to: .forestRoom(n - 1), now: now)
                } else {
                    hop(agent, to: .caveRoom(1), now: now)
                }
            }

        case .caveRoom(let n):
            if n == 1 {
                if agent.identity.role == .boss {
                    agent.task = .supervising
                    agent.taskStartedAt = now
                    return
                }
                if elapsed >= roomDuration(for: agent, location: agent.location) {
                    let target = agent.workingCaveFloor ?? 2
                    hop(agent, to: .caveRoom(2), now: now)
                    if target == 2 {
                        agent.task = .lookingForRock
                        agent.taskStartedAt = now
                    }
                }
            } else if let target = agent.workingCaveFloor, n < target {
                if elapsed >= roomDuration(for: agent, location: agent.location) {
                    hop(agent, to: .caveRoom(n + 1), now: now)
                    if n + 1 == target {
                        agent.task = .lookingForRock
                        agent.taskStartedAt = now
                    }
                }
            } else {
                agent.task = .lookingForRock
                agent.taskStartedAt = now
            }
        }
    }

    private func advanceCommuteHome(
        _ agent: GnomeAgent,
        elapsed: TimeInterval,
        now: TimeInterval,
        deltaTime: TimeInterval
    ) {
        if elapsed < 0 {
            advanceHiddenWanderIfNeeded(
                agent,
                deltaTime: deltaTime,
                fallback: restingPosition(for: agent.location, agent: agent),
                speed: GnomeTiming.idleWalkSpeed
            )
            return
        }

        updateTransitPositionIfHidden(agent: agent, elapsed: elapsed)
        ensureVisibleTraversal(agent: agent, now: now)

        switch agent.location {
        case .caveRoom(let n):
            if elapsed >= roomDuration(for: agent, location: agent.location) {
                if n > 1 {
                    hop(agent, to: .caveRoom(n - 1), now: now)
                } else {
                    hop(agent, to: .forestRoom(2), now: now)
                }
            }

        case .forestRoom(let n):
            if elapsed >= roomDuration(for: agent, location: agent.location) {
                if n < 4 {
                    hop(agent, to: .forestRoom(n + 1), now: now)
                } else {
                    hop(agent, to: .oakRoom(1), now: now)
                }
            }

        case .oakRoom(let room):
            guard elapsed >= roomDuration(for: agent, location: agent.location) else { return }
            if room == 1, agent.identity.homeOakRoom != 1 {
                hop(agent, to: .oakRoom(agent.identity.homeOakRoom), now: now)
                return
            }
            agent.task = .sleeping
            agent.taskStartedAt = now
            agent.wanderTarget = restingPosition(for: agent.location, agent: agent)
        }
    }

    // MARK: - Mining Loop

    private func advanceLookingForRock(
        _ agent: GnomeAgent,
        elapsed: TimeInterval,
        now: TimeInterval,
        deltaTime: TimeInterval
    ) {
        tickHuntWander(agent, now: now)
        advanceHiddenWanderIfNeeded(
            agent,
            deltaTime: deltaTime,
            fallback: restingPosition(for: agent.location, agent: agent),
            speed: GnomeTiming.huntWalkSpeed
        )

        if elapsed < GnomeTiming.rockHuntDuration {
            return
        }

        guard case let .caveRoom(room) = agent.location else { return }
        let here = SpawnLocation.caveRoom(room)
        guard let pick = ForagingManager.shared.spawnsFor(here).first(where: { $0.ingredient == .rock }) else {
            // No rocks left — try another room or head home.
            if let alt = ForagingManager.shared.nearestRockSpawn(preferredRoom: room) {
                if case let .caveRoom(altRoom) = alt.location, altRoom != room {
                    agent.workingCaveFloor = altRoom
                    agent.task = .commutingToMine
                    agent.taskStartedAt = now
                    return
                }
            }
            agent.task = .commutingHome
            agent.taskStartedAt = now
            return
        }
        ForagingManager.shared.collect(spawnID: pick.spawnID)
        agent.carried = .rock
        agent.carriedRockSpawnID = pick.spawnID
        agent.position = pick.position
        agent.wanderTarget = nil
        agent.hasRealPosition = true
        agent.task = .carryingRockToMachine
        agent.taskStartedAt = now
        agent.sceneNode?.refreshVisualBadges()
        startTraversalForCurrentTask(agent: agent, now: now)
        Log.debug(.npc, "[Gnomes] \(agent.identity.displayName) picked up rock \(pick.spawnID)")
    }

    private func advanceCarryingRockToMachine(
        _ agent: GnomeAgent,
        elapsed: TimeInterval,
        now: TimeInterval,
        deltaTime: TimeInterval
    ) {
        switch agent.location {
        case .caveRoom(let n):
            if n == 1 {
                agent.task = .usingMachine
                agent.taskStartedAt = now
                moveHiddenAgent(
                    agent,
                    toward: machineTargetPosition(),
                    deltaTime: deltaTime,
                    speed: GnomeTiming.taskWalkSpeed
                )
                walkAgentToMachine(agent)
                return
            }
            updateTransitPositionIfHidden(agent: agent, elapsed: elapsed)
            ensureVisibleTraversal(agent: agent, now: now)
            if elapsed >= roomDuration(for: agent, location: agent.location) {
                let nextRoom = n - 1
                hop(agent, to: .caveRoom(nextRoom), now: now)
                if nextRoom == 1 {
                    agent.task = .usingMachine
                    agent.taskStartedAt = now
                    moveHiddenAgent(
                        agent,
                        toward: machineTargetPosition(),
                        deltaTime: deltaTime,
                        speed: GnomeTiming.taskWalkSpeed
                    )
                    walkAgentToMachine(agent)
                }
            }
        default:
            agent.task = .commutingToMine
            agent.taskStartedAt = now
        }
    }

    private func advanceUsingMachine(
        _ agent: GnomeAgent,
        elapsed: TimeInterval,
        now: TimeInterval,
        deltaTime: TimeInterval
    ) {
        moveHiddenAgent(
            agent,
            toward: machineTargetPosition(),
            deltaTime: deltaTime,
            speed: GnomeTiming.taskWalkSpeed
        )
        if let node = agent.sceneNode, !node.isFrozen, !node.isTraversing {
            walkAgentToMachine(agent)
        }
        guard elapsed >= GnomeTiming.machineUseDuration else { return }
        guard let rockID = agent.carriedRockSpawnID else {
            agent.task = .lookingForRock
            agent.taskStartedAt = now
            agent.workingCaveFloor = agent.workingCaveFloor ?? 2
            agent.wanderTarget = nil
            return
        }

        let verdict = MineMachine.verdict(for: rockID, dayCount: currentDayCount)
        caveScene?.flashMineMachineIfPresent(green: verdict)

        // Broadcast so the guest's machine flashes too. Without this,
        // gnome-driven verdicts only render on the host. The receiver
        // also bumps the bin on red verdict; for gnomes the host's
        // bin bump happens later (after the dump-walk), so guest will
        // see the bin bump ~7s before host. Accepted as a minor visual
        // diff — far better than the bin never bumping at all.
        if MultiplayerService.shared.isConnected {
            MultiplayerService.shared.send(
                type: .mineMachineFed,
                payload: MineMachineFedMessage(
                    rockID: rockID,
                    dayCount: currentDayCount,
                    verdict: verdict
                )
            )
        }

        if verdict {
            agent.carried = .gem
            agent.carriedRockSpawnID = nil
            agent.wanderTarget = nil
            // Walk the gem over to the in-cave mine cart instead of
            // hauling it all the way back to the oak. The cart hauls
            // the day's full load to the treasury at dusk.
            agent.task = .depositingGemAtCart
            agent.taskStartedAt = now
            agent.sceneNode?.refreshVisualBadges()
            walkAgentToCart(agent)
            Log.debug(.npc, "[Gnomes] \(agent.identity.displayName) got a gem from \(rockID)")
        } else {
            agent.wanderTarget = nil
            agent.task = .dumpingRockInWasteBin
            agent.taskStartedAt = now
            walkAgentToBin(agent)
            Log.debug(.npc, "[Gnomes] \(agent.identity.displayName) heading to waste bin (red verdict)")
        }
    }

    private func advanceDumpingRockInWasteBin(
        _ agent: GnomeAgent,
        elapsed: TimeInterval,
        now: TimeInterval,
        deltaTime: TimeInterval
    ) {
        moveHiddenAgent(
            agent,
            toward: wasteBinTargetPosition(),
            deltaTime: deltaTime,
            speed: GnomeTiming.taskWalkSpeed
        )
        if let node = agent.sceneNode, !node.isFrozen, !node.isTraversing {
            walkAgentToBin(agent)
        }
        guard elapsed >= GnomeTiming.wasteDumpDuration else { return }
        agent.carried = nil
        agent.carriedRockSpawnID = nil
        caveScene?.bumpWasteBinIfPresent()
        agent.sceneNode?.refreshVisualBadges()
        agent.task = .commutingToMine
        agent.taskStartedAt = now
        // Rotate to a different floor so a sequence of bad rocks doesn't
        // park a miner on the same floor all day.
        agent.workingCaveFloor = nextWorkingCaveFloor(after: agent.workingCaveFloor)
        agent.wanderTarget = nil
    }

    private func advanceDepositingGemAtCart(
        _ agent: GnomeAgent,
        elapsed: TimeInterval,
        now: TimeInterval,
        deltaTime: TimeInterval
    ) {
        // The cart is parked in cave entrance (room 1) all day. If the
        // gnome ended up somewhere else, route them down to room 1
        // first by switching back to a temporary commute that
        // resolves at room 1 to .depositingGemAtCart.
        switch agent.location {
        case .caveRoom(let n) where n == 1:
            // We're in the cave entrance. Walk to the cart, stand there
            // for cartDepositDuration, then drop the gem onto it.
            let target = cartDepositTargetPosition()
            moveHiddenAgent(
                agent,
                toward: target,
                deltaTime: deltaTime,
                speed: GnomeTiming.taskWalkSpeed
            )
            if let node = agent.sceneNode, !node.isFrozen, !node.isTraversing {
                walkAgentToCart(agent)
            }
            guard elapsed >= GnomeTiming.cartDepositDuration else { return }

            // Deposit: gem disappears from the gnome, cart count goes up,
            // chronicle records this gnome as the depositor.
            agent.carried = nil
            agent.gemsDeliveredToday += 1
            agent.sceneNode?.refreshVisualBadges()
            cartGemCount += 1
            cartVisual?.setCount(cartGemCount, animated: true)
            DailyChronicleLedger.shared.recordGemDeposited(
                byGnomeID: agent.identity.id,
                byGnomeName: agent.identity.displayName
            )

            // Round-trip: pick the next floor and head back up to mine.
            agent.workingCaveFloor = nextWorkingCaveFloor(after: agent.workingCaveFloor)
            agent.task = .commutingToMine
            agent.taskStartedAt = now + TimeInterval.random(in: GnomeTiming.postArrivalPauseRange)
            agent.wanderTarget = nil
            // Hop into floor 2 → the existing commuteToMine logic will
            // walk them to whatever workingCaveFloor was set above.
            // (Skip the hop if they're staying at the entrance —
            // commuteToMine handles that.)

        case .caveRoom(let n) where n > 1:
            // We somehow ended up below room 1. Treat it as if we were
            // mid-carrying-rock-up: traverse upward and re-enter
            // depositing logic on arrival.
            updateTransitPositionIfHidden(agent: agent, elapsed: elapsed)
            ensureVisibleTraversal(agent: agent, now: now)
            if elapsed >= roomDuration(for: agent, location: agent.location) {
                hop(agent, to: .caveRoom(n - 1), now: now)
            }

        case .forestRoom, .oakRoom:
            // Edge case (e.g. legacy save migration left a gnome with
            // a gem in the forest/oak). Send them back to the cave to
            // deposit. They can't haul the gem the old way anymore.
            agent.task = .commutingToMine
            agent.taskStartedAt = now
            agent.workingCaveFloor = 1

        case .caveRoom:
            // Compiler-exhaustiveness placeholder — unreachable.
            break
        }
    }

    private func advanceGatheringForCartTrip(
        _ agent: GnomeAgent,
        elapsed: TimeInterval,
        now: TimeInterval,
        deltaTime: TimeInterval
    ) {
        if elapsed < 0 {
            advanceHiddenWanderIfNeeded(
                agent,
                deltaTime: deltaTime,
                fallback: restingPosition(for: agent.location, agent: agent),
                speed: GnomeTiming.idleWalkSpeed
            )
            return
        }

        switch agent.location {
        case .caveRoom(let n):
            // Walk up to room 1.
            if n > 1 {
                updateTransitPositionIfHidden(agent: agent, elapsed: elapsed)
                ensureVisibleTraversal(agent: agent, now: now)
                if elapsed >= roomDuration(for: agent, location: agent.location) {
                    hop(agent, to: .caveRoom(n - 1), now: now)
                }
            } else {
                // We're in cave entrance. Mill near the cart.
                let cart = cartDepositTargetPosition()
                let lateral = cartLateralOffset(for: agent)
                let standTarget = CGPoint(x: cart.x + lateral, y: cart.y - 70)
                moveHiddenAgent(
                    agent,
                    toward: standTarget,
                    deltaTime: deltaTime,
                    speed: GnomeTiming.idleWalkSpeed
                )
                if let node = agent.sceneNode, !node.isFrozen, !node.isTraversing {
                    if hypot(node.position.x - standTarget.x, node.position.y - standTarget.y) > 12 {
                        node.gnomeWanderTo(standTarget)
                    }
                }
                agent.wanderTarget = standTarget
            }

        case .forestRoom(let n):
            // Forest → cave. Outbound direction visually.
            updateTransitPositionIfHidden(agent: agent, elapsed: elapsed)
            ensureVisibleTraversal(agent: agent, now: now)
            if elapsed >= roomDuration(for: agent, location: agent.location) {
                if n > 2 {
                    hop(agent, to: .forestRoom(n - 1), now: now)
                } else {
                    hop(agent, to: .caveRoom(1), now: now)
                }
            }

        case .oakRoom(let room):
            // Oak → forest → cave. Pretend we're commutingToMine for the
            // visual/edge logic by reusing entry/exit anchored to .outbound.
            updateTransitPositionIfHidden(agent: agent, elapsed: elapsed)
            ensureVisibleTraversal(agent: agent, now: now)
            if elapsed >= roomDuration(for: agent, location: agent.location) {
                if room == 1 {
                    hop(agent, to: .forestRoom(4), now: now)
                } else {
                    hop(agent, to: .oakRoom(1), now: now)
                }
            }
        }
    }

    private func advanceHaulingCart(
        _ agent: GnomeAgent,
        elapsed: TimeInterval,
        now: TimeInterval,
        deltaTime: TimeInterval
    ) {
        // The procession's room/timing is owned by `tickCartState`.
        // Each gnome's job is just to keep next to the cart at a
        // stable lateral offset — hops, room changes, and timing
        // come from cart state, not from the agent.
        let cart = cartPosition
        let lateral = cartLateralOffset(for: agent)
        let standOffsetY: CGFloat
        switch agent.location {
        case .caveRoom:    standOffsetY = -50
        case .forestRoom:  standOffsetY = 0
        case .oakRoom:     standOffsetY = -30
        }
        let target = CGPoint(x: cart.x + lateral, y: cart.y + standOffsetY)

        moveHiddenAgent(
            agent,
            toward: target,
            deltaTime: deltaTime,
            speed: GnomeTiming.taskWalkSpeed
        )
        if let node = agent.sceneNode, !node.isFrozen {
            // Use a short SKAction so the visual smoothly tracks the
            // cart without the per-frame jitter that comes from
            // setting position directly.
            if !node.isTraversing {
                let from = node.position
                let dist = hypot(target.x - from.x, target.y - from.y)
                if dist > 8 {
                    let dur = max(0.3, TimeInterval(dist / GnomeTiming.taskWalkSpeed))
                    node.gnomeTraverse(from: from, to: target, duration: dur)
                }
            }
        }
        agent.position = target
    }

    private func advanceCelebrating(
        _ agent: GnomeAgent,
        elapsed: TimeInterval,
        now: TimeInterval,
        deltaTime: TimeInterval
    ) {
        // Stand near the treasury pile during the dusk turn-in beat.
        // Once dusk runs out, scatter to bedrooms (handled in
        // tickCartState → scatterGnomesHomeAfterCelebration).
        let pile = oakRestPosition(for: 5, agent: agent)
        moveHiddenAgent(
            agent,
            toward: pile,
            deltaTime: deltaTime,
            speed: GnomeTiming.idleWalkSpeed
        )
        if let node = agent.sceneNode, !node.isFrozen, !node.isTraversing {
            if hypot(node.position.x - pile.x, node.position.y - pile.y) > 14 {
                node.gnomeWanderTo(pile)
            }
        }
    }

    /// Legacy method kept for any direct callers we may have missed.
    /// New cart-based system uses cart deposit + procession dump
    /// instead of per-gnome treasury walks.
    private func depositGemFromAgent(_ agent: GnomeAgent, now: TimeInterval) {
        guard agent.carried == .gem else { return }
        agent.carried = nil
        agent.gemsDeliveredToday += 1
        agent.sceneNode?.refreshVisualBadges()
        incrementTreasury(amount: 1)
        agent.workingCaveFloor = nextWorkingCaveFloor(after: agent.workingCaveFloor)
        agent.task = .commutingToMine
        agent.taskStartedAt = now + TimeInterval.random(in: GnomeTiming.postArrivalPauseRange)
        agent.location = .oakRoom(5)
        agent.wanderTarget = oakRestPosition(for: 5, agent: agent)
    }

    /// Cycle 2 → 3 → 4 → 2. Used to spread miners across all rock-bearing
    /// cave floors over the course of a day. nil input means "start at 2".
    private func nextWorkingCaveFloor(after current: Int?) -> Int {
        switch current {
        case 2: return 3
        case 3: return 4
        case 4: return 2
        default: return 2
        }
    }

    // MARK: - Treasury

    func incrementTreasury(amount: Int = 1, broadcast: Bool = true, fromCartDelivery: Bool = false) {
        treasuryGemCount += amount
        // Cap is gone — treasury just keeps growing. The visual scale
        // is capped inside TreasuryPile.setCount so the emoji doesn't
        // grow unboundedly.
        oakScene?.updateTreasuryPileIfPresent(count: treasuryGemCount, didReset: false)
        if broadcast {
            broadcastTreasuryUpdate(didReset: false)
        }
        // Chronicle hook — skipped during cart-procession dumps because
        // each gem was already recorded against the depositing gnome
        // when it landed on the cart. Without this skip we'd
        // double-count the day's mining output.
        if !fromCartDelivery {
            for _ in 0..<max(0, amount) {
                DailyChronicleLedger.shared.recordGemDeposited(
                    byGnomeID: nil, byGnomeName: nil
                )
            }
        }
    }

    func applyRemoteTreasury(newCount: Int, didReset: Bool) {
        treasuryGemCount = newCount
        oakScene?.updateTreasuryPileIfPresent(count: newCount, didReset: didReset)
    }

    // MARK: - Hop Helper

    private func hop(_ agent: GnomeAgent, to newLocation: GnomeLocation, now: TimeInterval) {
        agent.sceneNode?.removeFromParent()
        agent.sceneNode = nil

        agent.location = newLocation
        agent.taskStartedAt = now
        agent.wanderTarget = nil

        let entry = entryPosition(for: newLocation, agent: agent)
        agent.position = entry
        agent.hasRealPosition = true

        respawnVisualIfRoomVisible(agent: agent)
    }

    // MARK: - Travel Direction

    private func travelDirection(for agent: GnomeAgent) -> GnomeTravelDirection {
        switch agent.task {
        case .commutingToMine, .gatheringForCartTrip:
            return .outbound
        case .carryingRockToMachine:
            return .inbound
        case .haulingCart:
            return cartState == .returningToMine ? .outbound : .inbound
        case .commutingHome, .carryingGemToTreasury:
            return .inbound
        case .sleeping, .idle, .supervising,
             .lookingForRock, .usingMachine,
             .depositingGemAtCart, .dumpingRockInWasteBin,
             .celebrating,
             .dining, .cookServingFromStation,
             .cookDeliveringToTable, .cookCheckingOnTable,
             .tidyingTables:
            return .neutral
        }
    }

    private func entryPosition(for location: GnomeLocation, agent: GnomeAgent) -> CGPoint {
        let direction = travelDirection(for: agent)

        switch location {
        case .forestRoom(let room):
            switch direction {
            case .outbound:
                return CGPoint(x:  GnomeGeometry.forestEdgeX,
                               y: forestLaneY(for: room, agent: agent, direction: direction))
            case .inbound:
                return CGPoint(x: -GnomeGeometry.forestEdgeX,
                               y: forestLaneY(for: room, agent: agent, direction: direction))
            case .neutral:
                let sign: CGFloat = stableUnitValue(for: "forest_idle_side_\(agent.identity.id)") < 0.5 ? -1 : 1
                return CGPoint(x: sign * (GnomeGeometry.forestEdgeX - 200),
                               y: stableSignedOffset(for: "forest_idle_y_\(room)_\(agent.identity.id)", magnitude: 170))
            }

        case .caveRoom(let room):
            switch direction {
            case .outbound:
                return CGPoint(x: caveLaneX(for: room, agent: agent, direction: direction),
                               y:  GnomeGeometry.caveEdgeY)
            case .inbound:
                return CGPoint(x: caveLaneX(for: room, agent: agent, direction: direction),
                               y: -GnomeGeometry.caveEdgeY)
            case .neutral:
                return CGPoint(x: stableSignedOffset(for: "cave_idle_x_\(room)_\(agent.identity.id)", magnitude: 170),
                               y: stableSignedOffset(for: "cave_idle_y_\(room)_\(agent.identity.id)", magnitude: 130))
            }

        case .oakRoom(let room):
            if let endpoints = oakDirectionalEndpoints(for: room, agent: agent, direction: direction) {
                return endpoints.entry
            }
            return restingPosition(for: location, agent: agent)
        }
    }

    private func exitPosition(for location: GnomeLocation, agent: GnomeAgent) -> CGPoint? {
        let direction = travelDirection(for: agent)
        guard direction != .neutral else { return nil }

        switch location {
        case .forestRoom(let room):
            switch direction {
            case .outbound:
                return CGPoint(x: -GnomeGeometry.forestEdgeX,
                               y: forestLaneY(for: room, agent: agent, direction: direction))
            case .inbound:
                return CGPoint(x:  GnomeGeometry.forestEdgeX,
                               y: forestLaneY(for: room, agent: agent, direction: direction))
            case .neutral: return nil
            }

        case .caveRoom(let room):
            switch direction {
            case .outbound:
                return CGPoint(x: caveLaneX(for: room, agent: agent, direction: direction),
                               y: -GnomeGeometry.caveEdgeY)
            case .inbound:
                return CGPoint(x: caveLaneX(for: room, agent: agent, direction: direction),
                               y:  GnomeGeometry.caveEdgeY)
            case .neutral: return nil
            }

        case .oakRoom(let room):
            return oakDirectionalEndpoints(for: room, agent: agent, direction: direction)?.exit
        }
    }

    /// Kick off the in-room walking action for the current task.
    private func startTraversalForCurrentTask(agent: GnomeAgent, now: TimeInterval) {
        guard let node = agent.sceneNode else { return }
        let entry = entryPosition(for: agent.location, agent: agent)
        guard let exit = exitPosition(for: agent.location, agent: agent) else { return }
        let from = agent.hasRealPosition ? agent.position : node.position
        let total = roomDuration(for: agent, location: agent.location)
        let remaining = remainingTraversalDuration(
            from: from,
            entry: entry,
            exit: exit,
            totalDuration: total
        )
        node.gnomeTraverse(from: from, to: exit, duration: remaining)
    }

    // MARK: - In-Cave Active Behaviors

    private func tickHuntWander(_ agent: GnomeAgent, now: TimeInterval) {
        guard now >= agent.nextWanderAt else { return }
        agent.nextWanderAt = now + GnomeTiming.wanderInterval + Double.random(in: 0...0.8)

        guard case let .caveRoom(room) = agent.location else { return }
        let spawns = ForagingManager.shared.spawnsFor(.caveRoom(room))
            .filter { $0.ingredient == .rock }

        let target: CGPoint
        if let pick = spawns.randomElement() {
            let jitterX = CGFloat.random(in: -25...25)
            let jitterY = CGFloat.random(in: -25...25)
            target = CGPoint(x: pick.position.x + jitterX,
                             y: pick.position.y + jitterY)
        } else {
            target = CGPoint(
                x: CGFloat.random(in: -180...180),
                y: CGFloat.random(in: -150...150)
            )
        }

        agent.wanderTarget = target
        agent.sceneNode?.gnomeWanderTo(target)
    }

    private func walkAgentToMachine(_ agent: GnomeAgent) {
        guard let node = agent.sceneNode else { return }
        let target = machineTargetPosition()
        let from = agent.hasRealPosition ? agent.position : node.position
        let dist = hypot(target.x - from.x, target.y - from.y)
        guard dist > 6 else {
            node.gnomeStandAt(target)
            return
        }
        let duration = max(0.6, TimeInterval(dist / GnomeTiming.taskWalkSpeed))
        node.gnomeTraverse(from: from, to: target, duration: duration)
    }

    private func walkAgentToBin(_ agent: GnomeAgent) {
        guard let node = agent.sceneNode else { return }
        let target = wasteBinTargetPosition()
        let from = agent.hasRealPosition ? agent.position : node.position
        let dist = hypot(target.x - from.x, target.y - from.y)
        guard dist > 6 else {
            node.gnomeStandAt(target)
            return
        }
        let duration = max(0.6, TimeInterval(dist / GnomeTiming.taskWalkSpeed))
        node.gnomeTraverse(from: from, to: target, duration: duration)
    }

    private func respawnVisualIfRoomVisible(agent: GnomeAgent) {
        switch agent.location {
        case .oakRoom(let n):
            guard let scene = oakScene, scene.currentOakRoom.rawValue == n else { return }
            spawnVisual(for: agent, in: scene, fallbackContainer: scene.roomContainerForGnomes())
        case .caveRoom(let n):
            guard let scene = caveScene, scene.currentCaveRoom.rawValue == n else { return }
            spawnVisual(for: agent, in: scene, fallbackContainer: nil)
        case .forestRoom(let n):
            guard let scene = forestScene, scene.currentRoom == n else { return }
            spawnVisual(for: agent, in: scene, fallbackContainer: nil)
        }
    }

    // MARK: - Wander Tick (sleeping/idle/supervising)

    private func tickWander(_ agent: GnomeAgent, now: TimeInterval) {
        guard now >= agent.nextWanderAt else { return }
        agent.nextWanderAt = now + GnomeTiming.wanderInterval + Double.random(in: 0...1.0)
        let dx = CGFloat.random(in: -120...120)
        let dy = CGFloat.random(in: -80...80)
        let target = CGPoint(x: agent.position.x + dx, y: agent.position.y + dy)
        agent.wanderTarget = clamp(target, to: agent.location)
        if let node = agent.sceneNode {
            node.gnomeWanderTo(agent.wanderTarget ?? agent.position)
        }
    }

    private func clamp(_ p: CGPoint, to location: GnomeLocation) -> CGPoint {
        let bounds: CGRect
        switch location {
        case .oakRoom:    bounds = CGRect(x: -500, y: -250, width: 1000, height: 500)
        case .caveRoom:   bounds = CGRect(x: -350, y: -200, width: 700,  height: 400)
        case .forestRoom: bounds = CGRect(x: -800, y: -300, width: 1600, height: 600)
        }
        return CGPoint(
            x: max(bounds.minX, min(bounds.maxX, p.x)),
            y: max(bounds.minY, min(bounds.maxY, p.y))
        )
    }

    // MARK: - Visual Position Sync

    private func updateVisualPosition(for agent: GnomeAgent) {
        guard let node = agent.sceneNode else { return }
        agent.position = node.position
        agent.hasRealPosition = true
    }

    // MARK: - Visual Spawning

    private func spawnVisual(for agent: GnomeAgent, in scene: SKScene, fallbackContainer: SKNode?) {
        guard agent.sceneNode == nil else { return }

        let now = CACurrentMediaTime()
        let elapsed = now - agent.taskStartedAt
        let direction = travelDirection(for: agent)

        let entry = entryPosition(for: agent.location, agent: agent)
        var visibleStart = agent.hasRealPosition ? agent.position : entry
        if !agent.hasRealPosition,
           elapsed >= 0,
           direction != .neutral,
           let exit = exitPosition(for: agent.location, agent: agent) {
            let total = roomDuration(for: agent, location: agent.location)
            let progress = min(1.0, max(0.0, elapsed / max(0.001, total)))
            visibleStart = interpolate(from: entry, to: exit, progress: CGFloat(progress))
        }
        agent.position = visibleStart
        agent.hasRealPosition = true

        let bounds = wanderBoundsFor(location: agent.location)
        let gnome = GnomeNPC(agent: agent, at: visibleStart, wanderBounds: bounds)
        scene.addChild(gnome)
        agent.sceneNode = gnome
        gnome.refreshVisualBadges()

        // Kick off the appropriate movement for the current task.
        if direction != .neutral,
           elapsed >= 0,
           let exit = exitPosition(for: agent.location, agent: agent) {
            let total = roomDuration(for: agent, location: agent.location)
            let remaining = remainingTraversalDuration(
                from: visibleStart,
                entry: entry,
                exit: exit,
                totalDuration: total
            )
            if hypot(exit.x - visibleStart.x, exit.y - visibleStart.y) <= 6 {
                gnome.gnomeStandAt(exit)
            } else {
                gnome.gnomeTraverse(from: visibleStart, to: exit, duration: remaining)
            }
        } else if agent.task == .usingMachine {
            walkAgentToMachine(agent)
        } else if agent.task == .dumpingRockInWasteBin {
            walkAgentToBin(agent)
        } else if agent.task == .dining, let target = agent.wanderTarget {
            let dist = hypot(target.x - visibleStart.x, target.y - visibleStart.y)
            if dist > 8 {
                let duration = max(0.25, TimeInterval(dist / GnomeTiming.taskWalkSpeed))
                gnome.gnomeTraverse(from: visibleStart, to: target, duration: duration)
            } else {
                gnome.gnomeStandAt(target)
            }
        } else if let target = agent.wanderTarget {
            gnome.gnomeWanderTo(target)
        } else {
            gnome.gnomeStandAt(visibleStart)
        }
    }

    private func wanderBoundsFor(location: GnomeLocation) -> CGRect {
        switch location {
        case .oakRoom:    return CGRect(x: -500, y: -250, width: 1000, height: 500)
        case .caveRoom:   return CGRect(x: -350, y: -200, width: 700,  height: 400)
        case .forestRoom: return CGRect(x: -800, y: -300, width: 1600, height: 600)
        }
    }

    // MARK: - Mine Cart Geometry & Helpers

    /// Where the cart parks within its current room (scene-space).
    /// Used during day (room 1, idle) and as the lockstep target
    /// during procession.
    private func cartRestingPosition(in location: GnomeLocation) -> CGPoint {
        switch location {
        case .caveRoom(let n):
            // Cart at cave entrance: tucked near top center, away from
            // machine + bin. Other cave floors don't normally host the
            // cart, but if the procession is mid-traverse we want a
            // sensible fallback.
            if n == 1 {
                return CGPoint(x: 0, y: 280)
            }
            return CGPoint(x: 0, y: 0)

        case .forestRoom:
            // Procession enters from the cave side (-X, inbound) and
            // exits toward oak (+X). Mid-room target is just centered.
            return CGPoint(x: 0, y: 0)

        case .oakRoom(let n):
            switch n {
            case 1:
                // Lobby: cart is between the door and the treasury stair.
                return CGPoint(x: -120, y: -80)
            case 5:
                // Treasury room: park right next to the pile.
                return CGPoint(x: 0, y: 30)
            default:
                return CGPoint(x: 0, y: 0)
            }
        }
    }

    /// Entry position for the cart when it just hopped into a room.
    private func cartEntryPosition(for location: GnomeLocation) -> CGPoint {
        switch location {
        case .caveRoom: return CGPoint(x: 0, y: 280)
        case .forestRoom: return CGPoint(x: -GnomeGeometry.forestEdgeX, y: 60)
        case .oakRoom(let n):
            switch n {
            case 1: return CGPoint(x: 455, y: -55)              // door
            case 5: return CGPoint(x: -235, y: -150)            // stair
            default: return CGPoint(x: 0, y: 0)
            }
        }
    }

    /// Reverse-route entry position for the dawn return procession.
    private func dawnCartEntryPosition(for location: GnomeLocation) -> CGPoint {
        switch location {
        case .caveRoom: return CGPoint(x: 0, y: -GnomeGeometry.caveEdgeY + 30)
        case .forestRoom: return CGPoint(x: GnomeGeometry.forestEdgeX, y: 60)
        case .oakRoom(let n):
            switch n {
            case 1: return CGPoint(x: -235, y: -150)             // from treasury stair
            case 5: return CGPoint(x: 0, y: 30)
            default: return CGPoint(x: 0, y: 0)
            }
        }
    }

    /// Exit position for the cart when leaving a room.
    private func cartExitPosition(for location: GnomeLocation) -> CGPoint {
        switch location {
        case .caveRoom: return CGPoint(x: 0, y: -GnomeGeometry.caveEdgeY + 30)
        case .forestRoom: return CGPoint(x: GnomeGeometry.forestEdgeX, y: 60)
        case .oakRoom(let n):
            switch n {
            case 1: return CGPoint(x: -235, y: -150)            // treasury stair
            case 5: return CGPoint(x: 0, y: 30)                  // at pile
            default: return CGPoint(x: 0, y: 0)
            }
        }
    }

    /// Reverse-route exit position for the dawn return procession.
    private func dawnCartExitPosition(for location: GnomeLocation) -> CGPoint {
        switch location {
        case .caveRoom: return CGPoint(x: 0, y: 280)
        case .forestRoom: return CGPoint(x: -GnomeGeometry.forestEdgeX, y: 60)
        case .oakRoom(let n):
            switch n {
            case 1: return CGPoint(x: 455, y: -55)               // out through lobby door
            case 5: return CGPoint(x: -235, y: -150)
            default: return CGPoint(x: 0, y: 0)
            }
        }
    }

    /// Where a gem-depositing gnome stands while feeding the cart
    /// during the day. Slightly south of the cart so the gnome and
    /// the cart visual don't overlap.
    private func cartDepositTargetPosition() -> CGPoint {
        let cart = cartRestingPosition(in: .caveRoom(1))
        return CGPoint(x: cart.x, y: cart.y - 50)
    }

    /// Stable lateral offset for an agent when walking next to the
    /// cart. Spreads the procession into a small flock instead of
    /// stacking everyone on top of the cart sprite.
    private func cartLateralOffset(for agent: GnomeAgent) -> CGFloat {
        // Use the agent's hash to assign a slot in [-90, +90] in 30pt steps.
        let slot = Int(stableHash("cart_lane_\(agent.identity.id)") % 7) - 3
        return CGFloat(slot) * 30
    }

    /// Walk a single gnome to the cart for an in-cave gem deposit.
    /// Mirrors `walkAgentToMachine` / `walkAgentToBin`.
    private func walkAgentToCart(_ agent: GnomeAgent) {
        guard let node = agent.sceneNode else { return }
        let target = cartDepositTargetPosition()
        let from = agent.hasRealPosition ? agent.position : node.position
        let dist = hypot(target.x - from.x, target.y - from.y)
        guard dist > 6 else {
            node.gnomeStandAt(target)
            return
        }
        let duration = max(0.6, TimeInterval(dist / GnomeTiming.taskWalkSpeed))
        node.gnomeTraverse(from: from, to: target, duration: duration)
    }

    private func clearDawnTiming() {
        dawnReturnStarted = false
    }

    private func tickDawnState(now: TimeInterval) {
        guard TimeManager.shared.currentPhase == .dawn else { return }
        guard !dawnReturnStarted else { return }
        guard TimeManager.shared.phaseProgress >= 0.5 else { return }
        beginDawnReturnProcession(now: now)
    }

    private func clearCartDuskTiming() {
        cartDuskEndsAt = 0
        cartDinnerStartsAt = 0
        cartTreasuryTurnInDuration = 0
        cartCurrentRoomDuration = GnomeTiming.processionRoomDuration
    }

    private func configureCartDuskTiming(now: TimeInterval) {
        cartDuskEndsAt = now
            + GnomeTiming.duskMinePrepDuration
            + GnomeTiming.duskCartTravelDuration
            + GnomeTiming.duskTreasuryDuration
            + GnomeTiming.duskDinnerDuration
        cartDinnerStartsAt = cartDuskEndsAt - GnomeTiming.duskDinnerDuration
        cartTreasuryTurnInDuration = GnomeTiming.duskTreasuryDuration
        cartCurrentRoomDuration = GnomeTiming.processionRoomDuration
    }

    private func ensureCartDuskTimingInitialized(now: TimeInterval) {
        guard cartState == .gathering
            || cartState == .processing
            || cartState == .atTreasury
            || cartState == .dinner else {
            return
        }
        guard cartDuskEndsAt == 0 else { return }

        switch cartState {
        case .gathering:
            configureCartDuskTiming(now: now)
        case .processing:
            cartCurrentRoomDuration = GnomeTiming.processionRoomDuration
            cartTreasuryTurnInDuration = GnomeTiming.duskTreasuryDuration
            cartDinnerStartsAt = now + GnomeTiming.duskCartTravelDuration + GnomeTiming.duskTreasuryDuration
            cartDuskEndsAt = cartDinnerStartsAt + GnomeTiming.duskDinnerDuration
        case .atTreasury:
            cartCurrentRoomDuration = GnomeTiming.processionRoomDuration
            cartTreasuryTurnInDuration = GnomeTiming.duskTreasuryDuration
            cartDinnerStartsAt = now + GnomeTiming.duskTreasuryDuration
            cartDuskEndsAt = cartDinnerStartsAt + GnomeTiming.duskDinnerDuration
        case .dinner:
            cartCurrentRoomDuration = GnomeTiming.processionRoomDuration
            cartTreasuryTurnInDuration = GnomeTiming.duskTreasuryDuration
            cartDinnerStartsAt = now
            cartDuskEndsAt = now + GnomeTiming.duskDinnerDuration
        case .returningToMine:
            break
        case .idle, .resting:
            break
        }
    }

    private func cartProcessionStartsAt() -> TimeInterval {
        cartDinnerStartsAt - cartTreasuryTurnInDuration - (5.0 * cartCurrentRoomDuration)
    }

    private func cartTreasuryTurnInStartsAt() -> TimeInterval {
        cartDinnerStartsAt - cartTreasuryTurnInDuration
    }

    private func beginDawnReturnProcession(now: TimeInterval) {
        dawnReturnStarted = true
        cartLocation = .oakRoom(1)
        cartState = .returningToMine
        cartTaskStartedAt = now
        cartPosition = cartRestingPosition(in: cartLocation)
        despawnCartVisualNode()
        spawnCartVisualIfCurrentRoomMatches(newLocation: cartLocation)
        cartVisual?.position = cartPosition
        cartVisual?.startRolling()

        // End the breakfast meal: clear seat assignments, but keep the
        // authored dining tables visible as permanent room props.
        GnomeSeating.shared.endMeal(agents: agents, oakScene: oakScene)

        for agent in agents where !agent.identity.role.livesInOak && agent.isOnMineDutyToday {
            agent.task = .haulingCart
            agent.taskStartedAt = now
            agent.location = .oakRoom(1)
            agent.position = cartPosition
            agent.wanderTarget = nil
            agent.hasRealPosition = true
            agent.sceneNode?.removeFromParent()
            agent.sceneNode = nil
            respawnVisualIfRoomVisible(agent: agent)
        }

        // Lobby crew (housekeepers + broker + treasurer) shift into
        // tidying. Cook joins the cleanup beat per the design even
        // though she was working through breakfast.
        for agent in agents where agent.identity.role.livesInOak {
            agent.task = .tidyingTables
            agent.taskStartedAt = now
            agent.location = .oakRoom(1)
            agent.wanderTarget = dinnerMinglePosition(for: agent)
            agent.hasRealPosition = true
            agent.sceneNode?.removeFromParent()
            agent.sceneNode = nil
            respawnVisualIfRoomVisible(agent: agent)
        }

        Log.info(.npc, "[Gnomes][Dawn] phase 2/2 started: cart return to the mines (\(Int(GnomeTiming.dawnReturnTravelDuration))s)")
        logDawnSnapshot("cart return started")
    }

    private func dinnerMinglePosition(for agent: GnomeAgent) -> CGPoint {
        if agent.identity.id == GnomeRoster.kitchenCook.id {
            return CGPoint(x: 210, y: 35)
        }
        if agent.identity.role.livesInOak {
            return CGPoint(
                x: -120 + stableSignedOffset(for: "oak_dinner_housekeeper_x_\(agent.identity.id)", magnitude: 60),
                y: 10 + stableSignedOffset(for: "oak_dinner_housekeeper_y_\(agent.identity.id)", magnitude: 35)
            )
        }
        return CGPoint(
            x: 60 + stableSignedOffset(for: "oak_dinner_x_\(agent.identity.id)", magnitude: 110),
            y: -35 + stableSignedOffset(for: "oak_dinner_y_\(agent.identity.id)", magnitude: 45)
        )
    }

    private func logDawnSnapshot(_ reason: String) {
        let locationCounts = Dictionary(grouping: agents, by: { $0.location.stringKey })
            .map { "\($0.key)=\($0.value.count)" }
            .sorted()
            .joined(separator: ", ")
        let taskCounts = Dictionary(grouping: agents, by: { $0.task.rawValue })
            .map { "\($0.key)=\($0.value.count)" }
            .sorted()
            .joined(separator: ", ")
        let details = agents
            .sorted { $0.identity.displayName < $1.identity.displayName }
            .map { "\($0.identity.displayName):\($0.task.rawValue)@\($0.location.stringKey)" }
            .joined(separator: " | ")

        Log.info(.npc, "[Gnomes][Dawn] \(reason) cartState=\(cartState.rawValue) cartRoom=\(cartLocation.stringKey) cartGems=\(cartGemCount)")
        Log.info(.npc, "[Gnomes][Dawn] locations: \(locationCounts)")
        Log.info(.npc, "[Gnomes][Dawn] tasks: \(taskCounts)")
        Log.debug(.npc, "[Gnomes][Dawn] roster: \(details)")
    }

    private func logDuskSnapshot(_ reason: String) {
        let locationCounts = Dictionary(grouping: agents, by: { $0.location.stringKey })
            .map { "\($0.key)=\($0.value.count)" }
            .sorted()
            .joined(separator: ", ")
        let taskCounts = Dictionary(grouping: agents, by: { $0.task.rawValue })
            .map { "\($0.key)=\($0.value.count)" }
            .sorted()
            .joined(separator: ", ")
        let details = agents
            .sorted { $0.identity.displayName < $1.identity.displayName }
            .map { "\($0.identity.displayName):\($0.task.rawValue)@\($0.location.stringKey)" }
            .joined(separator: " | ")

        Log.info(.npc, "[Gnomes][Dusk] \(reason) cartState=\(cartState.rawValue) cartRoom=\(cartLocation.stringKey) cartGems=\(cartGemCount)")
        Log.info(.npc, "[Gnomes][Dusk] locations: \(locationCounts)")
        Log.info(.npc, "[Gnomes][Dusk] tasks: \(taskCounts)")
        Log.debug(.npc, "[Gnomes][Dusk] roster: \(details)")
    }

    private func logVisibleDuskSpawn(scope: String, agentsHere: [GnomeAgent]) {
        guard TimeManager.shared.currentPhase == .dusk else { return }
        let details = agentsHere
            .sorted { $0.identity.displayName < $1.identity.displayName }
            .map { "\($0.identity.displayName):\($0.task.rawValue)" }
            .joined(separator: ", ")
        Log.info(.npc, "[Gnomes][Dusk] visible in \(scope): count=\(agentsHere.count) [\(details)]")
    }

    // MARK: - Mine Cart State Machine

    /// Once-per-frame cart state advance. Drives the dusk procession.
    private func tickCartState(now: TimeInterval) {
        switch cartState {
        case .idle:
            // Day mode: cart sits at cave entrance accumulating gems.
            // Make sure cartPosition stays anchored to the day-rest spot
            // so the visual draws correctly.
            cartLocation = .caveRoom(1)
            cartPosition = cartRestingPosition(in: cartLocation)
            cartVisual?.stopRolling()

        case .gathering:
            // Phase 1/4 of dusk: exactly one minute of cart prep in the
            // mines. Gnomes gather in cave_1 and mill around the cart.
            ensureCartDuskTimingInitialized(now: now)
            cartLocation = .caveRoom(1)
            cartPosition = cartRestingPosition(in: cartLocation)

            if now >= cartProcessionStartsAt() {
                beginCartProcession(now: now)
            }

        case .processing:
            // Phase 2/4 of dusk: exactly one minute hauling the cart
            // from the cave to the big oak tree.
            ensureCartDuskTimingInitialized(now: now)
            let elapsed = now - cartTaskStartedAt
            let entry = cartEntryPosition(for: cartLocation)
            let exit  = cartExitPosition(for: cartLocation)
            let roomDuration = max(0.25, cartCurrentRoomDuration)
            let progress = min(1.0,
                max(0.0, elapsed / roomDuration))
            cartPosition = interpolate(
                from: entry, to: exit, progress: CGFloat(progress)
            )
            // Drive the visual along with the agents.
            cartVisual?.position = cartPosition
            cartVisual?.startRolling()

            if elapsed >= roomDuration {
                hopCart(to: nextProcessionRoom(after: cartLocation),
                        now: now)
            }

        case .atTreasury:
            // Phase 3/4 of dusk: one full minute in the treasury room.
            ensureCartDuskTimingInitialized(now: now)
            cartLocation = .oakRoom(5)
            cartPosition = cartRestingPosition(in: cartLocation)
            cartVisual?.position = cartPosition
            cartVisual?.stopRolling()
            if now >= cartDinnerStartsAt {
                beginDinnerMingling(now: now)
            }
        case .dinner:
            // Phase 4/4 of dusk: dinner and mingling in the oak lobby.
            ensureCartDuskTimingInitialized(now: now)
            cartLocation = .oakRoom(1)
            cartPosition = cartRestingPosition(in: cartLocation)
            cartVisual?.position = cartPosition
            cartVisual?.stopRolling()
            if now >= cartDuskEndsAt {
                scatterGnomesHomeAfterCelebration(now: now)
            }

        case .returningToMine:
            // Phase 2/2 of dawn: the mine crew hauls the empty cart
            // back from the oak to the cave entrance together.
            let elapsed = now - cartTaskStartedAt
            let entry = dawnCartEntryPosition(for: cartLocation)
            let exit  = dawnCartExitPosition(for: cartLocation)
            let roomDuration = max(0.25, GnomeTiming.dawnReturnRoomDuration)
            let progress = min(1.0, max(0.0, elapsed / roomDuration))
            cartPosition = interpolate(from: entry, to: exit, progress: CGFloat(progress))
            cartVisual?.position = cartPosition
            cartVisual?.startRolling()

            if elapsed >= roomDuration {
                hopCartDuringDawnReturn(to: nextDawnReturnRoom(after: cartLocation), now: now)
            }

        case .resting:
            // Cart parks in the oak until the next dawn return procession.
            cartPosition = cartRestingPosition(in: cartLocation)
            cartVisual?.position = cartPosition
            cartVisual?.stopRolling()
        }
    }

    /// Procession sequence: cave_1 → forest_2 → forest_3 → forest_4 →
    /// oak_1 → oak_5. Returns the same room if we're past the end
    /// (the state-machine tick handles the atTreasury transition).
    private func nextProcessionRoom(after location: GnomeLocation) -> GnomeLocation {
        switch location {
        case .caveRoom(1):   return .forestRoom(2)
        case .forestRoom(2): return .forestRoom(3)
        case .forestRoom(3): return .forestRoom(4)
        case .forestRoom(4): return .oakRoom(1)
        case .oakRoom(1):    return .oakRoom(5)
        case .oakRoom(5):    return .oakRoom(5)
        default:             return .oakRoom(5)
        }
    }

    private func nextDawnReturnRoom(after location: GnomeLocation) -> GnomeLocation {
        switch location {
        case .oakRoom(1):    return .forestRoom(4)
        case .forestRoom(4): return .forestRoom(3)
        case .forestRoom(3): return .forestRoom(2)
        case .forestRoom(2): return .caveRoom(1)
        case .caveRoom(1):   return .caveRoom(1)
        default:             return .caveRoom(1)
        }
    }

    private func beginCartProcession(now: TimeInterval) {
        cartState = .processing
        cartTaskStartedAt = now

        let caveEntry = cartRestingPosition(in: .caveRoom(1))
        // Promote every gathering participant into haulingCart.
        for agent in agents where agent.task == .gatheringForCartTrip {
            if agent.location != .caveRoom(1) {
                agent.location = .caveRoom(1)
                agent.position = caveEntry
                agent.hasRealPosition = true
                agent.sceneNode?.removeFromParent()
                agent.sceneNode = nil
                respawnVisualIfRoomVisible(agent: agent)
            }
            agent.task = .haulingCart
            agent.taskStartedAt = now
            agent.wanderTarget = nil
        }
        cartVisual?.startRolling()
        Log.info(.npc, "[Gnomes] Cart procession started — hauling \(cartGemCount) gems")
        Log.info(.npc, "[Gnomes][Dusk] phase 2/4 started: cart travel (60s)")
        logDuskSnapshot("cart travel started")
    }

    /// Move the cart to the next room. If it's reaching oak_5, switch
    /// into atTreasury state and dump the gems into the pile.
    private func hopCart(to newLocation: GnomeLocation, now: TimeInterval) {
        let oldLocation = cartLocation
        cartLocation = newLocation
        cartTaskStartedAt = now
        cartPosition = cartEntryPosition(for: newLocation)

        // Pull every hauling gnome through to the new room. Reset
        // their taskStartedAt so any per-room timing is in sync
        // with the cart.
        for agent in agents where agent.task == .haulingCart {
            agent.location = newLocation
            agent.taskStartedAt = now
            agent.position = cartPosition
            agent.hasRealPosition = true
            agent.sceneNode?.removeFromParent()
            agent.sceneNode = nil
            respawnVisualIfRoomVisible(agent: agent)
        }

        // Cart visual itself — if the new room is the one being viewed,
        // respawn; otherwise drop it.
        despawnCartVisualNode()
        spawnCartVisualIfCurrentRoomMatches(newLocation: newLocation)

        // Arrival logic.
        if case .oakRoom(let n) = newLocation, n == 5 {
            arriveAtTreasury(now: now)
        }

        Log.info(.npc, "[Gnomes] Cart hopped \(oldLocation.stringKey) → \(newLocation.stringKey)")
        logDuskSnapshot("cart entered \(newLocation.stringKey)")
    }

    private func hopCartDuringDawnReturn(to newLocation: GnomeLocation, now: TimeInterval) {
        let oldLocation = cartLocation
        cartLocation = newLocation
        cartTaskStartedAt = now
        cartPosition = dawnCartEntryPosition(for: newLocation)

        for agent in agents where agent.task == .haulingCart {
            agent.location = newLocation
            agent.taskStartedAt = now
            agent.position = cartPosition
            agent.hasRealPosition = true
            agent.sceneNode?.removeFromParent()
            agent.sceneNode = nil
            respawnVisualIfRoomVisible(agent: agent)
        }

        despawnCartVisualNode()
        spawnCartVisualIfCurrentRoomMatches(newLocation: newLocation)

        if newLocation == .caveRoom(1) {
            finishDawnReturnProcession(now: now)
            return
        }

        Log.info(.npc, "[Gnomes] Dawn cart hopped \(oldLocation.stringKey) → \(newLocation.stringKey)")
        logDawnSnapshot("cart entered \(newLocation.stringKey)")
    }

    private func finishDawnReturnProcession(now: TimeInterval) {
        cartState = .idle
        cartLocation = .caveRoom(1)
        cartTaskStartedAt = now
        cartPosition = cartRestingPosition(in: cartLocation)
        cartVisual?.position = cartPosition
        cartVisual?.stopRolling()

        for agent in agents where agent.task == .haulingCart {
            agent.task = .idle
            agent.taskStartedAt = now
            agent.position = cartDepositTargetPosition()
            agent.wanderTarget = agent.position
            agent.hasRealPosition = true
        }

        Log.info(.npc, "[Gnomes][Dawn] cart return arrived at cave entrance")
        logDawnSnapshot("cart return finished")
    }

    /// Cart has reached oak_5. Dump cartGemCount into the treasury
    /// in one beat and start the celebration.
    private func arriveAtTreasury(now: TimeInterval) {
        cartState = .atTreasury
        cartTaskStartedAt = now

        let dumped = cartGemCount
        cartGemCount = 0
        cartVisual?.setCount(0, animated: false)

        // Drop the entire load into the treasury (skips the per-gem
        // chronicle hook because each deposit was already chronicled
        // when the gnome put it on the cart).
        if dumped > 0 {
            incrementTreasury(amount: dumped, fromCartDelivery: true)
        }

        // Visual celebration on both the cart and the pile.
        cartVisual?.playDumpCelebration()
        if let oak = oakScene,
           oak.currentOakRoom == .treasury,
           let pile = oak.treasuryPile {
            pile.playResetCelebration()
        }

        // Switch participants to celebrating.
        for agent in agents where agent.task == .haulingCart {
            agent.task = .celebrating
            agent.taskStartedAt = now
        }

        Log.info(.npc, "[Gnomes] Cart arrived at treasury — dumped \(dumped) gems")
        Log.info(.npc, "[Gnomes][Dusk] phase 3/4 started: treasury turn-in (60s)")
        logDuskSnapshot("treasury turn-in started")
    }

    private func beginDinnerMingling(now: TimeInterval) {
        cartState = .dinner
        cartTaskStartedAt = now
        cartLocation = .oakRoom(1)
        cartPosition = cartRestingPosition(in: cartLocation)
        despawnCartVisualNode()
        spawnCartVisualIfCurrentRoomMatches(newLocation: cartLocation)
        cartVisual?.position = cartPosition
        cartVisual?.stopRolling()

        // Try to seat everyone at dining tables. Falls back to
        // free-mingle if no seat anchors are authored yet.
        let seated = GnomeSeating.shared.beginMeal(
            .dinner, agents: agents, oakScene: oakScene, now: now
        )

        for agent in agents {
            let isCook = agent.identity.id == GnomeRoster.kitchenCook.id
            let target: CGPoint
            if seated {
                target = GnomeSeating.shared.mealPosition(
                    for: agent,
                    oakScene: oakScene,
                    fallbackMinglePosition: dinnerMinglePosition(for: agent)
                )
                agent.task = isCook ? .cookServingFromStation : .dining
            } else {
                target = dinnerMinglePosition(for: agent)
                agent.task = .idle
            }
            agent.location = .oakRoom(1)
            agent.taskStartedAt = now
            agent.position = target
            agent.wanderTarget = target
            agent.hasRealPosition = true
            agent.sceneNode?.removeFromParent()
            agent.sceneNode = nil
            respawnVisualIfRoomVisible(agent: agent)
        }

        Log.info(.npc, "[Gnomes][Dusk] phase 4/4 started: dinner and mingling (60s)")
        logDuskSnapshot("dinner mingling started")
    }

    /// After the celebration timer expires, send participants home.
    private func scatterGnomesHomeAfterCelebration(now: TimeInterval) {
        cartState = .resting
        cartTaskStartedAt = now
        cartLocation = .oakRoom(1)
        cartPosition = cartRestingPosition(in: cartLocation)
        cartVisual?.position = cartPosition
        cartVisual?.stopRolling()
        clearCartDuskTiming()

        // End any active meal: clear seat assignments while leaving
        // the authored tables in place. (Idempotent if no meal was
        // running.)
        GnomeSeating.shared.endMeal(agents: agents, oakScene: oakScene)

        for agent in agents {
            // Hop them straight to their home oak room and put them
            // to sleep — night has clearly fallen by now.
            let home: GnomeLocation = .oakRoom(agent.identity.homeOakRoom)
            agent.location = home
            agent.position = restingPosition(for: home, agent: agent)
            agent.wanderTarget = agent.position
            agent.task = .sleeping
            agent.taskStartedAt = now
            agent.hasRealPosition = true
            agent.sceneNode?.removeFromParent()
            agent.sceneNode = nil
            respawnVisualIfRoomVisible(agent: agent)
        }
        Log.info(.npc, "[Gnomes] Celebration over — gnomes scatter home for the night")
        logDuskSnapshot("night sleep started")
    }

    // MARK: - Public Cart Visual API (called by scenes)

    /// Cave scene calls this every time the active cave room changes.
    /// Spawns the cart visual into `scene` if the cart is logically
    /// in this cave room, otherwise no-op.
    func spawnVisibleCartIfPresent(inCaveRoom caveRoom: CaveRoom, scene: CaveScene) {
        guard case let .caveRoom(n) = cartLocation, caveRoom.rawValue == n else { return }
        attachCartVisual(to: scene)
    }

    /// Forest scene calls this every time the active forest room changes.
    func spawnVisibleCartIfPresent(inForestRoom forestRoom: Int, scene: ForestScene) {
        guard case let .forestRoom(n) = cartLocation, n == forestRoom else { return }
        attachCartVisual(to: scene)
    }

    /// Oak scene calls this every time the active oak room changes.
    func spawnVisibleCartIfPresent(inOakRoom oakRoom: OakRoom, scene: BigOakTreeScene) {
        guard case let .oakRoom(n) = cartLocation, oakRoom.rawValue == n else { return }
        attachCartVisual(to: scene)
    }

    /// Tear down the visual, e.g. when the player leaves a room or
    /// the cart hops out.
    func despawnCartVisual() {
        despawnCartVisualNode()
    }

    private func despawnCartVisualNode() {
        cartVisual?.removeFromParent()
        cartVisual = nil
    }

    /// If the player is currently watching the cart's logical room,
    /// reattach the visual to that scene. Used after a hopCart.
    private func spawnCartVisualIfCurrentRoomMatches(newLocation: GnomeLocation) {
        switch newLocation {
        case .caveRoom(let n):
            guard let scene = caveScene, scene.currentCaveRoom.rawValue == n else { return }
            attachCartVisual(to: scene)
        case .forestRoom(let n):
            guard let scene = forestScene, scene.currentRoom == n else { return }
            attachCartVisual(to: scene)
        case .oakRoom(let n):
            guard let scene = oakScene, scene.currentOakRoom.rawValue == n else { return }
            attachCartVisual(to: scene)
        }
    }

    private func attachCartVisual(to scene: SKScene) {
        despawnCartVisualNode()
        let cart = MineCart()
        cart.position = cartPosition
        cart.setCount(cartGemCount, animated: false)
        scene.addChild(cart)
        cartVisual = cart
        if cartState == .processing || cartState == .returningToMine {
            cart.startRolling()
        }
    }

    // MARK: - Player Action Hooks

    @discardableResult
    func playerFedRockToMachine(rockID: String) -> Bool {
        let verdict = MineMachine.verdict(for: rockID, dayCount: currentDayCount)
        caveScene?.flashMineMachineIfPresent(green: verdict)
        if !verdict {
            caveScene?.bumpWasteBinIfPresent()
        }
        ForagingManager.shared.collect(spawnID: rockID)
        if MultiplayerService.shared.isConnected {
            MultiplayerService.shared.send(
                type: .mineMachineFed,
                payload: MineMachineFedMessage(
                    rockID: rockID,
                    dayCount: currentDayCount,
                    verdict: verdict
                )
            )
        }
        return verdict
    }

    func playerDepositedGem() {
        incrementTreasury(amount: 1)
    }

    // MARK: - Multiplayer Sync

    private func broadcastFullState() {
        let snapshots = agents.map { $0.makeSnapshot() }
        let msg = GnomeStateSyncMessage(
            snapshots: snapshots,
            treasuryGemCount: treasuryGemCount,
            dayCount: currentDayCount,
            cartGemCount: cartGemCount,
            cartLocation: cartLocation.stringKey,
            cartPosition: CodablePoint(cartPosition),
            cartState: cartState.rawValue
        )
        MultiplayerService.shared.send(type: .gnomeStateSync, payload: msg)
    }

    private func broadcastTreasuryUpdate(didReset: Bool) {
        guard MultiplayerService.shared.isConnected else { return }
        MultiplayerService.shared.send(
            type: .treasuryUpdate,
            payload: TreasuryUpdateMessage(newCount: treasuryGemCount, didReset: didReset)
        )
    }

    func applyRemoteState(_ msg: GnomeStateSyncMessage) {
        currentDayCount = msg.dayCount
        for snap in msg.snapshots {
            guard let agent = agents.first(where: { $0.identity.id == snap.id }) else { continue }
            if agent.location.stringKey != snap.location {
                agent.sceneNode?.removeFromParent()
                agent.sceneNode = nil
            }
            agent.apply(snap)
            respawnVisualIfRoomVisible(agent: agent)
            // Drive the visual SKAction in response to the snapshot.
            // Without this, guest visuals finish their initial spawn-
            // time SKAction and then stand still while the host's
            // state machine continues advancing them.
            syncVisualToCurrentTask(agent)
        }
        treasuryGemCount = msg.treasuryGemCount
        oakScene?.updateTreasuryPileIfPresent(count: treasuryGemCount, didReset: false)

        // Mine cart state. Older builds omit these fields — fall back
        // to safe defaults that match a fresh idle cart.
        let newCartCount = msg.cartGemCount ?? 0
        let newCartState = msg.cartState
            .flatMap { MineCartState(rawValue: $0) } ?? .idle
        let newCartLocation = msg.cartLocation
            .flatMap { GnomeLocation(stringKey: $0) } ?? .caveRoom(1)
        let newCartPosition = msg.cartPosition?.cgPoint
            ?? cartRestingPosition(in: newCartLocation)

        let locationChanged = (cartLocation != newCartLocation)
        cartGemCount = newCartCount
        cartState = newCartState
        dawnReturnStarted = (newCartState == .returningToMine)
        cartLocation = newCartLocation
        cartPosition = newCartPosition
        cartVisual?.setCount(newCartCount, animated: false)
        cartVisual?.position = newCartPosition
        if locationChanged {
            despawnCartVisualNode()
            spawnCartVisualIfCurrentRoomMatches(newLocation: newCartLocation)
        }
    }

    /// Bridge a freshly-applied snapshot to the visual GnomeNPC node.
    /// Called on the GUEST after `agent.apply(snap)` in `applyRemoteState`.
    /// Ensures the appropriate SKAction is running for the agent's
    /// current task, and snap-corrects the visual if it has drifted
    /// too far from the host's authoritative position.
    private func syncVisualToCurrentTask(_ agent: GnomeAgent) {
        guard let node = agent.sceneNode, !node.isFrozen else { return }

        let drift = hypot(node.position.x - agent.position.x,
                          node.position.y - agent.position.y)

        switch agent.task {
        case .dining:
            if drift > 26 {
                node.gnomeStandAt(agent.position)
            } else if drift > 8 {
                node.gnomeWanderTo(agent.position)
            } else if node.isTraversing || node.isWandering {
                node.gnomeStandAt(agent.position)
            }

        case .sleeping, .idle, .supervising, .lookingForRock,
             .celebrating, .depositingGemAtCart,
             .cookServingFromStation,
             .cookDeliveringToTable, .cookCheckingOnTable,
             .tidyingTables:
            // Leave any active wander alone — let the SKAction finish.
            // Once it finishes, kick a new gentle wander toward
            // authoritative position so the gnome doesn't sit still.
            if !node.isWandering && !node.isTraversing {
                if drift > 60 {
                    node.gnomeStandAt(agent.position)
                }
                let jitter = CGPoint(
                    x: agent.position.x + CGFloat.random(in: -25...25),
                    y: agent.position.y + CGFloat.random(in: -25...25)
                )
                node.gnomeWanderTo(jitter)
            }

        case .commutingToMine, .commutingHome,
             .carryingRockToMachine, .carryingGemToTreasury,
             .gatheringForCartTrip, .haulingCart:
            // Cross-room traversal — make sure a traversal SKAction is
            // running. Rebase from agent.position when drift is large.
            guard let exit = exitPosition(for: agent.location, agent: agent) else { return }
            let entry = entryPosition(for: agent.location, agent: agent)
            let total = roomDuration(for: agent, location: agent.location)
            let driftThreshold: CGFloat = 90

            if drift > driftThreshold {
                let from = agent.position
                let remaining = remainingTraversalDuration(
                    from: from, entry: entry, exit: exit, totalDuration: total
                )
                if hypot(exit.x - from.x, exit.y - from.y) > 6 {
                    node.gnomeTraverse(from: from, to: exit, duration: remaining)
                } else {
                    node.gnomeStandAt(exit)
                }
            } else if !node.isTraversing {
                let from = node.position
                let remaining = remainingTraversalDuration(
                    from: from, entry: entry, exit: exit, totalDuration: total
                )
                if hypot(exit.x - from.x, exit.y - from.y) > 6 {
                    node.gnomeTraverse(from: from, to: exit, duration: remaining)
                }
            }

        case .usingMachine:
            let target = machineTargetPosition()
            if drift > 80 {
                node.gnomeStandAt(agent.position)
            }
            if !node.isTraversing && hypot(node.position.x - target.x, node.position.y - target.y) > 6 {
                walkAgentToMachine(agent)
            }

        case .dumpingRockInWasteBin:
            let target = wasteBinTargetPosition()
            if drift > 80 {
                node.gnomeStandAt(agent.position)
            }
            if !node.isTraversing && hypot(node.position.x - target.x, node.position.y - target.y) > 6 {
                walkAgentToBin(agent)
            }
        }
    }

    func applyRemoteRosterRefresh(_ msg: GnomeRosterRefreshMessage) {
        currentDayCount = msg.dayCount
        if let id = msg.promotedID ?? msg.demotedID,
           let rank = msg.newRank,
           let agent = agents.first(where: { $0.identity.id == id }),
           let r = GnomeRank(rawValue: rank) {
            agent.rank = r
        }
        todaysRankChangeID = msg.promotedID ?? msg.demotedID
        todaysRankChangeIsPromotion = msg.promotedID != nil
        todaysBossLine = msg.bossLine
    }

    // MARK: - Save / Load

    func exportSaveData() -> [String: Any] {
        let snapshots = agents.map { $0.makeSnapshot() }
        let data = (try? JSONEncoder().encode(snapshots)) ?? Data()
        return [
            "snapshots": String(data: data, encoding: .utf8) ?? "[]",
            "treasury": treasuryGemCount,
            "dayCount": currentDayCount,
            "cartGemCount": cartGemCount,
            "cartLocation": cartLocation.stringKey,
            "cartState": cartState.rawValue
        ]
    }

    func restoreSaveData(_ dict: [String: Any]) {
        clearCartDuskTiming()
        clearDawnTiming()
        if let json = dict["snapshots"] as? String,
           let data = json.data(using: .utf8),
           let snapshots = try? JSONDecoder().decode([GnomeSnapshot].self, from: data) {
            for snap in snapshots {
                guard let agent = agents.first(where: { $0.identity.id == snap.id }) else { continue }
                agent.apply(snap)
                // Migrate legacy task: anyone restored as
                // .carryingGemToTreasury becomes .depositingGemAtCart
                // since the long oak walk no longer exists.
                if agent.task == .carryingGemToTreasury {
                    agent.task = .depositingGemAtCart
                    agent.taskStartedAt = CACurrentMediaTime()
                    // If they're not in the cave anymore, send them
                    // back. The advance method handles this case.
                }
            }
        }
        if let count = dict["treasury"] as? Int {
            treasuryGemCount = max(0, count)
        }
        if let day = dict["dayCount"] as? Int {
            currentDayCount = day
        }
        if let cartCount = dict["cartGemCount"] as? Int {
            cartGemCount = max(0, cartCount)
        }
        if let key = dict["cartLocation"] as? String,
           let loc = GnomeLocation(stringKey: key) {
            cartLocation = loc
        }
        if let stateRaw = dict["cartState"] as? String,
           let s = MineCartState(rawValue: stateRaw) {
            cartState = s
            dawnReturnStarted = (s == .returningToMine)
        }
        cartPosition = cartRestingPosition(in: cartLocation)
        cartTaskStartedAt = CACurrentMediaTime()
    }

    // MARK: - Lookups

    func agent(byID id: String) -> GnomeAgent? {
        agents.first { $0.identity.id == id }
    }

    func agentsCurrentlyIn(_ location: GnomeLocation) -> [GnomeAgent] {
        agents.filter { $0.location == location }
    }

    // MARK: - Dining Tick

    /// Keep dawn/dusk diners centered on their assigned seats, with
    /// only brief near-table stretches so the room still feels alive.
    private func tickDiningForMeal(now: TimeInterval) {
        guard GnomeSeating.shared.isMealActive else { return }
        guard let scene = oakScene else { return }

        let cookID = GnomeRoster.kitchenCook.id
        for agent in agents
            where agent.identity.id != cookID
            && agent.task == .dining
            && agent.location == .oakRoom(1) {
            let seat = GnomeSeating.shared.mealPosition(
                for: agent,
                oakScene: scene,
                fallbackMinglePosition: dinnerMinglePosition(for: agent)
            )
            let target = nextDiningTarget(for: agent, seat: seat, now: now)
            agent.wanderTarget = target

            guard let node = agent.sceneNode, !node.isFrozen else { continue }

            let distToTarget = hypot(node.position.x - target.x, node.position.y - target.y)
            let seatOffset = hypot(target.x - seat.x, target.y - seat.y)

            if seatOffset <= 10 {
                if distToTarget > 12 {
                    let duration = max(0.25, TimeInterval(distToTarget / GnomeTiming.taskWalkSpeed))
                    node.gnomeTraverse(from: node.position, to: target, duration: duration)
                } else if distToTarget > 2 || node.isTraversing || node.isWandering {
                    node.gnomeStandAt(target)
                }
                continue
            }

            if distToTarget > 8 && !node.isTraversing {
                node.gnomeWanderTo(target)
            } else if distToTarget <= 4 && (node.isTraversing || node.isWandering) {
                node.gnomeStandAt(target)
            }
        }
    }

    private func nextDiningTarget(
        for agent: GnomeAgent,
        seat: CGPoint,
        now: TimeInterval
    ) -> CGPoint {
        let currentTarget = clamp(agent.wanderTarget ?? seat, to: agent.location)
        let currentSeatOffset = hypot(currentTarget.x - seat.x, currentTarget.y - seat.y)

        guard agent.wanderTarget == nil
            || now >= agent.nextWanderAt
            || currentSeatOffset > 80 else {
            return currentTarget
        }

        agent.nextWanderAt = now + Double.random(in: 2.8...5.2)

        if Double.random(in: 0...1) < 0.2 {
            let angle = Double.random(in: 0...(2 * Double.pi))
            let radiusX = CGFloat.random(in: 20...44)
            let radiusY = CGFloat.random(in: 10...26)
            let target = CGPoint(
                x: seat.x + CGFloat(cos(angle)) * radiusX,
                y: seat.y + CGFloat(sin(angle)) * radiusY
            )
            return clamp(target, to: agent.location)
        }

        let seatFidget = CGPoint(
            x: seat.x + CGFloat.random(in: -5...5),
            y: seat.y + CGFloat.random(in: -3...3)
        )
        return clamp(seatFidget, to: agent.location)
    }

    // MARK: - Cook Tick (meal-time)

    /// Per-frame hook that drives the cook's cycle during a meal.
    /// Delegates to GnomeSeating for the actual sub-state machine and
    /// reaction bubbles; this method's job is to (a) gate on whether
    /// a meal is in progress, (b) move the cook's agent.position to
    /// wherever the seating service says it should be (cook station,
    /// or the table the cook is currently delivering to / checking on),
    /// and (c) drive the visual SKAction so it walks smoothly.
    private func tickCookForMeal(now: TimeInterval) {
        guard GnomeSeating.shared.isMealActive else { return }
        guard let cook = agents.first(where: { $0.identity.id == GnomeRoster.kitchenCook.id }) else {
            return
        }
        // The cook always lives in oak_1 during a meal.
        guard cook.location == .oakRoom(1) else { return }

        // Advance the seating sub-state machine. This may flip
        // cook.task to .cookServingFromStation/.cookDeliveringToTable/
        // .cookCheckingOnTable and update cookTargetTableIndex.
        GnomeSeating.shared.tickCook(
            cook: cook,
            agents: agents,
            oakScene: oakScene,
            now: now
        )

        // Authoritative position for this frame from seating.
        let target = GnomeSeating.shared.cookCurrentPosition(
            cook: cook,
            oakScene: oakScene,
            fallbackMinglePosition: dinnerMinglePosition(for: cook)
        )
        cook.position = target
        cook.wanderTarget = target
        cook.hasRealPosition = true

        // Drive the visual: walk to the target if we're not already
        // close. Skip during checking (the cook stands still at the
        // table during reactions).
        guard let node = cook.sceneNode, !node.isFrozen else { return }
        let dist = hypot(node.position.x - target.x, node.position.y - target.y)
        if cook.task == .cookDeliveringToTable {
            if !node.isTraversing && dist > 8 {
                let dur = max(0.4, TimeInterval(dist / GnomeTiming.taskWalkSpeed))
                node.gnomeTraverse(from: node.position, to: target, duration: dur)
            }
        } else if cook.task == .cookServingFromStation || cook.task == .cookCheckingOnTable {
            if dist > 14 && !node.isTraversing {
                node.gnomeStandAt(target)
            }
        }
    }
}
