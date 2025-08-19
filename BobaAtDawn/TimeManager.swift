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
        case .dawn: return 4 * 60  // 4 minutes
        case .day: return 12 * 60  // 12 minutes
        case .dusk: return 4 * 60  // 4 minutes
        case .night: return 12 * 60 // 12 minutes
        }
    }
    
    var nextPhase: TimePhase {
        let allPhases = TimePhase.allCases
        guard let currentIndex = allPhases.firstIndex(of: self) else { return .dawn }
        let nextIndex = (currentIndex + 1) % allPhases.count
        return allPhases[nextIndex]
    }
}

// MARK: - Time Manager
class TimeManager {
    
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
        phaseStartTime = CFAbsoluteTimeGetCurrent()
        lastUpdateTime = phaseStartTime
    }
    
    // MARK: - Public Interface
    func advanceFromDawn() {
        guard currentPhase == .dawn && isBreakerTripped else { return }
        
        // Reset breaker and advance to day
        isBreakerTripped = false
        isTimeActive = true
        advanceToNextPhase() // Dawn → Day
        
        print("⏰ Breaker reset! Advancing from Dawn to Day")
    }
    
    func update() {
        guard isTimeActive else { return }
        
        let currentTime = CFAbsoluteTimeGetCurrent()
        let elapsedInPhase = currentTime - phaseStartTime
        let phaseDuration = currentPhase.duration
        
        // Update progress (0.0 to 1.0)
        phaseProgress = Float(min(elapsedInPhase / phaseDuration, 1.0))
        onProgressUpdated?(phaseProgress)
        
        // Check if phase should advance
        if elapsedInPhase >= phaseDuration {
            if currentPhase == .dawn {
                // Dawn completed - trip breaker, stop time
                tripBreaker()
            } else {
                // Normal phase transition
                advanceToNextPhase()
            }
        }
        
        lastUpdateTime = currentTime
    }
    
    // MARK: - Private Methods
    private func tripBreaker() {
        isTimeActive = false
        isBreakerTripped = true
        phaseProgress = 1.0
        
        print("🔴 Dawn cycle complete! Breaker tripped - player must advance to continue")
        onBreakerTripped?()
    }
    
    private func advanceToNextPhase() {
        let previousPhase = currentPhase
        currentPhase = currentPhase.nextPhase
        phaseStartTime = CFAbsoluteTimeGetCurrent()
        phaseProgress = 0.0
        
        print("🌅 Phase transition: \(previousPhase) → \(currentPhase)")
        onPhaseChanged?(currentPhase)
        onProgressUpdated?(phaseProgress)
    }
    
    // MARK: - Utility
    func getRemainingTimeInPhase() -> TimeInterval {
        guard isTimeActive else { return currentPhase.duration }
        
        let currentTime = CFAbsoluteTimeGetCurrent()
        let elapsedInPhase = currentTime - phaseStartTime
        return max(0, currentPhase.duration - elapsedInPhase)
    }
    
    func getTotalCycleDuration() -> TimeInterval {
        return TimePhase.allCases.reduce(0) { $0 + $1.duration }
    }
    
    // MARK: - Debug
    func getPhaseInfo() -> String {
        let remaining = getRemainingTimeInPhase()
        let progress = Int(phaseProgress * 100)
        return "\(currentPhase) - \(progress)% - \(Int(remaining))s remaining"
    }
}
