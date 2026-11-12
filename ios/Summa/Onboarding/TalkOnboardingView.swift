import SwiftUI
import SummaCore

/// "Talk with Summa": the same questions as a conversation. Speech becomes an
/// editable transcript; typing is always available.
struct TalkOnboardingView: View {
    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var onboarding: OnboardingStore
    @StateObject private var dictation = SpeechDictation()
    @StateObject private var speaker = PromptSpeaker()

    @State private var draft = ""
    @State private var textBeforeDictation = ""
    @FocusState private var inputFocused: Bool

    private var steps: [QuestionID] { OnboardingFlow.steps(for: onboarding.answers) }

    private var answeredSteps: [QuestionID] {
        guard let index = steps.firstIndex(of: onboarding.answers.currentStep) else { return [] }
        return Array(steps[..<index])
    }

    var body: some View {
        let question = onboarding.currentQuestion
        VStack(spacing: 0) {
            OnboardingTopBar(switchTitle: "Type instead", switchIcon: "list.bullet") {
                dictation.stop()
                speaker.stop()
                onboarding.answers.mode = "guided"
            }
            ScrollViewReader { reader in
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(answeredSteps, id: \.self) { id in
                            let past = OnboardingFlow.question(id, answers: onboarding.answers)
                            SummaBubble(text: past.prompt)
                            if id != .arc {
                                UserBubble(text: summary(for: id)) { edit(id) }
                            }
                        }
                        SummaBubble(text: question.prompt, detail: question.detail)
                            .id("current")
                        inlineCard(for: question)
                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: onboarding.answers.currentStep) { _, _ in
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.3)) { reader.scrollTo("bottom", anchor: .bottom) }
                }
                .onAppear { reader.scrollTo("bottom", anchor: .bottom) }
            }
            if dictation.access == .denied || dictation.access == .unavailable { microphoneNotice }
            inputBar(for: question)
        }
        .task {
            // Microphone and speech access are requested only here, after choosing voice.
            if dictation.access == .undetermined, !AppEnvironment.isUITesting { await dictation.requestAccess() }
            speaker.speak(question.prompt)
        }
        .onChange(of: onboarding.answers.currentStep) { _, _ in
            dictation.stop()
            draft = prefill(for: onboarding.currentQuestion)
            speaker.speak(onboarding.currentQuestion.prompt)
        }
        .onChange(of: dictation.transcript) { _, transcript in
            guard dictation.isRecording || !transcript.isEmpty else { return }
            draft = [textBeforeDictation, transcript].filter { !$0.isEmpty }.joined(separator: " ")
        }
        .onAppear { draft = prefill(for: question) }
        .onDisappear {
            dictation.stop()
            speaker.stop()
        }
    }

    // MARK: Pieces

    private var microphoneNotice: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "mic.slash").foregroundStyle(theme.muted)
            VStack(alignment: .leading, spacing: 4) {
                Text(dictation.access == .denied ? "Microphone or speech access is off." : "Dictation is not available right now.")
                    .font(.footnote.weight(.semibold))
                Text("You can type every answer here.")
                    .font(.footnote).foregroundStyle(theme.muted)
                if dictation.access == .denied {
                    Button("Open Settings") { Reminders.openSystemSettings() }
                        .font(.footnote.weight(.semibold)).foregroundStyle(theme.gold).frame(minHeight: 44)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .accessibilityElement(children: .contain)
    }

    /// Choice, schedule, chart, and body questions show their control in the thread.
    @ViewBuilder
    private func inlineCard(for question: Question) -> some View {
        switch question.kind {
        case .shortText, .longText, .username:
            EmptyView()
        case .single:
            QuestionInput(question: question, showsCustomField: false, onSinglePick: { advance() })
        default:
            QuestionInput(question: question, showsCustomField: false)
        }
    }

    private func isTextual(_ question: Question) -> Bool {
        switch question.kind {
        case .shortText, .longText, .username: return true
        case .multi(_, let allowsCustom): return allowsCustom
        default: return false
        }
    }

    @ViewBuilder
    private func inputBar(for question: Question) -> some View {
        VStack(spacing: 8) {
            if isTextual(question) {
                HStack(alignment: .bottom, spacing: 10) {
                    TextField(dictation.isRecording ? "Listening…" : "Speak or type your answer", text: $draft, axis: .vertical)
                        .lineLimit(1...6)
                        .focused($inputFocused)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .frame(minHeight: 48)
                        .background(theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(dictation.isRecording ? theme.gold : theme.divider))
                        .accessibilityIdentifier("talk.textField")
                    if dictation.access == .granted {
                        Button {
                            Haptics.select()
                            speaker.stop()
                            if !dictation.isRecording { textBeforeDictation = draft.trimmed }
                            dictation.toggle()
                        } label: {
                            Image(systemName: dictation.isRecording ? "stop.fill" : "mic.fill")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(dictation.isRecording ? theme.onGold : theme.gold)
                                .frame(width: 48, height: 48)
                                .background(dictation.isRecording ? theme.gold : theme.gold.opacity(0.14), in: Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(dictation.isRecording ? "Stop dictation" : "Start dictation")
                    }
                }
                if question.id == .username {
                    UsernameStatus(text: draft).frame(maxWidth: .infinity, alignment: .leading)
                }
                if dictation.isRecording {
                    Text("Your words appear above. Edit them before you send.")
                        .font(.caption).foregroundStyle(theme.muted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            HStack(spacing: 10) {
                Button {
                    speaker.isEnabled.toggle()
                } label: {
                    Image(systemName: speaker.isEnabled ? "speaker.wave.2" : "speaker.slash")
                        .foregroundStyle(theme.muted)
                        .frame(width: 48, height: 52)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(speaker.isEnabled ? "Mute Summa’s voice" : "Unmute Summa’s voice")

                Button(sendTitle(question)) { send(question) }
                    .buttonStyle(.summaPrimary)
                    .disabled(!canSend(question))
                    .accessibilityIdentifier("onboarding.continue")
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    // MARK: Behaviour

    private func prefill(for question: Question) -> String {
        switch question.kind {
        case .shortText, .longText, .username: return onboarding.answers.text(question.id)
        default: return ""
        }
    }

    private func canSend(_ question: Question) -> Bool {
        if question.id == .username { return UsernameRule.problem(with: draft) == nil }
        switch question.kind {
        case .shortText, .longText, .username: return question.isOptional || !draft.trimmed.isEmpty
        case .multi: return !draft.trimmed.isEmpty || onboarding.canContinue
        default: return onboarding.canContinue
        }
    }

    private func sendTitle(_ question: Question) -> String {
        if OnboardingFlow.next(after: question.id, answers: onboarding.answers) == nil { return "Build my plan" }
        switch question.kind {
        case .shortText, .longText, .username: return draft.trimmed.isEmpty && question.isOptional ? "Skip" : "Send"
        default: return "Continue"
        }
    }

    private func send(_ question: Question) {
        dictation.stop()
        switch question.kind {
        case .shortText, .longText, .username:
            onboarding.answers.set(question.id, text: draft)
        case .multi:
            if !draft.trimmed.isEmpty {
                onboarding.answers.set(question.id, onboarding.answers.selections(question.id) + [draft])
            }
        default:
            break
        }
        advance()
    }

    private func advance() {
        Haptics.select()
        draft = ""
        textBeforeDictation = ""
        onboarding.advance()
    }

    private func edit(_ id: QuestionID) {
        dictation.stop()
        onboarding.answers.currentStep = id
    }

    private func summary(for id: QuestionID) -> String {
        let answers = onboarding.answers
        switch id {
        case .days: return OnboardingFlow.describe(weekdays: answers.weekdays)
        default:
            let values = answers.selections(id)
            return values.isEmpty ? "Skipped" : values.joined(separator: ", ")
        }
    }
}

private struct SummaBubble: View {
    @Environment(\.theme) private var theme
    let text: String
    var detail: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Eyebrow("Summa", color: theme.gold)
            Text(text)
                .font(SummaFont.serif(24, relativeTo: .title3))
                .fixedSize(horizontal: false, vertical: true)
            if let detail {
                Text(detail).font(.footnote).foregroundStyle(theme.muted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

private struct UserBubble: View {
    @Environment(\.theme) private var theme
    let text: String
    let onEdit: () -> Void

    var body: some View {
        HStack {
            Spacer(minLength: 40)
            Button(action: onEdit) {
                VStack(alignment: .trailing, spacing: 4) {
                    Text(text).font(.body).foregroundStyle(theme.text).multilineTextAlignment(.leading)
                    Text("Edit").font(.caption.weight(.semibold)).foregroundStyle(theme.gold)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(theme.divider))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Your answer: \(text)")
            .accessibilityHint("Edits this answer")
        }
    }
}
