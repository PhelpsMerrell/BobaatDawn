//
//  TreasuryPile.swift
//  BobaAtDawn
//
//  The visible pile of gems in the oak tree's treasury room. Counts up
//  as gnomes (and the player) drop gems off, and resets to zero each
//  time it crosses the threshold (50 gems). Persists across sessions
//  and syncs to the other player.
//
//  Loaded from BigOakTreeScene.sks under the name `treasury_pile`.
//

import SpriteKit

@objc(TreasuryPile)
final class TreasuryPile: SKNode {

    static let nodeName = "treasury_pile"

    /// Legacy reset threshold. Kept defined so old code paths compile,
    /// but the gnome system no longer wraps the count when it's hit —
    /// the treasury just keeps growing. `playResetCelebration` is
    /// repurposed as the cart-arrival celebration animation.
    static let resetThreshold: Int = 180

    private let pileSprite: SKLabelNode
    private let glowSprite: SKLabelNode
    private let countLabel: SKLabelNode

    // MARK: - State (managed by GnomeManager)
    private(set) var displayedCount: Int = 0

    // MARK: - Init

    override init() {
        pileSprite = SKLabelNode(text: "\u{1F4B0}") // 💰 placeholder for "pile"
        glowSprite = SKLabelNode(text: "\u{2728}") // ✨ sparkle
        countLabel = SKLabelNode(text: "0")
        super.init()
        installChildren()
    }

    required init?(coder aDecoder: NSCoder) {
        pileSprite = SKLabelNode(text: "\u{1F4B0}")
        glowSprite = SKLabelNode(text: "\u{2728}")
        countLabel = SKLabelNode(text: "0")
        super.init(coder: aDecoder)
        installChildren()
    }

    private func installChildren() {
        pileSprite.fontSize = 64
        pileSprite.fontName = "Arial"
        pileSprite.horizontalAlignmentMode = .center
        pileSprite.verticalAlignmentMode = .center
        pileSprite.position = .zero
        pileSprite.zPosition = 0
        addChild(pileSprite)

        glowSprite.fontSize = 36
        glowSprite.fontName = "Arial"
        glowSprite.horizontalAlignmentMode = .center
        glowSprite.verticalAlignmentMode = .center
        glowSprite.position = CGPoint(x: 30, y: 25)
        glowSprite.zPosition = 1
        glowSprite.alpha = 0.0
        addChild(glowSprite)

        countLabel.fontSize = 22
        countLabel.fontName = "AvenirNext-Bold"
        countLabel.fontColor = SKColor(red: 0.95, green: 0.85, blue: 0.4, alpha: 1.0)
        countLabel.horizontalAlignmentMode = .center
        countLabel.verticalAlignmentMode = .top
        countLabel.position = CGPoint(x: 0, y: -42)
        countLabel.zPosition = 2
        addChild(countLabel)

        zPosition = ZLayers.furniture + 1
        name = TreasuryPile.nodeName
        isUserInteractionEnabled = false

        startIdleSparkle()
    }

    // MARK: - Public API

    /// Sync the displayed pile to a count value. Called by GnomeManager
    /// any time the treasury count changes (local deposit or remote sync).
    func setCount(_ count: Int) {
        displayedCount = count
        countLabel.text = "\(count)"

        // Pile grows visually with the count, but visual scale is
        // capped so the emoji doesn't get absurd as the count climbs.
        let visualCapForScale: CGFloat = 200
        let progress = min(CGFloat(count) / visualCapForScale, 1.0)
        let scale = 0.85 + progress * 0.6
        pileSprite.run(SKAction.scale(to: scale, duration: 0.25), withKey: "pile_grow")
    }

    /// Bounce + sparkle when a gem is added.
    func playDepositAnimation() {
        let bounce = SKAction.sequence([
            SKAction.scale(by: 1.12, duration: 0.1),
            SKAction.scale(by: 1.0 / 1.12, duration: 0.18)
        ])
        pileSprite.run(bounce, withKey: "pile_bounce")

        let sparkle = SKAction.sequence([
            SKAction.fadeIn(withDuration: 0.1),
            SKAction.wait(forDuration: 0.2),
            SKAction.fadeOut(withDuration: 0.4)
        ])
        glowSprite.run(sparkle, withKey: "pile_sparkle")
    }

    /// Bigger sparkle burst — used when the cart procession arrives
    /// at the treasury and dumps its full load in one beat. (Originally
    /// fired when the treasury count crossed the threshold; the cap has
    /// been removed but this animation is a perfect fit for the cart
    /// arrival celebration, so it's kept under the same name.)
    func playResetCelebration() {
        // Burst of sparkle around the pile then reset.
        for i in 0..<8 {
            let spark = SKLabelNode(text: "\u{2728}")
            spark.fontSize = 28
            spark.fontName = "Arial"
            spark.horizontalAlignmentMode = .center
            spark.verticalAlignmentMode = .center
            spark.position = .zero
            spark.zPosition = 3
            addChild(spark)
            let angle = (CGFloat(i) / 8.0) * .pi * 2
            let dx = cos(angle) * 110
            let dy = sin(angle) * 110
            let burst = SKAction.sequence([
                SKAction.group([
                    SKAction.move(by: CGVector(dx: dx, dy: dy), duration: 0.6),
                    SKAction.fadeOut(withDuration: 0.6),
                    SKAction.scale(to: 1.4, duration: 0.6)
                ]),
                SKAction.removeFromParent()
            ])
            spark.run(burst)
        }
    }

    // MARK: - Idle Animation

    private func startIdleSparkle() {
        // Subtle slow sparkle every few seconds so the pile feels alive.
        let blink = SKAction.repeatForever(
            SKAction.sequence([
                SKAction.wait(forDuration: 3.5, withRange: 2.0),
                SKAction.fadeAlpha(to: 0.7, duration: 0.4),
                SKAction.fadeAlpha(to: 0.0, duration: 0.6)
            ])
        )
        glowSprite.run(blink, withKey: "pile_idle_sparkle")
    }
}
