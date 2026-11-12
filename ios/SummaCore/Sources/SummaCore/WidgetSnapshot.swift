import Foundation

/// What the home-screen widget needs. Written by the app into the shared
/// container after every change. Carries timelines rather than precomputed
/// statuses so the widget stays correct when the day rolls over without the
/// app being opened.
public struct WidgetSnapshot: Codable, Equatable, Sendable {
    public struct Habit: Codable, Equatable, Sendable, Identifiable {
        public var id: UUID
        public var title: String
        public var colorHex: String
        public var symbol: String
        public var timeline: HabitTimeline

        public init(id: UUID, title: String, colorHex: String, symbol: String, timeline: HabitTimeline) {
            self.id = id; self.title = title; self.colorHex = colorHex; self.symbol = symbol; self.timeline = timeline
        }
    }

    public var habits: [Habit]
    public var isWhiteMarble: Bool
    /// Home-screen widgets are a Summa Pro feature. Missing in snapshots written before subscriptions existed.
    public var isPro: Bool?
    /// Every habit's record, archived ones included, for the program-wide heatmap.
    public var allTimelines: [HabitTimeline]?

    public init(habits: [Habit], isWhiteMarble: Bool, isPro: Bool = false, allTimelines: [HabitTimeline]? = nil) {
        self.habits = habits
        self.isWhiteMarble = isWhiteMarble
        self.isPro = isPro
        self.allTimelines = allTimelines
    }

    public var planStart: DayKey? { habits.first?.timeline.planStart ?? allTimelines?.first?.planStart }

    /// 1...90 once the plan has started; nil with no plan.
    public func dayNumber(today: DayKey) -> Int? {
        planStart.map { max(1, min(HabitTimeline.planLength, $0.days(until: today) + 1)) }
    }

    public func daysRemaining(today: DayKey) -> Int? {
        planStart.map { max(0, $0.adding(HabitTimeline.planLength - 1).ordinal - today.ordinal) }
    }

    public static let appGroup = "group.app.summa.Summa"
    public static let defaultsKey = "widgetSnapshot.v1"
    public static let widgetKind = "SummaTodayWidget"

    /// Monday-first week containing `today`.
    public static func week(containing today: DayKey) -> [DayKey] {
        let offset = (today.weekday + 5) % 7
        let monday = today.adding(-offset)
        return (0..<7).map { monday.adding($0) }
    }
}
