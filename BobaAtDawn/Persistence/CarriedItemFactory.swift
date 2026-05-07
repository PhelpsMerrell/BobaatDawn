//
//  CarriedItemFactory.swift
//  BobaAtDawn
//
//  Reconstructs a carriable RotatableObject from a persisted CarryContent,
//  so the player's in-hand item survives scene transitions + app restarts.
//
//  Ingredient cases are delegated to ForageableIngredient.makeCarriable()
//  so any new forageable added there automatically round-trips through
//  save/load without touching this file.
//

import SpriteKit

enum CarriedItemFactory {

    /// Build a fresh RotatableObject suitable for Character.pickupItem
    /// from a persisted carry state. Returns nil for `.none`.
    static func makeItem(for content: CarryContent) -> RotatableObject? {
        switch content {
        case .none:
            return nil

        case let .ingredient(ingredient):
            return ingredient.makeCarriable()

        case let .drink(hasTea, hasIce, hasBoba, hasFoam, hasLid):
            return buildDrink(hasTea: hasTea,
                              hasIce: hasIce,
                              hasBoba: hasBoba,
                              hasFoam: hasFoam,
                              hasLid: hasLid)
        }
    }

    // MARK: - Drink Builder

    private static func buildDrink(hasTea: Bool, hasIce: Bool, hasBoba: Bool, hasFoam: Bool, hasLid: Bool) -> RotatableObject {
        let complete = hasTea && hasLid
        let type: ObjectType = complete ? .completedDrink : .drink
        let name = complete ? "completed_drink" : "picked_up_drink"

        let drink = RotatableObject(type: type, color: .clear, shape: "drink")
        drink.size = CGSize(width: 30, height: 45)
        drink.name = name

        let atlas = SKTextureAtlas(named: "Boba")
        guard atlas.textureNames.count > 0 else {
            Log.warn(.drink, "CarriedItemFactory: Boba atlas empty, returning bare cup")
            return drink
        }

        let cupTex = atlas.textureNamed("cup_empty")
        let scale = 25.0 / cupTex.size().width

        func addLayer(_ texName: String, z: CGFloat) {
            guard atlas.textureNames.contains(texName) else { return }
            let tex = atlas.textureNamed(texName)
            tex.filteringMode = .nearest
            let node = SKSpriteNode(texture: tex)
            node.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            node.position = .zero
            node.setScale(scale)
            node.zPosition = z
            node.blendMode = .alpha
            node.name = texName
            drink.addChild(node)
        }

        addLayer("cup_empty",       z: 0)
        if hasTea  { addLayer("tea_black",       z: 1) }
        if hasIce  { addLayer("ice_cubes",       z: 2) }
        if hasBoba { addLayer("topping_tapioca", z: 3) }
        if hasFoam { addLayer("foam_cheese",     z: 4) }
        if hasLid  { addLayer("lid_straw",       z: 5) }

        return drink
    }
}
