//
//  GnomeDataLoader.swift
//  BobaAtDawn
//
//  Singleton that loads `Data/gnome_data.json` from the main bundle at
//  first access and exposes the decoded `GnomeDatabase`. Modeled on the
//  NPC equivalent in `DialogueService.loadNPCData()`.
//
//  Lookups are O(n) but n=18 — no need for caching dictionaries.
//
//  Failure modes
//  -------------
//  - Missing file in bundle: logs an error and exposes an empty
//    database. Calling code (`GnomeRoster`, `GnomeManager`) will see
//    an empty roster and the simulation will run in a degraded "no
//    gnomes" mode rather than crashing. Surface the error in the log
//    rather than via assertion so a misconfigured target build doesn't
//    ship a crashy app.
//  - Decode failure: same — log + empty database.
//  - Both cases mean "go fix the JSON or the Xcode resource step".
//

import Foundation

final class GnomeDataLoader {

    static let shared = GnomeDataLoader()

    /// Decoded database. Empty if loading or decoding fails.
    private(set) var database: GnomeDatabase

    /// Convenience: full gnome list in JSON order.
    var all: [GnomeData] { database.gnomes }

    /// Convenience: opinion topics in JSON order.
    var topics: [GnomeOpinionTopic] { database.opinionTopics }

    /// Convenience: hardcoded line pools (boss, miner_cave, etc.) used by
    /// `GnomeConversationService` when the LLM is unavailable.
    var poolLines: GnomePoolLinesData { database.poolLines }

    private init() {
        // Initialize to empty so failure paths still leave the loader
        // usable. We then attempt the actual load and overwrite on success.
        self.database = GnomeDataLoader.empty()
        loadFromBundle()
    }

    // MARK: - Lookups

    /// Find a gnome by stable id (e.g. "gnome_boss_thork"). Returns nil
    /// if the id isn't present in the JSON.
    func find(_ id: String) -> GnomeData? {
        database.gnomes.first { $0.id == id }
    }

    /// Find an opinion topic by id (e.g. "gems"). Returns nil if absent.
    func topic(_ id: String) -> GnomeOpinionTopic? {
        database.opinionTopics.first { $0.id == id }
    }

    /// All gnomes filtered by raw role string ("boss" | "miner" | "housekeeper").
    func gnomes(role: String) -> [GnomeData] {
        database.gnomes.filter { $0.role == role }
    }

    // MARK: - Loading

    private func loadFromBundle() {
        guard let url = Bundle.main.url(forResource: "gnome_data", withExtension: "json") else {
            Log.error(.npc, "[GnomeData] Could not find gnome_data.json in bundle — gnomes will be empty")
            return
        }
        do {
            let data = try Data(contentsOf: url)
            let decoded = try JSONDecoder().decode(GnomeDatabase.self, from: data)
            self.database = decoded
            Log.info(
                .npc,
                "[GnomeData] Loaded \(decoded.gnomes.count) gnomes (schema v\(decoded.schemaVersion)) with \(decoded.opinionTopics.count) opinion topics"
            )
        } catch {
            Log.error(.npc, "[GnomeData] Failed to decode gnome_data.json: \(error)")
        }
    }

    // MARK: - Empty Fallback

    private static func empty() -> GnomeDatabase {
        // Decode an empty JSON shell so we have a valid (if vacuous)
        // database object even before/without a successful load.
        let shell = #"{"schema_version":1,"gnome_opinion_topics":[],"gnome_pool_lines":{},"gnomes":[]}"#
        let data = Data(shell.utf8)
        // Force-try is safe here: the literal above is hand-authored
        // and known-valid. If decoding the literal ever starts failing,
        // we want the crash to be loud during development.
        // swiftlint:disable:next force_try
        return try! JSONDecoder().decode(GnomeDatabase.self, from: data)
    }
}
