import Foundation

/// Version 1 of the plan contract shared by the app and the plan API.
/// The server validates model output against the same shape before returning it.
public enum PlanSchema {
    public static let version = 1
    /// Every new plan starts with exactly this many habits.
    public static let initialHabits = 3
    public static let planLength = 90
}

public struct ReminderDraft: Codable, Hashable, Sendable {
    public var hour: Int
    public var minute: Int
    public init(hour: Int, minute: Int) { self.hour = hour; self.minute = minute }
}

public struct HabitDraft: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var title: String
    /// The concrete, calendar-ready action, e.g. "Read two pages after breakfast".
    public var action: String
    /// The smallest version that still counts on a difficult day.
    public var minimumVersion: String
    /// The measurable amount for one occurrence, e.g. "10 pages" or "20 minutes".
    public var target: String
    /// One or two sentences tying this habit to what the person said in onboarding.
    public var reason: String
    /// `Calendar` weekdays, 1 = Sunday … 7 = Saturday.
    public var weekdays: [Int]
    public var reminder: ReminderDraft?
    public var colorHex: String
    public var symbol: String

    public init(id: UUID = UUID(), title: String, action: String, minimumVersion: String, target: String = "", reason: String = "",
                weekdays: [Int], reminder: ReminderDraft? = nil, colorHex: String = HabitPalette.gold, symbol: String = "circle") {
        self.id = id; self.title = title; self.action = action; self.minimumVersion = minimumVersion
        self.target = target; self.reason = reason
        self.weekdays = weekdays; self.reminder = reminder; self.colorHex = colorHex; self.symbol = symbol
    }

    enum CodingKeys: String, CodingKey { case id, title, action, minimumVersion, target, reason, weekdays, reminder, colorHex, symbol }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try c.decode(String.self, forKey: .title)
        action = try c.decode(String.self, forKey: .action)
        minimumVersion = try c.decode(String.self, forKey: .minimumVersion)
        target = try c.decodeIfPresent(String.self, forKey: .target) ?? ""
        reason = try c.decodeIfPresent(String.self, forKey: .reason) ?? ""
        weekdays = try c.decode([Int].self, forKey: .weekdays)
        reminder = try c.decodeIfPresent(ReminderDraft.self, forKey: .reminder)
        colorHex = try c.decodeIfPresent(String.self, forKey: .colorHex) ?? HabitPalette.gold
        symbol = try c.decodeIfPresent(String.self, forKey: .symbol) ?? "circle"
    }
}

public struct PhaseDraft: Codable, Hashable, Sendable, Identifiable {
    public var title: String
    public var startDay: Int
    public var endDay: Int
    public var focus: String
    public var id: Int { startDay }

    public init(title: String, startDay: Int, endDay: Int, focus: String) {
        self.title = title; self.startDay = startDay; self.endDay = endDay; self.focus = focus
    }

    public static func standard(focus: [String] = []) -> [PhaseDraft] {
        let defaults = ["Build a start you can keep.", "Make consistency feel natural.", "Carry your discipline forward."]
        func text(_ i: Int) -> String { i < focus.count && !focus[i].trimmed.isEmpty ? focus[i].trimmed : defaults[i] }
        return [
            PhaseDraft(title: "Find your footing", startDay: 1, endDay: 21, focus: text(0)),
            PhaseDraft(title: "Settle into rhythm", startDay: 22, endDay: 66, focus: text(1)),
            PhaseDraft(title: "Make it yours", startDay: 67, endDay: 90, focus: text(2)),
        ]
    }

    public func contains(day: Int) -> Bool { (startDay...endDay).contains(day) }
}

public struct PlanDraft: Codable, Hashable, Sendable {
    public var schemaVersion: Int
    public var objective: String
    public var habits: [HabitDraft]
    public var phases: [PhaseDraft]
    /// "ai" when drafted by the plan service, "starter" when built on device.
    public var source: String

    public init(schemaVersion: Int = PlanSchema.version, objective: String, habits: [HabitDraft],
                phases: [PhaseDraft] = PhaseDraft.standard(), source: String = "starter") {
        self.schemaVersion = schemaVersion; self.objective = objective; self.habits = habits
        self.phases = phases; self.source = source
    }

    enum CodingKeys: String, CodingKey { case schemaVersion, objective, habits, phases, source }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decode(Int.self, forKey: .schemaVersion)
        objective = try c.decode(String.self, forKey: .objective)
        habits = try c.decode([HabitDraft].self, forKey: .habits)
        phases = try c.decodeIfPresent([PhaseDraft].self, forKey: .phases) ?? PhaseDraft.standard()
        source = try c.decodeIfPresent(String.self, forKey: .source) ?? "ai"
    }
}

public enum PlanValidationError: Error, Equatable, CustomStringConvertible {
    case unsupportedVersion(Int)
    case emptyObjective
    case habitCount(Int)
    case habitField(index: Int, field: String)
    case phases

    public var description: String {
        switch self {
        case .unsupportedVersion(let v): return "Unsupported plan version \(v)."
        case .emptyObjective: return "The plan has no objective."
        case .habitCount(let n): return "A new plan starts with exactly 3 habits, got \(n)."
        case .habitField(let i, let f): return "Habit \(i + 1) has an invalid \(f)."
        case .phases: return "The plan phases must cover days 1 to 90 in order."
        }
    }
}

extension PlanDraft {
    /// Validates and normalizes a draft (trims text, sorts weekdays, fixes colors).
    /// The app never trusts a server response without passing it through here.
    public func validated() throws -> PlanDraft {
        guard schemaVersion == PlanSchema.version else { throw PlanValidationError.unsupportedVersion(schemaVersion) }
        var plan = self
        plan.objective = objective.trimmed
        guard !plan.objective.isEmpty, plan.objective.count <= 280 else { throw PlanValidationError.emptyObjective }
        guard habits.count == PlanSchema.initialHabits else {
            throw PlanValidationError.habitCount(habits.count)
        }
        for (index, habit) in habits.enumerated() {
            var h = habit
            h.title = habit.title.trimmed
            h.action = habit.action.trimmed
            h.minimumVersion = habit.minimumVersion.trimmed
            h.target = String(habit.target.trimmed.prefix(60))
            h.reason = String(habit.reason.trimmed.prefix(300))
            guard !h.title.isEmpty, h.title.count <= 60 else { throw PlanValidationError.habitField(index: index, field: "title") }
            guard !h.action.isEmpty, h.action.count <= 200 else { throw PlanValidationError.habitField(index: index, field: "action") }
            guard !h.minimumVersion.isEmpty, h.minimumVersion.count <= 200 else {
                throw PlanValidationError.habitField(index: index, field: "minimum version")
            }
            let days = Array(Set(habit.weekdays)).sorted()
            guard !days.isEmpty, days.allSatisfy({ (1...7).contains($0) }) else {
                throw PlanValidationError.habitField(index: index, field: "schedule")
            }
            h.weekdays = days
            if let r = habit.reminder {
                guard (0...23).contains(r.hour), (0...59).contains(r.minute) else {
                    throw PlanValidationError.habitField(index: index, field: "reminder")
                }
            }
            if !HabitPalette.isValidHex(h.colorHex) { h.colorHex = HabitPalette.color(at: index) }
            if h.symbol.trimmed.isEmpty { h.symbol = "circle" }
            plan.habits[index] = h
        }
        guard phases.count == 3, phases.first?.startDay == 1, phases.last?.endDay == PlanSchema.planLength,
              zip(phases, phases.dropFirst()).allSatisfy({ $0.endDay + 1 == $1.startDay }),
              phases.allSatisfy({ $0.startDay <= $0.endDay && !$0.title.trimmed.isEmpty }) else {
            throw PlanValidationError.phases
        }
        return plan
    }
}

/// Accent colors a habit can carry across its heatmap, calendar, and detail view.
public enum HabitPalette {
    public static let gold = "#DCAF61"
    public static let sage = "#8AAF96"
    public struct Entry: Hashable, Sendable, Identifiable {
        public let name: String
        public let hex: String
        public var id: String { hex }
    }

    public static let all: [Entry] = [
        Entry(name: "Antique gold", hex: gold), Entry(name: "Sage", hex: sage),
        Entry(name: "Terracotta", hex: "#C97B5A"), Entry(name: "Aegean", hex: "#6F9BC0"),
        Entry(name: "Wine", hex: "#A86A84"), Entry(name: "Olive", hex: "#A3A55B"),
        Entry(name: "Lavender", hex: "#9C8FC4"), Entry(name: "Stone", hex: "#A9A49A"),
    ]

    public static func color(at index: Int) -> String { all[((index % all.count) + all.count) % all.count].hex }

    public static func name(for hex: String) -> String {
        all.first(where: { $0.hex.caseInsensitiveCompare(hex) == .orderedSame })?.name ?? "Custom"
    }

    public static func isValidHex(_ hex: String) -> Bool {
        guard hex.count == 7, hex.hasPrefix("#") else { return false }
        return hex.dropFirst().allSatisfy { $0.isHexDigit }
    }
}

extension String {
    public var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}

/// How many habits can be active at once. Free: three. Summa Pro: unlimited.
/// Archived habits and their history never count and are never removed by a change of tier.
public enum HabitLimit {
    public static let freeActiveHabits = 3

    public static func canAddHabit(activeCount: Int, isPro: Bool) -> Bool {
        isPro || activeCount < freeActiveHabits
    }
}
