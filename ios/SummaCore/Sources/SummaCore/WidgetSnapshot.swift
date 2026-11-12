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
        /// The habit's action in a few words, for the wider widget. Missing in older snapshots.
        public var detail: String?

        public init(id: UUID, title: String, colorHex: String, symbol: String, timeline: HabitTimeline, detail: String? = nil) {
            self.id = id; self.title = title; self.colorHex = colorHex; self.symbol = symbol; self.timeline = timeline
            self.detail = detail
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
    public static let habitWidgetKind = "SummaHabitWidget"
    public static let weekWidgetKind = "SummaWeekWidget"
    public static let victoryWidgetKind = "SummaVictoryWidget"
    public static let pendingKey = "widgetPendingCheckIns.v1"
    /// Opens the app straight into a conversation with Summa to record a victory.
    public static let victoryURL = "summa://victory"

    /// Monday-first week containing `today`.
    public static func week(containing today: DayKey) -> [DayKey] {
        let offset = (today.weekday + 5) % 7
        let monday = today.adding(-offset)
        return (0..<7).map { monday.adding($0) }
    }
}


/// A check-in made from the widget's button. The widget cannot reach the app's database, so it
/// leaves these in the shared container and updates its own snapshot; the app records them the
/// next time it is active. Only the newest answer for a habit and day is kept.
public struct PendingCheckIn: Codable, Equatable, Sendable {
    public var habitID: UUID
    public var day: DayKey
    public var completed: Bool

    public init(habitID: UUID, day: DayKey, completed: Bool) {
        self.habitID = habitID; self.day = day; self.completed = completed
    }
}

public enum WidgetInbox {
    /// Adds a change to the queue, replacing any earlier one for the same habit and day.
    public static func adding(_ change: PendingCheckIn, to queue: [PendingCheckIn]) -> [PendingCheckIn] {
        var result = queue.filter { !($0.habitID == change.habitID && $0.day == change.day) }
        result.append(change)
        return Array(result.suffix(200))
    }

    /// Flips today's check-in for one habit in the snapshot. Returns nil when the habit is unknown,
    /// today is outside its plan, or it is not scheduled today: a widget can never invent a record.
    public static func toggling(habitID: UUID, on today: DayKey, in snapshot: WidgetSnapshot) -> (snapshot: WidgetSnapshot, change: PendingCheckIn)? {
        guard let index = snapshot.habits.firstIndex(where: { $0.id == habitID }) else { return nil }
        var updated = snapshot
        var timeline = updated.habits[index].timeline
        let status = timeline.status(on: today, today: today)
        guard timeline.contains(today), status == .pending || status == .completed else { return nil }
        let nowCompleted = status != .completed
        if nowCompleted { timeline.completed.insert(today) } else { timeline.completed.remove(today) }
        let before = updated.habits[index].timeline
        updated.habits[index].timeline = timeline
        // Keep the program-wide record in step, so the combined heatmap agrees.
        if var all = updated.allTimelines, let position = all.firstIndex(of: before) {
            all[position] = timeline
            updated.allTimelines = all
        }
        return (updated, PendingCheckIn(habitID: habitID, day: today, completed: nowCompleted))
    }

    /// The changes the app should apply: only for days that are not in the future.
    public static func applicable(_ queue: [PendingCheckIn], today: DayKey) -> [PendingCheckIn] {
        queue.filter { $0.day <= today }
    }
}
