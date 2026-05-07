//
//  DailyChronicleService.swift
//  BobaAtDawn
//
//  Generates a folkloric daily chronicle from a snapshot of the day's
//  LedgerEvent list. Wraps Apple's on-device Foundation Models framework
//  (iOS 26+, gated by #if canImport(FoundationModels)) and falls back to
//  a deterministic stitched template when the LLM is unavailable.
//
//  --- HOW TO TWEAK THE VOICE ---
//
//  Two editable blocks live at the top of this file:
//
//    EDIT_ME_SYSTEM_INSTRUCTIONS  → describes who is "writing" the
//                                   chronicle, the rules they follow,
//                                   and the forbidden words.
//
//    EDIT_ME_PROMPT_TEMPLATE      → the per-day prompt body. Receives
//                                   day number, headlines, and a
//                                   bulleted list of the day's events.
//
//  Section guides on the @Generable struct (`openingLine`, `forestSection`
//  etc.) further constrain shape per section. Tweak those `description:`
//  strings to nudge length/tone per section.
//

import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

// MARK: - Result Type

/// Final chronicle, ready to persist as a DailySummary.
struct GeneratedDailyChronicleResult {
    let openingLine: String
    let forestSection: String
    let minesSection: String
    let shopSection: String
    let socialSection: String
    let closingLine: String
    /// True if the LLM produced this; false if the fallback template did.
    let usedLLM: Bool
}

// MARK: - Generable Schema (iOS 26+)

#if canImport(FoundationModels)
@available(iOS 26.0, *)
@Generable
struct GeneratedDailyChronicle {

    @Guide(description: """
    Opening line for the day's chronicle. ONE sentence, folkloric and
    slightly archaic. Set the mood — weather, light, the feeling of
    the woods waking. Examples of shape (do not copy): "Day eleven
    broke gray and slow.", "The fog held the trees long past the second
    cup.", "It was the kind of dawn that made the lanterns linger."
    """)
    let openingLine: String

    @Guide(description: """
    What happened in the forest today. 1 to 3 short sentences. Ground
    in concrete events from the prompt's event list when present —
    foraged items, trash that appeared or was cleaned, who came and
    went. If nothing happened in the forest, write a brief atmospheric
    line about quiet trees instead. Folkloric voice.
    """)
    let forestSection: String

    @Guide(description: """
    What happened in the gnome mines today. 1 to 3 short sentences.
    Mention rank changes (promotions, demotions) verbatim if a boss
    line is given in the prompt. Mention gems collected and roughly
    how the work went. If nothing rank-changing happened, describe the
    rhythm of the day's mining.
    """)
    let minesSection: String

    @Guide(description: """
    What happened in the shop today. 1 to 3 short sentences. Drinks
    served, guests who came in, anyone who drifted off. Ground in the
    numbers from the headlines. Folkloric voice — never "the shop"
    flatly; "the kettle", "the counter", "the warmth" are better.
    """)
    let shopSection: String

    @Guide(description: """
    Notable social shifts among the residents. 1 to 2 sentences. ONLY
    mention pairs whose opinion of each other crossed a threshold today
    (the prompt names them explicitly). If the prompt has none, write a
    brief line about quiet relations between neighbors. Never invent
    grudges or friendships not in the prompt.
    """)
    let socialSection: String

    @Guide(description: """
    Closing line. ONE sentence, folkloric. Points toward sleep, dusk,
    or the night to come. Slightly mournful, slightly warm. Never
    mentions ghosts, death, souls, or purgatory directly.
    """)
    let closingLine: String
}
#endif

// MARK: - Service

final class DailyChronicleService {

    static let shared = DailyChronicleService()
    private init() {}

    // MARK: - Availability

    var isAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available: return true
            default:         return false
            }
        }
        #endif
        return false
    }

    // MARK: - Public API

    /// Generate a chronicle for a day's ledger snapshot. Calls back on the
    /// main queue. Falls back to a deterministic template if the LLM is
    /// unavailable or errors out.
    ///
    /// `dayCount` is the day BEING described — not the new day that just
    /// dawned.
    func generate(
        dayCount: Int,
        events: [LedgerEvent],
        completion: @escaping (GeneratedDailyChronicleResult) -> Void
    ) {
        let headlines = DailyChronicleHeadlines.aggregate(events)

        guard isAvailable else {
            Log.info(.dialogue, "[Chronicle] LLM unavailable — using fallback template")
            DispatchQueue.main.async {
                completion(Self.fallbackResult(day: dayCount, headlines: headlines, events: events))
            }
            return
        }

        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            Task.detached { [weak self] in
                guard let self else { return }
                do {
                    let llmResult = try await self.runLLM(
                        dayCount: dayCount, headlines: headlines, events: events
                    )
                    DispatchQueue.main.async { completion(llmResult) }
                } catch {
                    Log.error(.dialogue, "[Chronicle] LLM generation failed: \(error)")
                    let fallback = Self.fallbackResult(day: dayCount, headlines: headlines, events: events)
                    DispatchQueue.main.async { completion(fallback) }
                }
            }
            return
        }
        #endif

        DispatchQueue.main.async {
            completion(Self.fallbackResult(day: dayCount, headlines: headlines, events: events))
        }
    }

    // MARK: - LLM Path

    #if canImport(FoundationModels)
    @available(iOS 26.0, *)
    private func runLLM(
        dayCount: Int,
        headlines: DailyChronicleHeadlines,
        events: [LedgerEvent]
    ) async throws -> GeneratedDailyChronicleResult {

        let session = LanguageModelSession(instructions: Self.EDIT_ME_SYSTEM_INSTRUCTIONS)
        let prompt = Self.buildPrompt(dayCount: dayCount, headlines: headlines, events: events)

        let response = try await session.respond(
            generating: GeneratedDailyChronicle.self
        ) {
            prompt
        }
        let g = response.content
        return GeneratedDailyChronicleResult(
            openingLine: g.openingLine,
            forestSection: g.forestSection,
            minesSection: g.minesSection,
            shopSection: g.shopSection,
            socialSection: g.socialSection,
            closingLine: g.closingLine,
            usedLLM: true
        )
    }
    #endif

    // ============================================================
    // MARK: - EDIT_ME_SYSTEM_INSTRUCTIONS
    // ============================================================
    //
    // This is the persona / voice / hard-rules block. The LLM reads
    // this once per chronicle. Tweak freely.
    //
    static let EDIT_ME_SYSTEM_INSTRUCTIONS: String = """
    You are the unseen chronicler of a small boba shop tucked deep in a \
    looping forest, for an iOS game called "Boba at Dawn". You write \
    one short page each dawn, describing the day that just ended. Your \
    voice is folkloric and a little archaic — the cadence of an old \
    forest almanac, a parish ledger, a hedge-witch's diary. Cozy at the \
    edges, dark in the middle. You notice weather, light, small \
    sensory detail; you name things specifically; you do not editorialize.

    HARD RULES (never break)
    - Never use the words: ghost, dead, soul, purgatory, afterlife, \
      spirit, heaven, hell. The shop's residents do not know they are \
      in purgatory. The chronicle preserves that.
    - Never invent events that aren't in the prompt's event list or \
      headlines. If a section has no input, write a brief atmospheric \
      line for it — never confabulate concrete happenings.
    - Never break the fourth wall. No mention of "the player", "you", \
      "the shopkeeper" as a character. The chronicle is told from the \
      forest's point of view, as if the trees themselves were watching.
    - When a boss promotion or demotion line is provided in the prompt, \
      quote it verbatim inside quotation marks within the mines section.
    - Keep each section the requested length. Do not pad.
    - Use lowercase for the days of the week and seasons. Use simple \
      punctuation; no em-dashes longer than one. No exclamation marks.

    VOICE TARGETS
    - Sentences are short to medium. No long ribbons of clauses.
    - Concrete nouns over abstract ones: "the kettle" not "the work", \
      "the path" not "the area", "the lantern" not "the light source".
    - Slight archaisms are welcome ("by midmorning", "before second \
      cup", "ere dusk") but never strained.
    - Names of residents and gnomes are sacred — render them exactly \
      as given in the prompt.
    """

    // ============================================================
    // MARK: - EDIT_ME_PROMPT_TEMPLATE
    // ============================================================
    //
    // Per-day prompt. Tweak the surrounding scaffolding here. The
    // numeric values are interpolated below in `buildPrompt`.
    //
    static func EDIT_ME_PROMPT_TEMPLATE(
        dayLabel: String,
        headlinesBlock: String,
        eventsBlock: String,
        bossLineBlock: String,
        socialBlock: String
    ) -> String {
        """
        Write the chronicle for \(dayLabel).

        Below are the day's headlines and the raw event log. Use them \
        to ground every section. If a section's input is empty, write \
        only a short atmospheric line for it — do not invent details.

        HEADLINES
        \(headlinesBlock)

        EVENTS (in the order they happened)
        \(eventsBlock)
        \(bossLineBlock)\(socialBlock)
        Now produce the six sections defined by the schema. Stay in \
        the folkloric voice. Quote any boss line verbatim. Keep each \
        section to its required length.
        """
    }

    // ============================================================

    // MARK: - Prompt Construction

    private static func buildPrompt(
        dayCount: Int,
        headlines: DailyChronicleHeadlines,
        events: [LedgerEvent]
    ) -> String {
        let dayLabel = "Day \(dayCount)"

        // Headlines block
        var headlineLines: [String] = [
            "  - drinks served: \(headlines.drinksServed)",
            "  - gems carried to the treasury: \(headlines.gemsCollected)",
            "  - trash gathered: \(headlines.trashCleanedCount)",
            "  - trash that appeared: \(headlines.trashSpawnedCount)",
            "  - liberations: \(headlines.liberations)",
            "  - rank changes among the gnomes: \(headlines.rankChanges)",
            "  - new arrivals at the counter: \(headlines.npcArrivals)"
        ]
        if !headlines.foragedByIngredient.isEmpty {
            let s = headlines.foragedByIngredient
                .map { "\($0.value) \($0.key)" }
                .sorted()
                .joined(separator: ", ")
            headlineLines.append("  - foraged: \(s)")
        }
        if !headlines.depositedByIngredient.isEmpty {
            let s = headlines.depositedByIngredient
                .map { "\($0.value) \($0.key)" }
                .sorted()
                .joined(separator: ", ")
            headlineLines.append("  - put into pantry/fridge: \(s)")
        }
        if !headlines.retrievedByIngredient.isEmpty {
            let s = headlines.retrievedByIngredient
                .map { "\($0.value) \($0.key)" }
                .sorted()
                .joined(separator: ", ")
            headlineLines.append("  - taken from pantry/fridge: \(s)")
        }
        let headlinesBlock = headlineLines.joined(separator: "\n")

        // Events block (skip threshold crossings — they go in the social block separately)
        let prosaicEvents = events.filter { $0.kind != .opinionThresholdCrossed }
        let eventsBlock: String
        if prosaicEvents.isEmpty {
            eventsBlock = "  (the day was quiet — nothing of note in the log)"
        } else {
            eventsBlock = prosaicEvents.map { describe($0) }.map { "  - \($0)" }.joined(separator: "\n")
        }

        // Boss line block (lifted verbatim, must be quoted in the chronicle)
        let bossEvent = events.first(where: {
            $0.kind == .gnomeRankChanged && ($0.bossLine?.isEmpty == false)
        })
        let bossLineBlock: String = {
            guard let e = bossEvent, let line = e.bossLine else { return "" }
            return "\n\nBOSS LINE (quote this verbatim, in quotation marks, in the mines section):\n  \"\(line)\"\n"
        }()

        // Social block (threshold crossings)
        let crossings = events.filter { $0.kind == .opinionThresholdCrossed }
        let topCrossings = Array(crossings.prefix(3))
        let socialBlock: String
        if topCrossings.isEmpty {
            socialBlock = "\n\nSOCIAL SHIFTS\n  (none worth recording — relations among neighbors held their shape today)\n"
        } else {
            let lines = topCrossings.map { e -> String in
                let of = e.pairOfName ?? e.pairOfID ?? "?"
                let toward = e.pairTowardName ?? e.pairTowardID ?? "?"
                let threshold = e.threshold ?? "?"
                let dir = e.crossingDirection ?? "?"
                let phrase: String
                switch (threshold, dir) {
                case ("hostile",  "down"): phrase = "tipped into open hostility toward"
                case ("hostile",  "up"):   phrase = "softened out of hostility toward"
                case ("avoidant", "down"): phrase = "pulled away from"
                case ("avoidant", "up"):   phrase = "began warming again toward"
                case ("friendly", "up"):   phrase = "grew friendly with"
                case ("friendly", "down"): phrase = "drifted out of friendship with"
                case ("close",    "up"):   phrase = "grew close with"
                case ("close",    "down"): phrase = "lost their closeness with"
                default:                   phrase = "shifted toward"
                }
                return "  - \(of) \(phrase) \(toward)"
            }.joined(separator: "\n")
            socialBlock = "\n\nSOCIAL SHIFTS (mention these specifically; do not invent others)\n\(lines)\n"
        }

        return EDIT_ME_PROMPT_TEMPLATE(
            dayLabel: dayLabel,
            headlinesBlock: headlinesBlock,
            eventsBlock: eventsBlock,
            bossLineBlock: bossLineBlock,
            socialBlock: socialBlock
        )
    }

    /// Render one ledger event as a short line for the prompt.
    private static func describe(_ e: LedgerEvent) -> String {
        switch e.kind {
        case .drinkServed:
            return "served a drink to \(e.npcName ?? "a guest")"
        case .gemDeposited:
            if let g = e.gnomeName { return "\(g) carried a gem to the treasury" }
            return "a gem was set on the treasury pile"
        case .ingredientForaged:
            return "foraged a \(e.ingredient ?? "thing") in the woods"
        case .ingredientDeposited:
            return "stowed a \(e.ingredient ?? "thing") in the \(e.container ?? "cupboard")"
        case .ingredientRetrieved:
            return "took a \(e.ingredient ?? "thing") from the \(e.container ?? "cupboard")"
        case .trashSpawned:
            return "a wrapper or cup ended up at \(e.location ?? "somewhere in the woods")"
        case .trashCleaned:
            return "tidied a piece of refuse from \(e.location ?? "the floor")"
        case .npcArrivedShop:
            return "\(e.npcName ?? "a neighbor") came to the counter"
        case .npcLiberated:
            let kind = e.liberationKind ?? "quiet"
            return "\(e.npcName ?? "a neighbor") was let go in a \(kind) light"
        case .gnomeRankChanged:
            let name = e.gnomeName ?? "a gnome"
            let rank = e.newRank ?? "a new station"
            let dir = (e.rankChangeIsPromotion ?? true) ? "raised to" : "set back to"
            return "\(name) was \(dir) \(rank)"
        case .opinionThresholdCrossed:
            // Handled separately in the social block.
            return ""
        }
    }

    // MARK: - Fallback Template

    /// Deterministic fallback used when the on-device LLM isn't available
    /// (pre-iOS 26 simulator, Apple Intelligence off, runtime error).
    /// The voice is plainer than the LLM path but stays folkloric.
    static func fallbackResult(
        day: Int,
        headlines: DailyChronicleHeadlines,
        events: [LedgerEvent]
    ) -> GeneratedDailyChronicleResult {

        let opening = "Day \(day) came in plain and went out the same."

        let forest: String = {
            var bits: [String] = []
            let foraged = headlines.foragedByIngredient.values.reduce(0, +)
            if foraged > 0 {
                let parts = headlines.foragedByIngredient
                    .map { "\($0.value) \($0.key)" }
                    .sorted()
                    .joined(separator: ", ")
                bits.append("The path gave up \(parts) to the basket.")
            }
            if headlines.trashSpawnedCount > 0 {
                bits.append("A wrapper or two turned up where they shouldn't have.")
            }
            if headlines.trashCleanedCount > 0 {
                bits.append("\(headlines.trashCleanedCount) bit\(headlines.trashCleanedCount == 1 ? "" : "s") of refuse went to the bin.")
            }
            return bits.isEmpty
                ? "The trees kept their own counsel today."
                : bits.joined(separator: " ")
        }()

        let mines: String = {
            var bits: [String] = []
            if headlines.gemsCollected > 0 {
                bits.append("\(headlines.gemsCollected) gem\(headlines.gemsCollected == 1 ? "" : "s") found their way to the treasury.")
            }
            if let rank = events.first(where: { $0.kind == .gnomeRankChanged }) {
                if let line = rank.bossLine, !line.isEmpty {
                    bits.append("The boss spoke: \"\(line)\"")
                } else if let name = rank.gnomeName, let r = rank.newRank {
                    let dir = (rank.rankChangeIsPromotion ?? true) ? "raised to" : "set back to"
                    bits.append("\(name) was \(dir) \(r).")
                }
            }
            return bits.isEmpty
                ? "The stones gave up nothing of note today."
                : bits.joined(separator: " ")
        }()

        let shop: String = {
            var bits: [String] = []
            if headlines.npcArrivals > 0 {
                bits.append("\(headlines.npcArrivals) neighbor\(headlines.npcArrivals == 1 ? "" : "s") found their way to the counter.")
            }
            if headlines.drinksServed > 0 {
                bits.append("\(headlines.drinksServed) cup\(headlines.drinksServed == 1 ? "" : "s") went out warm.")
            }
            if headlines.liberations > 0 {
                bits.append("One among them was finally let go.")
            }
            return bits.isEmpty
                ? "The kettle stayed cold most of the day."
                : bits.joined(separator: " ")
        }()

        let social: String = {
            let crossings = events.filter { $0.kind == .opinionThresholdCrossed }
            guard let top = crossings.first else {
                return "Among the cabins, things held their shape."
            }
            let of = top.pairOfName ?? "someone"
            let toward = top.pairTowardName ?? "another"
            switch (top.threshold ?? "", top.crossingDirection ?? "") {
            case ("hostile", "down"):  return "\(of) turned sour against \(toward)."
            case ("hostile", "up"):    return "\(of) softened a little toward \(toward)."
            case ("friendly", "up"):   return "\(of) grew friendly with \(toward)."
            case ("close", "up"):      return "\(of) and \(toward) drew close."
            case ("avoidant", "down"): return "\(of) began avoiding \(toward) outright."
            default:                    return "Something shifted between \(of) and \(toward)."
            }
        }()

        let closing = "And the lanterns dimmed, and the path went still."

        return GeneratedDailyChronicleResult(
            openingLine: opening,
            forestSection: forest,
            minesSection: mines,
            shopSection: shop,
            socialSection: social,
            closingLine: closing,
            usedLLM: false
        )
    }
}
