import SwiftUI
import SwiftData
import SummaCore

struct MainTabView: View {
    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var clock: TodayClock
    @EnvironmentObject private var store: Store
    let plan: Plan

    private enum Screen: Hashable { case heatmaps, progress, plan, settings }
    @State private var tab: Screen = .heatmaps
    @State private var selectedHabitID: UUID? = nil
    @State private var celebrating: Stage? = nil

    var body: some View {
        let stage = plan.stage(today: clock.today)
        let day = plan.dayNumber(today: clock.today)
        TabView(selection: $tab) {
            HeatmapsView(plan: plan,
                         openProgress: { habit in
                             selectedHabitID = habit.id
                             tab = .progress
                         },
                         openPlan: { tab = .plan })
                .background(StageBackground(stage: stage))
                .tabItem { Label("Heatmaps", systemImage: "square.grid.3x3.fill") }
                .tag(Screen.heatmaps)

            ProgressScreen(plan: plan, selectedHabitID: $selectedHabitID)
                .background(StageBackground(stage: stage))
                .tabItem { Label("Progress", systemImage: "chart.line.uptrend.xyaxis") }
                .tag(Screen.progress)

            PlanOverviewView(plan: plan)
                .background(StageBackground(stage: stage))
                .tabItem { Label("Plan", systemImage: "scroll") }
                .tag(Screen.plan)

            SettingsView(plan: plan)
                .background(StageBackground(stage: stage))
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(Screen.settings)
        }
        .toolbarBackground(theme.background.opacity(0.94), for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .overlay(alignment: .bottomTrailing) {
            if !plan.isFinished(today: clock.today) {
                StagePill(stage: stage, day: day)
                    .padding(.trailing, 14)
                    .padding(.bottom, 60)
            }
        }
        .overlay {
            if let celebrating {
                StageCelebration(stage: celebrating, day: day) { self.celebrating = nil }
                    .transition(.opacity)
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.35), value: celebrating)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.6), value: stage)
        .onAppear {
            WidgetBridge.publish(plan: plan)
            Reminders.sync(plan: plan)
            celebrating = StageMemory.stageToCelebrate(for: plan, today: clock.today)
        }
        .onChange(of: store.isPro) { _, _ in
            // A purchase, restore, expiry, or refund changes what widgets and reminders may do.
            WidgetBridge.publish(plan: plan)
            Reminders.sync(plan: plan)
        }
        .onChange(of: clock.today) { _, today in
            // The stage theme follows the program day: it changes on days 22 and 67.
            if let next = StageMemory.stageToCelebrate(for: plan, today: today) { celebrating = next }
        }
    }
}
