//
//  WasteBin.swift
//  BobaAtDawn
//
//  Where rejected rocks go. Sits next to the mine machine on the cave
//  entrance floor. Loaded from CaveScene.sks under the name `waste_bin`.
//

import SpriteKit

@objc(WasteBin)
final class WasteBin: SKNode {

    static let nodeName = "waste_bin"

    private let body: SKSpriteNode
    private let label: SKLabelNode

    // MARK: - Init

    override init() {
        body = SKSpriteNode(color: SKColor(red: 0.35, green: 0.3, blue: 0.25, alpha: 1.0),
                            size: CGSize(width: 70, height: 80))
        label = SKLabelNode(text: "\u{1F5D1}\u{FE0F}") // 🗑️
        super.init()
        installChildren()
    }

    required init?(coder aDecoder: NSCoder) {
        body = SKSpriteNode(color: SKColor(red: 0.35, green: 0.3, blue: 0.25, alpha: 1.0),
                            size: CGSize(width: 70, height: 80))
        label = SKLabelNode(text: "\u{1F5D1}\u{FE0F}")
        super.init(coder: aDecoder)
        installChildren()
    }

    private func installChildren() {
        body.zPosition = 0
        body.name = "waste_bin_body"
        addChild(body)

        label.fontSize = 40
        label.fontName = "Arial"
        label.horizontalAlignmentMode = .center
        label.verticalAlignmentMode = .center
        label.position = .zero
        label.zPosition = 1
        addChild(label)

        zPosition = ZLayers.furniture + 1
        name = WasteBin.nodeName
        isUserInteractionEnabled = false
    }

    // MARK: - Reactions

    /// Animate a "rock dropped in" beat.
    func acceptRock(completion: (() -> Void)? = nil) {
        let pulse = SKAction.sequence([
            SKAction.scale(to: 1.15, duration: 0.12),
            SKAction.scale(to: 1.0,  duration: 0.18)
        ])
        let done = SKAction.run { completion?() }
        run(SKAction.sequence([pulse, done]), withKey: "waste_bin_accept")
    }
}
