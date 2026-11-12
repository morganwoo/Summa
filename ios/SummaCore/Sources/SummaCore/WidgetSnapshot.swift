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

    public init(habits: [Habit], isWhiteMarble: Bool) {
        self.habits = habits
        self.isWhiteMarble = isWhiteMarble
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
