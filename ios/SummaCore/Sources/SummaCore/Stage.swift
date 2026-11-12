import Foundation

/// The three stages of the 90-day program. A stage depends only on the program day,
/// never on how much has been completed.
public enum Stage: Int, CaseIterable, Codable, Sendable {
    case foundation = 1, momentum, transformation

    public var name: String {
        switch self {
        case .foundation: return "Foundation"
        case .momentum: return "Momentum"
        case .transformation: return "Transformation"
        }
    }

    public var days: ClosedRange<Int> {
        switch self {
        case .foundation: return 1...21
        case .momentum: return 22...66
        case .transformation: return 67...90
        }
    }

    /// Green, red, gold.
    public var accentHex: String {
        switch self {
        case .foundation: return "#5FAE7A"
        case .momentum: return "#C8574B"
        case .transformation: return "#DCAF61"
        }
    }

    public var tagline: String {
        switch self {
        case .foundation: return "The beginning. Small, kept promises."
        case .momentum: return "The habit is taking hold. Hold the line."
        case .transformation: return "The final stretch. Make it yours."
        }
    }

    /// The stage for a 1-based program day. Days outside 1...90 clamp to the nearest stage.
    public static func forDay(_ day: Int) -> Stage {
        if day >= Stage.transformation.days.lowerBound { return .transformation }
        if day >= Stage.momentum.days.lowerBound { return .momentum }
        return .foundation
    }

    /// The stage to celebrate on arrival, if any. Foundation is where everyone starts, so it is
    /// never celebrated; a later stage is celebrated once, the first time the app sees it.
    public static func toCelebrate(current: Stage, lastCelebrated: Int) -> Stage? {
        current != .foundation && current.rawValue > lastCelebrated ? current : nil
    }
}

/// One day across every active habit.
public struct PlanDay: Equatable, Sendable {
    public enum Status: String, Sendable, CaseIterable {
        case completed, partial, missed, current, upcoming, rest

        public var label: String {
            switch self {
            case .completed: return "All done"
            case .partial: return "Partly done"
            case .missed: return "Missed"
            case .current: return "Today"
            case .upcoming: return "Upcoming"
            case .rest: return "Rest day"
            }
        }
    }

    public var status: Status
    public var completed: Int
    public var scheduled: Int

    public init(status: Status, completed: Int, scheduled: Int) {
        self.status = status
        self.completed = completed
        self.scheduled = scheduled
    }

    public var fraction: Double { scheduled == 0 ? 0 : Double(completed) / Double(scheduled) }
}

/// Program-wide progress computed from the real habit records.
public enum PlanProgress {
    public static func day(_ day: DayKey, timelines: [HabitTimeline], today: DayKey) -> PlanDay {
        var scheduled = 0
        var completed = 0
        for timeline in timelines where timeline.isScheduled(day) {
            scheduled += 1
            if timeline.completed.contains(day), day <= today { completed += 1 }
        }
        let status: PlanDay.Status
        if scheduled == 0 {
            status = .rest
        } else if day > today {
            status = .upcoming
        } else if completed == scheduled {
            status = .completed
        } else if day == today {
            status = .current
        } else if completed == 0 {
            status = .missed
        } else {
            status = .partial
        }
        return PlanDay(status: status, completed: completed, scheduled: scheduled)
    }

    /// Completed scheduled activities ÷ scheduled activities, from day 1 through today or day 90.
    public static func completion(timelines: [HabitTimeline], today: DayKey) -> (completed: Int, scheduled: Int, percent: Int?) {
        var completed = 0
        var scheduled = 0
        for timeline in timelines {
            let metrics = HabitMetrics.compute(timeline, today: today)
            completed += metrics.completedCount
            scheduled += metrics.scheduledCount
        }
        let percent = scheduled == 0 ? nil : Int((Double(completed) / Double(scheduled) * 100).rounded())
        return (completed, scheduled, percent)
    }
}
