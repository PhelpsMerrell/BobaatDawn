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
    
    func update()
    
    // Debug method for time control
    func setDebugPhase(_ phase: TimePhase)
}
