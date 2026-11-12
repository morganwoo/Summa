import SwiftUI
import SwiftData
import SummaCore

/// The plan reveal. Everything is editable before the first day begins.
struct PlanReviewView: View {
    @Environment(\.theme) private var theme
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var onboarding: OnboardingStore
    @EnvironmentObject private var clock: TodayClock

    @State private var editing: HabitDraft? = nil

    private var draft: PlanDraft {
        onboarding.draft ?? StarterPlanBuilder.build(from: onboarding.answers)
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    objective
                    phases
                    habits
                    Text("Nothing here is final. You can change habits, schedules, colors, and reminders at any time, and past days keep the schedule they were lived under.")
                        .font(.footnote)
                        .foregroundStyle(theme.muted)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)

            Button("Begin day one") { begin() }
                .buttonStyle(.summaPrimary)
                .disabled(!canBegin)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .accessibilityIdentifier("review.begin")
        }
        .sheet(item: $editing) { habit in
            HabitEditorView(heading: "Edit habit", draft: habit, reminderOn: onboarding.remindersOn.contains(habit.id),
                            otherRemindersOn: onboarding.remindersOn.subtracting([habit.id]).count) { updated, reminderOn in
                apply(updated, reminderOn: reminderOn)
            }
            .environment(\.theme, theme)
        }
        .onAppear {
            if onboarding.draft == nil { onboarding.draft = draft }
        }
    }

    private var canBegin: Bool {
        (try? draft.validated()) != nil
    }

    // MARK: Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button {
                    onboarding.stage = .questions
                } label: {
                    Label("Answers", systemImage: "chevron.left").font(.footnote.weight(.semibold)).frame(minHeight: 44)
                }
                .buttonStyle(.plain)
                .foregroundStyle(theme.muted)
                Spacer()
                Wordmark()
            }
            StatueArch(imageName: "StatueSeneca", alignment: .top)
                .frame(height: 230)
                .padding(.horizontal, 44)
            Eyebrow("Your 90 days")
            Text(onboarding.answers.name.isEmpty ? "Made for your life." : "Made for your life, \(onboarding.answers.name).")
                .font(SummaFont.serif(36, relativeTo: .largeTitle))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
        }
    }

    private var objective: some View {
        VStack(alignment: .leading, spacing: 8) {
            Eyebrow("Objective", color: theme.gold)
            TextField("What you want to accomplish", text: Binding(
                get: { draft.objective },
                set: { value in update { plan in plan.objective = String(value.prefix(280)) } }), axis: .vertical)
                .font(SummaFont.serif(24, relativeTo: .title3))
                .lineLimit(1...5)
                .accessibilityLabel("Objective")
                .accessibilityIdentifier("review.objective")
        }
        .card()
    }

    private var phases: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(draft.phases.enumerated()), id: \.offset) { index, phase in
                VStack(alignment: .leading, spacing: 4) {
                    Text(String(format: "DAYS %02d — %02d", phase.startDay, phase.endDay))
                        .font(.caption.weight(.semibold)).tracking(1.5).foregroundStyle(theme.gold)
                    HStack(spacing: 8) {
                        Circle().fill(phase.stage.color).frame(width: 9, height: 9).accessibilityHidden(true)
                        Text(phase.stage.name).font(SummaFont.serif(24, relativeTo: .title3))
                    }
                    Text(phase.focus).font(.subheadline).foregroundStyle(theme.muted)
                }
                .padding(.vertical, 14)
                .accessibilityElement(children: .combine)
                if index < draft.phases.count - 1 { Hairline() }
            }
        }
        .card(padding: 18)
    }

    private var habits: some View {
        VStack(alignment: .leading, spacing: 12) {
            Eyebrow("Your three habits")
            ForEach(draft.habits) { habit in
                HabitDraftRow(habit: habit, reminderOn: onboarding.remindersOn.contains(habit.id),
                              onEdit: { editing = habit },
                              onRegenerate: { regenerate(habit) })
            }
            Text("Every plan starts with three. Edit any of them, or ask for a different suggestion.")
                .font(.footnote).foregroundStyle(theme.muted)
        }
    }

    // MARK: Changes

    private func update(_ change: (inout PlanDraft) -> Void) {
        var next = draft
        change(&next)
        onboarding.draft = next
    }

    private func apply(_ habit: HabitDraft, reminderOn: Bool) {
        update { plan in
            if let index = plan.habits.firstIndex(where: { $0.id == habit.id }) {
                plan.habits[index] = habit
            }
        }
        if reminderOn { onboarding.remindersOn.insert(habit.id) } else { onboarding.remindersOn.remove(habit.id) }
    }

    /// Swaps one recommendation for the next one that fits this person. The other two stay as they are.
    private func regenerate(_ habit: HabitDraft) {
        Haptics.select()
        let next = StarterPlanBuilder.replacement(for: habit, in: draft, answers: onboarding.answers)
        update { plan in
            if let index = plan.habits.firstIndex(where: { $0.id == habit.id }) { plan.habits[index] = next }
        }
        onboarding.remindersOn.remove(habit.id)
        UIAccessibility.post(notification: .announcement, argument: "New suggestion: \(next.title)")
    }

    private func begin() {
        guard let plan = try? draft.validated() else { return }
        Haptics.commit()
        clock.refresh()
        PlanStore.startPlan(from: plan, answers: onboarding.answers, remindersOn: onboarding.remindersOn,
                            today: clock.today, in: context)
        onboarding.reset()
    }
}

private struct HabitDraftRow: View {
    @Environment(\.theme) private var theme
    let habit: HabitDraft
    let reminderOn: Bool
    let onEdit: () -> Void
    let onRegenerate: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: habit.symbol)
                    .foregroundStyle(Color.accent(habit.colorHex))
                    .frame(width: 40, height: 40)
                    .background(Color.accent(habit.colorHex).opacity(0.16), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(habit.title).font(SummaFont.serif(24, relativeTo: .title3))
                    Text(habit.action).font(.subheadline)
                }
                Spacer(minLength: 0)
            }
            if !habit.reason.isEmpty {
                Text(habit.reason)
                    .font(SummaFont.serifItalic(18, relativeTo: .subheadline))
                    .foregroundStyle(theme.text.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: 6) {
                if !habit.target.isEmpty { detail("target", "Target: \(habit.target)") }
                detail("calendar", OnboardingFlow.describe(weekdays: habit.weekdays))
                detail("arrow.down.right.circle", "Minimum: \(habit.minimumVersion)")
                if let reminder = habit.reminder {
                    detail(reminderOn ? "bell.fill" : "bell",
                           reminderOn ? "Reminder at \(Reminders.timeString(hour: reminder.hour, minute: reminder.minute))"
                                      : "Suggested reminder: \(Reminders.timeString(hour: reminder.hour, minute: reminder.minute)) (off)")
                }
            }
            HStack(spacing: 18) {
                Button("Edit", action: onEdit)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(theme.gold)
                    .frame(minHeight: 44)
                    .accessibilityLabel("Edit \(habit.title)")
                    .accessibilityIdentifier("review.edit.\(habit.title)")
                Button("Suggest another", action: onRegenerate)
                    .font(.subheadline)
                    .foregroundStyle(theme.muted)
                    .frame(minHeight: 44)
                    .accessibilityLabel("Suggest another habit instead of \(habit.title)")
                    .accessibilityIdentifier("review.regenerate.\(habit.title)")
            }
        }
        .card()
    }

    private func detail(_ icon: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: icon).font(.footnote).foregroundStyle(theme.muted).frame(width: 18)
            Text(text).font(.footnote).foregroundStyle(theme.muted)
        }
    }
}
