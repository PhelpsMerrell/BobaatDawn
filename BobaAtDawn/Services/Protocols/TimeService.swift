//
//  TimeService.swift
//  BobaAtDawn
//
//  Service protocol for time management
//

import Foundation

protocol TimeService {
    var currentPhase: TimePhase { get }
    var phaseProgress: Float { get }
    var isTimeActive: Bool { get }
    
    func update()
}
