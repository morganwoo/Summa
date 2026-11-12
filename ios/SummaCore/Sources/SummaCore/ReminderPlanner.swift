import Foundation

/// What one habit asks for in the way of reminders.
public struct ReminderRequest: Equatable, Sendable {
    public var habitID: UUID
    public var title: String
    public var body: String
    public var weekdays: [Int]
    public var enabled: Bool
    public var hour: Int
    public var minute: Int
    /// A second, later reminder on the same days. Summa Pro only.
    public var secondEnabled: Bool
    public var secondHour: Int
    public var secondMinute: Int

    public init(habitID: UUID, title: String, body: String, weekdays: [Int], enabled: Bool, hour: Int, minute: Int,
                secondEnabled: Bool = false, secondHour: Int = 20, secondMinute: Int = 0) {
        self.habitID = habitID; self.title = title; self.body = body; self.weekdays = weekdays; self.enabled = enabled
        self.hour = hour; self.minute = minute
        self.secondEnabled = secondEnabled; self.secondHour = secondHour; self.secondMinute = secondMinute
    }
}

/// One repeating local notification. `weekday == nil` repeats every day.
public struct PlannedReminder: Equatable, Sendable {
    public var identifier: String
    public var habitID: UUID
    public var weekday: Int?
    public var hour: Int
    public var minute: Int
    public var title: String
    public var body: String
}

/// Decides which notifications to schedule. Pure, so the rules are testable:
/// - Summa Free: one basic reminder, for the first habit that has one switched on.
/// - Summa Pro: a reminder for every habit, plus an optional second time per habit.
/// - A habit due every day uses one daily notification instead of seven.
/// - iOS keeps at most 64 pending notifications per app; the plan stays under that.
/// Stored preferences are never changed here, so reminders return if Pro is restored.
public enum ReminderPlanner {
    public static let freeReminders = 1
    public static let maxPending = 60

    public struct Plan: Equatable, Sendable {
        public var scheduled: [PlannedReminder]
        /// Habits whose reminder is switched on but not scheduled because of the free limit.
        public var pausedHabits: Int
        /// Reminders left out because of the iOS pending-notification limit.
        public var droppedForLimit: Int
    }

    public static func canEnableReminder(othersEnabled: Int, isPro: Bool) -> Bool {
        isPro || othersEnabled < freeReminders
    }

    public static func plan(_ requests: [ReminderRequest], isPro: Bool) -> Plan {
        let wanting = requests.filter { $0.enabled && !validDays($0.weekdays).isEmpty }
        let allowed = isPro ? wanting : Array(wanting.prefix(freeReminders))
        var all: [PlannedReminder] = []
        for request in allowed {
            all += entries(for: request, slot: "a", hour: request.hour, minute: request.minute)
            if isPro, request.secondEnabled, (request.secondHour, request.secondMinute) != (request.hour, request.minute) {
                all += entries(for: request, slot: "b", hour: request.secondHour, minute: request.secondMinute)
            }
        }
        let kept = Array(all.prefix(maxPending))
        return Plan(scheduled: kept, pausedHabits: wanting.count - allowed.count, droppedForLimit: all.count - kept.count)
    }

    private static func validDays(_ weekdays: [Int]) -> [Int] {
        Array(Set(weekdays.filter { (1...7).contains($0) })).sorted()
    }

    private static func entries(for request: ReminderRequest, slot: String, hour: Int, minute: Int) -> [PlannedReminder] {
        let days = validDays(request.weekdays)
        let h = min(23, max(0, hour))
        let m = min(59, max(0, minute))
        let base = "habit-\(request.habitID.uuidString)-\(slot)"
        if days.count == 7 {
            return [PlannedReminder(identifier: "\(base)-daily", habitID: request.habitID, weekday: nil, hour: h, minute: m,
                                    title: request.title, body: request.body)]
        }
        return days.map {
            PlannedReminder(identifier: "\(base)-\($0)", habitID: request.habitID, weekday: $0, hour: h, minute: m,
                            title: request.title, body: request.body)
        }
    }
}
