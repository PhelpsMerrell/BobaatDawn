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

// MARK: - Time Manager
final class TimeManager {
    
    // MARK: - State
    private(set) var currentPhase: TimePhase = .day // Start in day, not dawn
    private(set) var isTimeActive: Bool = true // Start flowing immediately
    private(set) var phaseProgress: Float = 0.0 // 0.0 to 1.0 through current phase
    private(set) var isBreakerTripped: Bool = false // Dawn completed, needs player reset
    
    // MARK: - Timing
    private var phaseStartTime: TimeInterval = 0
    private var lastUpdateTime: TimeInterval = 0
    
    // MARK: - Callbacks
    var onPhaseChanged: ((TimePhase) -> Void)?
    var onProgressUpdated: ((Float) -> Void)?
    var onBreakerTripped: (() -> Void)? // Dawn completed
    
    // MARK: - Singleton
    static let shared = TimeManager()
    
    private init() {
        // Start time immediately when created
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
        
        print("🔄 DEBUG: Force setting time phase to \(phase.displayName)")
    }
    
    // Advance to next phase; trips breaker when finishing night -> dawn
    func advancePhase(at time: TimeInterval) {
        switch currentPhase {
        case .dawn:
            currentPhase = .day
        case .day:
            currentPhase = .dusk
        case .dusk:
            currentPhase = .night
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
        
        print("🔄 DEBUG: Time now at \(currentPhase.displayName), active: \(isTimeActive)")
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
