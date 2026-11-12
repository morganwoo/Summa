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

    /// Replaces every scheduled reminder with what the plan and the current tier allow.
    /// Removing first and using stable identifiers means an edit can never leave a duplicate behind.
    @MainActor
    @discardableResult
    static func sync(plan: Plan) -> ReminderPlanner.Plan {
        let finished = plan.isFinished(today: DayKey(date: Date()))
        let requests = finished ? [] : plan.activeHabits.map { habit in
            ReminderRequest(habitID: habit.id, title: habit.title,
                            body: "\(habit.action). On a hard day: \(habit.minimumVersion).",
                            weekdays: habit.currentWeekdays, enabled: habit.reminderEnabled,
                            hour: habit.reminderHour, minute: habit.reminderMinute,
                            secondEnabled: habit.secondReminderEnabled, secondHour: habit.secondReminderHour,
                            secondMinute: habit.secondReminderMinute)
        }
        let planned = ReminderPlanner.plan(requests, isPro: Entitlements.isPro)
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        for entry in planned.scheduled {
            let content = UNMutableNotificationContent()
            content.title = entry.title
            content.body = entry.body
            content.sound = .default
            var when = DateComponents(hour: entry.hour, minute: entry.minute)
            when.weekday = entry.weekday
            center.add(UNNotificationRequest(identifier: entry.identifier, content: content,
                                             trigger: UNCalendarNotificationTrigger(dateMatching: when, repeats: true)))
        }
        return planned
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

/// Lets a reminder appear as a banner even while Summa is open.
final class ReminderPresenter: NSObject, UNUserNotificationCenterDelegate {
    static let shared = ReminderPresenter()

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }
}
