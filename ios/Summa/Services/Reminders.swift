import Foundation
import UserNotifications
import UIKit
import SummaCore

/// Local reminders. Permission is requested only when a person turns one on.
enum Reminders {
    enum Access { case allowed, denied, undetermined }

    static func access() async -> Access {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral: return .allowed
        case .denied: return .denied
        default: return .undetermined
        }
    }

    /// Asks for permission if it has not been decided. Returns whether reminders can be delivered.
    static func requestIfNeeded() async -> Bool {
        if AppEnvironment.isUITesting { return false }
        switch await access() {
        case .allowed: return true
        case .denied: return false
        case .undetermined:
            return (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
        }
    }

    private struct Entry {
        let id: String
        let title: String
        let body: String
        let weekday: Int
        let hour: Int
        let minute: Int
    }

    /// Replaces every scheduled reminder with what the plan currently asks for.
    @MainActor
    static func sync(plan: Plan) {
        let finished = plan.isFinished(today: DayKey(date: Date()))
        var entries: [Entry] = []
        if !finished {
            for habit in plan.activeHabits where habit.reminderEnabled {
                for weekday in habit.currentWeekdays {
                    entries.append(Entry(id: "habit-\(habit.id.uuidString)-\(weekday)", title: habit.title,
                                         body: "\(habit.action). On a hard day: \(habit.minimumVersion).",
                                         weekday: weekday, hour: habit.reminderHour, minute: habit.reminderMinute))
                }
            }
        }
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        for entry in entries {
            let content = UNMutableNotificationContent()
            content.title = entry.title
            content.body = entry.body
            content.sound = .default
            let trigger = UNCalendarNotificationTrigger(
                dateMatching: DateComponents(hour: entry.hour, minute: entry.minute, weekday: entry.weekday), repeats: true)
            center.add(UNNotificationRequest(identifier: entry.id, content: content, trigger: trigger))
        }
    }

    static func removeAll() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }

    @MainActor
    static func openSystemSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
    }

    static func timeString(hour: Int, minute: Int) -> String {
        var calendar = Calendar.current
        calendar.timeZone = .current
        let date = calendar.date(from: DateComponents(hour: hour, minute: minute)) ?? Date()
        return date.formatted(date: .omitted, time: .shortened)
    }
}
