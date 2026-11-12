import SwiftUI
import SwiftData
import SummaCore

struct SettingsView: View {
    @Environment(\.theme) private var theme
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var clock: TodayClock
    @EnvironmentObject private var onboarding: OnboardingStore
    @EnvironmentObject private var store: Store
    @AppStorage(ThemeChoice.storageKey) private var themeChoice = ThemeChoice.black.rawValue
    let plan: Plan

    @State private var notificationAccess: Reminders.Access = .undetermined
    @State private var confirmRestart = false
    @State private var paywall: PaywallContext? = nil
    #if DEBUG
    @State private var showDeveloper = false
    #endif

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Eyebrow("Settings")
                    Text(plan.userName.isEmpty ? "Your Summa." : "\(plan.userName)’s Summa.")
                        .font(SummaFont.serif(36, relativeTo: .largeTitle))
                        .accessibilityAddTraits(.isHeader)
                }

                VStack(alignment: .leading, spacing: 10) {
                    Eyebrow("Membership")
                    Text(store.planName).font(SummaFont.serif(24, relativeTo: .title3))
                    Text(store.isPro ? "Unlimited habits and friends, reminders for every habit, widgets, and the graduation certificate."
                                     : "Three active habits, two friends, one daily reminder, the full 90-day program.")
                        .font(.footnote).foregroundStyle(theme.muted)
                    Button(store.isPro ? "View Summa Pro" : "See Summa Pro") { paywall = .settings }
                        .buttonStyle(.summaSecondary)
                        .accessibilityIdentifier("settings.pro")
                }
                .card()

                VStack(alignment: .leading, spacing: 12) {
                    Eyebrow("Theme")
                    HStack(spacing: 12) {
                        ForEach(ThemeChoice.allCases) { choice in
                            themeSwatch(choice)
                        }
                    }
                }
                .card()

                VStack(alignment: .leading, spacing: 12) {
                    Eyebrow("Reminders")
                    if notificationAccess == .denied {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Notifications are off for Summa.").font(.subheadline.weight(.semibold))
                            Text("Tracking works without them. To get reminders, allow notifications in Settings.")
                                .font(.footnote).foregroundStyle(theme.muted)
                            Button("Open Settings") { Reminders.openSystemSettings() }
                                .font(.footnote.weight(.semibold)).foregroundStyle(theme.gold).frame(minHeight: 44)
                        }
                    }
                    if plan.activeHabits.isEmpty {
                        Text("Add a habit to set a reminder.").font(.footnote).foregroundStyle(theme.muted)
                    }
                    ForEach(plan.activeHabits) { habit in
                        ReminderRow(habit: habit,
                                    othersOn: plan.activeHabits.filter { $0.reminderEnabled && $0.id != habit.id }.count,
                                    isPro: store.isPro,
                                    onBlocked: { paywall = .reminders }) { await refreshAccess() }
                        if habit.id != plan.activeHabits.last?.id { Hairline() }
                    }
                    if !store.isPro, plan.activeHabits.filter({ $0.reminderEnabled }).count > 1 {
                        Text("Summa Free delivers one reminder, for the first habit in your plan that has one on. The others are paused, not deleted.")
                            .font(.footnote).foregroundStyle(theme.muted)
                    } else if !store.isPro {
                        Text("Summa Free includes one daily reminder.").font(.footnote).foregroundStyle(theme.muted)
                    }
                }
                .card()

                VStack(alignment: .leading, spacing: 10) {
                    Eyebrow("Widgets")
                    Text(store.isPro
                         ? "Add a Summa widget from your home screen: touch and hold an empty area, tap Edit, then Add Widget."
                         : "Home-screen widgets show today’s habits, your day and stage, and the 90-day heatmap. They are part of Summa Pro.")
                        .font(.footnote).foregroundStyle(theme.muted)
                    if !store.isPro {
                        Button("Unlock widgets") { paywall = .widgets }
                            .buttonStyle(.summaSecondary)
                            .accessibilityIdentifier("settings.widgets")
                    }
                }
                .card()

                VStack(alignment: .leading, spacing: 10) {
                    Eyebrow("Your data")
                    Text("Your plan and check-ins are stored on this device and work offline. Voice is transcribed live and the audio is never saved. \(PlanService.configured.usesRemote ? "Plan drafts are generated by the Summa plan service from your onboarding answers." : "This build drafts plans on device; no answers leave your phone.")")
                        .font(.footnote).foregroundStyle(theme.muted)
                    Button("Erase all data", role: .destructive) { confirmRestart = true }
                        .font(.subheadline.weight(.semibold))
                        .frame(minHeight: 44)
                        .disabled(DevSandbox.isActive)
                        .accessibilityIdentifier("settings.restart")
                }
                .card()

                #if DEBUG
                if !DevSandbox.isActive {
                    VStack(alignment: .leading, spacing: 10) {
                        Eyebrow("Developer")
                        Text("Preview any day, stage, graduation result, and tier with made-up data. Debug builds only; your real record is never touched.")
                            .font(.footnote).foregroundStyle(theme.muted)
                        Button("Developer testing") { showDeveloper = true }
                            .buttonStyle(.summaSecondary)
                            .accessibilityIdentifier("settings.developer")
                    }
                    .card()
                }
                #endif

                Text("Memento mori. Memento vivere.")
                    .font(SummaFont.serifItalic(18, relativeTo: .footnote))
                    .foregroundStyle(theme.muted)
                    .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .task { await refreshAccess() }
        #if DEBUG
        .sheet(isPresented: $showDeveloper) {
            DevDashboardView()
                .environment(\.theme, theme)
                .environmentObject(clock).environmentObject(store).environmentObject(onboarding)
        }
        #endif
        .sheet(item: $paywall) { context in
            SummaProView(context: context).environment(\.theme, theme)
        }
        .confirmationDialog("Erase all data?", isPresented: $confirmRestart, titleVisibility: .visible) {
            Button("Erase everything and start over", role: .destructive) {
                PlanStore.deleteEverything(in: context)
                onboarding.reset()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently deletes every chapter, habit, check-in, milestone, and photo on this device. It cannot be undone. To begin a new chapter and keep your history, use Plan > Graduation after day 90.")
        }
    }

    private func refreshAccess() async {
        notificationAccess = await Reminders.access()
    }

    private func themeSwatch(_ choice: ThemeChoice) -> some View {
        let swatch = choice.theme
        let isSelected = themeChoice == choice.rawValue
        return Button {
            Haptics.select()
            themeChoice = choice.rawValue
            WidgetBridge.publish(plan: plan)
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(LinearGradient(colors: [swatch.background, swatch.backgroundEdge], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(height: 64)
                    .overlay(alignment: .bottomLeading) {
                        HStack(spacing: 4) {
                            ForEach(0..<5, id: \.self) { index in
                                RoundedRectangle(cornerRadius: 2).fill(swatch.gold.opacity(index % 2 == 0 ? 1 : 0.35)).frame(width: 10, height: 10)
                            }
                        }
                        .padding(10)
                    }
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(isSelected ? theme.gold : theme.divider, lineWidth: isSelected ? 2 : 1))
                HStack(spacing: 6) {
                    if isSelected { Image(systemName: "checkmark.circle.fill").foregroundStyle(theme.gold) }
                    Text(choice.name).font(.subheadline.weight(.medium)).foregroundStyle(theme.text)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(choice.name)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("theme.\(choice.rawValue)")
    }
}

private struct ReminderRow: View {
    @Environment(\.theme) private var theme
    @Environment(\.modelContext) private var context
    let habit: Habit
    let othersOn: Int
    let isPro: Bool
    let onBlocked: () -> Void
    let onPermissionChange: () async -> Void

    private func time(hour: ReferenceWritableKeyPath<Habit, Int>, minute: ReferenceWritableKeyPath<Habit, Int>) -> Binding<Date> {
        Binding(
            get: { Calendar.current.date(from: DateComponents(hour: habit[keyPath: hour], minute: habit[keyPath: minute])) ?? Date() },
            set: { date in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                habit[keyPath: hour] = parts.hour ?? 8
                habit[keyPath: minute] = parts.minute ?? 0
                PlanStore.save(context, plan: habit.plan)
            })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(isOn: Binding(get: { habit.reminderEnabled }, set: { set($0) })) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(habit.title).font(.subheadline.weight(.semibold))
                    Text(OnboardingFlow.describe(weekdays: habit.currentWeekdays)).font(.footnote).foregroundStyle(theme.muted)
                }
            }
            .tint(Color.accent(habit.colorHex))
            .accessibilityIdentifier("reminder.toggle.\(habit.title)")
            if habit.reminderEnabled {
                DatePicker("Time", selection: time(hour: \.reminderHour, minute: \.reminderMinute), displayedComponents: .hourAndMinute)
                    .font(.subheadline)
                Toggle(isOn: Binding(get: { isPro && habit.secondReminderEnabled }, set: { setSecond($0) })) {
                    Text(isPro ? "Second reminder" : "Second reminder · Pro").font(.subheadline)
                }
                .tint(Color.accent(habit.colorHex))
                if isPro, habit.secondReminderEnabled {
                    DatePicker("Second time", selection: time(hour: \.secondReminderHour, minute: \.secondReminderMinute),
                               displayedComponents: .hourAndMinute)
                        .font(.subheadline)
                }
            }
        }
    }

    private func set(_ on: Bool) {
        guard on else {
            habit.reminderEnabled = false
            habit.secondReminderEnabled = false
            PlanStore.save(context, plan: habit.plan)
            return
        }
        guard ReminderPlanner.canEnableReminder(othersEnabled: othersOn, isPro: isPro) else {
            onBlocked()
            return
        }
        Task { @MainActor in
            // Permission is asked here, when a reminder is first switched on.
            let allowed = await Reminders.requestIfNeeded()
            habit.reminderEnabled = allowed
            PlanStore.save(context, plan: habit.plan)
            await onPermissionChange()
        }
    }

    private func setSecond(_ on: Bool) {
        guard isPro else {
            onBlocked()
            return
        }
        habit.secondReminderEnabled = on
        PlanStore.save(context, plan: habit.plan)
    }
}
