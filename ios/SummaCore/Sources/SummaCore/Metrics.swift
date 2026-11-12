import Foundation

/// Streak and completion figures for one habit.
///
/// Rules (also explained in the app's Progress screen):
/// - A streak counts consecutive *scheduled* occurrences that were completed.
///   Rest days neither add to nor break a streak.
/// - Today's occurrence is *pending* until the day ends: it does not break the
///   streak, and it adds to the streak once completed.
/// - Completion = completed scheduled occurrences ÷ scheduled occurrences from
///   the start of the range through the end of the range or today, whichever
///   comes first. Today's occurrence counts in the denominator.
public struct HabitMetrics: Equatable, Sendable {
    public var currentStreak: Int
    public var longestStreak: Int
    public var completedCount: Int
    public var scheduledCount: Int
    /// First and last day actually measured. Nil when the range has not started.
    public var measuredRange: ClosedRange<DayKey>?
    public var todayStatus: DayStatus

    /// Nil when nothing was due in the range, so the UI can show an empty state
    /// instead of a misleading 0% or 100%.
    public var completion: Double? {
        scheduledCount == 0 ? nil : Double(completedCount) / Double(scheduledCount)
    }

    public var completionPercent: Int? {
        completion.map { Int(($0 * 100).rounded()) }
    }

    public static func compute(_ timeline: HabitTimeline, today: DayKey,
                               range: ClosedRange<DayKey>? = nil) -> HabitMetrics {
        let lastCountable = min(today, timeline.planEnd)

        var run = 0
        var longest = 0
        if lastCountable >= timeline.planStart {
            var day = timeline.planStart
            while day <= lastCountable {
                switch timeline.status(on: day, today: today) {
                case .completed where timeline.isScheduled(day):
                    run += 1
                    longest = max(longest, run)
                case .missed:
                    run = 0
                default:
                    break // rest days, pending today, bonus check-ins on rest days
                }
                day = day.adding(1)
            }
        }

        let requested = range ?? (timeline.planStart...timeline.planEnd)
        let lower = max(requested.lowerBound, timeline.planStart)
        let upper = min(requested.upperBound, lastCountable)
        var completed = 0
        var scheduled = 0
        var measured: ClosedRange<DayKey>?
        if lower <= upper {
            measured = lower...upper
            var day = lower
            while day <= upper {
                if timeline.isScheduled(day) {
                    scheduled += 1
                    if timeline.completed.contains(day) { completed += 1 }
                }
                day = day.adding(1)
            }
        }

        return HabitMetrics(currentStreak: run, longestStreak: longest, completedCount: completed,
                            scheduledCount: scheduled, measuredRange: measured,
                            todayStatus: timeline.status(on: today, today: today))
    }
}

/// Idempotent check-in bookkeeping, kept free of persistence so it can be tested.
public enum CheckInLedger {
    /// Stable identity for one habit on one day. Used as a unique key so a
    /// duplicate write (double tap, retried save, widget + app) cannot create
    /// two records.
    public static func key(habitID: UUID, day: DayKey) -> String {
        "\(habitID.uuidString)|\(day.string)"
    }

    /// Returns the set after marking `day` complete. Marking twice is a no-op.
    public static func marking(_ day: DayKey, in completed: Set<DayKey>) -> Set<DayKey> {
        completed.union([day])
    }

    public static func clearing(_ day: DayKey, in completed: Set<DayKey>) -> Set<DayKey> {
        completed.subtracting([day])
    }
}
