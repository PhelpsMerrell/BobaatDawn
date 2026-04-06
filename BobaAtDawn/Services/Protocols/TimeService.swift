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
    
    /// Current day number (incremented each dawn). Persisted across sessions.
    var dayCount: Int { get }
    
    /// Whether today is a ritual day (every 3rd day, starting from day 3).
    var isRitualDay: Bool { get }
    
    func update()
    
    /// Called by the game scene when dawn arrives to advance the day counter.
    func advanceDay()
    
    // Debug method for time control
    func setDebugPhase(_ phase: TimePhase)
}
