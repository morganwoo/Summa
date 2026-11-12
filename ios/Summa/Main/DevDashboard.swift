#if DEBUG
import SwiftUI
import SwiftData
import SummaCore

/// Developer testing. Debug builds only: this whole file is compiled out of Release.
///
/// A preview runs the real screens over a made-up plan held in memory. While it is open,
/// `DevSandbox` stops anything from reaching the widget, reminders, the server, or the photo
/// folder, and the tier shown is an in-memory override that never touches StoreKit.
struct DevDashboardView: View {
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var clock: TodayClock
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var onboarding: OnboardingStore

    @State private var day = 22
    @State private var afterDay90 = false
    @State private var rate = 80
    @State private var asPro = false
    @State private var running: Scenario? = nil
    @State private var note: String? = nil

    struct Scenario: Identifiable, Equatable {
        let id = UUID()
        let day: Int
        let afterDay90: Bool
        let rate: Int
        let asPro: Bool
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Eyebrow("Developer testing")
                        Text("Preview any day.").font(SummaFont.serif(34, relativeTo: .largeTitle)).accessibilityAddTraits(.isHeader)
                        Text("Made-up data in memory. Your real plan, check-ins, reminders, widget, account, and subscription are not touched.")
                            .font(.footnote).foregroundStyle(theme.muted)
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Eyebrow("Program day")
                        FlowLayout(spacing: 8) {
                            ForEach(DevScenario.presetDays, id: \.self) { preset in
                                chip("Day \(preset)", selected: !afterDay90 && day == preset) { day = preset; afterDay90 = false }
                            }
                            chip("After day 90", selected: afterDay90) { afterDay90 = true; day = 90 }
                        }
                        Stepper("Custom: day \(day)", value: $day, in: 1...HabitTimeline.planLength)
                            .disabled(afterDay90)
                        Text(afterDay90 ? "All 90 days are over, so the graduation result is due."
                                        : "\(Stage.forDay(day).name) stage. Days 22 and 67 play their celebration once.")
                            .font(.footnote).foregroundStyle(theme.muted)
                    }
                    .card()

                    VStack(alignment: .leading, spacing: 12) {
                        Eyebrow("Completion of scheduled activities")
                        Picker("Completion", selection: $rate) {
                            ForEach(DevScenario.presetRates, id: \.self) { Text("\($0)%").tag($0) }
                        }
                        .pickerStyle(.segmented)
                        Text("Graduation needs \(Graduation.threshold)% of scheduled activities. 79% shows the summary without the laurel; 80% and 100% graduate. After day 90, “Continue with the same habits” starts a new 90 days inside the preview only.")
                            .font(.footnote).foregroundStyle(theme.muted)
                    }
                    .card()

                    VStack(alignment: .leading, spacing: 12) {
                        Eyebrow("Tier shown in the preview")
                        Picker("Tier", selection: $asPro) {
                            Text("Summa Free").tag(false)
                            Text("Summa Pro").tag(true)
                        }
                        .pickerStyle(.segmented)
                        Text("A mock entitlement for the preview only. No purchase is made or changed.")
                            .font(.footnote).foregroundStyle(theme.muted)
                    }
                    .card()

                    Button("Open preview") { running = Scenario(day: day, afterDay90: afterDay90, rate: rate, asPro: asPro) }
                        .buttonStyle(.summaPrimary)
                        .accessibilityIdentifier("dev.open")
                    Button("Reset milestone animations") {
                        StageMemory.reset(planID: DevSandbox.previewPlanID)
                        note = "Stage celebrations will play again in the next preview."
                    }
                    .buttonStyle(.summaSecondary)
                    .accessibilityIdentifier("dev.reset")
                    if let note { Text(note).font(.footnote).foregroundStyle(theme.muted) }
                }
                .padding(20)
            }
            .marbleBackground()
            .tint(theme.gold)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .foregroundStyle(theme.text)
        .fullScreenCover(item: $running) { scenario in
            DevPreviewHost(scenario: scenario) { running = nil }
                .environment(\.theme, theme)
                .environmentObject(clock).environmentObject(store).environmentObject(onboarding)
        }
    }

    private func chip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.footnote.weight(.semibold))
                .padding(.horizontal, 12).frame(minHeight: 36)
                .foregroundStyle(selected ? theme.onGold : theme.text)
                .background(selected ? theme.gold : theme.surface, in: Capsule())
                .overlay(Capsule().strokeBorder(selected ? Color.clear : theme.divider))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Shows the newest plan in the preview store, exactly as the app's own root does. Continuing into a
/// new 90-day chapter inside the preview therefore lands on that new chapter, with the old one kept.
private struct PreviewRoot: View {
    @Query(sort: \Plan.createdAt, order: .reverse) private var plans: [Plan]

    var body: some View {
        if let plan = plans.first {
            MainTabView(plan: plan).id(plan.id)
        }
    }
}

/// Runs the production tab view over an in-memory store. Nothing here is written to disk.
private struct DevPreviewHost: View {
    @Environment(\.theme) private var theme
    @EnvironmentObject private var clock: TodayClock
    let scenario: DevDashboardView.Scenario
    let exit: () -> Void

    @State private var container: ModelContainer? = nil
    @State private var plan: Plan? = nil

    var body: some View {
        Group {
            if let container, plan != nil {
                PreviewRoot()
                    .modelContainer(container)
                    .overlay(alignment: .topLeading) {
                        Button { close() } label: {
                            Label("Preview · \(scenario.afterDay90 ? "after day 90" : "day \(scenario.day)") · \(scenario.rate)% · \(scenario.asPro ? "Pro" : "Free") · Exit",
                                  systemImage: "xmark.circle.fill")
                                .font(.caption.weight(.semibold)).lineLimit(1)
                                .padding(.horizontal, 12).frame(minHeight: 36)
                                .foregroundStyle(theme.onGold).background(theme.gold, in: Capsule())
                        }
                        .padding(.leading, 12).padding(.top, 4)
                        .accessibilityIdentifier("dev.exit")
                    }
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity).marbleBackground()
            }
        }
        .task { build() }
    }

    private func build() {
        guard container == nil else { return }
        // The sandbox goes up before any preview data exists, and the tier is an in-memory override.
        DevSandbox.isActive = true
        Store.shared.setDebugOverride(scenario.asPro)
        let schema = Schema(SummaSchema.models)
        guard let made = try? ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]) else {
            close()
            return
        }
        let context = made.mainContext
        let today = clock.today
        let resolved = scenario.afterDay90 ? HabitTimeline.planLength : scenario.day - 1
        let start = today.adding(-(scenario.afterDay90 ? HabitTimeline.planLength : scenario.day - 1))
        let draft = StarterPlanBuilder.build(from: OnboardingAnswers())
        let preview = Plan(objective: "Preview: keep three practices for ninety days.", userName: "Preview", startDay: start,
                           phases: draft.phases, source: "developer-preview")
        preview.id = DevSandbox.previewPlanID
        context.insert(preview)
        var habits: [Habit] = []
        for (index, item) in draft.habits.enumerated() {
            var habitDraft = item
            habitDraft.weekdays = [1, 2, 3, 4, 5, 6, 7]
            habits.append(PlanStore.addHabit(habitDraft, to: preview, sortOrder: index, startDay: start, reminderEnabled: false, in: context))
        }
        let offsets = DevScenario.completedOffsets(habits: habits.count, resolvedDays: resolved, percent: scenario.rate)
        for (habit, days) in zip(habits, offsets) {
            for offset in days {
                let checkIn = CheckIn(habitID: habit.id, day: start.adding(offset))
                context.insert(checkIn)
                checkIn.habit = habit
            }
        }
        PlanStore.ensureMilestones(for: preview, in: context)
        try? context.save()
        container = made
        plan = preview
    }

    private func close() {
        PhotoStore.clearPreview() // while the sandbox is still up
        Store.shared.setDebugOverride(nil)
        DevSandbox.isActive = false
        exit()
    }
}
#endif
