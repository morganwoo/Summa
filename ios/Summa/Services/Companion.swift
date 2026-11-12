import Foundation
import SummaCore

/// The reflection companion: a short conversation with Summa about the day.
///
/// It talks to the same Summa API as plan drafting, so the AI key stays on the server.
/// The conversation lives in memory only. Nothing is stored unless the person approves a
/// proposed reflection, and then only that reviewed text is saved, on this device.
@MainActor
enum Companion {
    struct Turn: Codable, Equatable, Identifiable {
        enum Role: String, Codable { case user, assistant }
        var id = UUID()
        let role: Role
        let text: String
        private enum CodingKeys: String, CodingKey { case role, text = "content" }
    }

    enum Failure: LocalizedError, Equatable {
        case proRequired, notConnected, dailyLimit, rateLimited, offline, unavailable
        /// Nothing answered at the server's address.
        case unreachable
        /// The server answered with an unexpected status.
        case server(Int)
        var errorDescription: String? {
            switch self {
            case .proRequired: return "Talking with Summa is part of Summa Pro."
            case .notConnected: return "The companion is not connected in this build. You can still write a reflection."
            case .dailyLimit: return "You have reached today's conversation limit. It resets tomorrow. You can still write a reflection."
            case .rateLimited: return "Summa needs a short pause. Try again in a few minutes."
            case .offline: return "You appear to be offline. You can still write a reflection."
            case .unavailable: return "Summa could not answer just now. Try again."
            case .unreachable: return "Summa could not be reached just now. Try again." + Self.hint("nothing is listening at the server address. In Terminal, go to the server folder and run npm start.")
            case .server(let status):
                let why: String
                switch status {
                case 404: why = "the running server is an older version without this feature. Stop it with Ctrl+C and run npm start again."
                case 400: why = "the server rejected the request, so it is probably an older version. Stop it with Ctrl+C and run npm start again."
                case 503: why = "the server has no APPLE_ENVIRONMENT setting loaded. Check server/.env, then restart npm start."
                case 502: why = "the AI provider failed or returned something unusable. The server's Terminal window shows the provider's status."
                default: why = "the server answered with status \(status). Check its Terminal window."
                }
                return "Summa could not answer just now. Try again." + Self.hint(why)
            }
        }

        /// Extra detail for whoever is building the app. Never shown in a Release build.
        private static func hint(_ text: String) -> String {
            #if DEBUG
            return "\n\nDeveloper note: " + text
            #else
            return ""
            #endif
        }
    }

    /// What the conversation is for. It changes how Summa listens and what it offers to keep.
    enum Purpose: String, Encodable { case reflection, victory }

    private struct Body: Encodable {
        let purpose: Purpose
        let dayNumber: Int
        let stage: String
        let name: String
        let messages: [Turn]
    }

    static var isConnected: Bool { PlanService.configured.baseURL != nil }

    // The count is a courtesy shown to the person; the server keeps the limit that matters.
    private static func usageKey(_ day: DayKey) -> String { "summa.companion.used.\(day.string)" }
    static func usedToday(_ day: DayKey) -> Int { UserDefaults.standard.integer(forKey: usageKey(day)) }

    static func send(_ turns: [Turn], purpose: Purpose = .reflection, plan: Plan, today: DayKey) async throws -> CompanionReply {
        guard Entitlements.isPro else { throw Failure.proRequired }
        guard let base = PlanService.configured.baseURL else { throw Failure.notConnected }
        guard CompanionLimit.canSend(usedToday: usedToday(today)) else { throw Failure.dailyLimit }

        var request = URLRequest(url: base.appendingPathComponent("v1/reflections/chat"))
        request.httpMethod = "POST"
        request.timeoutInterval = 45
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(InstallIdentity.token, forHTTPHeaderField: "X-Summa-Install")
        // The server checks this signed App Store transaction itself; it does not take the app's word for Pro.
        if let jws = Store.shared.latestTransactionJWS { request.setValue(jws, forHTTPHeaderField: "X-Summa-Transaction") }
        #if DEBUG
        // Honoured only by a server running in its local Xcode test mode.
        if Store.shared.isDebugPro { request.setValue("1", forHTTPHeaderField: "X-Summa-Debug-Pro") }
        #endif
        let recent = turns.suffix(CompanionLimit.turnsSent).map {
            Turn(role: $0.role, text: String($0.text.prefix(CompanionLimit.maxMessageLength)))
        }
        request.httpBody = try JSONEncoder().encode(Body(purpose: purpose, dayNumber: plan.dayNumber(today: today), stage: plan.stage(today: today).name,
                                                         name: String(plan.userName.prefix(40)), messages: Array(recent)))
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            switch (response as? HTTPURLResponse)?.statusCode ?? 0 {
            case 200..<300:
                guard let reply = try? JSONDecoder().decode(CompanionReply.self, from: data) else { throw Failure.unavailable }
                if !DevSandbox.isActive { UserDefaults.standard.set(usedToday(today) + 1, forKey: usageKey(today)) }
                return reply
            case 402, 403: throw Failure.proRequired
            case 429: throw Failure.rateLimited
            case let status: throw Failure.server(status)
            }
        } catch let error as URLError where [.notConnectedToInternet, .networkConnectionLost, .dataNotAllowed].contains(error.code) {
            throw Failure.offline
        } catch let error as Failure {
            throw error
        } catch let error as URLError where [.cannotConnectToHost, .cannotFindHost, .timedOut, .secureConnectionFailed].contains(error.code) {
            throw Failure.unreachable
        } catch {
            throw Failure.unavailable
        }
    }
}
