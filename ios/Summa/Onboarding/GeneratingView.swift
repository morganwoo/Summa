import SwiftUI
import SummaCore

/// "Fine-tuning your plan". Each status line reflects a step that is actually running.
struct GeneratingView: View {
    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var onboarding: OnboardingStore

    private enum Phase: Equatable { case working, ready, failed(String) }

    @State private var phase: Phase = .working
    @State private var stage: GenerationStage = .reviewing
    @State private var pulse = false
    @State private var attempt = 0

    private let service = PlanService.configured

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            switch phase {
            case .working: working
            case .ready: ready
            case .failed(let message): failed(message)
            }
            Spacer()
        }
        .padding(.horizontal, 28)
        .frame(maxWidth: .infinity)
        .task(id: attempt) { await generate() }
    }

    private var working: some View {
        VStack(spacing: 22) {
            ZStack {
                Circle().stroke(theme.divider, lineWidth: 1).frame(width: 88, height: 88)
                Circle()
                    .trim(from: 0, to: CGFloat(stage.rawValue + 1) / CGFloat(GenerationStage.allCases.count))
                    .stroke(theme.gold, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: 88, height: 88)
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.5), value: stage)
                Image(systemName: "laurel.leading")
                    .font(.title)
                    .foregroundStyle(theme.gold)
                    .opacity(reduceMotion ? 1 : (pulse ? 1 : 0.45))
            }
            .accessibilityHidden(true)
            Text("Fine-tuning your plan")
                .font(SummaFont.serif(32, relativeTo: .title))
                .accessibilityAddTraits(.isHeader)
            VStack(alignment: .leading, spacing: 10) {
                ForEach(GenerationStage.allCases, id: \.rawValue) { item in
                    HStack(spacing: 10) {
                        Image(systemName: item.rawValue < stage.rawValue ? "checkmark" : (item == stage ? "circle.fill" : "circle"))
                            .font(.caption2)
                            .foregroundStyle(item.rawValue <= stage.rawValue ? theme.gold : theme.muted)
                            .frame(width: 16)
                        Text(item.label)
                            .font(.subheadline)
                            .foregroundStyle(item.rawValue <= stage.rawValue ? theme.text : theme.muted)
                    }
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(stage.label)
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) { pulse = true }
        }
    }

    private var ready: some View {
        VStack(spacing: 18) {
            Image(systemName: "checkmark")
                .font(.title2.weight(.semibold))
                .foregroundStyle(theme.onGold)
                .frame(width: 64, height: 64)
                .background(theme.gold, in: Circle())
                .accessibilityHidden(true)
            Text("Your 90-day plan is ready.")
                .font(SummaFont.serif(32, relativeTo: .title))
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
            Text(onboarding.draft?.source == "ai"
                 ? "Built around your life. It is a draft: change anything before you begin."
                 : "A starter plan built on this device from your answers. Change anything before you begin.")
                .font(.subheadline)
                .foregroundStyle(theme.muted)
                .multilineTextAlignment(.center)
            Button("View my 90-day plan") {
                Haptics.commit()
                onboarding.stage = .review
            }
            .buttonStyle(.summaPrimary)
            .padding(.top, 8)
            .accessibilityIdentifier("generating.viewPlan")
        }
    }

    private func failed(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.circle")
                .font(.largeTitle)
                .foregroundStyle(theme.muted)
                .accessibilityHidden(true)
            Text("The plan did not come through.")
                .font(SummaFont.serif(30, relativeTo: .title))
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
            Text("\(message) Your answers are saved.")
                .font(.subheadline)
                .foregroundStyle(theme.muted)
                .multilineTextAlignment(.center)
            Button("Try again") { attempt += 1 }
                .buttonStyle(.summaPrimary)
                .accessibilityIdentifier("generating.retry")
            Button("Start from an editable plan") {
                onboarding.draft = (try? StarterPlanBuilder.build(from: onboarding.answers).validated())
                    ?? StarterPlanBuilder.build(from: OnboardingAnswers())
                onboarding.stage = .review
            }
            .buttonStyle(.summaSecondary)
            .accessibilityIdentifier("generating.starter")
            Button("Review my answers") {
                onboarding.stage = .questions
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(theme.gold)
            .frame(minHeight: 44)
        }
    }

    private func generate() async {
        phase = .working
        stage = .reviewing
        do {
            let draft = try await service.generate(from: onboarding.answers) { stage = $0 }
            try Task.checkCancellation()
            onboarding.draft = draft
            onboarding.remindersOn = []
            phase = .ready
            UIAccessibility.post(notification: .announcement, argument: "Your 90-day plan is ready.")
        } catch is CancellationError {
            return
        } catch {
            phase = .failed((error as? LocalizedError)?.errorDescription ?? "Something went wrong.")
        }
    }
}
