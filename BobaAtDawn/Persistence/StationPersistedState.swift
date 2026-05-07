//
//  StationPersistedState.swift
//  BobaAtDawn
//
//  VESTIGIAL / DEPRECATED as of the drink-in-hand refactor. Stations no
//  longer hold recipe state — a drink's state lives on the drink itself
//  (the RotatableObject carried by the player). See DrinkCreator and
//  GameScene.handleStationInteraction.
//
//  This file is kept in place so existing Xcode project references don't
//  need to be updated, and so any old save payloads that reference the
//  StationFlags type can still be decoded (harmlessly) if needed. It can
//  be removed entirely in a future cleanup pass along with the Xcode
//  reference and the `stationStatesJSON` field on WorldState.
//

// MARK: - Station Flags

@available(*, deprecated, message: "Station state moved onto the held drink. See DrinkCreator.applyIngredient.")
struct StationFlags: Codable, Equatable {
    var hasIce: Bool = false
    var hasTea: Bool = false
    var hasBoba: Bool = false
    var hasFoam: Bool = false
    var hasLid: Bool = false

    static let empty = StationFlags()
}

// MARK: - Persisted Station State

@available(*, deprecated, message: "Station state moved onto the held drink. See DrinkCreator.applyIngredient.")
final class StationPersistedState {
    static let shared = StationPersistedState()

    private(set) var flags: StationFlags = .empty

    /// Fired on mutation. SaveService no longer wires this.
    var onDidMutate: (() -> Void)?

    private init() {}

    func sync(_ newFlags: StationFlags) {
        guard flags != newFlags else { return }
        flags = newFlags
        onDidMutate?()
    }

    func reset() {
        guard flags != .empty else { return }
        flags = .empty
        onDidMutate?()
    }

    func load(_ flags: StationFlags) {
        self.flags = flags
    }
}
