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
    case lobbyStart
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
    case timeSubphaseRequest
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
    case dialogueFollowupChosen
    // Host-authoritative streaming dialogue (parallel multi-NPC dialogs).
    case dialogueOpenRequest      // either → host
    case dialogueOpened            // host → both
    case dialogueLineDelta         // host → both (unreliable)
    case dialogueFollowupsReady    // host → both
    // Movable shop objects (tables / furniture rearrangement).
    case objectPickedUp            // either → both
    case objectDropped             // either → both
    case objectRotated             // either → both
    case npcConversationLine
    case npcConversationEnded
    case itemForaged
    case storageDeposited
    case storageRetrieved
    // Daily chronicle (book in the shop)
    case dailySummaryGenerated
    // Gnome simulation
    case gnomeStateSync
    case gnomeRosterRefresh
    case treasuryUpdate
    case mineMachineFed
    case gnomeConversationLine
    case gnomeConversationEnded
}

extension MessageType {
    var isReliable: Bool {
        switch self {
        case .playerPosition, .npcShopSync, .forestNpcSync, .snailSync, .gnomeStateSync,
             .dialogueLineDelta:
            return false
        default:
            return true
        }
    }
}

// MARK: - Message Payloads

struct LobbyStartMessage: Codable {
    let sessionType: String
    let slotIndex: Int
}

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

/// Sent when a player presses the debug time-control button. Either
/// host or guest may send. The host applies it locally; if a guest
/// sent the request, the host echoes the same message back so the
/// guest's local view matches without waiting for the next periodic
/// `timeSync`.
struct TimeSubphaseRequestMessage: Codable {
    let subphaseRawValue: String
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
    let mood: String?       // Optional emoji-mood key ("happy", "wistful", etc.)
    let position: CodablePoint
    let sceneType: String   // "shop" | "forest_<room>" | "cave" | "big_oak"
}

/// Sent when a player taps an LLM-generated followup pill. Lets the
/// remote player see which option was chosen (kind/blunt/neutral) and
/// the exact wording, before the turn-2 reply streams.
struct DialogueFollowupChosenMessage: Codable {
    let npcID: String
    let chosenText: String
    let tone: String        // "kind" | "neutral" | "blunt"
}

/// One line of an NPC ↔ NPC conversation. The host generates and
/// broadcasts these; the guest renders them. The conversation as a
/// whole is identified by `conversationID`.
struct NPCConversationLineMessage: Codable {
    let conversationID: String
    let speakerNPCID: String
    let speakerName: String
    let listenerNPCIDs: [String]
    let text: String
    let mood: String?
    let position: CodablePoint
    let sceneType: String
    let isClosing: Bool
}

/// Marks the end of an NPC ↔ NPC conversation. Sent by host with the
/// final list of interactions that occurred so the guest can apply
/// matching opinion deltas locally (or, if desired, just trust host
/// authority and skip).
struct NPCConversationEndedMessage: Codable {
    let conversationID: String
    let participants: [String]
    /// Each tuple: (speaker, listener, interactionRawValue).
    /// Encoded as a flat array of `Entry` for stable Codable.
    struct Entry: Codable {
        let speaker: String
        let listener: String
        let interaction: String
    }
    let interactions: [Entry]
    let interruptedByPlayer: Bool
}

struct DialogueDismissedMessage: Codable {
    /// NPC id whose bubble should close. Optional for back-compat with
    /// older clients that sent an empty payload — receivers should treat
    /// nil as "dismiss all" to preserve old behavior.
    let npcID: String?
    init(npcID: String? = nil) { self.npcID = npcID }
}

// MARK: - Streaming Dialogue (Host-Authoritative)

/// Either player → host. Player tapped an NPC and wants a dialogue.
/// Host decides whether to honor it (e.g. NPC must be in the host's
/// scene, not currently liberated, etc.) and replies with a
/// `dialogueOpened` if approved.
struct DialogueOpenRequestMessage: Codable {
    let npcID: String
    let sceneType: String   // requester's scene; host gates on it matching
}

/// Host → both. A new dialogue bubble should appear, anchored to the
/// named NPC. Both players render an empty streaming bubble and wait
/// for line deltas.
struct DialogueOpenedMessage: Codable {
    let npcID: String
    let speakerName: String
    let position: CodablePoint
    let sceneType: String
}

/// Host → both. Streamed token chunk. `partialText` is the cumulative
/// text-so-far (not the diff) so out-of-order delivery is harmless.
/// Sent unreliable; the next delta supersedes any lost frame.
struct DialogueLineDeltaMessage: Codable {
    let npcID: String
    let partialText: String
    let mood: String?
}

/// Host → both. The line is finalized and the kind/blunt followup pills
/// are ready to render. Sent reliably.
struct DialogueFollowupsReadyMessage: Codable {
    let npcID: String
    let kindText: String
    let bluntText: String
}

// MARK: - Movable Shop Objects

/// Sent when a player picks up an editor-placed RotatableObject (table
/// or furniture). `byHost` lets the receiver know whose RemoteCharacter
/// to parent the object to while it's being carried.
struct ObjectPickedUpMessage: Codable {
    let editorName: String
    let byHost: Bool
}

/// Sent when a carried RotatableObject is dropped onto the grid.
/// Position + rotation are the world-truth that the receiver applies.
struct ObjectDroppedMessage: Codable {
    let editorName: String
    let position: CodablePoint
    let rotationDegrees: Int
}

/// Sent when a player rotates the object they're currently carrying.
/// Only meaningful between pickup and drop.
struct ObjectRotatedMessage: Codable {
    let editorName: String
    let rotationDegrees: Int
}

/// Sent when a player picks up a foraged ingredient (leaf, berry,
/// mushroom, or any future forageable). The receiver marks the spawn
/// collected locally and, if viewing the same location, removes the
/// visual node.
struct ItemForagedMessage: Codable {
    let spawnID: String
    let locationKey: String
}

/// One realized forage spawn for cross-machine snapshot. Mirrors
/// `ForageSpawn` in ForagingManager but flattens the enums to wire-
/// safe strings.
struct ForageSpawnEntry: Codable {
    let spawnID: String
    let ingredient: String   // ForageableIngredient.rawValue
    let locationKey: String  // SpawnLocation.stringKey
    let position: CodablePoint
    let isCollected: Bool
}

/// One pending (not-yet-released) forage spawn. Mirrors `PendingSpawn`
/// in ForagingManager. `scheduledOffsetSeconds` is host-relative — the
/// host computes `(scheduledTime - hostNow)` at export, the guest
/// rebases to its own clock at apply: `scheduledTime = guestNow + offset`.
struct PendingSpawnEntry: Codable {
    let spawnID: String
    let ingredient: String
    let locationKey: String
    let position: CodablePoint
    let scheduledOffsetSeconds: Double
    let maxConcurrent: Int
}

/// Full forage state envelope for join-time sync. Sent inside
/// `WorldSyncMessage.forageSpawnsJSON`. Includes the day stamp so the
/// guest doesn't apply a stale snapshot if its own day counter has
/// already advanced for some reason.
struct ForageSpawnsSnapshot: Codable {
    let spawnDay: Int
    let spawns: [ForageSpawnEntry]
    let pendingSpawns: [PendingSpawnEntry]
}

struct StorageDepositedMessage: Codable {
    let containerName: String
    let ingredient: String
}

struct StorageRetrievedMessage: Codable {
    let containerName: String
    let ingredient: String
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

/// Snapshot of one gnome agent for cross-session save and one-message
/// network sync. Counterpart of GnomeSnapshot in Gnomes/GnomeIdentity.swift,
/// declared there to keep all gnome-specific types together.
struct WorldSyncMessage: Codable {
    let dayCount: Int
    let timePhase: String
    let timeProgress: Float
    let npcStatesJSON: String
    let npcMemories: [NPCMemoryEntry]
    let worldItems: [WorldItem]
    let storage: [String: StorageContents]
    let saveTimestamp: Double
    /// Persisted gnome state — see GnomeManager.exportSaveData.
    /// Optional for backward compatibility with older world saves.
    let gnomeSnapshotsJSON: String?
    let treasuryGemCount: Int?
    /// Persisted mine cart state. Optional for back-compat with
    /// pre-cart saves. nil = cart at idle in cave entrance with 0 gems.
    let cartGemCount: Int?
    let cartLocation: String?
    let cartState: String?
    /// Recent daily chronicle summaries. Optional for back-compat with
    /// pre-chronicle saves. Receiver merges by dayCount.
    let recentSummaries: [DailySummaryEntry]?
    /// Editor-placed RotatableObjects that have been rearranged from
    /// their .sks default positions. Optional for back-compat with
    /// pre-rearrangement saves. nil/empty = everything at editor default.
    let movableObjects: [MovableObjectEntry]?
    /// Broker economy state (box contents, broker gem reserve, transient
    /// errand flags). Optional for back-compat with pre-3b saves. nil or
    /// "{}" leaves the receiver's live state untouched.
    let brokerEconomyJSON: String?
    /// Forage spawn snapshot (current realized spawns + pending spawns
    /// scheduled for later in the day). Optional for back-compat with
    /// older worldSync exchanges. Sent only at join time — mid-day
    /// spawn promotions and dawn rollovers are NOT yet broadcast and
    /// the guest will diverge until the next worldSync. Future:
    /// emit a `forageSpawnsSync` message at host dawn rollover.
    let forageSpawnsJSON: String?
}

// MARK: - Gnome ↔ Gnome Conversation Sync

/// One streamed line of a gnome ↔ gnome ambient conversation. Distinct
/// from NPCConversationLineMessage so the receiver can route them to
/// GnomeConversationService instead of NPCConversationService and so
/// the gnome-specific schema stays clean.
struct GnomeConversationLineMessage: Codable {
    let conversationID: String
    let speakerGnomeID: String
    let speakerName: String
    let listenerGnomeIDs: [String]
    let text: String
    let mood: String?
    let position: CodablePoint
    let sceneType: String
    let isClosing: Bool
}

struct GnomeConversationEndedMessage: Codable {
    let conversationID: String
    let participants: [String]
    let interruptedByPlayer: Bool
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
