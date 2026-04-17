//
//  NetworkMessage.swift
//  BobaAtDawn
//
//  Codable messages sent between host and guest over GameKit.
//  Every world-state mutation is expressed as one of these messages.
//

import Foundation
import CoreGraphics
import QuartzCore

// MARK: - Top-Level Envelope

struct NetworkEnvelope: Codable {
    let type: MessageType
    let payload: Data
    let senderIsHost: Bool
    let timestamp: TimeInterval
}

// MARK: - Message Types

enum MessageType: String, Codable {
    case hostHandshake
    case guestReady
    case playerPosition
    case npcInteraction
    case npcSatisfactionSync
    case npcMovedToShop
    case npcLeftShop
    case npcLiberated
    case stationToggled
    case drinkCreated
    case drinkPlacedOnTable
    case drinkServed
    case timePhaseChanged
    case timeSync
    case trashSpawned
    case trashCleaned
    case ritualStepCompleted
    case ritualStateSync
    case forestRoomChanged
    case saveRequested
    case fullStateSync
    case stateRequest
    case worldSync
    case npcShopSync
    case forestNpcSync
    case snailSync
    case dialogueShown
    case dialogueDismissed
}

extension MessageType {
    var isReliable: Bool {
        switch self {
        case .playerPosition, .npcShopSync, .forestNpcSync, .snailSync: return false
        default: return true
        }
    }
}

// MARK: - Message Payloads

struct HostHandshake: Codable {
    let dayCount: Int
    let timePhase: String
    let timeProgress: Float
    let isTimeFlowing: Bool
    let npcStatesJSON: String
    let hostPlayerPosition: CodablePoint
    let ritualActive: Bool
}

struct GuestReady: Codable {
    let guestDisplayName: String
}

struct PlayerPositionMessage: Codable {
    let position: CodablePoint
    let isMoving: Bool
    let animationDirection: String?
    let isCarrying: Bool
    let carriedItemType: String?
    let sceneType: String
}

struct NPCInteractionMessage: Codable {
    let npcID: String
    let responseType: String
}

struct NPCSatisfactionSync: Codable {
    struct Entry: Codable {
        let npcID: String
        let satisfactionScore: Int
        let totalDrinksReceived: Int
        let isLiberated: Bool
    }
    let entries: [Entry]
}

struct NPCMovedToShopMessage: Codable {
    let npcID: String
    let animalType: String
}

struct NPCLeftShopMessage: Codable {
    let npcID: String
    let satisfied: Bool
    let hadDrink: Bool
}

struct NPCLiberatedMessage: Codable {
    let npcID: String
    let liberationType: String
}

struct StationToggledMessage: Codable {
    let stationName: String
    let newState: String
}

struct DrinkCreatedMessage: Codable {
    let drinkID: String
    let hasTea: Bool
    let hasIce: String
    let hasBoba: Bool
    let hasFoam: Bool
    let hasLid: Bool
}

struct DrinkPlacedOnTableMessage: Codable {
    let tablePosition: CodablePoint
    let slotIndex: Int
    let hasTea: Bool
    let hasIce: Bool
    let hasBoba: Bool
    let hasFoam: Bool
    let hasLid: Bool
}

struct DrinkServedMessage: Codable {
    let drinkID: String
    let npcID: String
}

struct TimePhaseChangedMessage: Codable {
    let newPhase: String
    let dayCount: Int
}

struct TimeSyncMessage: Codable {
    let phase: String
    let progress: Float
    let isFlowing: Bool
    let dayCount: Int
}

struct TrashSpawnedMessage: Codable {
    let position: CodablePoint
    let location: String
}

struct TrashCleanedMessage: Codable {
    let position: CodablePoint
    let location: String
}

struct RitualStepMessage: Codable {
    let step: String
    let npcID: String?
}

struct RitualStateSyncMessage: Codable {
    let isActive: Bool
    let currentStep: String?
    let ritualNPCId: String?
}

struct ForestRoomChangedMessage: Codable {
    let newRoom: Int
    let playerPosition: CodablePoint
}

struct FullStateSyncMessage: Codable {
    let handshake: HostHandshake
}

// MARK: - Host-Authoritative Sync Payloads

struct NPCShopSyncEntry: Codable {
    let npcID: String
    let animalType: String
    let position: CodablePoint
    let state: String
}

struct NPCShopSyncMessage: Codable {
    let entries: [NPCShopSyncEntry]
}

struct SnailSyncMessage: Codable {
    let room: Int
    let position: CodablePoint
    let isActive: Bool
}

struct ForestNpcSyncEntry: Codable {
    let npcID: String
    let position: CodablePoint
}

struct ForestNpcSyncMessage: Codable {
    let room: Int
    let entries: [ForestNpcSyncEntry]
}

struct DialogueShownMessage: Codable {
    let npcID: String
    let speakerName: String
    let text: String
    let position: CodablePoint
}

struct DialogueDismissedMessage: Codable {
    let placeholder: Bool // Empty payload, just needs to be Codable
    init() { self.placeholder = true }
}

struct StateRequestMessage: Codable {
    let requestingScene: String
    let saveTimestamp: Double // TimeInterval since 1970
}

struct NPCMemoryEntry: Codable {
    let npcID: String
    let name: String
    let animalType: String
    let satisfactionScore: Int
    let totalInteractions: Int
    let totalDrinksReceived: Int
    let niceTreatmentCount: Int
    let meanTreatmentCount: Int
    let isLiberated: Bool
    let liberationDate: Double? // TimeInterval since 1970, nil if not liberated
}

struct WorldSyncMessage: Codable {
    let dayCount: Int
    let timePhase: String
    let timeProgress: Float
    let npcStatesJSON: String
    let npcMemories: [NPCMemoryEntry]
    let saveTimestamp: Double
}

// MARK: - Helpers

struct CodablePoint: Codable {
    let x: CGFloat
    let y: CGFloat

    init(_ point: CGPoint) {
        self.x = point.x
        self.y = point.y
    }

    var cgPoint: CGPoint { CGPoint(x: x, y: y) }
}

// MARK: - Encoding / Decoding Convenience

extension NetworkEnvelope {
    static func make<T: Encodable>(
        type: MessageType,
        payload: T,
        isHost: Bool
    ) throws -> NetworkEnvelope {
        let data = try JSONEncoder().encode(payload)
        return NetworkEnvelope(
            type: type,
            payload: data,
            senderIsHost: isHost,
            timestamp: CACurrentMediaTime()
        )
    }

    func decode<T: Decodable>(_ type: T.Type) throws -> T {
        return try JSONDecoder().decode(type, from: payload)
    }

    func encoded() throws -> Data {
        return try JSONEncoder().encode(self)
    }

    static func from(_ data: Data) throws -> NetworkEnvelope {
        return try JSONDecoder().decode(NetworkEnvelope.self, from: data)
    }
}
