//
//  StandardTimeService.swift
//  BobaAtDawn
//
//  Standard implementation of TimeService wrapping TimeManager
//

import Foundation

class StandardTimeService: TimeService {
    
    var currentPhase: TimePhase {
        return TimeManager.shared.currentPhase
    }
    
    var phaseProgress: Float {
        return TimeManager.shared.phaseProgress
    }
    
    var isTimeActive: Bool {
        return TimeManager.shared.isTimeActive
    }
    
    func update() {
        TimeManager.shared.update()
    }
}
