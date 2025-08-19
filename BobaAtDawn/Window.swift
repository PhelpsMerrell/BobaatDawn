//
//  Window.swift
//  BobaAtDawn
//
//  Created by Phelps Merrell on 8/18/25.
//

import SpriteKit

// MARK: - Time Window
class Window: SKSpriteNode {
    
    // MARK: - Window Properties
    private let windowSize = CGSize(width: 80, height: 80)
    
    // MARK: - Color Definitions
    private let phaseColors: [TimePhase: SKColor] = [
        .dawn: SKColor(red: 1.0, green: 0.7, blue: 0.8, alpha: 1.0),    // Soft pink
        .day: SKColor(red: 0.7, green: 0.9, blue: 1.0, alpha: 1.0),     // Bright blue
        .dusk: SKColor(red: 1.0, green: 0.6, blue: 0.4, alpha: 1.0),    // Orange
        .night: SKColor(red: 0.2, green: 0.2, blue: 0.6, alpha: 1.0)    // Dark blue
    ]
    
    // MARK: - Current State
    private var currentPhase: TimePhase = .day
    private var targetColor: SKColor
    
    // MARK: - Initialization
    init() {
        self.targetColor = phaseColors[.day] ?? SKColor.white // Start with day color
        
        super.init(texture: nil, color: targetColor, size: windowSize)
        
        setupWindow()
        setupTimeCallbacks()
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Setup
    private func setupWindow() {
        name = "time_window"
        zPosition = 5
        
        // Add subtle border
        let border = SKSpriteNode(color: SKColor(red: 0.4, green: 0.3, blue: 0.2, alpha: 1.0), 
                                 size: CGSize(width: windowSize.width + 4, height: windowSize.height + 4))
        border.zPosition = -1
        border.name = "window_border"
        addChild(border)
        
        print("🪟 Window created at day phase (time starts flowing)")
    }
    
    private func setupTimeCallbacks() {
        // Listen for phase changes
        TimeManager.shared.onPhaseChanged = { [weak self] newPhase in
            self?.transitionToPhase(newPhase)
        }
        
        // Listen for progress updates for smooth transitions
        TimeManager.shared.onProgressUpdated = { [weak self] progress in
            self?.updateTransition(progress: progress)
        }
    }
    
    // MARK: - Color Transitions
    private func transitionToPhase(_ newPhase: TimePhase) {
        currentPhase = newPhase
        
        guard let newColor = phaseColors[newPhase] else {
            print("⚠️ Warning: No color defined for phase \(newPhase)")
            return
        }
        
        targetColor = newColor
        
        // Smooth color transition
        let colorAction = SKAction.colorize(with: newColor, colorBlendFactor: 1.0, duration: 2.0)
        colorAction.timingMode = .easeInEaseOut
        
        run(colorAction)
        
        // Add subtle phase change animation
        let pulseAction = SKAction.sequence([
            SKAction.scale(to: 1.1, duration: 0.5),
            SKAction.scale(to: 1.0, duration: 0.5)
        ])
        pulseAction.timingMode = .easeInEaseOut
        
        run(pulseAction)
        
        print("🪟 Window transitioning to \(newPhase) phase")
    }
    
    private func updateTransition(progress: Float) {
        // For very smooth gradual transitions during long phases
        // This creates subtle color shifts throughout each phase
        
        guard let baseColor = phaseColors[currentPhase] else { return }
        
        // Add subtle brightness variation based on progress through phase
        let brightnessVariation: CGFloat = 0.1 * CGFloat(sin(Double(progress) * .pi))
        
        let adjustedColor = SKColor(
            red: min(1.0, baseColor.redComponent + brightnessVariation),
            green: min(1.0, baseColor.greenComponent + brightnessVariation),
            blue: min(1.0, baseColor.blueComponent + brightnessVariation),
            alpha: baseColor.alphaComponent
        )
        
        // Very subtle, gradual shift
        let subtleAction = SKAction.colorize(with: adjustedColor, colorBlendFactor: 0.3, duration: 1.0)
        run(subtleAction, withKey: "subtle_shift")
    }
    
    // MARK: - Public Interface
    func getCurrentPhase() -> TimePhase {
        return currentPhase
    }
    
    func getCurrentColor() -> SKColor {
        return color
    }
    
    // MARK: - Manual Color Override (for testing)
    func previewPhase(_ phase: TimePhase) {
        guard let previewColor = phaseColors[phase] else { return }
        
        removeAction(forKey: "subtle_shift")
        
        let previewAction = SKAction.colorize(with: previewColor, colorBlendFactor: 1.0, duration: 0.5)
        run(previewAction)
        
        print("🪟 Window previewing \(phase) phase")
    }
    
    func resetToCurrentPhase() {
        transitionToPhase(currentPhase)
    }
}

// MARK: - SKColor Extension for Component Access
extension SKColor {
    var redComponent: CGFloat {
        var red: CGFloat = 0
        getRed(&red, green: nil, blue: nil, alpha: nil)
        return red
    }
    
    var greenComponent: CGFloat {
        var green: CGFloat = 0
        getRed(nil, green: &green, blue: nil, alpha: nil)
        return green
    }
    
    var blueComponent: CGFloat {
        var blue: CGFloat = 0
        getRed(nil, green: nil, blue: &blue, alpha: nil)
        return blue
    }
    
    var alphaComponent: CGFloat {
        var alpha: CGFloat = 0
        getRed(nil, green: nil, blue: nil, alpha: &alpha)
        return alpha
    }
}
