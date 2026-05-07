//
//  TimeService.swift
//  BobaAtDawn
//
//  Service protocol for time management
//

import Foundation

protocol TimeService: AnyObject {
    var currentPhase: TimePhase { get }
    var phaseProgress: Float { get }
    var isTimeActive: Bool { get }

    /// Active subphase computed from currentPhase + phaseProgress.
    /// See TimeSubphase for the breakdown.
    var currentSubphase: TimeSubphase { get }

    /// Progress (0..1) within the active subphase.
    var subphaseProgress: Float { get }
    
    /// Current day number (incremented each dawn). Persisted across sessions.
    var dayCount: Int { get }
    
    /// Whether today is a ritual day (every 3rd day, starting from day 3).
    var isRitualDay: Bool { get }
    
    func update()
    
    /// Called by the game scene when dawn arrives to advance the day counter.
    func advanceDay()
    
    /// Sync the runtime day count from a network source (e.g. host handshake)
    /// without triggering persistence (the host persists). Updates the in-memory
    /// cache so `isRitualDay` etc. reflect the correct value.
    func syncDayCount(_ count: Int)
    
    // Debug method for time control
    func setDebugPhase(_ phase: TimePhase)

    /// Jump to a specific subphase (used by the debug button so the
    /// player can step through dawn1→dawn2→day→dusk1… without \
    /// waiting). Implementations defer to `TimeManager.setSubphase`.
    func setDebugSubphase(_ subphase: TimeSubphase)
}
