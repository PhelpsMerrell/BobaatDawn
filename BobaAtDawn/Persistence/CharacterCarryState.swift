//
//  CharacterCarryState.swift
//  BobaAtDawn
//
//  Singleton that persists the player's carried item across scene
//  transitions and app restarts. Character.pickupItem/dropItem keeps
//  this in sync; BaseGameScene.setupCharacter reads this and calls
//  CarriedItemFactory to reconstruct the in-hand item on scene load.
//

// MARK: - Carry Content

enum CarryContent: Codable, Equatable {
    case none
    case ingredient(ForageableIngredient)
    case drink(hasTea: Bool, hasIce: Bool, hasBoba: Bool, hasFoam: Bool, hasLid: Bool)

    var isEmpty: Bool {
        if case .none = self { return true }
        return false
    }

    var isDrink: Bool {
        if case .drink = self { return true }
        return false
    }

    var isIngredient: Bool {
        if case .ingredient = self { return true }
        return false
    }
}

// MARK: - Carry State

final class CharacterCarryState {
    static let shared = CharacterCarryState()

    private(set) var content: CarryContent = .none

    /// Fired on mutation. SaveService wires this to persist-to-disk.
    var onDidMutate: (() -> Void)?

    private init() {}

    // MARK: - Mutations

    func set(_ content: CarryContent) {
        guard self.content != content else { return }
        self.content = content
        onDidMutate?()
    }

    func clear() {
        guard !content.isEmpty else { return }
        content = .none
        onDidMutate?()
    }

    /// Clear only if currently carrying a drink. Keeps ingredients
    /// since the player expects gathered items to survive the dawn rollover.
    /// Used at dawn rollover (in-progress drinks reset, ingredients don't).
    func clearDrinkOnly() {
        if case .drink = content {
            content = .none
            onDidMutate?()
        }
    }

    // MARK: - Loading

    /// Bulk-set from disk without firing onDidMutate.
    func load(_ content: CarryContent) {
        self.content = content
    }
}
