//
//  ChronicleModels.swift
//  BobaAtDawn
//
//  Models for the daily chronicle system. The ledger collects a flat
//  list of LedgerEvent values during the day. At dawn the host snapshots
//  it, runs DailyChronicleService to turn the snapshot into folkloric
//  prose, and persists a DailySummary. Both prose and the raw event
//  list are stored, so the prompt can be regenerated later if you want
//  to tweak the chronicle service and re-render history.
//

import Foundation
import SwiftData

// MARK: - Ledger Event

/// One thing that happened during the day. Stored as a flat list while
/// the day is in progress, then aggregated at dawn into prose + headlines.
/// All optional fields are populated based on `kind`. Kept as a single
/// struct (rather than an enum with associated values) so Codable is
/// trivial and SwiftData JSON storage stays simple.
struct LedgerEvent: Codable, Equatable {

    enum Kind: String, Codable {
        case drinkServed
        case gemDeposited
        case ingredientForaged
        case ingredientDeposited
        case ingredientRetrieved
        case trashSpawned
        case trashCleaned
        case npcArrivedShop
        case npcLiberated
        case gnomeRankChanged          // covers both promote and demote
        case opinionThresholdCrossed
    }

    let kind: Kind
    let timestamp: Date

    // Optional fields, populated per `kind`:
    var npcID: String?
    var npcName: String?
    var ingredient: String?
    var container: String?
    var location: String?
    var gnomeID: String?
    var gnomeName: String?
    var newRank: String?
    var bossLine: String?
    var liberationKind: String?            // "divine" | "hellish"
    var rankChangeIsPromotion: Bool?       // true = up, false = down
    var pairOfID: String?
    var pairOfName: String?
    var pairTowardID: String?
    var pairTowardName: String?
    var threshold: String?                 // "hostile" | "avoidant" | "friendly" | "close"
    var crossingDirection: String?         // "up" | "down"
}

// MARK: - Headlines

/// Numeric summary derived from a day's LedgerEvent list. Stored
/// alongside the prose so the book page can show stats without
/// re-aggregating.
struct DailyChronicleHeadlines: Codable, Equatable {
    var drinksServed: Int = 0
    var gemsCollected: Int = 0
    var trashCleanedCount: Int = 0
    var trashSpawnedCount: Int = 0
    var liberations: Int = 0
    var rankChanges: Int = 0
    var npcArrivals: Int = 0
    var thresholdCrossings: Int = 0

    var foragedByIngredient: [String: Int] = [:]
    var depositedByIngredient: [String: Int] = [:]
    var retrievedByIngredient: [String: Int] = [:]

    /// Build headlines from a flat event list.
    static func aggregate(_ events: [LedgerEvent]) -> DailyChronicleHeadlines {
        var h = DailyChronicleHeadlines()
        for e in events {
            switch e.kind {
            case .drinkServed:
                h.drinksServed += 1
            case .gemDeposited:
                h.gemsCollected += 1
            case .trashCleaned:
                h.trashCleanedCount += 1
            case .trashSpawned:
                h.trashSpawnedCount += 1
            case .npcLiberated:
                h.liberations += 1
            case .gnomeRankChanged:
                h.rankChanges += 1
            case .npcArrivedShop:
                h.npcArrivals += 1
            case .opinionThresholdCrossed:
                h.thresholdCrossings += 1
            case .ingredientForaged:
                if let i = e.ingredient { h.foragedByIngredient[i, default: 0] += 1 }
            case .ingredientDeposited:
                if let i = e.ingredient { h.depositedByIngredient[i, default: 0] += 1 }
            case .ingredientRetrieved:
                if let i = e.ingredient { h.retrievedByIngredient[i, default: 0] += 1 }
            }
        }
        return h
    }
}

// MARK: - Daily Summary (SwiftData persistent model)

/// One generated chronicle page. One row per day. `dayCount` is the
/// canonical key; if the host generates twice for the same day (e.g.
/// after a debug rollback) the existing row is overwritten in place.
@Model
final class DailySummary {
    var saveSlotID: String = WorldState.slotID(for: 1)
    /// The day number this chronicle describes. NOT the day after.
    var dayCount: Int

    /// When the LLM (or fallback template) produced this prose.
    var generatedAt: Date

    /// Whether the LLM was actually used (true) or the fallback
    /// template stitched it together (false).
    var usedLLM: Bool

    var openingLine: String
    var forestSection: String
    var minesSection: String
    var shopSection: String
    var socialSection: String
    var closingLine: String

    var headlinesJSON: String
    var ledgerJSON: String

    init(
        dayCount: Int,
        generatedAt: Date,
        usedLLM: Bool,
        openingLine: String,
        forestSection: String,
        minesSection: String,
        shopSection: String,
        socialSection: String,
        closingLine: String,
        headlinesJSON: String,
        ledgerJSON: String
    ) {
        self.dayCount = dayCount
        self.generatedAt = generatedAt
        self.usedLLM = usedLLM
        self.openingLine = openingLine
        self.forestSection = forestSection
        self.minesSection = minesSection
        self.shopSection = shopSection
        self.socialSection = socialSection
        self.closingLine = closingLine
        self.headlinesJSON = headlinesJSON
        self.ledgerJSON = ledgerJSON
    }

    // MARK: - Decoded helpers

    var headlines: DailyChronicleHeadlines {
        guard let data = headlinesJSON.data(using: .utf8),
              let h = try? JSONDecoder().decode(DailyChronicleHeadlines.self, from: data)
        else { return DailyChronicleHeadlines() }
        return h
    }

    var ledger: [LedgerEvent] {
        guard let data = ledgerJSON.data(using: .utf8),
              let l = try? JSONDecoder().decode([LedgerEvent].self, from: data)
        else { return [] }
        return l
    }
}

// MARK: - Network DTO

struct DailySummaryEntry: Codable, Equatable {
    let dayCount: Int
    let generatedAt: Double           // TimeInterval since 1970
    let usedLLM: Bool
    let openingLine: String
    let forestSection: String
    let minesSection: String
    let shopSection: String
    let socialSection: String
    let closingLine: String
    let headlinesJSON: String
    let ledgerJSON: String
}

extension DailySummary {
    func toEntry() -> DailySummaryEntry {
        DailySummaryEntry(
            dayCount: dayCount,
            generatedAt: generatedAt.timeIntervalSince1970,
            usedLLM: usedLLM,
            openingLine: openingLine,
            forestSection: forestSection,
            minesSection: minesSection,
            shopSection: shopSection,
            socialSection: socialSection,
            closingLine: closingLine,
            headlinesJSON: headlinesJSON,
            ledgerJSON: ledgerJSON
        )
    }

    func apply(_ entry: DailySummaryEntry) {
        self.generatedAt = Date(timeIntervalSince1970: entry.generatedAt)
        self.usedLLM = entry.usedLLM
        self.openingLine = entry.openingLine
        self.forestSection = entry.forestSection
        self.minesSection = entry.minesSection
        self.shopSection = entry.shopSection
        self.socialSection = entry.socialSection
        self.closingLine = entry.closingLine
        self.headlinesJSON = entry.headlinesJSON
        self.ledgerJSON = entry.ledgerJSON
    }
}

// MARK: - Single-message broadcast payload

struct DailySummaryGeneratedMessage: Codable {
    let entry: DailySummaryEntry
}
