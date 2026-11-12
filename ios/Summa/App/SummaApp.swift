import SwiftUI
import SwiftData
import SummaCore
import UserNotifications

@main
struct SummaApp: App {
    @AppStorage(ThemeChoice.storageKey) private var themeChoice = ThemeChoice.black.rawValue
    @StateObject private var onboarding = OnboardingStore(persistent: AppEnvironment.usesDisk)
    @StateObject private var clock = TodayClock()
    @StateObject private var store = Store.shared
    private let container: ModelContainer

    init() {
        let schema = Schema(SummaSchema.models)
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: !AppEnvironment.usesDisk)
        do {
            container = try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Could not open the Summa store: \(error)")
        }
        UNUserNotificationCenter.current().delegate = ReminderPresenter.shared
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
                .environmentObject(store)
                .task { store.start() }
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
    @State private var paywall: PaywallContext? = nil
    /// True while someone with a finished chapter is setting up the next one.
    @AppStorage("summa.newChapter") private var startingNewChapter = false

    var body: some View {
        ZStack {
            MarbleBackground()
            if let plan = plans.first, !startingNewChapter {
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
        .onOpenURL { url in
            // The locked widget links here: tapping it is the request to unlock widgets.
            if url.scheme == "summa", url.host == "pro", !Entitlements.isPro { paywall = .widgets }
        }
        .sheet(item: $paywall) { context in
            SummaProView(context: context).environment(\.theme, theme)
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
