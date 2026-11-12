import Foundation

/// A set of weekdays using `Calendar` numbering (1 = Sunday … 7 = Saturday).
public struct WeekdaySet: OptionSet, Hashable, Codable, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue & 0b111_1111 }

    public init(weekdays: [Int]) {
        var raw = 0
        for day in weekdays where (1...7).contains(day) { raw |= 1 << (day - 1) }
        self.init(rawValue: raw)
    }

    public static let everyDay = WeekdaySet(rawValue: 0b111_1111)
    public static let weekdays = WeekdaySet(weekdays: [2, 3, 4, 5, 6])

    public func contains(weekday: Int) -> Bool {
        (1...7).contains(weekday) && rawValue & (1 << (weekday - 1)) != 0
    }

    public var days: [Int] { (1...7).filter { contains(weekday: $0) } }
    public var count: Int { days.count }

    public init(from decoder: Decoder) throws {
        self.init(rawValue: try decoder.singleValueContainer().decode(Int.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// A schedule that applies from `effectiveFrom` until a later rule replaces it.
/// Editing a schedule appends a rule instead of rewriting history.
public struct ScheduleRule: Hashable, Codable, Sendable {
    public var effectiveFrom: DayKey
    public var weekdays: WeekdaySet

    public init(effectiveFrom: DayKey, weekdays: WeekdaySet) {
        self.effectiveFrom = effectiveFrom
        self.weekdays = weekdays
    }
}

public enum DayStatus: String, Codable, Sendable, CaseIterable {
    /// Checked in on this day.
    case completed
    /// Scheduled, in the past, and not checked in.
    case missed
    /// Scheduled today and not yet checked in. Never breaks a streak.
    case pending
    /// Scheduled on a future day.
    case upcoming
    /// A rest day, or a day outside the habit's active life.
    case unscheduled

    public var label: String {
        switch self {
        case .completed: return "Completed"
        case .missed: return "Missed"
        case .pending: return "Due today"
        case .upcoming: return "Upcoming"
        case .unscheduled: return "Rest day"
        }
    }
}

/// Everything needed to answer "what happened on day X" for one habit.
public struct HabitTimeline: Hashable, Codable, Sendable {
    public static let planLength = 90

    public var planStart: DayKey
    public var length: Int
    /// First day this habit can be scheduled (habits can be added mid-plan).
    public var habitStart: DayKey
    /// First day the habit is no longer scheduled, if archived.
    public var archivedOn: DayKey?
    public var rules: [ScheduleRule]
    public var completed: Set<DayKey>

    public init(planStart: DayKey, length: Int = HabitTimeline.planLength, habitStart: DayKey? = nil,
                archivedOn: DayKey? = nil, rules: [ScheduleRule], completed: Set<DayKey> = []) {
        self.planStart = planStart
        self.length = max(1, length)
        self.habitStart = habitStart ?? planStart
        self.archivedOn = archivedOn
        self.rules = rules.sorted { $0.effectiveFrom < $1.effectiveFrom }
        self.completed = completed
    }

    public var planEnd: DayKey { planStart.adding(length - 1) }

    public var days: [DayKey] { (0..<length).map { planStart.adding($0) } }

    public func contains(_ day: DayKey) -> Bool { day >= planStart && day <= planEnd }

    /// The rule in force on `day`: the latest rule that started on or before it.
    public func rule(on day: DayKey) -> ScheduleRule? {
        let ordered = rules.sorted { $0.effectiveFrom < $1.effectiveFrom }
        return ordered.last(where: { $0.effectiveFrom <= day }) ?? ordered.first
    }

    public func isScheduled(_ day: DayKey) -> Bool {
        guard contains(day), day >= habitStart else { return false }
        if let archivedOn, day >= archivedOn { return false }
        guard let rule = rule(on: day) else { return false }
        return rule.weekdays.contains(weekday: day.weekday)
    }

    public func status(on day: DayKey, today: DayKey) -> DayStatus {
        if completed.contains(day), day <= today, contains(day) { return .completed }
        guard isScheduled(day) else { return .unscheduled }
        if day > today { return .upcoming }
        if day == today { return .pending }
        return .missed
    }

    /// 1-based day of the plan, clamped to 1...length. Nil before the plan starts.
    public func dayNumber(today: DayKey) -> Int? {
        guard today >= planStart else { return nil }
        return min(length, planStart.days(until: today) + 1)
    }

    public func nextScheduledDay(after day: DayKey) -> DayKey? {
        var cursor = max(day.adding(1), planStart)
        while cursor <= planEnd {
            if isScheduled(cursor) { return cursor }
            cursor = cursor.adding(1)
        }
        return nil
    }
}
