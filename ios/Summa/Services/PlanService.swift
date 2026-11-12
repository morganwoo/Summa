import Foundation
import SummaCore

enum GenerationStage: Int, CaseIterable {
    case reviewing, drafting, checking, preparing

    var label: String {
        switch self {
        case .reviewing: return "Reviewing your goals"
        case .drafting: return "Drafting your habits"
        case .checking: return "Checking the plan against your week"
        case .preparing: return "Preparing your 90 days"
        }
    }
}

enum PlanServiceError: LocalizedError {
    case offline
    case rateLimited
    case server(Int)
    case invalidPlan(String)
    case simulated

    var errorDescription: String? {
        switch self {
        case .offline: return "You appear to be offline."
        case .rateLimited: return "Too many plans were requested. Try again in a minute."
        case .server(let code): return "The plan service did not respond as expected (\(code))."
        case .invalidPlan: return "The drafted plan did not pass our checks."
        case .simulated: return "The plan service could not be reached."
        }
    }
}

/// The single place the app talks to the plan API.
///
/// With no `SummaAPIBaseURL` configured (the development default) plans are
/// built on device, so the whole journey works without paid credentials.
struct PlanService {
    var baseURL: URL?
    var session: URLSession = .shared
    var minimumStageTime: Duration = .milliseconds(650)

    static var configured: PlanService {
        let raw = (Bundle.main.object(forInfoDictionaryKey: "SummaAPIBaseURL") as? String)?.trimmed ?? ""
        var service = PlanService(baseURL: raw.isEmpty ? nil : URL(string: raw))
        if AppEnvironment.isUITesting { service.minimumStageTime = .milliseconds(50) }
        return service
    }

    var usesRemote: Bool { baseURL != nil }

    private struct RequestBody: Encodable {
        let schemaVersion: Int
        let answers: [String: [String]]
        let weekdays: [Int]
        let minutesPerDay: Int
    }

    func generate(from answers: OnboardingAnswers, stage: @MainActor @escaping (GenerationStage) -> Void) async throws -> PlanDraft {
        await stage(.reviewing)
        // Send only what the plan needs. The referral code and UI state stay on device.
        let body = RequestBody(schemaVersion: PlanSchema.version, answers: answers.values,
                               weekdays: answers.weekdays, minutesPerDay: answers.minutesPerDay)
        let payload = try JSONEncoder().encode(body)
        try await Task.sleep(for: minimumStageTime)

        await stage(.drafting)
        if AppEnvironment.consumeSimulatedFailure() {
            try await Task.sleep(for: minimumStageTime)
            throw PlanServiceError.simulated
        }
        let draft: PlanDraft
        if let baseURL {
            draft = try await requestPlan(payload: payload, baseURL: baseURL)
        } else {
            draft = StarterPlanBuilder.build(from: answers)
            try await Task.sleep(for: minimumStageTime)
        }

        await stage(.checking)
        let validated: PlanDraft
        do {
            validated = try assignColors(draft).validated()
        } catch {
            throw PlanServiceError.invalidPlan(String(describing: error))
        }
        try await Task.sleep(for: minimumStageTime)

        await stage(.preparing)
        try await Task.sleep(for: minimumStageTime)
        return validated
    }

    private func requestPlan(payload: Data, baseURL: URL) async throws -> PlanDraft {
        var request = URLRequest(url: baseURL.appendingPathComponent("v1/plans"))
        request.httpMethod = "POST"
        request.timeoutInterval = 45
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(InstallIdentity.token, forHTTPHeaderField: "X-Summa-Install")
        request.httpBody = payload
        do {
            let (data, response) = try await session.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if status == 429 { throw PlanServiceError.rateLimited }
            guard (200..<300).contains(status) else { throw PlanServiceError.server(status) }
            do {
                return try JSONDecoder().decode(PlanDraft.self, from: data)
            } catch {
                throw PlanServiceError.invalidPlan("undecodable")
            }
        } catch let error as URLError where [.notConnectedToInternet, .networkConnectionLost, .dataNotAllowed].contains(error.code) {
            throw PlanServiceError.offline
        }
    }

    /// The service does not choose colors; give each habit a distinct accent.
    private func assignColors(_ draft: PlanDraft) -> PlanDraft {
        var draft = draft
        var used = Set<String>()
        for index in draft.habits.indices {
            var hex = draft.habits[index].colorHex
            if !HabitPalette.isValidHex(hex) || used.contains(hex.uppercased()) {
                hex = HabitPalette.all.map(\.hex).first { !used.contains($0.uppercased()) } ?? HabitPalette.color(at: index)
            }
            used.insert(hex.uppercased())
            draft.habits[index].colorHex = hex
        }
        return draft
    }
}

enum AppEnvironment {
    static let arguments = ProcessInfo.processInfo.arguments
    /// UI tests run with an in-memory store unless they also pass `-persist`.
    static let isUITesting = arguments.contains("-uiTesting")
    static let usesDisk = !isUITesting || arguments.contains("-persist")
    private static var failuresLeft = arguments.contains("-simulateGenerationFailure") ? 1 : 0

    /// True once when launched with `-simulateGenerationFailure`, to exercise the retry path.
    static func consumeSimulatedFailure() -> Bool {
        guard failuresLeft > 0 else { return false }
        failuresLeft -= 1
        return true
    }
}

/// An anonymous, random install token used only so the API can rate-limit fairly.
/// Stored in the Keychain; it is not tied to a person or an account.
enum InstallIdentity {
    static var token: String {
        if let existing = Keychain.read("install-token") { return existing }
        let fresh = UUID().uuidString
        Keychain.write(fresh, for: "install-token")
        return fresh
    }
}

enum Keychain {
    private static let service = "app.summa.Summa"

    static func read(_ account: String) -> String? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                    kSecAttrAccount as String: account, kSecReturnData as String: true,
                                    kSecMatchLimit as String: kSecMatchLimitOne]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    static func write(_ value: String, for account: String) -> Bool {
        let base: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                   kSecAttrAccount as String: account]
        SecItemDelete(base as CFDictionary)
        var attributes = base
        attributes[kSecValueData as String] = Data(value.utf8)
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(attributes as CFDictionary, nil) == errSecSuccess
    }
}
