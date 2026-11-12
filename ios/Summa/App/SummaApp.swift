import SwiftUI
import SwiftData
import SummaCore

@main
struct SummaApp: App {
    @AppStorage(ThemeChoice.storageKey) private var themeChoice = ThemeChoice.black.rawValue
    @StateObject private var onboarding = OnboardingStore(persistent: AppEnvironment.usesDisk)
    @StateObject private var clock = TodayClock()
    private let container: ModelContainer

    init() {
        let schema = Schema(SummaSchema.models)
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: !AppEnvironment.usesDisk)
        do {
            container = try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Could not open the Summa store: \(error)")
        }
        if AppEnvironment.arguments.contains("-resetState") {
            PlanStore.deleteEverything(in: container.mainContext)
            OnboardingStore.eraseSavedFile()
        }
    }

    var body: some Scene {
        WindowGroup {
            let theme = (ThemeChoice(rawValue: themeChoice) ?? .black).theme
            RootView()
                .environment(\.theme, theme)
                .environmentObject(onboarding)
                .environmentObject(clock)
                .preferredColorScheme(theme.isDark ? .dark : .light)
                .tint(theme.gold)
        }
        .modelContainer(container)
    }
}

/// Routes between onboarding and the daily app based on whether a plan has started.
struct RootView: View {
    @Environment(\.theme) private var theme
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var onboarding: OnboardingStore
    @EnvironmentObject private var clock: TodayClock
    @Query(sort: \Plan.createdAt, order: .reverse) private var plans: [Plan]

    var body: some View {
        ZStack {
            MarbleBackground()
            if let plan = plans.first {
                MainTabView(plan: plan)
                    .transition(.opacity)
            } else {
                onboardingStage
                    .transition(.opacity)
            }
        }
        .foregroundStyle(theme.text)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.35), value: onboarding.stage)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.5), value: plans.first?.id)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { clock.refresh() }
        }
    }

    @ViewBuilder
    private var onboardingStage: some View {
        switch onboarding.stage {
        case .welcome: WelcomeView()
        case .choosePath: PathChoiceView()
        case .questions:
            if onboarding.answers.mode == "talk" { TalkOnboardingView() } else { GuidedOnboardingView() }
        case .generating: GeneratingView()
        case .review: PlanReviewView()
        }
    }
}
