import Foundation

/// Rules for daily reflections: private journal entries attached to one day of one journey.
public enum ReflectionRule {
    public static let maxLength = 4000

    /// Trimmed, and clipped to the longest entry that is kept.
    public static func normalized(_ text: String) -> String {
        String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(maxLength))
    }

    public static func isSavable(_ text: String) -> Bool { !normalized(text).isEmpty }
}

/// Daily reflections are part of Summa Pro. Every read and write goes through this check;
/// hiding a button is never the only thing standing in the way.
public enum ReflectionAccess {
    public enum Denial: Error, Equatable, Sendable { case proRequired }

    public static func denial(isPro: Bool) -> Denial? { isPro ? nil : .proRequired }

    /// Saved entries are never removed when a subscription ends: they are only withheld.
    public static func visible<T>(_ saved: [T], isPro: Bool) -> [T] { isPro ? saved : [] }
}

/// Fair-use limits for the reflection companion. The server enforces its own limit as well.
public enum CompanionLimit {
    public static let messagesPerDay = 30
    /// Only the most recent turns are sent, to keep requests small.
    public static let turnsSent = 16
    public static let maxMessageLength = 2000

    public static func remaining(usedToday: Int) -> Int { max(0, messagesPerDay - max(0, usedToday)) }
    public static func canSend(usedToday: Int) -> Bool { remaining(usedToday: usedToday) > 0 }
}

/// One answer from the companion. A proposed reflection is only ever a suggestion:
/// nothing is saved until the person reviews it and approves.
public struct CompanionReply: Codable, Equatable, Sendable {
    public var reply: String
    public var proposedReflection: String?
    /// A `VictoryCategory` raw value suggested with the proposal, if any.
    public var proposedCategory: String?

    public init(reply: String, proposedReflection: String? = nil, proposedCategory: String? = nil) {
        self.reply = reply
        self.proposedReflection = proposedReflection
        self.proposedCategory = proposedCategory
    }

    /// The proposal as an editable draft, or nil when there is nothing worth offering.
    public var draft: String? {
        guard let proposedReflection, ReflectionRule.isSavable(proposedReflection) else { return nil }
        return ReflectionRule.normalized(proposedReflection)
    }
}

/// Builds the made-up records used by the developer preview. Pure, so the thresholds are testable.
public enum DevScenario {
    public static let presetDays = [1, 21, 22, 66, 67, 89, 90]
    public static let presetRates = [79, 80, 100]

    /// Completed occurrences for a target rate, rounded down so 79% never reaches 80%.
    public static func completedCount(scheduled: Int, percent: Int) -> Int {
        max(0, min(scheduled, scheduled * max(0, min(100, percent)) / 100))
    }

    /// For each habit, the day offsets (0-based from the plan start) that are checked in,
    /// with misses spread evenly across the resolved days.
    public static func completedOffsets(habits: Int, resolvedDays: Int, percent: Int) -> [Set<Int>] {
        var result = Array(repeating: Set<Int>(), count: max(0, habits))
        let total = max(0, habits) * max(0, resolvedDays)
        guard total > 0 else { return result }
        let misses = total - completedCount(scheduled: total, percent: percent)
        for slot in 0..<total {
            let missed = (slot + 1) * misses / total > slot * misses / total
            if !missed { result[slot % habits].insert(slot / habits) }
        }
        return result
    }
}

/// The kind of win a victory is. It chooses the emblem shown beside it in Your Colosseum.
public enum VictoryCategory: String, CaseIterable, Codable, Sendable {
    /// Body, sport, courage, and anything that fits nowhere else: crossed swords.
    case physical
    /// Science in general, medicine, health knowledge: the caduceus.
    case science
    /// Mathematics, physics, computing, logic: the abacus.
    case reckoning
    /// Reading, writing, languages, study of letters: the scroll.
    case letters
    /// Money, work, trade: the coin pouch.
    case wealth

    public var title: String {
        switch self {
        case .physical: return "Strength"
        case .science: return "Science"
        case .reckoning: return "Reckoning"
        case .letters: return "Letters"
        case .wealth: return "Fortune"
        }
    }

    public var emblemName: String {
        switch self {
        case .physical: return "crossed swords"
        case .science: return "caduceus"
        case .reckoning: return "abacus"
        case .letters: return "scroll"
        case .wealth: return "coin pouch"
        }
    }

    /// Reads a stored or model-supplied value; anything unknown is nil.
    public init?(loose value: String?) {
        guard let value, let match = VictoryCategory(rawValue: value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()) else { return nil }
        self = match
    }

    // Checked in this order, so "physics exam" is reckoning, not science, and a "raise" is wealth.
    private static let keywords: [(VictoryCategory, [String])] = [
        (.wealth, ["money", "salary", "raise", "saved", "saving", "savings", "debt", "paid off", "invest", "budget", "income", "revenue",
                   "client", "sale", "sold", "profit", "bonus", "promotion", "paycheck", "loan", "mortgage", "$", "dollar", "financ"]),
        (.reckoning, ["math", "calculus", "algebra", "geometry", "proof", "theorem", "statistic", "probability", "physics", "computer science",
                      "coding", "code", "program", "algorithm", "leetcode", "software", "debug", "data structure", "cpsc", "equation", "logic"]),
        (.science, ["science", "biology", "chemistry", "medicine", "medical", "anatomy", "research", "experiment", "lab ", "laboratory",
                    "neuroscience", "clinical", "dental", "dentist", "patient", "genetic", "hypothesis", "published", "paper accepted", "peer review"]),
        (.letters, ["read", "book", "chapter", "page", "wrote", "writing", "essay", "journal", "poem", "novel", "library", "language",
                    "vocabulary", "literature", "philosophy", "stoic", "meditations", "article"]),
        (.physical, ["run", "ran", "gym", "lift", "workout", "walk", "swim", "bike", "cycle", "yoga", "stretch", "weight", "kg", "lbs",
                     "marathon", "push-up", "pushup", "squat", "sport", "match", "game", "hike", "sleep", "train"]),
    ]

    /// A best guess from the words alone, used when no one has chosen. Unmatched text is `.physical`.
    public static func classify(_ text: String) -> VictoryCategory {
        let lowered = " " + text.lowercased() + " "
        for (category, words) in keywords where words.contains(where: { lowered.contains($0) }) { return category }
        return .physical
    }
}

extension CompanionReply {
    /// The category suggested with a proposal, when the model gave a valid one.
    public var category: VictoryCategory? { VictoryCategory(loose: proposedCategory) }
}

/// Roman numerals for the Colosseum's inscriptions.
public enum RomanNumeral {
    private static let table: [(Int, String)] = [(1000, "M"), (900, "CM"), (500, "D"), (400, "CD"), (100, "C"), (90, "XC"),
                                                 (50, "L"), (40, "XL"), (10, "X"), (9, "IX"), (5, "V"), (4, "IV"), (1, "I")]

    /// 1...3999 as a numeral. Anything outside that range is written in digits.
    public static func string(_ value: Int) -> String {
        guard (1...3999).contains(value) else { return String(value) }
        var rest = value, out = ""
        for (amount, symbol) in table {
            while rest >= amount { out += symbol; rest -= amount }
        }
        return out
    }
}
