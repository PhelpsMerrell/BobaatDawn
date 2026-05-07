//
//  TimeManager.swift
//  BobaAtDawn
//
//  Created by Phelps Merrell on 8/18/25.
//

import Foundation

// MARK: - Time Phase Definition
enum TimePhase: CaseIterable {
    case dawn, day, dusk, night
    
    var duration: TimeInterval {
        switch self {
        case .dawn: return GameConfig.Time.dawnDuration
        case .day: return GameConfig.Time.dayDuration
        case .dusk: return GameConfig.Time.duskDuration
        case .night: return GameConfig.Time.nightDuration
        }
    }
    
    var displayName: String {
        switch self {
        case .dawn: return "dawn"
        case .day: return "day"
        case .dusk: return "dusk"
        case .night: return "night"
        }
    }
}

// MARK: - Time Subphase

/// Finer-grained time slices used by the gnome simulation. Each
/// subphase is a contiguous range within a `TimePhase`.
///   Dawn  splits 50/50 — Dawn 1 (breakfast), Dawn 2 (cleanup + cart return).
///   Day   has no subphases (single Day).
///   Dusk  splits 25/25/25/25 — mine prep, cart travel, treasury, dinner.
///   Night has no subphases (single Night).
enum TimeSubphase: String, CaseIterable {
    case dawn1
    case dawn2
    case day
    case dusk1
    case dusk2
    case dusk3
    case dusk4
    case night

    /// The parent phase this subphase belongs to.
    var phase: TimePhase {
        switch self {
        case .dawn1, .dawn2: return .dawn
        case .day:           return .day
        case .dusk1, .dusk2, .dusk3, .dusk4: return .dusk
        case .night:         return .night
        }
    }

    /// Where this subphase starts within its phase, as a fraction.
    var startFraction: Float {
        switch self {
        case .dawn1, .day, .dusk1, .night: return 0.0
        case .dawn2: return 0.5
        case .dusk2: return 0.25
        case .dusk3: return 0.5
        case .dusk4: return 0.75
        }
    }

    /// Where this subphase ends within its phase, as a fraction.
    var endFraction: Float {
        switch self {
        case .dawn1: return 0.5
        case .dawn2, .day, .dusk4, .night: return 1.0
        case .dusk1: return 0.25
        case .dusk2: return 0.5
        case .dusk3: return 0.75
        }
    }

    /// Short human-readable label for the time-control button.
    var displayName: String {
        switch self {
        case .dawn1: return "Dawn 1 \u{2014} Breakfast"
        case .dawn2: return "Dawn 2 \u{2014} Cleanup"
        case .day:   return "Day"
        case .dusk1: return "Dusk 1 \u{2014} Mine Prep"
        case .dusk2: return "Dusk 2 \u{2014} Cart Travel"
        case .dusk3: return "Dusk 3 \u{2014} Treasury"
        case .dusk4: return "Dusk 4 \u{2014} Dinner"
        case .night: return "Night"
        }
    }

    /// Cycle to the next subphase in the user-facing tap order.
    var next: TimeSubphase {
        switch self {
        case .dawn1: return .dawn2
        case .dawn2: return .day
        case .day:   return .dusk1
        case .dusk1: return .dusk2
        case .dusk2: return .dusk3
        case .dusk3: return .dusk4
        case .dusk4: return .night
        case .night: return .dawn1
        }
    }

    /// Compute the active subphase for a given (phase, phaseProgress).
    static func from(phase: TimePhase, progress: Float) -> TimeSubphase {
        switch phase {
        case .dawn:  return progress < 0.5 ? .dawn1 : .dawn2
        case .day:   return .day
        case .dusk:
            if progress < 0.25 { return .dusk1 }
            if progress < 0.50 { return .dusk2 }
            if progress < 0.75 { return .dusk3 }
            return .dusk4
        case .night: return .night
        }
    }
}

// MARK: - Time Manager
final class TimeManager {
    
    // MARK: - State
    private(set) var currentPhase: TimePhase = .day
    private(set) var isTimeActive: Bool = true
    private(set) var phaseProgress: Float = 0.0
    private(set) var isBreakerTripped: Bool = false
    
    // MARK: - Timing
    private var phaseStartTime: TimeInterval = 0
    private var lastUpdateTime: TimeInterval = 0
    
    // MARK: - Callbacks
    var onPhaseChanged: ((TimePhase) -> Void)?
    var onProgressUpdated: ((Float) -> Void)?
    var onBreakerTripped: (() -> Void)?
    
    // MARK: - Singleton
    static let shared = TimeManager()
    
    private init() {
        let currentTime = CFAbsoluteTimeGetCurrent()
        start(at: currentTime)
    }
    
    // MARK: - Public Controls
    func start(at time: TimeInterval) {
        phaseStartTime = time
        lastUpdateTime = time
        isTimeActive = true
        isBreakerTripped = false
        phaseProgress = 0
        onProgressUpdated?(phaseProgress)
    }
    
    func pause() {
        isTimeActive = false
    }
    
    func resume(at time: TimeInterval) {
        isTimeActive = true
        lastUpdateTime = time
    }
    
    func setPhase(_ phase: TimePhase, at time: TimeInterval) {
        currentPhase = phase
        phaseStartTime = time
        lastUpdateTime = time
        phaseProgress = 0
        isBreakerTripped = false
        onPhaseChanged?(phase)
        onProgressUpdated?(phaseProgress)
        
        Log.debug(.time, "Force setting time phase to \(phase.displayName)")
    }

    /// Jump straight to a specific subphase. Sets the parent phase and
    /// rewinds `phaseStartTime` so `phaseProgress` lands at the
    /// subphase's `startFraction`. Useful for testing dusk phase 3 etc.
    /// without sitting through the prior beats.
    func setSubphase(_ subphase: TimeSubphase, at time: TimeInterval) {
        let phase = subphase.phase
        currentPhase = phase
        // Rewind phaseStartTime so that progress = startFraction now.
        let offset = TimeInterval(subphase.startFraction) * phase.duration
        phaseStartTime = time - offset
        lastUpdateTime = time
        phaseProgress = subphase.startFraction
        isBreakerTripped = false
        onPhaseChanged?(phase)
        onProgressUpdated?(phaseProgress)

        Log.debug(.time, "Force setting subphase to \(subphase.rawValue) (phase=\(phase.displayName), progress=\(phaseProgress))")
    }

    // MARK: - Subphase Accessors

    /// Current subphase derived from `(currentPhase, phaseProgress)`.
    var currentSubphase: TimeSubphase {
        TimeSubphase.from(phase: currentPhase, progress: phaseProgress)
    }

    /// Progress (0..1) within the *current subphase*. e.g. if we're at
    /// 60% of dawn (dawn2 spans 50-100%), this returns 0.2.
    var subphaseProgress: Float {
        let sp = currentSubphase
        let span = max(0.0001, sp.endFraction - sp.startFraction)
        let local = (phaseProgress - sp.startFraction) / span
        return max(0, min(1, local))
    }
    
    // Advance to next phase; trips breaker when finishing night -> dawn
    func advancePhase(at time: TimeInterval) {
        switch currentPhase {
        case .dawn:  currentPhase = .day
        case .day:   currentPhase = .dusk
        case .dusk:  currentPhase = .night
        case .night:
            currentPhase = .dawn
            isBreakerTripped = true
            onBreakerTripped?()
        }
        
        phaseStartTime = time
        lastUpdateTime = time
        phaseProgress = 0
        onPhaseChanged?(currentPhase)
        onProgressUpdated?(phaseProgress)
        
        Log.info(.time, "Phase advanced to \(currentPhase.displayName)")
    }
    
    // MARK: - Update Loop
    func update(currentTime: TimeInterval) {
        guard isTimeActive else { return }
        
        let dt = currentTime - lastUpdateTime
        lastUpdateTime = currentTime
        guard dt >= 0 else { return }
        
        let duration = currentPhase.duration
        let elapsed = currentTime - phaseStartTime
        let rawProgress = max(0, min(1, elapsed / duration))
        phaseProgress = Float(rawProgress)
        onProgressUpdated?(phaseProgress)
        
        if elapsed >= duration {
            advancePhase(at: currentTime)
        }
    }
}
