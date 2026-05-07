//
//  MineCart.swift
//  BobaAtDawn
//
//  Lightweight cart visual used by the gnome haul sequence. The
//  manager creates and attaches it to whichever room scene currently
//  hosts the cart.
//

import SpriteKit

@objc(MineCart)
final class MineCart: SKNode {

    static let nodeName = "mine_cart"

    private let body: SKSpriteNode
    private let cargo: SKLabelNode
    private let countLabel: SKLabelNode
    private let wheelLeft: SKShapeNode
    private let wheelRight: SKShapeNode

    private(set) var displayedCount: Int = 0

    override init() {
        body = SKSpriteNode(
            color: SKColor(red: 0.45, green: 0.29, blue: 0.15, alpha: 1.0),
            size: CGSize(width: 92, height: 34)
        )
        cargo = SKLabelNode(text: "\u{1F48E}")
        countLabel = SKLabelNode(text: "0")
        wheelLeft = SKShapeNode(circleOfRadius: 9)
        wheelRight = SKShapeNode(circleOfRadius: 9)
        super.init()
        installChildren()
    }

    required init?(coder aDecoder: NSCoder) {
        body = SKSpriteNode(
            color: SKColor(red: 0.45, green: 0.29, blue: 0.15, alpha: 1.0),
            size: CGSize(width: 92, height: 34)
        )
        cargo = SKLabelNode(text: "\u{1F48E}")
        countLabel = SKLabelNode(text: "0")
        wheelLeft = SKShapeNode(circleOfRadius: 9)
        wheelRight = SKShapeNode(circleOfRadius: 9)
        super.init(coder: aDecoder)
        installChildren()
    }

    private func installChildren() {
        let accent = SKColor(red: 0.67, green: 0.47, blue: 0.24, alpha: 1.0)
        let wheelColor = SKColor(red: 0.18, green: 0.16, blue: 0.15, alpha: 1.0)

        body.zPosition = 1
        body.name = "mine_cart_body"
        addChild(body)

        let lip = SKSpriteNode(color: accent, size: CGSize(width: 92, height: 6))
        lip.position = CGPoint(x: 0, y: 14)
        lip.zPosition = 2
        addChild(lip)

        let handle = SKSpriteNode(color: accent, size: CGSize(width: 32, height: 4))
        handle.position = CGPoint(x: 54, y: 6)
        handle.zRotation = 0.35
        handle.zPosition = 0
        addChild(handle)

        configureWheel(wheelLeft, color: wheelColor, position: CGPoint(x: -24, y: -22))
        configureWheel(wheelRight, color: wheelColor, position: CGPoint(x: 24, y: -22))

        cargo.fontSize = 28
        cargo.fontName = "Arial"
        cargo.horizontalAlignmentMode = .center
        cargo.verticalAlignmentMode = .center
        cargo.position = CGPoint(x: 0, y: 6)
        cargo.zPosition = 3
        addChild(cargo)

        countLabel.fontSize = 18
        countLabel.fontName = "AvenirNext-Bold"
        countLabel.fontColor = SKColor(red: 0.95, green: 0.89, blue: 0.45, alpha: 1.0)
        countLabel.horizontalAlignmentMode = .center
        countLabel.verticalAlignmentMode = .top
        countLabel.position = CGPoint(x: 0, y: -38)
        countLabel.zPosition = 3
        addChild(countLabel)

        zPosition = ZLayers.npcs - 1
        name = MineCart.nodeName
        isUserInteractionEnabled = false

        setCount(0, animated: false)
    }

    private func configureWheel(_ wheel: SKShapeNode, color: SKColor, position: CGPoint) {
        wheel.fillColor = color
        wheel.strokeColor = color
        wheel.lineWidth = 1.5
        wheel.position = position
        wheel.zPosition = 0

        let hub = SKShapeNode(circleOfRadius: 2.5)
        hub.fillColor = .lightGray
        hub.strokeColor = .lightGray
        hub.lineWidth = 0
        hub.zPosition = 1
        wheel.addChild(hub)

        addChild(wheel)
    }

    func setCount(_ count: Int, animated: Bool) {
        let clamped = max(0, count)
        let grew = clamped > displayedCount
        displayedCount = clamped

        countLabel.text = "\(clamped)"
        cargo.alpha = clamped > 0 ? 1.0 : 0.25

        let visualCap: CGFloat = 24
        let progress = min(CGFloat(clamped) / visualCap, 1.0)
        let bodyScale = 1.0 + (progress * 0.18)
        let cargoScale = 0.9 + (progress * 0.35)

        if animated {
            body.run(SKAction.scale(to: bodyScale, duration: 0.18), withKey: "cart_scale")
            cargo.run(SKAction.scale(to: cargoScale, duration: 0.18), withKey: "cargo_scale")

            if grew {
                let pulse = SKAction.sequence([
                    SKAction.scale(to: 1.12, duration: 0.08),
                    SKAction.scale(to: 1.0, duration: 0.16)
                ])
                countLabel.run(pulse, withKey: "count_pulse")
            }
        } else {
            body.setScale(bodyScale)
            cargo.setScale(cargoScale)
        }
    }

    func startRolling() {
        guard action(forKey: "cart_bob") == nil else { return }

        let spin = SKAction.repeatForever(SKAction.rotate(byAngle: -.pi * 2, duration: 0.4))
        wheelLeft.run(spin, withKey: "wheel_spin")
        wheelRight.run(spin, withKey: "wheel_spin")

        let bob = SKAction.repeatForever(
            SKAction.sequence([
                SKAction.moveBy(x: 0, y: 3, duration: 0.16),
                SKAction.moveBy(x: 0, y: -3, duration: 0.16)
            ])
        )
        run(bob, withKey: "cart_bob")
    }

    func stopRolling() {
        removeAction(forKey: "cart_bob")
        wheelLeft.removeAction(forKey: "wheel_spin")
        wheelRight.removeAction(forKey: "wheel_spin")
        position = CGPoint(x: position.x, y: round(position.y))
    }

    func playDumpCelebration() {
        let hop = SKAction.sequence([
            SKAction.moveBy(x: 0, y: 14, duration: 0.12),
            SKAction.moveBy(x: 0, y: -14, duration: 0.18)
        ])
        run(hop, withKey: "dump_hop")

        for index in 0..<6 {
            let spark = SKLabelNode(text: "\u{2728}")
            spark.fontSize = 20
            spark.fontName = "Arial"
            spark.horizontalAlignmentMode = .center
            spark.verticalAlignmentMode = .center
            spark.position = CGPoint(x: 0, y: 8)
            spark.zPosition = 4
            addChild(spark)

            let angle = (CGFloat(index) / 6.0) * .pi * 2
            let dx = cos(angle) * 70
            let dy = sin(angle) * 45 + 18
            let burst = SKAction.sequence([
                SKAction.group([
                    SKAction.moveBy(x: dx, y: dy, duration: 0.45),
                    SKAction.fadeOut(withDuration: 0.45),
                    SKAction.scale(to: 1.3, duration: 0.45)
                ]),
                SKAction.removeFromParent()
            ])
            spark.run(burst)
        }
    }
}
