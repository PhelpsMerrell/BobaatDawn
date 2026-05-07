//
//  TimeControlButton.swift
//  BobaAtDawn
//
//  Debug button for advancing time phases during development.
//
//  This used to be a small circular ⏰ button that long-pressed to
//  advance one phase at a time, host-only. The redesign:
//
//    * Horizontal pill (~180×44) showing the current SUBPHASE name and
//      a percentage progress through that subphase.
//    * Background gradient interpolates across a 24-hour palette
//      (deep navy at midnight → peach at dawn → warm yellow at noon →
//      coral at dusk → fading back to navy at night). The fill updates
//      every frame so the button visibly tracks the day/night cycle.
//    * Tap = advance ONE subphase forward (dawn1 → dawn2 → day →
//      dusk1 → dusk2 → dusk3 → dusk4 → night → dawn1).
//    * Long-press = same as tap (kept so muscle memory survives).
//    * EITHER player can drive it. Host applies locally and broadcasts
//      `timeSubphaseRequest`; guest sends `timeSubphaseRequest` and
//      waits for the host's echo before mutating local time state.
//      This keeps the simulation host-authoritative while still letting
//      the guest control time.
//

import SpriteKit
import Foundation

// MARK: - Time Control Button
class TimeControlButton: SKNode {

    private let buttonSize = CGSize(width: 200, height: 44)

    private let background: SKShapeNode
    private let topLabel: SKLabelNode      // subphase name
    private let bottomLabel: SKLabelNode   // percentage progress

    private weak var timeService: TimeService?

    // MARK: - Initialization

    init(timeService: TimeService) {
        self.timeService = timeService

        // Rounded rectangle background; we set fillColor every frame.
        background = SKShapeNode(rectOf: buttonSize, cornerRadius: 10)
        background.name = "time_control_button"
        background.lineWidth = 1.5
        background.strokeColor = SKColor.white.withAlphaComponent(0.35)
        background.fillColor = SKColor(red: 0.2, green: 0.3, blue: 0.5, alpha: 0.9)

        // Subphase name (top line).
        topLabel = SKLabelNode(fontNamed: "AvenirNext-DemiBold")
        topLabel.fontSize = 12
        topLabel.fontColor = .white
        topLabel.verticalAlignmentMode = .center
        topLabel.horizontalAlignmentMode = .center
        topLabel.position = CGPoint(x: 0, y: 8)

        // Percentage (bottom line, smaller).
        bottomLabel = SKLabelNode(fontNamed: "AvenirNext-Regular")
        bottomLabel.fontSize = 10
        bottomLabel.fontColor = SKColor.white.withAlphaComponent(0.8)
        bottomLabel.verticalAlignmentMode = .center
        bottomLabel.horizontalAlignmentMode = .center
        bottomLabel.position = CGPoint(x: 0, y: -8)

        super.init()

        addChild(background)
        addChild(topLabel)
        addChild(bottomLabel)

        isUserInteractionEnabled = true
        zPosition = 1000  // Always on top

        updateButtonAppearance()
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Visual Updates

    /// Called every frame from GameScene's update loop via `update()`.
    func update() {
        updateButtonAppearance()
    }

    private func updateButtonAppearance() {
        guard let timeService = timeService else { return }
        let subphase = timeService.currentSubphase
        let pct = Int((timeService.subphaseProgress * 100).rounded())

        topLabel.text = subphase.displayName
        bottomLabel.text = "\(pct)%"
        background.fillColor = gradientColor(
            for: timeService.currentPhase,
            phaseProgress: timeService.phaseProgress
        )
    }

    /// 24-hour palette. We treat the day as a circle and pick a color
    /// by interpolating between phase anchors:
    ///
    ///   dawn  start -> #1E2845 (deep navy)
    ///   dawn  end   -> #FCC78A (peach)
    ///   day   start -> #FCC78A (peach)
    ///   day   end   -> #FFF1A8 (warm yellow)
    ///   dusk  start -> #FFF1A8 (warm yellow)
    ///   dusk  end   -> #E2725B (coral)
    ///   night start -> #E2725B (coral)
    ///   night end   -> #1E2845 (deep navy)
    ///
    /// Within a phase we lerp linearly between the start and end
    /// anchors using `phaseProgress`. The result is a smooth fill that
    /// always reflects roughly where in the day cycle we are.
    private func gradientColor(for phase: TimePhase, phaseProgress: Float) -> SKColor {
        let t = CGFloat(max(0, min(1, phaseProgress)))
        let (a, b) = anchors(for: phase)
        return lerpColor(from: a, to: b, t: t)
    }

    private func anchors(for phase: TimePhase) -> (SKColor, SKColor) {
        let navy = SKColor(red: 0.118, green: 0.157, blue: 0.271, alpha: 0.95)   // #1E2845
        let peach = SKColor(red: 0.988, green: 0.780, blue: 0.541, alpha: 0.95)  // #FCC78A
        let warm = SKColor(red: 1.000, green: 0.945, blue: 0.659, alpha: 0.95)   // #FFF1A8
        let coral = SKColor(red: 0.886, green: 0.447, blue: 0.357, alpha: 0.95)  // #E2725B

        switch phase {
        case .dawn:  return (navy,  peach)
        case .day:   return (peach, warm)
        case .dusk:  return (warm,  coral)
        case .night: return (coral, navy)
        }
    }

    private func lerpColor(from a: SKColor, to b: SKColor, t: CGFloat) -> SKColor {
        var ar: CGFloat = 0, ag: CGFloat = 0, ab: CGFloat = 0, aa: CGFloat = 0
        var br: CGFloat = 0, bg: CGFloat = 0, bb: CGFloat = 0, ba: CGFloat = 0
        a.getRed(&ar, green: &ag, blue: &ab, alpha: &aa)
        b.getRed(&br, green: &bg, blue: &bb, alpha: &ba)
        return SKColor(
            red:   ar + (br - ar) * t,
            green: ag + (bg - ag) * t,
            blue:  ab + (bb - ab) * t,
            alpha: aa + (ba - aa) * t
        )
    }

    // MARK: - Touch Handling

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        let press = SKAction.scale(to: 0.96, duration: 0.08)
        background.run(press)
        let impact = UIImpactFeedbackGenerator(style: .light)
        impact.impactOccurred()
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        let release = SKAction.scale(to: 1.0, duration: 0.08)
        background.run(release)
        advanceSubphase()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        let release = SKAction.scale(to: 1.0, duration: 0.08)
        background.run(release)
    }

    // MARK: - Time Control

    /// Advance one subphase forward and broadcast to the partner.
    /// Either player can call this; the message handler in
    /// GameScene+Multiplayer applies the change on whichever side
    /// receives it.
    private func advanceSubphase() {
        guard let timeService = timeService else { return }
        let next = timeService.currentSubphase.next

        let impact = UIImpactFeedbackGenerator(style: .medium)
        impact.impactOccurred()

        if MultiplayerService.shared.isConnected && MultiplayerService.shared.isGuest {
            // Guest: send a request and wait for the host's echo. Don't
            // mutate local time state directly — the world is host-
            // authoritative, and applying it locally before the host
            // confirms can flicker the gnome simulation when the next
            // host timeSync arrives.
            MultiplayerService.shared.send(
                type: .timeSubphaseRequest,
                payload: TimeSubphaseRequestMessage(
                    subphaseRawValue: next.rawValue,
                    dayCount: timeService.dayCount
                )
            )
            Log.info(.time, "Guest requested subphase \(next.rawValue) from host")
            createTimeAdvanceEffect()
            return
        }

        // Host (or solo): apply locally and broadcast to the guest.
        timeService.setDebugSubphase(next)
        if MultiplayerService.shared.isHost && MultiplayerService.shared.isConnected {
            MultiplayerService.shared.send(
                type: .timeSubphaseRequest,
                payload: TimeSubphaseRequestMessage(
                    subphaseRawValue: next.rawValue,
                    dayCount: timeService.dayCount
                )
            )
        }

        Log.info(.time, "Advanced subphase to \(next.rawValue)")
        createTimeAdvanceEffect()
        updateButtonAppearance()
    }

    // MARK: - Visual Effects

    private func createTimeAdvanceEffect() {
        // Brief pulse on the button itself.
        let flash = SKAction.sequence([
            SKAction.fadeAlpha(to: 0.5, duration: 0.05),
            SKAction.fadeAlpha(to: 1.0, duration: 0.05),
            SKAction.fadeAlpha(to: 0.5, duration: 0.05),
            SKAction.fadeAlpha(to: 1.0, duration: 0.05)
        ])
        topLabel.run(flash)
        bottomLabel.run(flash)

        // Ripple — a rounded outline expanding outward from the pill.
        let ripple = SKShapeNode(rectOf: buttonSize, cornerRadius: 10)
        ripple.strokeColor = SKColor.white.withAlphaComponent(0.6)
        ripple.lineWidth = 2
        ripple.fillColor = .clear
        ripple.zPosition = -1
        addChild(ripple)

        let expand = SKAction.scale(to: 1.6, duration: 0.5)
        let fade = SKAction.fadeOut(withDuration: 0.5)
        let remove = SKAction.removeFromParent()
        ripple.run(SKAction.sequence([
            SKAction.group([expand, fade]),
            remove
        ]))
    }

    // MARK: - Debug Info
    func printStatus() {
        guard let timeService = timeService else { return }
        print("⏰ === TIME CONTROL STATUS ===")
        print("⏰ Phase:    \(timeService.currentPhase.displayName) — \(Int(timeService.phaseProgress * 100))%")
        print("⏰ Subphase: \(timeService.currentSubphase.rawValue) — \(Int(timeService.subphaseProgress * 100))%")
        print("⏰ =============================")
    }
}
