//
//  StandardTimeService.swift
//  BobaAtDawn
//
//  Standard implementation of TimeService wrapping TimeManager
//

import Foundation

class StandardTimeService: TimeService {
    
    // MARK: - Phase Access
    var currentPhase: TimePhase {
        return TimeManager.shared.currentPhase
    }
    
    var phaseProgress: Float {
        return TimeManager.shared.phaseProgress
    }
    
    var isTimeActive: Bool {
        return TimeManager.shared.isTimeActive
    }
    
    // MARK: - Day Counter (persisted via SaveService)
    
    /// Runtime cache of the day count so we don't hit SwiftData every frame.
    private var _dayCount: Int
    
    var dayCount: Int { _dayCount }
    
    /// Ritual triggers every Nth day, per GameConfig.Ritual.ritualDayInterval.
    var isRitualDay: Bool {
        return _dayCount > 0 && _dayCount % GameConfig.Ritual.ritualDayInterval == 0
    }
    
    // MARK: - Init
    init() {
        // Load persisted day count on startup
        let worldState = SaveService.shared.loadGameState()
        _dayCount = worldState?.dayCount ?? 0
        Log.info(.time, "TimeService loaded dayCount: \(_dayCount)")
    }
    
    // MARK: - Update
    func update() {
        let currentTime = CFAbsoluteTimeGetCurrent()
        TimeManager.shared.update(currentTime: currentTime)
    }
    
    // MARK: - Day Advancement
    /// Call once when night → dawn transition occurs.
    func advanceDay() {
        _dayCount += 1
        
        // Persist immediately
        SaveService.shared.setDayCount(_dayCount)
        
        Log.info(.time, "NEW DAY \(_dayCount) — ritual day: \(isRitualDay)")
    }
    
    /// Update the runtime day count cache from a network source.
    /// Does NOT persist — the host owns persistence.
    func syncDayCount(_ count: Int) {
        guard count != _dayCount else { return }
        _dayCount = count
        Log.info(.time, "Day count synced from network: \(_dayCount) — ritual day: \(isRitualDay)")
    }
    
    // MARK: - Debug
    func setDebugPhase(_ phase: TimePhase) {
        let currentTime = CFAbsoluteTimeGetCurrent()
        TimeManager.shared.setPhase(phase, at: currentTime)
    }
}
