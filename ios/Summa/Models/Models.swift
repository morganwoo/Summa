import Foundation
import SwiftData
import SummaCore

@Model
final class Plan {
    @Attribute(.unique) var id: UUID
    var objective: String
    var userName: String
    /// First day of the plan as `yyyy-MM-dd`.
    var startDay: String
    var createdAt: Date
    var phasesData: Data
    var source: String
    /// Chosen in onboarding. Global uniqueness is enforced once accounts exist.
    var username: String = ""
    /// The onboarding answers this plan was built from, kept for later recommendations.
    var answersData: Data = Data()
    @Relationship(deleteRule: .cascade, inverse: \Habit.plan) var habits: [Habit] = []

    init(objective: String, userName: String, username: String = "", answers: OnboardingAnswers? = nil,
         startDay: DayKey, phases: [PhaseDraft], source: String) {
        self.username = username
        self.answersData = answers.flatMap { try? JSONEncoder().encode($0) } ?? Data()
        self.id = UUID()
        self.objective = objective
        self.userName = userName
        self.startDay = startDay.string
        self.createdAt = Date()
        self.phasesData = (try? JSONEncoder().encode(phases)) ?? Data()
        self.source = source
    }

    var start: DayKey { DayKey(startDay) ?? DayKey(date: createdAt) }
    var end: DayKey { start.adding(HabitTimeline.planLength - 1) }

    var phases: [PhaseDraft] {
        (try? JSONDecoder().decode([PhaseDraft].self, from: phasesData)) ?? PhaseDraft.standard()
    }

    var answers: OnboardingAnswers {
        (try? JSONDecoder().decode(OnboardingAnswers.self, from: answersData)) ?? OnboardingAnswers()
    }

    var activeHabits: [Habit] {
        habits.filter { $0.archivedDay == nil }.sorted { $0.sortOrder < $1.sortOrder }
    }

    var archivedHabits: [Habit] {
        habits.filter { $0.archivedDay != nil }.sorted { $0.sortOrder < $1.sortOrder }
    }

    /// 1...90 once the plan has started.
    func dayNumber(today: DayKey) -> Int {
        max(1, min(HabitTimeline.planLength, start.days(until: today) + 1))
    }

    func isFinished(today: DayKey) -> Bool { today > end }
}

@Model
final class Habit {
    @Attribute(.unique) var id: UUID
    var title: String
    var action: String
    var minimumVersion: String
    /// Measurable amount for one occurrence, e.g. "10 pages".
    var target: String = ""
    /// Why this habit was recommended, in terms of the onboarding answers.
    var reason: String = ""
    var colorHex: String
    var symbol: String
    var sortOrder: Int
    /// First day this habit can be due.
    var startDay: String
    /// First day this habit is no longer due. Nil while active.
    var archivedDay: String?
    var reminderEnabled: Bool
    var reminderHour: Int
    var reminderMinute: Int
    var plan: Plan?
    @Relationship(deleteRule: .cascade, inverse: \ScheduleVersion.habit) var schedules: [ScheduleVersion] = []
    @Relationship(deleteRule: .cascade, inverse: \CheckIn.habit) var checkIns: [CheckIn] = []

    init(draft: HabitDraft, sortOrder: Int, startDay: DayKey, reminderEnabled: Bool) {
        self.id = draft.id
        self.title = draft.title
        self.action = draft.action
        self.minimumVersion = draft.minimumVersion
        self.target = draft.target
        self.reason = draft.reason
        self.colorHex = draft.colorHex
        self.symbol = draft.symbol
        self.sortOrder = sortOrder
        self.startDay = startDay.string
        self.archivedDay = nil
        self.reminderEnabled = reminderEnabled
        self.reminderHour = draft.reminder?.hour ?? 8
        self.reminderMinute = draft.reminder?.minute ?? 0
    }

    var currentWeekdays: [Int] {
        let latest = schedules.max { $0.effectiveFromDay < $1.effectiveFromDay }
        return WeekdaySet(rawValue: latest?.weekdayMask ?? WeekdaySet.everyDay.rawValue).days
    }

    var completedDays: Set<DayKey> { Set(checkIns.compactMap { DayKey($0.day) }) }

    func timeline(planStart: DayKey) -> HabitTimeline {
        HabitTimeline(
            planStart: planStart,
            habitStart: DayKey(startDay) ?? planStart,
            archivedOn: archivedDay.flatMap { DayKey($0) },
            rules: schedules.compactMap { version in
                DayKey(version.effectiveFromDay).map { ScheduleRule(effectiveFrom: $0, weekdays: WeekdaySet(rawValue: version.weekdayMask)) }
            },
            completed: completedDays
        )
    }

    func asDraft() -> HabitDraft {
        HabitDraft(id: id, title: title, action: action, minimumVersion: minimumVersion, target: target, reason: reason, weekdays: currentWeekdays,
                   reminder: ReminderDraft(hour: reminderHour, minute: reminderMinute), colorHex: colorHex, symbol: symbol)
    }
}

/// One schedule in force from a given day. A schedule edit adds a version,
/// so days before the edit keep the schedule they were lived under.
@Model
final class ScheduleVersion {
    var effectiveFromDay: String
    var weekdayMask: Int
    var habit: Habit?

    init(effectiveFrom: DayKey, weekdays: WeekdaySet) {
        self.effectiveFromDay = effectiveFrom.string
        self.weekdayMask = weekdays.rawValue
    }
}

@Model
final class CheckIn {
    /// `habitID|yyyy-MM-dd`. Unique, so a duplicate write cannot create a second record.
    @Attribute(.unique) var key: String
    var day: String
    var completedAt: Date
    var habit: Habit?

    init(habitID: UUID, day: DayKey) {
        self.key = CheckInLedger.key(habitID: habitID, day: day)
        self.day = day.string
        self.completedAt = Date()
    }
}

enum SummaSchema {
    static let models: [any PersistentModel.Type] = [Plan.self, Habit.self, ScheduleVersion.self, CheckIn.self]
}
