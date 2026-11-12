import Foundation
import SwiftUI
import UIKit
import SummaCore

enum OnboardingStage: String, Codable {
    case welcome, choosePath, questions, generating, review
}

/// Onboarding state that survives going back, switching modes, and relaunching.
/// Saved as a small protected JSON file; removed once the plan starts.
@MainActor
final class OnboardingStore: ObservableObject {
    private struct Saved: Codable {
        var stage: OnboardingStage
        var answers: OnboardingAnswers
        var draft: PlanDraft?
        var remindersOn: [UUID]
    }

    @Published var stage: OnboardingStage = .welcome { didSet { persist() } }
    @Published var answers = OnboardingAnswers() { didSet { persist() } }
    @Published var draft: PlanDraft? { didSet { persist() } }
    @Published var remindersOn: Set<UUID> = [] { didSet { persist() } }

    private let fileURL: URL?
    private var isLoading = false

    private static var savedFileURL: URL? {
        (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))?
            .appendingPathComponent("onboarding.json")
    }

    nonisolated static func eraseSavedFile() {
        if let directory = try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true) {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent("onboarding.json"))
        }
    }

    init(persistent: Bool = true) {
        fileURL = persistent ? Self.savedFileURL : nil
        if AppEnvironment.arguments.contains("-resetState") { Self.eraseSavedFile() }
        load()
    }

    private func load() {
        guard let fileURL, let data = try? Data(contentsOf: fileURL),
              let saved = try? JSONDecoder().decode(Saved.self, from: data) else { return }
        isLoading = true
        answers = saved.answers
        draft = saved.draft
        remindersOn = Set(saved.remindersOn)
        // Never resume into a spinner: reopen generation from the last question instead.
        stage = saved.stage == .generating ? (saved.draft == nil ? .questions : .review) : saved.stage
        isLoading = false
    }

    private func persist() {
        guard !isLoading, let fileURL else { return }
        let saved = Saved(stage: stage, answers: answers, draft: draft, remindersOn: Array(remindersOn))
        guard let data = try? JSONEncoder().encode(saved) else { return }
        try? data.write(to: fileURL, options: [.atomic, .completeFileProtection])
    }

    /// Clears everything once the plan has started, or when the user starts over.
    func reset() {
        isLoading = true
        answers = OnboardingAnswers()
        draft = nil
        remindersOn = []
        stage = .welcome
        isLoading = false
        if let fileURL { try? FileManager.default.removeItem(at: fileURL) }
    }

    // MARK: Question navigation shared by the guided and talk paths

    var currentQuestion: Question { OnboardingFlow.question(answers.currentStep, answers: answers) }
    var canContinue: Bool { OnboardingFlow.canContinue(answers.currentStep, answers: answers) }
    var progress: Double { OnboardingFlow.progress(at: answers.currentStep, answers: answers) }

    func advance() {
        if let next = OnboardingFlow.next(after: answers.currentStep, answers: answers) {
            answers.currentStep = next
        } else {
            draft = nil
            stage = .generating
        }
    }

    func goBack() {
        if let previous = OnboardingFlow.previous(before: answers.currentStep, answers: answers) {
            answers.currentStep = previous
        } else {
            stage = .choosePath
        }
    }

    func binding(for id: QuestionID) -> Binding<[String]> {
        Binding(get: { self.answers.selections(id) }, set: { self.answers.set(id, $0) })
    }

    func textBinding(for id: QuestionID) -> Binding<String> {
        // Keep the raw text while typing; trimming happens when the answer is read.
        Binding(get: { self.answers.values[id.rawValue]?.first ?? "" },
                set: { self.answers.values[id.rawValue] = $0.isEmpty ? nil : [$0] })
    }
}

/// Publishes the current civil day and refreshes it at midnight and on return to the app.
@MainActor
final class TodayClock: ObservableObject {
    @Published private(set) var today = DayKey(date: Date())
    private var observers: [NSObjectProtocol] = []

    init() {
        let center = NotificationCenter.default
        for name in [UIApplication.significantTimeChangeNotification, UIApplication.didBecomeActiveNotification, .NSSystemTimeZoneDidChange] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.refresh() }
            })
        }
    }

    func refresh() {
        let now = DayKey(date: Date())
        if now != today { today = now }
    }
}
