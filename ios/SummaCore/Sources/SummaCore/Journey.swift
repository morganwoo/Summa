import Foundation

/// One habit's identity and record, as the reports need it.
public struct HabitRecord: Equatable, Sendable {
    public var id: UUID
    public var title: String
    public var minimumVersion: String
    public var timeline: HabitTimeline

    public init(id: UUID, title: String, minimumVersion: String, timeline: HabitTimeline) {
        self.id = id; self.title = title; self.minimumVersion = minimumVersion; self.timeline = timeline
    }
}

/// A report for one week of the program, computed from the stored records every time it is shown.
public struct WeeklyReport: Equatable, Sendable, Identifiable {
    public var week: Int
    public var range: ClosedRange<DayKey>
    public var scheduled: Int
    public var completed: Int
    public var strongest: String?
    public var weakest: String?
    /// Last week's completion, when there was a last week with anything due.
    public var previousPercent: Int?
    /// Plain-language suggestions. Nothing is ever changed without the person editing a habit themselves.
    public var suggestions: [String]
    /// Habits missed often enough that an adjustment is worth considering.
    public var habitsToReview: [UUID]

    public var id: Int { week }
    public var missed: Int { scheduled - completed }
    public var percent: Int? { scheduled == 0 ? nil : Int((Double(completed) / Double(scheduled) * 100).rounded()) }
    public var change: Int? {
        guard let percent, let previousPercent else { return nil }
        return percent - previousPercent
    }
}

public enum ReportBuilder {
    /// Twelve full weeks, then days 85–90.
    public static let weekCount = 13

    public static func range(week: Int, planStart: DayKey) -> ClosedRange<DayKey> {
        let first = planStart.adding((week - 1) * 7)
        let last = min(first.adding(6), planStart.adding(HabitTimeline.planLength - 1))
        return first...last
    }

    /// Weeks that have ended, newest first. A report appears the day after its week closes.
    public static func finishedWeeks(planStart: DayKey, today: DayKey) -> [Int] {
        (1...weekCount).filter { range(week: $0, planStart: planStart).upperBound < today }.reversed()
    }

    public static func report(week: Int, habits: [HabitRecord], today: DayKey) -> WeeklyReport {
        guard let planStart = habits.first?.timeline.planStart else {
            let day = today
            return WeeklyReport(week: week, range: day...day, scheduled: 0, completed: 0, strongest: nil, weakest: nil,
                                previousPercent: nil, suggestions: ["Nothing was due this week."], habitsToReview: [])
        }
        let span = range(week: week, planStart: planStart)
        func stats(_ record: HabitRecord, _ range: ClosedRange<DayKey>) -> HabitMetrics {
            HabitMetrics.compute(record.timeline, today: today, range: range)
        }
        let rows = habits.map { (record: $0, metrics: stats($0, span)) }.filter { $0.metrics.scheduledCount > 0 }
        let scheduled = rows.reduce(0) { $0 + $1.metrics.scheduledCount }
        let completed = rows.reduce(0) { $0 + $1.metrics.completedCount }

        var previousPercent: Int?
        var previousByHabit: [UUID: Double] = [:]
        if week > 1 {
            let before = range(week: week - 1, planStart: planStart)
            var s = 0, c = 0
            for habit in habits {
                let m = stats(habit, before)
                s += m.scheduledCount
                c += m.completedCount
                if let rate = m.completion { previousByHabit[habit.id] = rate }
            }
            if s > 0 { previousPercent = Int((Double(c) / Double(s) * 100).rounded()) }
        }

        let ranked = rows.sorted {
            let a = $0.metrics.completion ?? 0, b = $1.metrics.completion ?? 0
            return a != b ? a > b : $0.metrics.scheduledCount > $1.metrics.scheduledCount
        }
        let strongest = ranked.first
        let weakest = ranked.count > 1 && (ranked.last?.metrics.completion ?? 1) < 1
            && ranked.last?.metrics.completion != strongest?.metrics.completion ? ranked.last : nil

        var suggestions: [String] = []
        var review: [UUID] = []
        for row in rows where row.metrics.scheduledCount >= 2 && (row.metrics.completion ?? 1) <= 0.5 {
            let title = row.record.title
            if let before = previousByHabit[row.record.id], before <= 0.5 {
                review.append(row.record.id)
                suggestions.append("“\(title)” was missed more often than kept for two weeks running. Consider fewer days, or making the minimum version (“\(row.record.minimumVersion)”) the target. Nothing changes unless you edit it.")
            } else {
                suggestions.append("“\(title)” slipped this week. On a hard day the minimum still counts: \(row.record.minimumVersion).")
            }
        }
        // The weekday that cost the most.
        var missesByWeekday: [Int: Int] = [:]
        var day = span.lowerBound
        while day <= span.upperBound {
            for habit in habits where habit.timeline.status(on: day, today: today) == .missed { missesByWeekday[day.weekday, default: 0] += 1 }
            day = day.adding(1)
        }
        if let worst = missesByWeekday.max(by: { $0.value != $1.value ? $0.value < $1.value : $0.key > $1.key }), worst.value >= 2,
           missesByWeekday.values.filter({ $0 == worst.value }).count == 1 {
            let names = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
            suggestions.append("Most misses fell on \(names[worst.key - 1]). Consider lightening or moving that day.")
        }
        let percent = scheduled == 0 ? nil : Int((Double(completed) / Double(scheduled) * 100).rounded())
        if let percent, let previousPercent, percent - previousPercent <= -15 {
            suggestions.append("Down \(previousPercent - percent) points from last week. Find the day the run broke and protect it next week.")
        }
        if scheduled == 0 {
            suggestions = ["Nothing was due this week."]
        } else if suggestions.isEmpty {
            suggestions.append((percent ?? 0) >= 90 ? "A strong week. Keep the schedule exactly as it is."
                                                    : "Steady. Pick one missed day and decide in advance how you will keep it next week.")
        }
        return WeeklyReport(week: week, range: span, scheduled: scheduled, completed: completed,
                            strongest: strongest?.record.title, weakest: weakest?.record.title,
                            previousPercent: previousPercent, suggestions: suggestions, habitsToReview: review)
    }
}

/// Day 90 graduation: at least 80% of every scheduled activity across the whole program.
/// Non-daily habits, rest days, mid-plan habits, archived habits, and schedule changes are all
/// already reflected in each habit's timeline, so the count is simply completed ÷ scheduled.
public struct GraduationResult: Equatable, Sendable {
    public var completed: Int
    public var scheduled: Int
    public var percent: Int
    public var eligible: Bool

    public init(completed: Int, scheduled: Int, percent: Int, eligible: Bool) {
        self.completed = completed; self.scheduled = scheduled; self.percent = percent; self.eligible = eligible
    }
}

public enum Graduation {
    public static let threshold = 80

    public static func evaluate(timelines: [HabitTimeline]) -> GraduationResult {
        var completed = 0, scheduled = 0
        for timeline in timelines {
            let m = HabitMetrics.compute(timeline, today: timeline.planEnd)
            completed += m.completedCount
            scheduled += m.scheduledCount
        }
        let percent = scheduled == 0 ? 0 : Int((Double(completed) / Double(scheduled) * 100).rounded(.down))
        // Integer comparison, so 79.9% never rounds up into a graduation.
        return GraduationResult(completed: completed, scheduled: scheduled, percent: percent,
                                eligible: scheduled > 0 && completed * 100 >= threshold * scheduled)
    }

    /// True once day 90 is finished: every habit due that day is done, or the day has passed.
    public static func isDue(timelines: [HabitTimeline], planStart: DayKey, today: DayKey) -> Bool {
        let last = planStart.adding(HabitTimeline.planLength - 1)
        if today > last { return true }
        guard today == last else { return false }
        let day = PlanProgress.day(last, timelines: timelines, today: today)
        return day.scheduled == 0 || day.completed == day.scheduled
    }
}

/// Starting text for the three milestones, drawn from the person's own objective. They can rewrite each one.
public enum MilestoneBuilder {
    public static let days = [21, 66, 90]

    public static func defaults(objective: String, firstHabit: String, target: String) -> [(day: Int, text: String)] {
        let goal = objective.trimmed.isEmpty ? "your objective" : "“\(String(objective.trimmed.prefix(120)))”"
        let habit = firstHabit.trimmed.isEmpty ? "your first habit" : "“\(firstHabit.trimmed)”"
        let amount = target.trimmed.isEmpty ? "" : " at \(target.trimmed)"
        return [
            (21, "Foundation laid: \(habit)\(amount) kept for three weeks, and one visible first step toward \(goal)."),
            (66, "Momentum: a measurable halfway result for \(goal). Write the number or proof you want to see here."),
            (90, "Transformation: \(goal), done or clearly within reach. Describe what done looks like."),
        ]
    }
}
