import SwiftUI
import SummaCore

/// "Build my plan": one question per screen, mostly taps.
struct GuidedOnboardingView: View {
    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var onboarding: OnboardingStore
    @State private var showReferral = false

    var body: some View {
        let question = onboarding.currentQuestion
        VStack(spacing: 0) {
            OnboardingTopBar(switchTitle: "Talk instead", switchIcon: "mic") {
                onboarding.answers.mode = "talk"
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(question.prompt)
                        .font(SummaFont.serif(32, relativeTo: .title))
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    if let detail = question.detail {
                        Text(detail).font(.subheadline).foregroundStyle(theme.muted)
                    }
                    QuestionInput(question: question)
                        .padding(.top, 6)
                    if question.id == .name { referral }
                }
                .padding(.horizontal, 24)
                .padding(.top, 20)
                .padding(.bottom, 24)
                .frame(maxWidth: .infinity, alignment: .leading)
                .id(question.id)
                .transition(reduceMotion ? .opacity : .asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))
            }
            .scrollDismissesKeyboard(.interactively)

            VStack(spacing: 10) {
                Button(continueTitle(question)) {
                    Haptics.select()
                    onboarding.advance()
                }
                .buttonStyle(.summaPrimary)
                .disabled(!onboarding.canContinue)
                .accessibilityIdentifier("onboarding.continue")
                if question.isOptional, question.id != .arc, onboarding.answers.isAnswered(question.id) == false {
                    Text("Optional. Continue to skip.").font(.footnote).foregroundStyle(theme.muted)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: question.id)
    }

    private func continueTitle(_ question: Question) -> String {
        OnboardingFlow.next(after: question.id, answers: onboarding.answers) == nil ? "Build my plan" : "Continue"
    }

    @ViewBuilder
    private var referral: some View {
        if showReferral || !onboarding.answers.referralCode.isEmpty {
            TextField("Referral code", text: $onboarding.answers.referralCode)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .padding(.horizontal, 16)
                .frame(minHeight: 48)
                .background(theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(theme.divider))
        } else {
            Button("I have a referral code") { showReferral = true }
                .font(.footnote)
                .foregroundStyle(theme.muted)
                .underline()
                .frame(minHeight: 44)
        }
    }
}

/// Back, progress, and the control that switches between the two paths.
struct OnboardingTopBar: View {
    @Environment(\.theme) private var theme
    @EnvironmentObject private var onboarding: OnboardingStore
    let switchTitle: String
    let switchIcon: String
    let onSwitch: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Button {
                    onboarding.goBack()
                } label: {
                    Image(systemName: "chevron.left").font(.body.weight(.semibold)).frame(width: 44, height: 44, alignment: .leading)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back")
                .accessibilityIdentifier("onboarding.back")
                Spacer()
                Wordmark()
                Spacer()
                Button(action: onSwitch) {
                    Label(switchTitle, systemImage: switchIcon)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(theme.gold)
                        .frame(minHeight: 44)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("onboarding.switchMode")
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Rectangle().fill(theme.divider)
                    Rectangle().fill(theme.gold).frame(width: proxy.size.width * onboarding.progress)
                }
            }
            .frame(height: 2)
            .accessibilityElement()
            .accessibilityLabel("Progress")
            .accessibilityValue("\(Int(onboarding.progress * 100)) percent")
        }
        .padding(.horizontal, 20)
        .padding(.top, 4)
    }
}
