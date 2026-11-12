import Foundation
import SwiftData
import SummaCore
import WidgetKit

/// All writes to the saved plan go through here so the heatmap, calendar,
/// streaks, completion, reminders, and widget read from one source of truth.
@MainActor
enum PlanStore {
    @discardableResult
    static func startPlan(from draft: PlanDraft, userName: String, remindersOn: Set<UUID>, today: DayKey,
                          in context: ModelContext) -> Plan {
        let plan = Plan(objective: draft.objective, userName: userName, startDay: today, phases: draft.phases, source: draft.source)
        context.insert(plan)
        for (index, habitDraft) in draft.habits.enumerated() {
            addHabit(habitDraft, to: plan, sortOrder: index, startDay: today,
                     reminderEnabled: remindersOn.contains(habitDraft.id), in: context)
        }
        save(context, plan: plan)
        return plan
    }

    @discardableResult
    static func addHabit(_ draft: HabitDraft, to plan: Plan, sortOrder: Int? = nil, startDay: DayKey,
                         reminderEnabled: Bool, in context: ModelContext) -> Habit {
        var draft = draft
        if plan.habits.contains(where: { $0.id == draft.id }) { draft.id = UUID() }
        let habit = Habit(draft: draft, sortOrder: sortOrder ?? ((plan.habits.map(\.sortOrder).max() ?? -1) + 1),
                          startDay: startDay, reminderEnabled: reminderEnabled)
        context.insert(habit)
        habit.plan = plan
        let version = ScheduleVersion(effectiveFrom: startDay, weekdays: WeekdaySet(weekdays: draft.weekdays))
        context.insert(version)
        version.habit = habit
        return habit
    }

    /// Applies edits. A changed schedule takes effect today and leaves earlier days untouched.
    static func update(_ habit: Habit, with draft: HabitDraft, reminderEnabled: Bool, today: DayKey, in context: ModelContext) {
        habit.title = draft.title.trimmed
        habit.action = draft.action.trimmed
        habit.minimumVersion = draft.minimumVersion.trimmed
        habit.colorHex = draft.colorHex
        habit.symbol = draft.symbol
        habit.reminderEnabled = reminderEnabled
        if let reminder = draft.reminder {
            habit.reminderHour = reminder.hour
            habit.reminderMinute = reminder.minute
        }
        let newDays = WeekdaySet(weekdays: draft.weekdays)
        if newDays.rawValue != WeekdaySet(weekdays: habit.currentWeekdays).rawValue, !newDays.isEmpty {
            let effective = max(today, DayKey(habit.startDay) ?? today)
            if let sameDay = habit.schedules.first(where: { $0.effectiveFromDay == effective.string }) {
                sameDay.weekdayMask = newDays.rawValue
            } else {
                let version = ScheduleVersion(effectiveFrom: effective, weekdays: newDays)
                context.insert(version)
                version.habit = habit
            }
        }
        save(context, plan: habit.plan)
    }

    static func archive(_ habit: Habit, today: DayKey, in context: ModelContext) {
        habit.archivedDay = today.string
        habit.reminderEnabled = false
        save(context, plan: habit.plan)
    }

    static func restore(_ habit: Habit, in context: ModelContext) {
        habit.archivedDay = nil
        save(context, plan: habit.plan)
    }

    /// Marks or clears one day. Safe to call repeatedly with the same value.
    static func setCompleted(_ completed: Bool, habit: Habit, day: DayKey, in context: ModelContext) {
        let key = CheckInLedger.key(habitID: habit.id, day: day)
        let existing = habit.checkIns.filter { $0.key == key }
        if completed {
            guard existing.isEmpty else { return }
            let checkIn = CheckIn(habitID: habit.id, day: day)
            context.insert(checkIn)
            checkIn.habit = habit
        } else {
            guard !existing.isEmpty else { return }
            habit.checkIns.removeAll { $0.key == key }
            existing.forEach { context.delete($0) }
        }
        save(context, plan: habit.plan)
    }

    static func deleteEverything(in context: ModelContext) {
        if let plans = try? context.fetch(FetchDescriptor<Plan>()) {
            plans.forEach { context.delete($0) }
        }
        try? context.save()
        Reminders.removeAll()
        WidgetBridge.clear()
    }

    static func save(_ context: ModelContext, plan: Plan?) {
        do {
            try context.save()
        } catch {
            // Keep the in-memory change; SwiftData retries on the next save.
            assertionFailure("Save failed: \(error)")
        }
        if let plan {
            WidgetBridge.publish(plan: plan)
            Reminders.sync(plan: plan)
        }
    }
}

/// Shares a snapshot with the widget through the app group.
enum WidgetBridge {
    static var defaults: UserDefaults? { UserDefaults(suiteName: WidgetSnapshot.appGroup) }

    @MainActor
    static func publish(plan: Plan) {
        let start = plan.start
        let habits = plan.activeHabits.map {
            WidgetSnapshot.Habit(id: $0.id, title: $0.title, colorHex: $0.colorHex, symbol: $0.symbol, timeline: $0.timeline(planStart: start))
        }
        let white = UserDefaults.standard.string(forKey: ThemeChoice.storageKey) == ThemeChoice.white.rawValue
        let snapshot = WidgetSnapshot(habits: habits, isWhiteMarble: white)
        if let data = try? JSONEncoder().encode(snapshot) {
            defaults?.set(data, forKey: WidgetSnapshot.defaultsKey)
        }
        WidgetCenter.shared.reloadAllTimelines()
    }

    static func clear() {
        defaults?.removeObject(forKey: WidgetSnapshot.defaultsKey)
        WidgetCenter.shared.reloadAllTimelines()
    }
}
