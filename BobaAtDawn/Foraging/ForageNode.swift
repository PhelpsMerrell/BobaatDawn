//
//  ForageNode.swift
//  BobaAtDawn
//
//  The in-world visual node the player sees and long-presses to pick
//  up a foraged ingredient. Replaces the three near-identical classes
//  MatchaLeaf / StrawberryPlant / CaveMushroom.
//
//  Carries its originating spawnID + ingredient identity so the scene
//  can report a pickup back to ForagingManager and broadcast it.
//

import SpriteKit

final class ForageNode: SKLabelNode {

    // MARK: - Identity

    let spawnID: String
    let ingredient: ForageableIngredient
    let location: SpawnLocation

    // MARK: - Init

    init(spawn: ForageSpawn) {
        self.spawnID = spawn.spawnID
        self.ingredient = spawn.ingredient
        self.location = spawn.location

        super.init()

        text = ingredient.displayEmoji
        fontSize = 26
        fontName = "Arial"
        horizontalAlignmentMode = .center
        verticalAlignmentMode = .center
        position = spawn.position
        zPosition = ZLayers.groundObjects + 2
        name = ForageNode.nodeName
        alpha = 0.0
        setScale(0.0)

        // Slight random tilt for organic feel.
        zRotation = CGFloat.random(in: -0.2...0.2)

        // Spawn-in animation — shared shape, per-ingredient idle loop.
        let appear = SKAction.sequence([
            SKAction.wait(forDuration: Double.random(in: 0.0...0.4)),
            SKAction.group([
                SKAction.fadeIn(withDuration: 0.45),
                SKAction.scale(to: 1.0, duration: 0.45)
            ])
        ])
        appear.timingMode = .easeOut
        run(appear)

        // Per-ingredient idle vibe.
        run(idleAction(for: ingredient), withKey: Self.idleActionKey)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented — ForageNode is spawned in code")
    }

    // MARK: - Pickup

    /// Animate the pickup and remove from the scene. Parent callbacks
    /// handle the ForagingManager bookkeeping and network broadcast.
    func pickUp(completion: @escaping () -> Void) {
        removeAction(forKey: Self.idleActionKey)
        let pickup = SKAction.sequence([
            SKAction.group([
                SKAction.scale(to: 1.4, duration: 0.1),
                SKAction.fadeOut(withDuration: 0.2)
            ]),
            SKAction.removeFromParent(),
            SKAction.run { completion() }
        ])
        run(pickup)
    }

    // MARK: - Idle Loops

    /// Per-ingredient idle animation. Matcha sways, strawberries bob,
    /// mushrooms breathe.
    private func idleAction(for ingredient: ForageableIngredient) -> SKAction {
        switch ingredient {
        case .matchaLeaf:
            return SKAction.repeatForever(
                SKAction.sequence([
                    SKAction.rotate(byAngle:  0.15, duration: 1.8),
                    SKAction.rotate(byAngle: -0.15, duration: 1.8)
                ])
            )

        case .strawberry:
            return SKAction.repeatForever(
                SKAction.sequence([
                    SKAction.moveBy(x: 0, y:  2, duration: 1.2),
                    SKAction.moveBy(x: 0, y: -2, duration: 1.2)
                ])
            )

        case .mushroom:
            return SKAction.repeatForever(
                SKAction.sequence([
                    SKAction.scale(to: 1.05, duration: 1.6),
                    SKAction.scale(to: 0.95, duration: 1.6)
                ])
            )

        case .rock:
            return SKAction.repeatForever(
                SKAction.sequence([
                    SKAction.rotate(byAngle:  0.06, duration: 2.2),
                    SKAction.rotate(byAngle: -0.06, duration: 2.2)
                ])
            )

        case .gem:
            return SKAction.repeatForever(
                SKAction.sequence([
                    SKAction.scale(to: 1.08, duration: 1.1),
                    SKAction.scale(to: 0.96, duration: 1.1)
                ])
            )
        }
    }

    // MARK: - Constants

    static let nodeName = "forage_node"
    private static let idleActionKey = "forage_idle"
}
