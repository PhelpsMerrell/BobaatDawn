//
//  OpinionModels.swift
//  BobaAtDawn
//
//  Types backing the NPC ↔ NPC opinion system: global topics, per-NPC
//  stances on those topics, the categorical interactions that move
//  pairwise opinion scores, and shared math for seeding initial scores.
//
//  All NPCs have a single fixed `talkativeness` (defined in NPCData) and a
//  bag of `opinion_stances` keyed by global topic id. When two NPCs are
//  considered for the first time, we seed their pairwise opinion score by
//  walking each topic and applying agreement / disagreement deltas. Beyond
//  that, conversation outcomes (ConversationInteraction) and explicit JSON
//  relationship overrides bend the score over time.
//

import Foundation

// MARK: - Opinion Topic

/// A global "thing to have an opinion on". Defined once in npc_dialogue.json
/// under `opinion_topics`. Every NPC may declare a stance on it.
struct OpinionTopic: Codable, Equatable {
    let id: String        // stable key, e.g. "gnomes", "the_cave"
    let label: String     // human-readable, used by the LLM prompt
    let axis: String      // grouping hint: "fear" | "wonder" | "tastes" | "habit" | "social"
}

// MARK: - Opinion Stance

/// How strongly an NPC feels about a topic. `unaware` means they have no
/// opinion at all — neither agreement nor disagreement nudges them.
enum OpinionStance: String, Codable, CaseIterable {
    case loves
    case likes
    case neutral
    case dislikes
    case fears
    case unaware

    /// Numeric "valence" used for agreement math.
    /// Range: -2 ... +2. `unaware` is treated specially (skipped).
    var valence: Int {
        switch self {
        case .loves:    return  2
        case .likes:    return  1
        case .neutral:  return  0
        case .dislikes: return -1
        case .fears:    return -2
        case .unaware:  return  0
        }
    }

    /// Whether this NPC actually has a stance worth comparing.
    var isVoiced: Bool { self != .unaware }
}

// MARK: - Conversation Interaction (Enum-Oriented Score Deltas)

/// One discrete *thing that happened* during an NPC ↔ NPC exchange. The LLM
/// produces a list of these per conversation; the conversation service
/// applies the deltas mechanically so opinion-score movement is predictable
/// and not at the mercy of free-form generation.
///
/// Each case carries `selfDelta` (how the speaker's opinion of the other
/// shifts) and `otherDelta` (how the listener's opinion of the speaker
/// shifts). Numbers are intentionally small — opinion change should
/// accumulate over many conversations, not lurch in one.
enum ConversationInteraction: String, Codable, CaseIterable {
    case agreement
    case strongAgreement
    case disagreement
    case strongDisagreement
    case sharedFear
    case sharedJoy
    case venting
    case dismissal
    case insult
    case compliment
    case gossipShared        // gossip about an absent third party — bonding
    case awkwardSilence
    case smallTalk

    var selfDelta: Int {
        switch self {
        case .agreement:           return  2
        case .strongAgreement:     return  4
        case .disagreement:        return -1
        case .strongDisagreement:  return -3
        case .sharedFear:          return  3
        case .sharedJoy:           return  4
        case .venting:             return  2
        case .dismissal:           return  0    // dismisser is unbothered
        case .insult:              return -1    // bit of self-disgust
        case .compliment:          return  1
        case .gossipShared:        return  2
        case .awkwardSilence:      return -1
        case .smallTalk:           return  1
        }
    }

    var otherDelta: Int {
        switch self {
        case .agreement:           return  2
        case .strongAgreement:     return  4
        case .disagreement:        return -1
        case .strongDisagreement:  return -3
        case .sharedFear:          return  3
        case .sharedJoy:           return  4
        case .venting:             return  2
        case .dismissal:           return -3    // dismissed party feels it
        case .insult:              return -5    // target feels it the most
        case .compliment:          return  3
        case .gossipShared:        return  2
        case .awkwardSilence:      return -1
        case .smallTalk:           return  1
        }
    }
}

// MARK: - Past-Life Echo

/// A vague, oblique sense one NPC has of another from their before-time.
/// Surfaces only at night and only as a fragment — never named. The
/// dialogue system feeds `hint` to the LLM with strict instructions not
/// to name causes or use forbidden words ("dead", "ghost", etc.).
struct PastLifeEcho: Codable, Equatable {
    let with: String      // other NPC's id
    let vibe: String      // "fragment" | "warmth" | "unease" | "familiar" | "longing"
    let hint: String      // sense-fragment, never a full thought
}

// MARK: - Explicit Relationship Override

/// Hand-authored adjustments layered on top of the auto-seeded opinion
/// score. Use for "Qari blames Rascal for the road incident" style cases
/// that aren't expressible through topic-stance overlap.
struct ExplicitRelationship: Codable, Equatable {
    let with: String       // other NPC's id
    let delta: Int         // signed; added to the seeded base score
    let reason: String     // designer note + optional LLM context
}

// MARK: - Personality

/// Voice/style hints fed to the LLM. Optional — defaults are fine.
struct NPCPersonality: Codable, Equatable {
    let archetype: String          // one-line shape ("skittish optimist")
    let traits: [String]           // adjectives for prompt seasoning
    let speechQuirks: [String]?    // optional cadence hints

    enum CodingKeys: String, CodingKey {
        case archetype, traits
        case speechQuirks = "speech_quirks"
    }
}

// MARK: - Pairwise Opinion Seeding

enum OpinionSeed {

    /// Seed a starting opinion score (typically clamped to [-100, +100])
    /// from two NPCs' stances on the global topics, plus any explicit
    /// relationship deltas one declares about the other.
    ///
    /// Math:
    ///   for each topic both NPCs have a *voiced* stance on:
    ///     dot = stanceA.valence * stanceB.valence
    ///       agreement same sign      →  +(2..4)
    ///       opposite sign            →  -(2..4)
    ///       one neutral              →   0
    ///
    ///   "fears + fears" feels like a bigger bond than "likes + likes",
    ///   so absolute valence multiplies the magnitude — products land in
    ///   {1, 2, 4} naturally.
    static func seedScore(
        a: NPCData,
        b: NPCData,
        topics: [OpinionTopic]
    ) -> Int {
        var score = 0
        for topic in topics {
            let sa = a.opinionStances[topic.id] ?? .unaware
            let sb = b.opinionStances[topic.id] ?? .unaware
            guard sa.isVoiced && sb.isVoiced else { continue }
            // dot is in {-4, -2, -1, 1, 2, 4} once we strip 0s
            let dot = sa.valence * sb.valence
            if dot == 0 { continue }
            score += dot
        }

        // Layer explicit overrides A → B.
        if let override = a.explicitRelationships.first(where: { $0.with == b.id }) {
            score += override.delta
        }

        return clamp(score, lo: -100, hi: 100)
    }

    /// Topic ids both NPCs have a voiced stance on. Used by the
    /// conversation service to pick a topic seed both speakers can
    /// actually engage with.
    static func sharedVoicedTopics(
        a: NPCData,
        b: NPCData,
        topics: [OpinionTopic]
    ) -> [OpinionTopic] {
        topics.filter { topic in
            let sa = a.opinionStances[topic.id] ?? .unaware
            let sb = b.opinionStances[topic.id] ?? .unaware
            return sa.isVoiced && sb.isVoiced
        }
    }

    /// Whether two NPCs' stances on a topic *agree* (same sign of valence).
    /// `unaware` on either side returns nil.
    static func stancesAgree(
        _ a: OpinionStance,
        _ b: OpinionStance
    ) -> Bool? {
        guard a.isVoiced && b.isVoiced else { return nil }
        if a.valence == 0 || b.valence == 0 { return nil }
        return (a.valence > 0) == (b.valence > 0)
    }

    @inline(__always)
    static func clamp(_ v: Int, lo: Int, hi: Int) -> Int {
        max(lo, min(hi, v))
    }
}

// MARK: - Hostility Thresholds

enum HostilityThreshold {
    /// Below this score, NPC may actively pursue petty hostile actions
    /// (drop trash at the other's home, refuse to converse, etc.).
    static let hostile = -45
    /// Below this, the two strongly avoid each other in conversation pairing.
    static let avoidant = -20
    /// At or above this, they're friendly enough for shared-joy interactions
    /// to fire more easily.
    static let friendly = 25
    /// At or above this, they're close — eligible for "shared inside joke"
    /// or "sit at the same table" behaviors down the line.
    static let close = 55
}
