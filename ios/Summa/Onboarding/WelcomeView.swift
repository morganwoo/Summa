import SwiftUI

struct WelcomeView: View {
    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var onboarding: OnboardingStore

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    StatueArch(imageName: "StatueHero", alignment: .trailing)
                        .frame(height: max(220, proxy.size.height * 0.36))
                        .padding(.horizontal, 36)
                        .padding(.top, 12)

                    VStack(spacing: 14) {
                        Wordmark()
                        Text("This is your invitation to become who you want to be.")
                            .font(SummaFont.serif(34, relativeTo: .largeTitle))
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("Welcome to Summa.")
                            .font(SummaFont.serifItalic(24, relativeTo: .title2))
                            .foregroundStyle(theme.gold)
                    }
                    .padding(.horizontal, 28)
                    .padding(.top, 20)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("This is your invitation to become who you want to be. Welcome to Summa.")
                    .accessibilityAddTraits(.isHeader)

                    Spacer(minLength: 20)

                    FingerprintHold(reduceMotion: reduceMotion) { begin() }
                        .padding(.top, 20)
                    Text("Press and hold to begin")
                        .font(.footnote)
                        .foregroundStyle(theme.muted)
                        .padding(.top, 10)
                        .accessibilityHidden(true)

                    Button("Continue") { begin() }
                        .buttonStyle(.summaSecondary)
                        .padding(.horizontal, 28)
                        .padding(.top, 18)
                        .padding(.bottom, 20)
                        .accessibilityIdentifier("welcome.continue")
                        .accessibilityHint("Begins setting up your 90-day plan")
                }
                .frame(minHeight: proxy.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    private func begin() {
        Haptics.commit()
        onboarding.stage = .choosePath
    }
}

/// Decorative press-and-hold. A ripple shows progress; one haptic fires on completion.
/// VoiceOver and Switch Control users use the Continue button instead.
private struct FingerprintHold: View {
    @Environment(\.theme) private var theme
    let reduceMotion: Bool
    let onComplete: () -> Void

    private let duration = 1.4
    @State private var progress: CGFloat = 0
    @State private var isPressing = false

    var body: some View {
        ZStack {
            if !reduceMotion {
                ForEach(0..<3, id: \.self) { ring in
                    Circle()
                        .stroke(theme.gold.opacity(Double(0.34 - CGFloat(ring) * 0.09) * Double(progress)), lineWidth: 1)
                        .frame(width: 96, height: 96)
                        .scaleEffect(1 + progress * (0.32 + CGFloat(ring) * 0.26))
                }
            }
            Circle()
                .fill(theme.surface)
                .frame(width: 96, height: 96)
                .overlay(Circle().strokeBorder(theme.divider))
            Circle()
                .trim(from: 0, to: progress)
                .stroke(theme.gold, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .frame(width: 96, height: 96)
            Image(systemName: "touchid")
                .font(.system(size: 46, weight: .ultraLight))
                .foregroundStyle(theme.gold.opacity(0.55 + 0.45 * Double(progress)))
        }
        .frame(width: 170, height: 170)
        .contentShape(Circle())
        .onLongPressGesture(minimumDuration: duration, maximumDistance: 80) {
            isPressing = false
            onComplete()
        } onPressingChanged: { pressing in
            isPressing = pressing
            if pressing {
                withAnimation(.linear(duration: duration)) { progress = 1 }
            } else {
                withAnimation(.easeOut(duration: 0.25)) { progress = 0 }
            }
        }
        .accessibilityHidden(true)
    }
}

struct PathChoiceView: View {
    @Environment(\.theme) private var theme
    @EnvironmentObject private var onboarding: OnboardingStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Button {
                    onboarding.stage = .welcome
                } label: {
                    Image(systemName: "chevron.left").font(.body.weight(.semibold)).frame(width: 44, height: 44, alignment: .leading)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back")

                Eyebrow("Your beginning")
                Text("Bring your story. We’ll shape the plan.")
                    .font(SummaFont.serif(36, relativeTo: .largeTitle))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Text("Both paths ask the same questions and build the same plan. You can switch at any time without losing an answer.")
                    .font(.body)
                    .foregroundStyle(theme.muted)

                choice(icon: "mic", title: "Talk with Summa",
                       detail: "A spoken conversation. Your words appear as text you can edit before sending.",
                       id: "path.talk") { choose("talk") }
                choice(icon: "list.bullet", title: "Build my plan",
                       detail: "A short guided sequence. Mostly taps, a little typing.",
                       id: "path.guided") { choose("guided") }

                Text("About three minutes. Your answers stay on this device until you ask for a plan.")
                    .font(.footnote)
                    .foregroundStyle(theme.muted)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
        }
    }

    private func choose(_ mode: String) {
        Haptics.select()
        onboarding.answers.mode = mode
        onboarding.stage = .questions
    }

    private func choice(icon: String, title: String, detail: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 16) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(theme.gold)
                    .frame(width: 44, height: 44)
                    .background(theme.gold.opacity(0.14), in: Circle())
                VStack(alignment: .leading, spacing: 6) {
                    Text(title).font(SummaFont.serif(26, relativeTo: .title2)).foregroundStyle(theme.text)
                    Text(detail).font(.subheadline).foregroundStyle(theme.muted).multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(theme.muted).padding(.top, 14)
            }
            .card()
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }
}
