//
//  GnomeIdentity.swift
//  BobaAtDawn
//
//  Shared types for the gnome simulation: roles, ranks, locations, and
//  the task state machine. All `Codable` so they can be persisted and
//  synced over the network.
//

import CoreGraphics
import Foundation

// MARK: - Gnome Role
/// What kind of life this gnome leads.
/// - `boss`: oversees mining ops, lives in oak lobby. One per world.
/// - `miner`: works the mines during the day, sleeps in oak at night.
/// - `housekeeper`: never leaves the oak — cooks, cleans, manages the treasury.
enum GnomeRole: String, Codable {
    case boss
    case miner
    case housekeeper
}

// MARK: - Miner Rank
/// Cosmetic rank used for boss promotions/demotions.
/// Only meaningful for `miner` role (boss is always `foreman`,
/// housekeepers don't have a rank). Pure flavor.
enum GnomeRank: Int, Codable, CaseIterable {
    case junior  = 0
    case standard = 1
    case senior  = 2
    case foreman = 3

    var title: String {
        switch self {
        case .junior:   return "Junior Miner"
        case .standard: return "Miner"
        case .senior:   return "Senior Miner"
        case .foreman:  return "Foreman"
        }
    }
}

// MARK: - Gnome Location
/// Where a gnome currently is in the world. Coarse — one room at a time.
/// Transit between scenes is modeled by changing this value over time
/// rather than animating cross-scene paths.
enum GnomeLocation: Codable, Equatable, Hashable {
    case oakRoom(Int)     // 1...4 — see OakRoom rawValues, plus 5 for treasury
    case caveRoom(Int)    // 1...4 — see CaveRoom rawValues
    case forestRoom(Int)  // 1...5

    /// Stable string key for logs and network sync.
    var stringKey: String {
        switch self {
        case let .oakRoom(n):    return "oak_\(n)"
        case let .caveRoom(n):   return "cave_\(n)"
        case let .forestRoom(n): return "forest_\(n)"
        }
    }

    init?(stringKey: String) {
        let parts = stringKey.split(separator: "_")
        guard parts.count == 2, let n = Int(parts[1]) else { return nil }
        switch parts[0] {
        case "oak":    self = .oakRoom(n)
        case "cave":   self = .caveRoom(n)
        case "forest": self = .forestRoom(n)
        default:       return nil
        }
    }
}

// MARK: - Gnome Task
/// A small state machine. The `GnomeManager` advances each agent through
/// these states based on time-of-day and per-agent timers.
enum GnomeTask: String, Codable {
    /// Idling — wandering near home or workplace. Default fallback state.
    case idle

    /// Sleeping it off. Set during night phase. Visual is a still gnome
    /// with a "z" indicator.
    case sleeping

    /// Walking from oak → mines through forest rooms.
    case commutingToMine

    /// In a cave floor with rocks, picking one up.
    case lookingForRock

    /// Carrying a rock back up to the entrance machine.
    case carryingRockToMachine

    /// Standing at the machine, putting a rock in. Brief.
    case usingMachine

    /// LEGACY — retained for save-data back-compat only. The state
    /// machine no longer assigns this task; gnomes deposit gems at
    /// the in-cave mine cart via `.depositingGemAtCart` instead, and
    /// the cart hauls them to the oak treasury at dusk. If a save
    /// from an older build contains this state, the manager will
    /// migrate it to `.depositingGemAtCart` at apply time.
    case carryingGemToTreasury

    /// New: walk a freshly-produced gem from the mine machine over to
    /// the in-cave mine cart at the cave entrance. Strictly cave-bound.
    case depositingGemAtCart

    /// Got a red verdict — walking the rock to the waste bin.
    case dumpingRockInWasteBin

    /// At dusk — head from wherever in the cave the gnome is up to
    /// the cave entrance to join the cart procession. Replaces the
    /// old per-gnome `.commutingHome` for the daily cart trip; the
    /// commute home now happens AS A GROUP via `.haulingCart`.
    case gatheringForCartTrip

    /// Group state: marching in lockstep with the cart from cave
    /// entrance through the forest to the oak treasury. All gnomes
    /// in this state share the same room transitions and timing.
    case haulingCart

    /// At the oak treasury after the cart has dumped its load. Brief
    /// celebration before scattering to bedrooms to sleep.
    case celebrating

    /// At dusk/night — walking from mines back to oak. Used now only
    /// as a fallback when no procession occurs (e.g. the cart is
    /// empty at dusk because nothing was mined).
    case commutingHome

    /// Boss-only: stands near the machine in the entrance, occasionally
    /// barks orders or hands out promotions.
    case supervising
}

// MARK: - Gnome Carried
/// What the gnome currently holds. Mirrors the player's carry slot.
enum GnomeCarried: String, Codable {
    case rock
    case gem
}

// MARK: - Mine Cart State
/// Lifecycle of the daily mine-cart trip. Tracked by GnomeManager.
enum MineCartState: String, Codable {
    /// Cart is sitting at the cave entrance, accumulating gems as
    /// miners deposit them throughout the day.
    case idle

    /// Dusk — cart is still at the cave entrance; miners + boss are
    /// converging there to begin the procession.
    case gathering

    /// Cart is being hauled in lockstep with the gnomes through:
    /// cave_1 → forest_2 → forest_3 → forest_4 → oak_1 → oak_5.
    case processing

    /// Cart has arrived at the treasury and is dumping its load. The
    /// celebration animation runs during this state.
    case atTreasury

    /// The cart is parked after turn-in while the gnomes eat and
    /// mingle in the oak before bed.
    case dinner

    /// Dawn — the mine crew is hauling the empty cart back from the
    /// oak to the cave entrance together.
    case returningToMine

    /// Post-celebration. Gnomes are dispersing to bedrooms. Cart is
    /// parked in the oak until the dawn return procession begins.
    case resting
}

// MARK: - Gnome Snapshot (sync payload)
/// Serializable snapshot of one gnome's full state. The host produces
/// these every ~0.5s and broadcasts; the guest applies. Also written to
/// disk via SaveService for cross-session persistence.
struct GnomeSnapshot: Codable {
    let id: String
    let role: String          // GnomeRole.rawValue
    let rank: Int             // GnomeRank.rawValue (0 for non-miners)
    let location: String      // GnomeLocation.stringKey
    let task: String          // GnomeTask.rawValue
    let carried: String?      // GnomeCarried.rawValue or nil
    let position: CodablePoint
    let displayName: String
}

// MARK: - GnomeStateSyncMessage Payload
/// Broadcast every ~0.5s by the host. Carries the entire gnome roster
/// snapshot plus the current treasury count, plus the in-flight mine
/// cart state.
struct GnomeStateSyncMessage: Codable {
    let snapshots: [GnomeSnapshot]
    let treasuryGemCount: Int
    let dayCount: Int

    // MARK: - Mine Cart Sync (optional for back-compat with older builds)

    /// Number of gems currently in the cart. nil from old builds = 0.
    let cartGemCount: Int?
    /// Logical room the cart is in. nil from old builds = cave entrance.
    let cartLocation: String?
    /// Cart's interpolated position within the current room. nil = use
    /// the room's default cart anchor.
    let cartPosition: CodablePoint?
    /// Cart lifecycle state. nil from old builds = .idle.
    let cartState: String?
}

// MARK: - GnomeRosterRefreshMessage Payload
/// Broadcast at dawn by the host: identifies which agent (if any) was
/// promoted or demoted today, and which agents have been assigned to
/// mine duty. The guest renders the resulting boss line if appropriate.
struct GnomeRosterRefreshMessage: Codable {
    /// id of the agent promoted today, if any.
    let promotedID: String?
    /// id of the agent demoted today, if any. Mutually exclusive with promoted.
    let demotedID: String?
    /// New rank value of the affected agent (0...3).
    let newRank: Int?
    /// The boss line announcing the promotion/demotion.
    let bossLine: String?
    let dayCount: Int
}

// MARK: - TreasuryUpdateMessage Payload
/// Broadcast by either side when a gem is deposited. Carries the new
/// total (post-increment) so both clients converge to the same count
/// even if messages cross.
struct TreasuryUpdateMessage: Codable {
    let newCount: Int
    /// True if this deposit just rolled the count past the threshold (50)
    /// and reset to zero. Lets the receiver play a celebration locally.
    let didReset: Bool
}

// MARK: - MineMachineFedMessage Payload
/// Broadcast when a player or gnome feeds a rock to the machine. The
/// verdict is computed deterministically from the rockID + dayCount,
/// so both sides agree without an authoritative ruling. Player-fed
/// rocks bump the waste bin immediately on a red verdict; gnome-fed
/// rocks rely on the gnome's subsequent walk to the bin (driven by
/// gnomeStateSync task transitions) for the bin animation.
struct MineMachineFedMessage: Codable {
    let rockID: String       // ForageSpawn.spawnID
    let dayCount: Int
    /// True if green → gem produced. False if red → rock is rejected.
    let verdict: Bool
}
