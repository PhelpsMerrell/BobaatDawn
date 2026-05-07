//
//  MineMachine.swift
//  BobaAtDawn
//
//  The heart of the mining loop. Players (or gnomes) feed it a rock;
//  it flashes green or red. Green → produces a gem. Red → the rock is
//  rejected and sent to the waste bin.
//
//  The verdict is computed deterministically from the rock's spawn ID
//  and the current day count, so both clients (host + guest) reach the
//  same answer without an extra round trip.
//
//  Visual is placeholder: a labeled box that turns green or red briefly.
//  Replace with real Sprite2D art via SKS later — the node is loaded
//  from CaveScene.sks under the name `mine_machine`.
//

import SpriteKit

@objc(MineMachine)
final class MineMachine: SKNode {

    // MARK: - Visual Constants
    static let nodeName = "mine_machine"

    private let body: SKSpriteNode
    private let label: SKLabelNode

    // MARK: - Color States
    private static let idleColor = SKColor(red: 0.55, green: 0.55, blue: 0.6, alpha: 1.0)
    private static let greenColor = SKColor(red: 0.3, green: 0.85, blue: 0.4, alpha: 1.0)
    private static let redColor   = SKColor(red: 0.9,  green: 0.3,  blue: 0.3, alpha: 1.0)

    // MARK: - Init

    override init() {
        body = SKSpriteNode(color: MineMachine.idleColor, size: CGSize(width: 110, height: 90))
        label = SKLabelNode(text: "\u{2699}\u{FE0F}") // ⚙️
        super.init()

        body.zPosition = 0
        body.name = "mine_machine_body"
        addChild(body)

        label.fontSize = 44
        label.fontName = "Arial"
        label.horizontalAlignmentMode = .center
        label.verticalAlignmentMode = .center
        label.position = .zero
        label.zPosition = 1
        addChild(label)

        zPosition = ZLayers.furniture + 2
        name = MineMachine.nodeName
        isUserInteractionEnabled = false // CaveScene handles long-press
    }

    required init?(coder aDecoder: NSCoder) {
        // Loaded from .sks. SKS-side node should be a plain SKNode named
        // `mine_machine`; we install our own visual children at runtime.
        body = SKSpriteNode(color: MineMachine.idleColor, size: CGSize(width: 110, height: 90))
        label = SKLabelNode(text: "\u{2699}\u{FE0F}")
        super.init(coder: aDecoder)

        body.zPosition = 0
        body.name = "mine_machine_body"
        addChild(body)

        label.fontSize = 44
        label.fontName = "Arial"
        label.horizontalAlignmentMode = .center
        label.verticalAlignmentMode = .center
        label.position = .zero
        label.zPosition = 1
        addChild(label)

        zPosition = ZLayers.furniture + 2
        name = MineMachine.nodeName
    }

    // MARK: - Verdict Logic

    /// Compute the verdict for a rock spawn ID on a given day. True =
    /// green (gem produced). False = red (rock rejected). Hash-based and
    /// fully deterministic so host and guest always agree.
    static func verdict(for rockID: String, dayCount: Int) -> Bool {
        let key = "\(rockID)#\(dayCount)"
        var hash: UInt64 = 14695981039346656037 // FNV offset basis
        for byte in key.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1099511628211 // FNV prime
        }
        // 50% chance — flip on the low bit. Could be tuned later (e.g.
        // 60% to make the loop feel rewarding) but 50% matches the
        // user's "green or red" framing.
        return (hash & 1) == 0
    }

    // MARK: - Visual Reactions

    /// Run the green-flash animation. Caller should also spawn a gem in
    /// the consumer's hand (player or gnome).
    func flashGreen(completion: (() -> Void)? = nil) {
        flash(color: MineMachine.greenColor, completion: completion)
    }

    /// Run the red-flash animation. Caller should send the rock to the bin.
    func flashRed(completion: (() -> Void)? = nil) {
        flash(color: MineMachine.redColor, completion: completion)
    }

    private func flash(color: SKColor, completion: (() -> Void)?) {
        body.removeAction(forKey: "machine_flash")
        let toColor = SKAction.colorize(with: color, colorBlendFactor: 1.0, duration: 0.15)
        let hold    = SKAction.wait(forDuration: 0.6)
        let revert  = SKAction.colorize(with: MineMachine.idleColor, colorBlendFactor: 1.0, duration: 0.4)
        let pulse   = SKAction.sequence([
            SKAction.scale(to: 1.12, duration: 0.12),
            SKAction.scale(to: 1.0,  duration: 0.18)
        ])
        let group   = SKAction.group([
            SKAction.sequence([toColor, hold, revert]),
            pulse
        ])
        let done = SKAction.run { completion?() }
        body.run(SKAction.sequence([group, done]), withKey: "machine_flash")
    }
}
