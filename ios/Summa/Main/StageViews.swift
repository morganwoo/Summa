import SwiftUI
import SummaCore

extension Stage {
    var color: Color { Color(hex: accentHex) }
}

/// A pair of laurel branches forming a wreath.
struct LaurelWreath: View {
    let size: CGFloat
    var weight: Font.Weight = .light

    var body: some View {
        HStack(spacing: -size * 0.14) {
            Image(systemName: "laurel.leading")
            Image(systemName: "laurel.trailing")
        }
        .font(.system(size: size, weight: weight))
    }
}

/// Marble with golden laurels that grow from small to ornate as the stages advance.
/// Purely decorative, kept faint so text and data stay legible.
struct StageBackground: View {
    @Environment(\.theme) private var theme
    let stage: Stage

    var body: some View {
        ZStack {
            MarbleBackground()
            GeometryReader { proxy in
                let w = proxy.size.width
                let h = proxy.size.height
                let base = theme.isDark ? 0.09 : 0.13
                ZStack {
                    switch stage {
                    case .foundation:
                        LaurelWreath(size: 56, weight: .ultraLight)
                            .opacity(base)
                            .position(x: w * 0.8, y: h * 0.16)
                    case .momentum:
                        LaurelWreath(size: 128, weight: .light)
                            .opacity(base + 0.02)
                            .position(x: w * 0.76, y: h * 0.2)
                        LaurelWreath(size: 84, weight: .light)
                            .opacity(base)
                            .position(x: w * 0.2, y: h * 0.74)
                    case .transformation:
                        ZStack {
                            LaurelWreath(size: 250, weight: .regular)
                            LaurelWreath(size: 150, weight: .light).opacity(0.7)
                        }
                        .opacity(base + 0.04)
                        .position(x: w * 0.5, y: h * 0.4)
                        LaurelWreath(size: 96, weight: .regular)
                            .opacity(base + 0.02)
                            .position(x: w * 0.84, y: h * 0.1)
                        LaurelWreath(size: 96, weight: .regular)
                            .opacity(base + 0.02)
                            .position(x: w * 0.16, y: h * 0.84)
                    }
                }
                .foregroundStyle(theme.gold)
            }
            .ignoresSafeArea()
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// The current stage, shown in the bottom-right corner of the daily app.
struct StagePill: View {
    @Environment(\.theme) private var theme
    let stage: Stage
    let day: Int

    var body: some View {
        HStack(spacing: 7) {
            Circle().fill(stage.color).frame(width: 9, height: 9)
            Text(stage.name.uppercased())
                .font(.caption2.weight(.semibold))
                .tracking(1.4)
                .foregroundStyle(theme.text)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 7)
        .background(theme.surfaceRaised, in: Capsule())
        .overlay(Capsule().strokeBorder(stage.color.opacity(0.75), lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Stage \(stage.rawValue) of 3: \(stage.name). Day \(day) of \(HabitTimeline.planLength).")
        .accessibilityIdentifier("stage.pill")
    }
}

/// Shown once, the first time the app is opened in a new stage.
struct StageCelebration: View {
    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let stage: Stage
    let day: Int
    let onDismiss: () -> Void

    @State private var arrived = false

    var body: some View {
        ZStack {
            theme.background.opacity(0.96).ignoresSafeArea()
            VStack(spacing: 18) {
                ZStack {
                    Circle()
                        .stroke(stage.color.opacity(0.5), lineWidth: 1)
                        .frame(width: 190, height: 190)
                        .scaleEffect(reduceMotion || arrived ? 1 : 0.7)
                    LaurelWreath(size: stage == .transformation ? 132 : 104, weight: stage == .transformation ? .regular : .light)
                        .foregroundStyle(theme.gold)
                        .scaleEffect(reduceMotion || arrived ? 1 : 0.55)
                    Text(["I", "II", "III"][stage.rawValue - 1])
                        .font(SummaFont.roman(26, relativeTo: .title2))
                        .foregroundStyle(stage.color)
                }
                .accessibilityHidden(true)
                Eyebrow("Day \(day) · Stage \(stage.rawValue) of 3", color: stage.color)
                Text(stage.name)
                    .font(SummaFont.serif(46, relativeTo: .largeTitle))
                    .accessibilityAddTraits(.isHeader)
                Text(stage.tagline)
                    .font(SummaFont.serifItalic(22, relativeTo: .title3))
                    .foregroundStyle(theme.muted)
                    .multilineTextAlignment(.center)
                Button("Continue", action: onDismiss)
                    .buttonStyle(.summaPrimary)
                    .padding(.top, 14)
                    .accessibilityIdentifier("stage.continue")
            }
            .padding(.horizontal, 32)
            .opacity(arrived ? 1 : 0)
        }
        .foregroundStyle(theme.text)
        .accessibilityAddTraits(.isModal)
        .onAppear {
            Haptics.commit()
            withAnimation(reduceMotion ? .easeIn(duration: 0.2) : .spring(response: 0.75, dampingFraction: 0.68)) { arrived = true }
        }
    }
}

/// Remembers which stage has already been celebrated for a plan, so the moment never replays.
enum StageMemory {
    private static func key(_ plan: Plan) -> String { "summa.stageCelebrated.\(plan.id.uuidString)" }

    /// Forgets what has been celebrated for one plan, so its stage celebrations play again.
    static func reset(planID: UUID) {
        UserDefaults.standard.removeObject(forKey: "summa.stageCelebrated.\(planID.uuidString)")
    }

    /// Returns the stage to celebrate now, and records it so it is shown only once.
    static func stageToCelebrate(for plan: Plan, today: DayKey) -> Stage? {
        guard !plan.isFinished(today: today), !AppEnvironment.arguments.contains("-skipStageCelebration") else { return nil }
        let defaults = UserDefaults.standard
        let current = Stage.forDay(plan.dayNumber(today: today))
        let stage = Stage.toCelebrate(current: current, lastCelebrated: defaults.integer(forKey: key(plan)))
        if defaults.integer(forKey: key(plan)) < current.rawValue { defaults.set(current.rawValue, forKey: key(plan)) }
        return stage
    }
}
