//
//  ForageableIngredient.swift
//  BobaAtDawn
//
//  Single source of truth for every gathered ingredient in the game.
//  Adding a new foraged ingredient = add one case here and fill in the
//  visual helpers. All other systems (spawning, carrying, pantry,
//  multiplayer) read their behavior from this enum.
//

import SpriteKit

enum ForageableIngredient: String, CaseIterable, Codable {
    case matchaLeaf = "matcha_leaf"
    case strawberry = "strawberry"
    case mushroom   = "mushroom"
    case rock       = "rock"
    case gem        = "gem"

    // MARK: - Display Metadata

    /// Emoji used for in-world spawn nodes, carried-item sprites,
    /// and pantry/fridge slot icons.
    var displayEmoji: String {
        switch self {
        case .matchaLeaf: return "\u{1F343}" // 🍃
        case .strawberry: return "\u{1F353}" // 🍓
        case .mushroom:   return "\u{1F344}" // 🍄
        case .rock:       return "\u{1FAA8}" // 🪨
        case .gem:        return "\u{1F48E}" // 💎
        }
    }

    /// Human-readable name for logs and dialogue.
    var displayName: String {
        switch self {
        case .matchaLeaf: return "Matcha Leaf"
        case .strawberry: return "Strawberry"
        case .mushroom:   return "Mushroom"
        case .rock:       return "Rock"
        case .gem:        return "Gem"
        }
    }

    // MARK: - Carry-System Identity

    /// Node name stamped on the carriable RotatableObject the player
    /// holds above their head. Used by BaseGameScene.drinkCode,
    /// GameScene.depositableIngredient, Character.carryContent, etc.
    var carriedNodeName: String {
        "carried_\(rawValue)"
    }

    /// Single-character code broadcast to the remote player so their
    /// overhead icon matches ours. Keep these unique across all three
    /// ingredients AND the drink codes ("T", "I", "B", "F", "L", "C").
    var remoteCarryCode: String {
        switch self {
        case .matchaLeaf: return "M" // Matcha
        case .strawberry: return "S" // Strawberry
        case .mushroom:   return "U" // fUngi — "M" already taken
        case .rock:       return "R" // Rock
        case .gem:        return "G" // Gem
        }
    }

    /// True if this ingredient should be eligible for pantry/fridge
    /// deposit. Rocks and gems are work-items, not pantry food, so
    /// they're excluded — depositing them in the pantry doesn't make
    /// sense and would clutter slots.
    var isPantryDepositable: Bool {
        switch self {
        case .matchaLeaf, .strawberry, .mushroom: return true
        case .rock, .gem:                          return false
        }
    }

    // MARK: - Factories

    /// Build the RotatableObject the Character carry system holds when
    /// the player picks up or retrieves this ingredient.
    func makeCarriable() -> RotatableObject {
        let item = RotatableObject(type: .drink, color: colorHint, shape: "rectangle")
        item.name = carriedNodeName
        item.size = CGSize(width: 20, height: 20)

        // Replace the default shape-child with an emoji label.
        item.children.forEach { $0.removeFromParent() }

        let emoji = SKLabelNode(text: displayEmoji)
        emoji.fontSize = 22
        emoji.fontName = "Arial"
        emoji.horizontalAlignmentMode = .center
        emoji.verticalAlignmentMode = .center
        emoji.position = .zero
        emoji.zPosition = 1
        item.addChild(emoji)

        item.color = .clear
        item.colorBlendFactor = 0.0
        return item
    }

    /// Background tint for the carriable sprite's fallback (the emoji
    /// covers it, but this is what shows if the atlas fails).
    private var colorHint: SKColor {
        switch self {
        case .matchaLeaf: return .green
        case .strawberry: return .red
        case .mushroom:   return .brown
        case .rock:       return .gray
        case .gem:        return SKColor(red: 0.4, green: 0.7, blue: 1.0, alpha: 1.0)
        }
    }

    // MARK: - Lookup

    /// Reverse lookup from a carry-node name back to the ingredient.
    /// Returns nil if the name isn't one of the known carriables.
    static func fromCarriedNodeName(_ name: String?) -> ForageableIngredient? {
        guard let name else { return nil }
        return ForageableIngredient.allCases.first { $0.carriedNodeName == name }
    }
}
