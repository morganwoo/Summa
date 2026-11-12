import Foundation
import SwiftData
import SummaCore
import WidgetKit

/// All writes to the saved plan go through here so the heatmap, calendar,
/// streaks, completion, reminders, and widget read from one source of truth.
@MainActor
enum PlanStore {
    @discardableResult
    static func startPlan(from draft: PlanDraft, answers: OnboardingAnswers, remindersOn: Set<UUID>, today: DayKey,
                          chapter: Int = 1, in context: ModelContext) -> Plan {
        let plan = Plan(objective: draft.objective, userName: answers.name, username: answers.username, answers: answers,
                        startDay: today, phases: draft.phases, source: draft.source)
        plan.chapter = chapter
        context.insert(plan)
        for (index, habitDraft) in draft.habits.enumerated() {
            addHabit(habitDraft, to: plan, sortOrder: index, startDay: today,
                     reminderEnabled: remindersOn.contains(habitDraft.id), in: context)
        }
        ensureMilestones(for: plan, in: context)
        save(context, plan: plan)
        return plan
    }

    static func nextChapterNumber(in context: ModelContext) -> Int {
        ((try? context.fetch(FetchDescriptor<Plan>()))?.map(\.chapter).max() ?? 0) + 1
    }

    /// Creates the day 21, 66, and 90 milestones from the objective if the plan has none yet.
    static func ensureMilestones(for plan: Plan, in context: ModelContext) {
        guard plan.milestones.isEmpty else { return }
        let first = plan.habits.min { $0.sortOrder < $1.sortOrder }
        for entry in MilestoneBuilder.defaults(objective: plan.objective, firstHabit: first?.title ?? "", target: first?.target ?? "") {
            let milestone = Milestone(day: entry.day, text: entry.text)
            context.insert(milestone)
            milestone.plan = plan
        }
        try? context.save()
    }

    /// Begins the next chapter with the same habits. The finished chapter and its history are kept.
    @discardableResult
    static func continueChapter(from old: Plan, today: DayKey, in context: ModelContext) -> Plan {
        let plan = Plan(objective: old.objective, userName: old.userName, username: old.username, answers: old.answers,
                        startDay: today, phases: old.phases, source: "continued")
        plan.chapter = nextChapterNumber(in: context)
        context.insert(plan)
        for (index, habit) in old.activeHabits.enumerated() {
            var draft = habit.asDraft()
            draft.id = UUID()
            let copy = addHabit(draft, to: plan, sortOrder: index, startDay: today, reminderEnabled: habit.reminderEnabled, in: context)
            copy.secondReminderEnabled = habit.secondReminderEnabled
            copy.secondReminderHour = habit.secondReminderHour
            copy.secondReminderMinute = habit.secondReminderMinute
        }
        ensureMilestones(for: plan, in: context)
        save(context, plan: plan)
        return plan
    }

    static func addPhoto(_ data: Data, milestoneDay: Int?, to plan: Plan, today: DayKey, in context: ModelContext) {
        guard !DevSandbox.isActive else { return } // the developer preview never writes image files
        guard let fileName = PhotoStore.save(data) else { return }
        let photo = ProgressPhoto(day: today, milestoneDay: milestoneDay, fileName: fileName)
        context.insert(photo)
        photo.plan = plan
        try? context.save()
    }

    /// Removes the record and the image file together.
    static func deletePhoto(_ photo: ProgressPhoto, in context: ModelContext) {
        PhotoStore.delete(photo.fileName)
        photo.plan?.photos.removeAll { $0.id == photo.id }
        context.delete(photo)
        try? context.save()
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
        habit.target = draft.target.trimmed
        habit.colorHex = draft.colorHex
        habit.symbol = draft.symbol
        habit.reminderEnabled = reminderEnabled
        if let reminder = draft.reminder {
            habit.reminderHour = reminder.hour
            habit.reminderMinute = reminder.minute
        }
        if !reminderEnabled { habit.secondReminderEnabled = false }
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

    /// Free accounts keep three active habits; Summa Pro removes the limit.
    static func canAddHabit(to plan: Plan) -> Bool {
        HabitLimit.canAddHabit(activeCount: plan.activeHabits.count, isPro: Entitlements.isPro)
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
        PhotoStore.deleteAll()
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
            Backend.shared.scheduleSync(plan: plan)
        }
    }
}

/// True only while the DEBUG developer preview is on screen. While it is, nothing reaches the widget,
/// the notification schedule, the social backend, or the photo folder, so made-up preview data can
/// never replace the person's real record. Always false in Release builds.
enum DevSandbox {
    #if DEBUG
    static var isActive = false
    #else
    static let isActive = false
    #endif
    /// The preview plan always uses this id, so its one-time celebrations can be reset and replayed.
    static let previewPlanID = UUID(uuidString: "00000000-0000-4000-8000-0000000D0E0B")!
}

enum ReflectionError: LocalizedError, Equatable {
    case proRequired, empty, futureDay
    var errorDescription: String? {
        switch self {
        case .proRequired: return "Daily reflections are part of Summa Pro."
        case .empty: return "Write something before saving."
        case .futureDay: return "That day has not arrived yet."
        }
    }
}

/// The only way reflections and victories are read or written. Every call checks the Summa Pro
/// entitlement first. Saved entries are never deleted when a subscription ends: they are simply
/// not returned until Pro is active again.
@MainActor
enum ReflectionStore {
    private static func requirePro() throws {
        if ReflectionAccess.denial(isPro: Entitlements.isPro) != nil { throw ReflectionError.proRequired }
    }

    static func all(for plan: Plan) -> [Reflection] {
        ReflectionAccess.visible(plan.reflections, isPro: Entitlements.isPro).sorted { $0.createdAt < $1.createdAt }
    }

    static func entries(for plan: Plan, dayNumber: Int) -> [Reflection] {
        all(for: plan).filter { $0.dayNumber == dayNumber }
    }

    /// Days that carry at least one reflection, for the heatmap's gold glow.
    static func days(for plan: Plan) -> Set<DayKey> {
        Set(all(for: plan).compactMap { DayKey($0.day) })
    }

    @discardableResult
    static func add(_ text: String, to plan: Plan, dayNumber: Int, today: DayKey, fromCompanion: Bool = false,
                    in context: ModelContext) throws -> Reflection {
        try requirePro()
        guard ReflectionRule.isSavable(text) else { throw ReflectionError.empty }
        guard (1...plan.dayNumber(today: today)).contains(dayNumber), today >= plan.start else { throw ReflectionError.futureDay }
        let owner = DevSandbox.isActive ? "preview" : (Backend.shared.session?.userID.uuidString ?? "device")
        let entry = Reflection(text: ReflectionRule.normalized(text), dayNumber: dayNumber, day: plan.start.adding(dayNumber - 1),
                               journeyID: plan.id, chapter: plan.chapter, ownerID: owner, fromCompanion: fromCompanion)
        context.insert(entry)
        entry.plan = plan
        try context.save()
        return entry
    }

    static func update(_ entry: Reflection, text: String, in context: ModelContext) throws {
        try requirePro()
        guard ReflectionRule.isSavable(text) else { throw ReflectionError.empty }
        entry.text = ReflectionRule.normalized(text)
        entry.updatedAt = Date()
        try context.save()
    }

    static func delete(_ entry: Reflection, in context: ModelContext) throws {
        try requirePro()
        entry.plan?.reflections.removeAll { $0.id == entry.id }
        context.delete(entry)
        try context.save()
    }

    // MARK: Your Colosseum

    static func victories(for plan: Plan) -> [Victory] {
        ReflectionAccess.visible(plan.victories, isPro: Entitlements.isPro).sorted { $0.createdAt > $1.createdAt }
    }

    static func isPromoted(_ entry: Reflection) -> Bool {
        guard let id = entry.victoryID else { return false }
        return entry.plan?.victories.contains { $0.id == id } ?? false
    }

    /// Copies a reflection into the Colosseum. The reflection is kept, and promoting it again
    /// returns the victory that already exists instead of making a second one.
    @discardableResult
    static func promote(_ entry: Reflection, in context: ModelContext) throws -> Victory {
        try requirePro()
        guard let plan = entry.plan else { throw ReflectionError.empty }
        if let existing = plan.victories.first(where: { $0.id == entry.victoryID || $0.sourceReflectionID == entry.id }) {
            entry.victoryID = existing.id
            try context.save()
            return existing
        }
        let victory = Victory(text: entry.text, dayNumber: entry.dayNumber, day: entry.day, sourceReflectionID: entry.id)
        victory.category = VictoryCategory.classify(entry.text).rawValue
        context.insert(victory)
        victory.plan = plan
        entry.victoryID = victory.id
        try context.save()
        return victory
    }

    /// Adds a victory directly, written by the person or approved from a suggestion.
    @discardableResult
    static func addVictory(_ text: String, category: VictoryCategory, to plan: Plan, today: DayKey, in context: ModelContext) throws -> Victory {
        try requirePro()
        guard ReflectionRule.isSavable(text) else { throw ReflectionError.empty }
        let dayNumber = plan.dayNumber(today: today)
        let victory = Victory(text: ReflectionRule.normalized(text), dayNumber: dayNumber,
                              day: plan.start.adding(dayNumber - 1).string, sourceReflectionID: nil)
        victory.category = category.rawValue
        context.insert(victory)
        victory.plan = plan
        try context.save()
        return victory
    }

    static func setCategory(_ category: VictoryCategory, for victory: Victory, in context: ModelContext) throws {
        try requirePro()
        victory.category = category.rawValue
        try context.save()
    }

    static func delete(_ victory: Victory, in context: ModelContext) throws {
        try requirePro()
        let plan = victory.plan
        plan?.reflections.filter { $0.victoryID == victory.id }.forEach { $0.victoryID = nil }
        plan?.victories.removeAll { $0.id == victory.id }
        context.delete(victory)
        try context.save()
    }
}

/// What the current account is entitled to, from verified App Store transactions.
@MainActor
enum Entitlements {
    static var isPro: Bool { Store.shared.isPro }
}

/// Shares a snapshot with the widget through the app group.
enum WidgetBridge {
    static var defaults: UserDefaults? { UserDefaults(suiteName: WidgetSnapshot.appGroup) }

    @MainActor
    static func publish(plan: Plan) {
        guard !DevSandbox.isActive else { return }
        let start = plan.start
        let habits = plan.activeHabits.map {
            WidgetSnapshot.Habit(id: $0.id, title: $0.title, colorHex: $0.colorHex, symbol: $0.symbol, timeline: $0.timeline(planStart: start))
        }
        let white = UserDefaults.standard.string(forKey: ThemeChoice.storageKey) == ThemeChoice.white.rawValue
        let snapshot = WidgetSnapshot(habits: habits, isWhiteMarble: white, isPro: Entitlements.isPro, allTimelines: plan.timelines)
        if let data = try? JSONEncoder().encode(snapshot) {
            defaults?.set(data, forKey: WidgetSnapshot.defaultsKey)
        }
        WidgetCenter.shared.reloadAllTimelines()
    }

    static func clear() {
        guard !DevSandbox.isActive else { return }
        defaults?.removeObject(forKey: WidgetSnapshot.defaultsKey)
        WidgetCenter.shared.reloadAllTimelines()
    }
}
