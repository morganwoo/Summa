import SwiftUI
import SwiftData
import SummaCore

struct MainTabView: View {
    @Environment(\.theme) private var theme
    let plan: Plan

    private enum Screen: Hashable { case heatmaps, progress, plan, settings }
    @State private var tab: Screen = .heatmaps
    @State private var selectedHabitID: UUID? = nil

    var body: some View {
        TabView(selection: $tab) {
            HeatmapsView(plan: plan,
                         openProgress: { habit in
                             selectedHabitID = habit.id
                             tab = .progress
                         },
                         openPlan: { tab = .plan })
                .marbleBackground()
                .tabItem { Label("Heatmaps", systemImage: "square.grid.3x3.fill") }
                .tag(Screen.heatmaps)

            ProgressScreen(plan: plan, selectedHabitID: $selectedHabitID)
                .marbleBackground()
                .tabItem { Label("Progress", systemImage: "chart.line.uptrend.xyaxis") }
                .tag(Screen.progress)

            PlanOverviewView(plan: plan)
                .marbleBackground()
                .tabItem { Label("Plan", systemImage: "scroll") }
                .tag(Screen.plan)

            SettingsView(plan: plan)
                .marbleBackground()
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(Screen.settings)
        }
        .toolbarBackground(theme.background.opacity(0.94), for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .onAppear {
            WidgetBridge.publish(plan: plan)
            Reminders.sync(plan: plan)
        }
    }
}
