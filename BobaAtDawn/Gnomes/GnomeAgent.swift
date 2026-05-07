//
//  GnomeAgent.swift
//  BobaAtDawn
//
//  Per-gnome runtime state. One agent per identity in the roster, owned
//  and ticked by GnomeManager. Distinct from `GnomeNPC` (the visual
//  scene node) — agents persist regardless of which scene the player is
//  in, and a GnomeNPC is spawned/despawned around them as needed.
//

import CoreGraphics
import Foundation

// MARK: - Gnome Agent
final class GnomeAgent {

    // MARK: - Identity (immutable)
    let identity: GnomeIdentity

    // MARK: - Mutable State
    /// Current rank. Promotions/demotions mutate this. Boss is locked at
    /// `.foreman`. Housekeepers don't have a meaningful rank but we
    /// store one for uniform sync.
    var rank: GnomeRank

    /// Coarse logical location.
    var location: GnomeLocation

    /// Current task. Drives behavior in `GnomeManager.update`.
    var task: GnomeTask

    /// Carried item, if any.
    var carried: GnomeCarried?

    /// Time (CACurrentMediaTime) at which the current task started.
    /// Used to compute timed transitions (e.g. "spend 8s in this room").
    var taskStartedAt: TimeInterval

    /// Position within the current location, in scene-space. Updated
    /// every frame when the agent has a visible scene node, otherwise
    /// the manager interpolates a notional position so the visual can
    /// pick up where it left off when the player enters the scene.
    var position: CGPoint
    var hasRealPosition: Bool = false

    /// Velocity used by the simple in-room wander animation.
    var wanderTarget: CGPoint?
    var nextWanderAt: TimeInterval = 0

    /// Currently-attached visual node, when one exists. Weak so the
    /// scene can despawn the visual without involving the manager.
    weak var sceneNode: GnomeNPC?

    /// id of the rock spawn currently being carried (so we can clean up
    /// the foraging registry entry when it gets fed to the machine).
    var carriedRockSpawnID: String?

    /// id of the cave floor the gnome is currently working. Set when
    /// they descend, used to remember where to look for more rocks.
    var workingCaveFloor: Int?

    /// Number of gems delivered to treasury today. Used by the boss
    /// to pick the most-productive miner for promotion.
    var gemsDeliveredToday: Int = 0

    /// Whether this gnome is on mine duty today. Oak-only roles always
    /// stay off duty; the boss and miners are assigned by the manager.
    var isOnMineDutyToday: Bool

    // MARK: - Meal-time State

    /// Anchor name of the seat this gnome is assigned to for the
    /// current meal beat (e.g. "gnome_seat_3_2"). Set by
    /// `GnomeSeating.assignSeats(forMeal:)` at the start of breakfast
    /// and dinner. Cleared when the meal ends. Cook never has a seat.
    var currentSeatAnchor: String?

    /// Cook-only: the table number (1...5) the cook is currently
    /// delivering to or checking on. Reset each cook-cycle. Other
    /// gnomes leave this nil.
    var cookTargetTableIndex: Int?

    /// Cook-only: the agent id of the gnome the cook is currently
    /// chatting with at a table. Used by `GnomeSeating` to fire the
    /// reaction bubble on the right gnome. Reset each cook-cycle.
    var cookTargetSeatedAgentID: String?

    /// Where this gnome should head when its current commute ends.
    /// Used by phase-change reroute logic. See `GnomeArrivalIntent`.
    /// Defaults to `.nothing` (use the task's normal arrival branch).
    var arrivalIntent: GnomeArrivalIntent = .nothing

    // MARK: - Init

    init(identity: GnomeIdentity, startTime: TimeInterval) {
        self.identity = identity
        self.rank = identity.initialRank
        self.task = identity.role.livesInOak ? .idle : .sleeping
        self.carried = nil
        self.taskStartedAt = startTime
        self.position = .zero
        self.location = .oakRoom(identity.homeOakRoom)
        // Default everyone (including boss) to mine duty initially.
        // Manager rotates per-day at dawn.
        self.isOnMineDutyToday = !identity.role.livesInOak
    }

    // MARK: - Convenience

    /// Display name with rank suffix for miners and boss. Oak-only
    /// support roles just get their flavor name.
    var fullDisplayName: String {
        switch identity.role {
        case .boss:        return "\(identity.displayName), \(rank.title)"
        case .miner:       return "\(identity.displayName), \(rank.title)"
        case .housekeeper, .npcBroker, .treasurer:
            return identity.displayName
        }
    }

    /// Convenience: are we currently in any cave room?
    var isInCave: Bool {
        if case .caveRoom = location { return true }
        return false
    }

    /// Convenience: are we currently in any oak room?
    var isInOak: Bool {
        if case .oakRoom = location { return true }
        return false
    }

    /// Convenience: are we currently in any forest room?
    var isInForest: Bool {
        if case .forestRoom = location { return true }
        return false
    }

    // MARK: - Snapshot Bridge

    func makeSnapshot() -> GnomeSnapshot {
        GnomeSnapshot(
            id: identity.id,
            role: identity.role.rawValue,
            rank: rank.rawValue,
            location: location.stringKey,
            task: task.rawValue,
            carried: carried?.rawValue,
            position: CodablePoint(position),
            displayName: fullDisplayName
        )
    }

    /// Apply a snapshot received from the host. Replaces all mutable state.
    func apply(_ snapshot: GnomeSnapshot) {
        if let r = GnomeRank(rawValue: snapshot.rank) {
            rank = r
        }
        if let loc = GnomeLocation(stringKey: snapshot.location) {
            location = loc
        }
        if let t = GnomeTask(rawValue: snapshot.task) {
            // Legacy task migration: an older host may still emit
            // `.carryingGemToTreasury` snapshots. Map them to the new
            // in-cave deposit task so the local state machine doesn't
            // try to walk back to the oak.
            task = (t == .carryingGemToTreasury) ? .depositingGemAtCart : t
        }
        if let raw = snapshot.carried {
            carried = GnomeCarried(rawValue: raw)
        } else {
            carried = nil
        }
        position = snapshot.position.cgPoint
        hasRealPosition = true
    }
}
