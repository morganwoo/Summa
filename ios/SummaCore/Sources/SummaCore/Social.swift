import Foundation

/// One habit on one scheduled day, as shared with accepted friends.
public struct SharedDayRow: Codable, Equatable, Sendable {
    public var habitId: UUID
    public var day: String
    public var done: Bool

    public init(habitId: UUID, day: String, done: Bool) {
        self.habitId = habitId; self.day = day; self.done = done
    }
}

public enum SocialSnapshot {
    /// Every scheduled day so far for every habit. Derived from the local record each time, so sending it
    /// again is harmless: the server keys rows by habit and day and an undo simply flips `done`.
    public static func rows(for records: [HabitRecord], today: DayKey) -> [SharedDayRow] {
        var rows: [SharedDayRow] = []
        for record in records {
            let last = min(today, record.timeline.planEnd)
            var day = record.timeline.planStart
            while day <= last {
                if record.timeline.isScheduled(day) {
                    rows.append(SharedDayRow(habitId: record.id, day: day.string, done: record.timeline.completed.contains(day)))
                }
                day = day.adding(1)
            }
        }
        return rows
    }
}

public struct LeaderboardEntry: Codable, Equatable, Sendable, Identifiable {
    public var userId: UUID
    public var username: String
    public var planStart: String?
    public var weekCompleted: Int
    public var weekScheduled: Int
    public var totalCompleted: Int
    public var totalScheduled: Int
    public var isMe: Bool

    public var id: UUID { userId }

    public init(userId: UUID, username: String, planStart: String? = nil, weekCompleted: Int, weekScheduled: Int,
                totalCompleted: Int, totalScheduled: Int, isMe: Bool = false) {
        self.userId = userId; self.username = username; self.planStart = planStart
        self.weekCompleted = weekCompleted; self.weekScheduled = weekScheduled
        self.totalCompleted = totalCompleted; self.totalScheduled = totalScheduled; self.isMe = isMe
    }

    /// This week's completed ÷ scheduled, shown beside the count so a lighter schedule is not penalised.
    public var weekPercent: Int? {
        weekScheduled == 0 ? nil : Int((Double(weekCompleted) / Double(weekScheduled) * 100).rounded())
    }

    public func dayNumber(today: DayKey) -> Int? {
        planStart.flatMap { DayKey($0) }.map { max(1, min(HabitTimeline.planLength, $0.days(until: today) + 1)) }
    }
}

public enum Leaderboard {
    public enum Sort: String, CaseIterable, Sendable { case completed, consistency }

    /// The Monday that starts the week containing `today`.
    public static func weekStart(for today: DayKey) -> DayKey { today.adding(-((today.weekday + 5) % 7)) }

    public static func ranked(_ entries: [LeaderboardEntry], by sort: Sort) -> [LeaderboardEntry] {
        entries.sorted { a, b in
            let ap = a.weekPercent ?? -1, bp = b.weekPercent ?? -1
            switch sort {
            case .completed:
                if a.weekCompleted != b.weekCompleted { return a.weekCompleted > b.weekCompleted }
                if ap != bp { return ap > bp }
            case .consistency:
                if ap != bp { return ap > bp }
                if a.weekCompleted != b.weekCompleted { return a.weekCompleted > b.weekCompleted }
            }
            return a.username < b.username
        }
    }
}

/// The only messages a nudge can carry.
public enum NudgeMessage: String, CaseIterable, Sendable {
    case keepGoing = "keep_going", oneSmallStep = "one_small_step", thinkingOfYou = "thinking_of_you", proudOfYou = "proud_of_you"

    public var text: String {
        switch self {
        case .keepGoing: return "Keep going. You have this."
        case .oneSmallStep: return "One small step today still counts."
        case .thinkingOfYou: return "Thinking of you. Go at your own pace."
        case .proudOfYou: return "Proud of what you are building."
        }
    }
}

public struct ActivityEvent: Codable, Equatable, Hashable, Sendable {
    public var kind: String
    public var detail: Int
    public var chapter: Int

    public init(kind: String, detail: Int, chapter: Int) {
        self.kind = kind; self.detail = detail; self.chapter = chapter
    }

    public static func describe(kind: String, detail: Int) -> String {
        switch kind {
        case "week_complete": return "finished week \(detail)"
        case "entered_momentum": return "entered Momentum"
        case "entered_transformation": return "entered Transformation"
        case "day_90": return "reached day 90"
        case "graduated": return "earned Summa Graduation"
        default: return "made progress"
        }
    }
}

public enum ActivityBuilder {
    /// Milestones worth telling friends about, derived from the record. Sending them twice is harmless.
    public static func events(planStart: DayKey, timelines: [HabitTimeline], chapter: Int, today: DayKey) -> [ActivityEvent] {
        guard today >= planStart else { return [] }
        var events = ReportBuilder.finishedWeeks(planStart: planStart, today: today).reversed()
            .map { ActivityEvent(kind: "week_complete", detail: $0, chapter: chapter) }
        let day = planStart.days(until: today) + 1
        if day >= Stage.momentum.days.lowerBound { events.append(ActivityEvent(kind: "entered_momentum", detail: 0, chapter: chapter)) }
        if day >= Stage.transformation.days.lowerBound { events.append(ActivityEvent(kind: "entered_transformation", detail: 0, chapter: chapter)) }
        if day >= HabitTimeline.planLength { events.append(ActivityEvent(kind: "day_90", detail: 0, chapter: chapter)) }
        if Graduation.isDue(timelines: timelines, planStart: planStart, today: today), Graduation.evaluate(timelines: timelines).eligible {
            events.append(ActivityEvent(kind: "graduated", detail: 0, chapter: chapter))
        }
        return events
    }
}
