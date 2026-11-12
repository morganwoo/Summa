import Foundation

public enum QuestionID: String, Codable, CaseIterable, Sendable {
    case name, username, motivation, focus, objective, obstacles, arc, minutes, days, timeOfDay, startSize, body, future, extra
}

public enum QuestionKind: Equatable, Sendable {
    case shortText(placeholder: String)
    /// A handle with live validation. Global uniqueness is enforced once accounts exist.
    case username
    case longText(placeholder: String)
    case single(options: [String])
    case multi(options: [String], allowsCustom: Bool)
    case weekdays
    /// The illustrative 90-day arc. Nothing to answer.
    case arc
    /// Optional age / height / weight / gender, each skippable.
    case body
}

public struct Question: Equatable, Identifiable, Sendable {
    public let id: QuestionID
    public let prompt: String
    public let detail: String?
    public let kind: QuestionKind
    public let isOptional: Bool
}

/// Onboarding answers. Only what the plan needs is kept; voice audio is never stored.
public struct OnboardingAnswers: Codable, Equatable, Sendable {
    public var values: [String: [String]] = [:]
    public var referralCode: String = ""
    public var currentStep: QuestionID = .name
    /// "guided" or "talk". Switching modes keeps every answer.
    public var mode: String = "guided"

    public init() {}

    public func selections(_ id: QuestionID) -> [String] { values[id.rawValue] ?? [] }
    public func text(_ id: QuestionID) -> String { selections(id).first ?? "" }

    public mutating func set(_ id: QuestionID, _ items: [String]) {
        let cleaned = items.map { $0.trimmed }.filter { !$0.isEmpty }
        values[id.rawValue] = cleaned.isEmpty ? nil : cleaned
    }

    public mutating func set(_ id: QuestionID, text: String) { set(id, [text]) }

    public func isAnswered(_ id: QuestionID) -> Bool { !selections(id).isEmpty }

    public var name: String { text(.name) }
    public var username: String { UsernameRule.normalized(text(.username)) }
    public var focusAreas: [String] { selections(.focus) }

    public var minutesPerDay: Int {
        Int(text(.minutes).prefix(while: { $0.isNumber })) ?? 10
    }

    public var weekdays: [Int] {
        let days = selections(.days).compactMap { Int($0) }.filter { (1...7).contains($0) }
        return days.isEmpty ? [2, 3, 4, 5, 6] : Array(Set(days)).sorted()
    }

    /// Body details matter only when a goal touches movement or sleep.
    public var wantsBodyDetails: Bool {
        focusAreas.contains { ["Movement", "Sleep routine"].contains($0) }
    }
}

public enum OnboardingFlow {
    public static let focusOptions = ["Focus", "Movement", "Reading", "Sleep routine", "Reflection"]

    public static func question(_ id: QuestionID, answers: OnboardingAnswers) -> Question {
        let name = answers.name.isEmpty ? "" : ", \(answers.name)"
        switch id {
        case .name:
            return Question(id: id, prompt: "Hi, I’m Summa. What should I call you?", detail: nil,
                            kind: .shortText(placeholder: "Your name"), isOptional: false)
        case .username:
            return Question(id: id, prompt: "Choose a username\(name).",
                            detail: "3 to 20 characters: lowercase letters, numbers, and underscores, starting with a letter. Friends will find you by it later.",
                            kind: .username, isOptional: false)
        case .motivation:
            return Question(id: id, prompt: "What brought you here\(name)?", detail: "Choose any that fit.",
                            kind: .multi(options: ["I keep starting over", "I want more discipline", "A new chapter is beginning",
                                                   "I feel scattered", "Curious about Stoic practice"], allowsCustom: true),
                            isOptional: false)
        case .focus:
            return Question(id: id, prompt: "What do you want to practice for the next 90 days?",
                            detail: "Pick up to three. Fewer is stronger.",
                            kind: .multi(options: focusOptions, allowsCustom: true), isOptional: false)
        case .objective:
            return Question(id: id, prompt: "Ninety days from now, what do you want to have accomplished?",
                            detail: "One sentence is enough.",
                            kind: .longText(placeholder: "In 90 days I want to…"), isOptional: false)
        case .obstacles:
            return Question(id: id, prompt: "What typically gets in the way?", detail: "Naming it is the first defence.",
                            kind: .multi(options: ["Not enough time", "Low energy", "Phone and distractions", "Starting too big",
                                                   "An unpredictable schedule", "Losing interest"], allowsCustom: true),
                            isOptional: false)
        case .arc:
            return Question(id: id, prompt: "Resistance. Then rhythm. Then you.",
                            detail: "An illustration of how ninety days tend to feel, from getting started to finding a rhythm. It is not a forecast.",
                            kind: .arc, isOptional: true)
        case .minutes:
            return Question(id: id, prompt: "How much time can you realistically give on a normal day?",
                            detail: "Be honest. The plan is built around this.",
                            kind: .single(options: ["5 minutes", "10 minutes", "20 minutes", "30 minutes", "45 minutes or more"]),
                            isOptional: false)
        case .days:
            return Question(id: id, prompt: "Which days work?", detail: "Rest days are part of the plan. They never break a streak.",
                            kind: .weekdays, isOptional: false)
        case .timeOfDay:
            return Question(id: id, prompt: "When are you most likely to follow through?", detail: nil,
                            kind: .single(options: ["Morning", "Midday", "Evening"]), isOptional: false)
        case .startSize:
            return Question(id: id, prompt: "How small should we start?", detail: "You can always do more. The minimum is what you promise.",
                            kind: .single(options: ["Tiny — almost too easy", "Modest — a real effort", "Ambitious — I have room for it"]),
                            isOptional: false)
        case .body:
            return Question(id: id, prompt: "A few optional details",
                            detail: "You chose a goal that involves your body. Age, height, weight, and gender help set a sensible starting effort. Skip any or all of them.",
                            kind: .body, isOptional: true)
        case .future:
            return Question(id: id, prompt: "When these 90 days end, who do you want to be, and what does an ordinary day look like?",
                            detail: "Your own words shape the plan.", kind: .longText(placeholder: "On day 90 I am someone who…"), isOptional: false)
        case .extra:
            return Question(id: id, prompt: "Anything else I should know before I build your plan?", detail: "Optional.",
                            kind: .longText(placeholder: "Injuries, shift work, a newborn, a deadline…"), isOptional: true)
        }
    }

    /// The ordered steps for these answers. The body step appears only when relevant.
    public static func steps(for answers: OnboardingAnswers) -> [QuestionID] {
        QuestionID.allCases.filter { $0 != .body || answers.wantsBodyDetails }
    }

    public static func canContinue(_ id: QuestionID, answers: OnboardingAnswers) -> Bool {
        let q = question(id, answers: answers)
        if q.isOptional { return true }
        if id == .days { return true }
        if id == .username { return UsernameRule.problem(with: answers.text(.username)) == nil }
        return answers.isAnswered(id)
    }

    public static func next(after id: QuestionID, answers: OnboardingAnswers) -> QuestionID? {
        let all = steps(for: answers)
        guard let i = all.firstIndex(of: id), i + 1 < all.count else { return nil }
        return all[i + 1]
    }

    public static func previous(before id: QuestionID, answers: OnboardingAnswers) -> QuestionID? {
        let all = steps(for: answers)
        guard let i = all.firstIndex(of: id), i > 0 else { return nil }
        return all[i - 1]
    }

    public static func progress(at id: QuestionID, answers: OnboardingAnswers) -> Double {
        let all = steps(for: answers)
        guard let i = all.firstIndex(of: id) else { return 0 }
        return Double(i + 1) / Double(all.count)
    }

    public static let weekdaySymbols = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

    /// "Weekdays", "Every day", or "Mon, Wed, Fri".
    public static func describe(weekdays: [Int]) -> String {
        let days = Array(Set(weekdays.filter { (1...7).contains($0) })).sorted()
        if days.count == 7 { return "Every day" }
        if days == [2, 3, 4, 5, 6] { return "Weekdays" }
        if days == [1, 7] { return "Weekends" }
        if days.isEmpty { return "No days" }
        // Read Monday-first.
        let ordered = days.sorted { ($0 + 5) % 7 < ($1 + 5) % 7 }
        return ordered.map { weekdaySymbols[$0 - 1] }.joined(separator: ", ")
    }
}

/// Local username rules. The server will also enforce global uniqueness when accounts arrive.
public enum UsernameRule {
    public static let minLength = 3
    public static let maxLength = 20
    static let reserved: Set<String> = ["summa", "admin", "support", "help", "root", "system", "official", "moderator"]

    public static func normalized(_ raw: String) -> String { raw.trimmed.lowercased() }

    /// Nil when valid; otherwise a short sentence saying what to fix.
    public static func problem(with raw: String) -> String? {
        let name = normalized(raw)
        if name.isEmpty { return "Enter a username." }
        if name.count < minLength { return "Use at least \(minLength) characters." }
        if name.count > maxLength { return "Use \(maxLength) characters or fewer." }
        let allowed = Set("abcdefghijklmnopqrstuvwxyz0123456789_")
        if !name.allSatisfy({ allowed.contains($0) }) { return "Use only lowercase letters, numbers, and underscores." }
        if let first = name.first, !("a"..."z").contains(first) { return "Start with a letter." }
        if name.hasSuffix("_") || name.contains("__") { return "Underscores cannot end the name or sit side by side." }
        if reserved.contains(name) { return "That name is reserved. Try another." }
        return nil
    }
}
