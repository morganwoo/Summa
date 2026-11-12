import SwiftUI
import SwiftData
import SummaCore

/// The plan at a glance, with add, edit, and archive for habits.
struct PlanOverviewView: View {
    @Environment(\.theme) private var theme
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var clock: TodayClock
    let plan: Plan

    @State private var editing: Habit? = nil
    @State private var addingNew = false
    @State private var archiving: Habit? = nil
    @State private var paywall: PaywallContext? = nil

    var body: some View {
        let today = clock.today
        let dayNumber = plan.dayNumber(today: today)
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Eyebrow("Your 90 days")
                    Text(plan.objective)
                        .font(SummaFont.serif(32, relativeTo: .title))
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    Text("\(plan.start.formatted(.dateTime.month(.abbreviated).day())) – \(plan.end.formatted(.dateTime.month(.abbreviated).day().year())) · Day \(dayNumber) of \(HabitTimeline.planLength)")
                        .font(.footnote).foregroundStyle(theme.muted)
                }

                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(plan.phases.enumerated()), id: \.offset) { index, phase in
                        let isCurrent = phase.contains(day: dayNumber) && !plan.isFinished(today: today)
                        HStack(alignment: .top, spacing: 12) {
                            Rectangle().fill(isCurrent ? phase.stage.color : Color.clear).frame(width: 2)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(String(format: "DAYS %02d — %02d", phase.startDay, phase.endDay) + (isCurrent ? " · NOW" : ""))
                                    .font(.caption.weight(.semibold)).tracking(1.5).foregroundStyle(theme.gold)
                                HStack(spacing: 8) {
                                    Circle().fill(phase.stage.color).frame(width: 9, height: 9).accessibilityHidden(true)
                                    Text(phase.stage.name).font(SummaFont.serif(24, relativeTo: .title3))
                                }
                                Text(phase.focus).font(.subheadline).foregroundStyle(theme.muted)
                            }
                        }
                        .padding(.vertical, 14)
                        .accessibilityElement(children: .combine)
                        if index < plan.phases.count - 1 { Hairline() }
                    }
                }
                .card()

                Eyebrow("Habits")
                if plan.activeHabits.isEmpty {
                    Text("No active habits. Add one to keep practicing.")
                        .font(.subheadline).foregroundStyle(theme.muted).card()
                }
                ForEach(plan.activeHabits) { habit in
                    habitRow(habit)
                }
                Button {
                    if PlanStore.canAddHabit(to: plan) { addingNew = true } else { paywall = .habits }
                } label: {
                    Label("Add a habit", systemImage: "plus")
                }
                .buttonStyle(.summaSecondary)
                .disabled(plan.isFinished(today: today))
                .accessibilityIdentifier("plan.addHabit")

                if !plan.archivedHabits.isEmpty {
                    Eyebrow("Archived")
                    ForEach(plan.archivedHabits) { habit in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(habit.title).font(.headline)
                                Text("History kept. No longer scheduled.").font(.footnote).foregroundStyle(theme.muted)
                            }
                            Spacer()
                            Button("Restore") {
                                if PlanStore.canAddHabit(to: plan) { PlanStore.restore(habit, in: context) } else { paywall = .habits }
                            }
                                .font(.subheadline.weight(.semibold)).foregroundStyle(theme.gold).frame(minHeight: 44)
                        }
                        .card(padding: 14)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .sheet(item: $editing) { habit in
            HabitEditorView(heading: "Edit habit", draft: habit.asDraft(), reminderOn: habit.reminderEnabled,
                            otherRemindersOn: plan.activeHabits.filter { $0.reminderEnabled && $0.id != habit.id }.count,
                            scheduleNote: "A new schedule starts today. Earlier days keep the schedule they had.") { draft, reminderOn in
                PlanStore.update(habit, with: draft, reminderEnabled: reminderOn, today: clock.today, in: context)
            }
            .environment(\.theme, theme)
        }
        .sheet(isPresented: $addingNew) {
            HabitEditorView(heading: "New habit",
                            draft: HabitDraft(title: "", action: "", minimumVersion: "", weekdays: [2, 3, 4, 5, 6],
                                              colorHex: nextColor, symbol: "leaf"),
                            reminderOn: false,
                            otherRemindersOn: plan.activeHabits.filter { $0.reminderEnabled }.count,
                            scheduleNote: "This habit starts today. Earlier days will show as rest days.") { draft, reminderOn in
                PlanStore.addHabit(draft, to: plan, startDay: clock.today, reminderEnabled: reminderOn, in: context)
                PlanStore.save(context, plan: plan)
            }
            .environment(\.theme, theme)
        }
        .sheet(item: $paywall) { context in
            SummaProView(context: context).environment(\.theme, theme)
        }
        .confirmationDialog("Archive this habit?", isPresented: Binding(get: { archiving != nil }, set: { if !$0 { archiving = nil } }),
                            titleVisibility: .visible) {
            Button("Archive", role: .destructive) {
                if let habit = archiving { PlanStore.archive(habit, today: clock.today, in: context) }
                archiving = nil
            }
            Button("Cancel", role: .cancel) { archiving = nil }
        } message: {
            Text("Its history stays in Progress. It stops being scheduled from today, and you can restore it later.")
        }
    }

    private var nextColor: String {
        let used = Set(plan.activeHabits.map { $0.colorHex.uppercased() })
        return HabitPalette.all.map(\.hex).first { !used.contains($0.uppercased()) } ?? HabitPalette.gold
    }

    private func habitRow(_ habit: Habit) -> some View {
        let accent = Color.accent(habit.colorHex)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: habit.symbol)
                    .foregroundStyle(accent)
                    .frame(width: 40, height: 40)
                    .background(accent.opacity(0.16), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(habit.title).font(SummaFont.serif(24, relativeTo: .title3))
                    Text(habit.action).font(.subheadline)
                    Text((habit.target.isEmpty ? "" : "Target: \(habit.target) · ") + "\(OnboardingFlow.describe(weekdays: habit.currentWeekdays)) · Minimum: \(habit.minimumVersion)")
                        .font(.footnote).foregroundStyle(theme.muted)
                    if habit.reminderEnabled {
                        Label("Reminder at \(Reminders.timeString(hour: habit.reminderHour, minute: habit.reminderMinute))", systemImage: "bell.fill")
                            .font(.footnote).foregroundStyle(theme.muted)
                    }
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 18) {
                Button("Edit") { editing = habit }
                    .font(.subheadline.weight(.semibold)).foregroundStyle(theme.gold).frame(minHeight: 44)
                    .accessibilityLabel("Edit \(habit.title)")
                    .accessibilityIdentifier("plan.edit.\(habit.title)")
                Button("Archive") { archiving = habit }
                    .font(.subheadline).foregroundStyle(theme.muted).frame(minHeight: 44)
                    .accessibilityLabel("Archive \(habit.title)")
            }
        }
        .card()
    }
}
