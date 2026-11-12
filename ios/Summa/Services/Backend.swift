import Foundation
import Combine
import CryptoKit
import SummaCore

/// The social backend (Supabase Auth + PostgREST), reached with URLSession only.
///
/// Habit tracking never depends on this: the app is local-first, and everything sent here is
/// derived from the local record. Authorisation is enforced by the server (row level security
/// and checked functions); the anon key in the app is public by design and grants nothing alone.
@MainActor
final class Backend: ObservableObject {
    static let shared = Backend()

    struct Config {
        let url: URL
        let anonKey: String

        static var current: Config? {
            let info = Bundle.main
            guard let raw = (info.object(forInfoDictionaryKey: "SupabaseURL") as? String)?.trimmed, !raw.isEmpty,
                  let url = URL(string: raw), url.scheme == "https" || url.host == "localhost" || url.host == "127.0.0.1",
                  let key = (info.object(forInfoDictionaryKey: "SupabaseAnonKey") as? String)?.trimmed, !key.isEmpty,
                  !isSecretKey(key) else { return nil }
            return Config(url: url, anonKey: key)
        }

        /// A service-role or secret key must never ship in the app. If one is configured by mistake,
        /// the app refuses to use it and Friends reports that it is not connected.
        static func isSecretKey(_ key: String) -> Bool {
            if key.hasPrefix("sb_secret_") { return true }
            let parts = key.split(separator: ".")
            guard parts.count == 3 else { return false }
            var payload = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
            while payload.count % 4 != 0 { payload += "=" }
            guard let data = Data(base64Encoded: payload),
                  let claims = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return false }
            return (claims["role"] as? String) == "service_role"
        }
    }

    struct Session: Codable, Equatable {
        var accessToken: String
        var refreshToken: String
        var expiresAt: Date
        var userID: UUID
        var email: String?
    }

    enum Failure: LocalizedError, Equatable {
        case notConfigured, signedOut, usernameTaken, proRequired, offline
        /// The caller already has the two friends Summa Free allows.
        case friendLimit
        /// The other person has reached their own limit.
        case friendLimitOther
        case server(Int)

        var errorDescription: String? {
            switch self {
            case .notConfigured: return "Friends is not connected in this build."
            case .signedOut: return "Please sign in again."
            case .usernameTaken: return "That username is taken. Choose another."
            case .proRequired: return "Summa Pro is needed for this."
            case .friendLimit: return "Summa Free holds two friends. Summa Pro makes it unlimited."
            case .friendLimitOther: return "They have reached their friend limit for now, so this could not be accepted."
            case .offline: return "You appear to be offline. Your tracking is saved and will sync later."
            case .server(let code): return "The server did not respond as expected (\(code))."
            }
        }
    }

    let config = Config.current
    @Published private(set) var session: Session?
    @Published private(set) var username: String?
    @Published private(set) var lastSync: Date?
    /// What happened to the last confirmation link that was opened, for the sign-in card to show.
    @Published var authNotice: String?
    /// What the sign-in service said about the last failed account request: its short code and message.
    /// These describe the failure, not the person, and are used to choose a clearer sentence.
    private(set) var lastAuthProblem: (code: String, message: String)?

    private static let keychainAccount = "backend-session"
    private static let verifierAccount = "backend-pkce-verifier"
    private var pendingSync: Task<Void, Never>?
    private let urlSession: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        return URLSession(configuration: configuration)
    }()

    private init() {
        // The refresh token lives in the Keychain, never in UserDefaults or logs.
        if let stored = Keychain.read(Self.keychainAccount), let saved = try? JSONDecoder().decode(Session.self, from: Data(stored.utf8)) {
            session = saved
        }
    }

    var isSignedIn: Bool { session != nil }

    // MARK: Auth (email and password, or an emailed one-time code)

    /// Creates an account. Returns true when signed in straight away, false when the project asks
    /// for the email to be confirmed first. The password is sent over TLS and never stored on the device.
    func signUp(email: String, password: String) async throws -> Bool {
        var fields: [String: Any] = ["email": email.trimmed.lowercased(), "password": password]
        fields.merge(newChallenge()) { _, new in new }
        let data = try await send("POST", "auth/v1/signup", query: Self.redirectQuery, body: json(fields), authorized: false)
        guard (try? store(tokenResponse: data)) != nil else { return false }
        Keychain.write("", for: Self.verifierAccount) // signed in at once: no link will follow
        return true
    }

    func signIn(email: String, password: String) async throws {
        let data = try await send("POST", "auth/v1/token", query: [URLQueryItem(name: "grant_type", value: "password")],
                                  body: json(["email": email.trimmed.lowercased(), "password": password]), authorized: false)
        try store(tokenResponse: data)
    }

    func requestCode(email: String) async throws {
        var fields: [String: Any] = ["email": email.trimmed.lowercased(), "create_user": true]
        fields.merge(newChallenge()) { _, new in new }
        _ = try await send("POST", "auth/v1/otp", query: Self.redirectQuery, body: json(fields), authorized: false)
    }

    func verify(email: String, code: String) async throws {
        let data = try await send("POST", "auth/v1/verify",
                                  body: json(["type": "email", "email": email.trimmed.lowercased(), "token": code.trimmed]), authorized: false)
        try store(tokenResponse: data)
    }

    // MARK: Email confirmation link (summa://auth/callback)

    private static let redirectQuery = [URLQueryItem(name: "redirect_to", value: AuthCallback.redirectURL)]

    /// Starts a PKCE exchange: keeps a fresh random verifier in the Keychain and returns its challenge
    /// for the server. The link in the email then carries a one-time code that only this device can redeem.
    private func newChallenge() -> [String: Any] {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { return [:] }
        let verifier = Self.base64URL(Data(bytes))
        guard Keychain.write(verifier, for: Self.verifierAccount) else { return [:] }
        return ["code_challenge": Self.base64URL(Data(SHA256.hash(data: Data(verifier.utf8)))), "code_challenge_method": "s256"]
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }

    /// Handles a link the app was opened with. Returns false when it is not an auth callback.
    /// Local tracking is never touched here; only the session changes.
    @discardableResult
    func handleCallback(_ url: URL) async -> Bool {
        guard let callback = AuthCallback.parse(url) else { return false }
        let confirmedElsewhere = "Your email is confirmed. Sign in with your email and password."
        switch callback {
        case .failed(.expired):
            authNotice = "That link has expired or was already used. Try signing in, or create the account again for a new link."
        case .failed(.unusable):
            authNotice = "That link could not be used. Try signing in with your email and password."
        case .code(let code):
            guard let verifier = Keychain.read(Self.verifierAccount), !verifier.isEmpty else {
                authNotice = confirmedElsewhere // opened on a device that did not start the sign-up
                return true
            }
            do {
                let data = try await send("POST", "auth/v1/token", query: [URLQueryItem(name: "grant_type", value: "pkce")],
                                          body: json(["auth_code": code, "code_verifier": verifier]), authorized: false)
                try store(tokenResponse: data)
                Keychain.write("", for: Self.verifierAccount)
                authNotice = nil
            } catch Failure.offline {
                authNotice = "You appear to be offline. Open the link again once you are connected."
            } catch {
                authNotice = confirmedElsewhere
            }
        }
        return true
    }

    /// A plain sentence for a failed account request, or nil when there is nothing more specific to say.
    func authProblemSentence(status: Int) -> String? {
        guard let problem = lastAuthProblem else { return nil }
        let text = (problem.code + " " + problem.message).lowercased()
        var sentence: String?
        if text.contains("sending") && text.contains("email") {
            sentence = "The confirmation email could not be sent, so the account was not created. Please try again later."
        } else if text.contains("not authorized") || text.contains("email_address_not_authorized") {
            sentence = "Confirmation emails cannot be sent to this address yet."
        } else if text.contains("rate limit") || text.contains("over_email_send_rate_limit") {
            sentence = "Too many emails were requested. Wait a while and try again."
        } else if text.contains("already registered") || text.contains("user_already_exists") {
            sentence = "That email already has an account. Sign in instead."
        } else if text.contains("weak_password") || text.contains("password should") {
            sentence = "That password is too weak. Use at least 8 characters."
        } else if text.contains("database error") {
            sentence = "The account could not be created just now. Please try again later."
        } else if text.contains("signups not allowed") || text.contains("signup_disabled") {
            sentence = "New accounts are switched off at the moment."
        }
        #if DEBUG
        let note = "\n\nDeveloper note: Supabase answered \(status) \(problem.code.isEmpty ? "" : "[\(problem.code)] ")\(problem.message). See Supabase > Logs > Auth for the full reason."
        return (sentence ?? "That did not work.") + note
        #else
        return sentence
        #endif
    }

    func signOut() async {
        _ = try? await send("POST", "auth/v1/logout")
        clearSession()
    }

    /// Deletes the account and everything stored for it on the server. Local tracking is untouched.
    func deleteAccount() async throws {
        try await call("delete_my_account")
        clearSession()
    }

    private struct TokenResponse: Decodable {
        struct User: Decodable { let id: UUID; let email: String? }
        let accessToken: String
        let refreshToken: String
        let expiresIn: Double
        let user: User
    }

    private func store(tokenResponse data: Data) throws {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let token = try decoder.decode(TokenResponse.self, from: data)
        let new = Session(accessToken: token.accessToken, refreshToken: token.refreshToken,
                          expiresAt: Date().addingTimeInterval(token.expiresIn), userID: token.user.id, email: token.user.email)
        session = new
        if let encoded = try? JSONEncoder().encode(new), let text = String(data: encoded, encoding: .utf8) {
            Keychain.write(text, for: Self.keychainAccount)
        }
    }

    private func clearSession() {
        session = nil
        username = nil
        Keychain.write("", for: Self.keychainAccount)
    }

    private func validAccessToken() async throws -> String {
        guard let current = session else { throw Failure.signedOut }
        if current.expiresAt > Date().addingTimeInterval(60) { return current.accessToken }
        do {
            let data = try await send("POST", "auth/v1/token", query: [URLQueryItem(name: "grant_type", value: "refresh_token")],
                                      body: json(["refresh_token": current.refreshToken]), authorized: false)
            try store(tokenResponse: data)
        } catch Failure.server(let code) where code == 400 || code == 401 {
            clearSession()
            throw Failure.signedOut
        }
        guard let refreshed = session else { throw Failure.signedOut }
        return refreshed.accessToken
    }

    // MARK: Requests

    private func json(_ object: [String: Any]) -> Data {
        (try? JSONSerialization.data(withJSONObject: object)) ?? Data("{}".utf8)
    }

    @discardableResult
    private func send(_ method: String, _ path: String, query: [URLQueryItem] = [], body: Data? = nil,
                      authorized: Bool = true, prefer: String? = nil) async throws -> Data {
        guard let config else { throw Failure.notConfigured }
        if path.hasPrefix("auth/v1") { lastAuthProblem = nil }
        var components = URLComponents(url: config.url.appendingPathComponent(path), resolvingAgainstBaseURL: false)
        if !query.isEmpty { components?.queryItems = query }
        guard let url = components?.url else { throw Failure.notConfigured }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(config.anonKey, forHTTPHeaderField: "apikey")
        var bearer = config.anonKey
        if authorized { bearer = try await validAccessToken() }
        request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
        if let prefer { request.setValue(prefer, forHTTPHeaderField: "Prefer") }
        do {
            let (data, response) = try await urlSession.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if (200..<300).contains(status) { return data }
            // PostgREST reports the SQLSTATE in "code". Bodies are never logged.
            let body = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            let code = body?["code"] as? String
            if path.hasPrefix("auth/v1") {
                lastAuthProblem = (code: (body?["error_code"] as? String) ?? "",
                                   message: String(((body?["msg"] as? String) ?? (body?["error_description"] as? String) ?? (body?["message"] as? String) ?? "").prefix(200)))
            }
            if code == "23505" { throw Failure.usernameTaken }
            if code == "42501" { throw Failure.proRequired }
            if code == "SF001" { throw Failure.friendLimit }
            if code == "SF002" { throw Failure.friendLimitOther }
            if status == 401 && authorized {
                clearSession()
                throw Failure.signedOut
            }
            throw Failure.server(status)
        } catch let error as URLError {
            if [.notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotFindHost, .cannotConnectToHost, .dataNotAllowed].contains(error.code) {
                throw Failure.offline
            }
            throw Failure.server(error.errorCode)
        }
    }

    /// Calls a database function and decodes its rows.
    func fetch<T: Decodable>(_ function: String, _ arguments: [String: Any] = [:], as type: T.Type = T.self) async throws -> T {
        let data = try await send("POST", "rest/v1/rpc/\(function)", body: json(arguments))
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(T.self, from: data)
    }

    /// Calls a database function whose result is not needed.
    func call(_ function: String, _ arguments: [String: Any] = [:]) async throws {
        try await send("POST", "rest/v1/rpc/\(function)", body: json(arguments))
    }

    private func upsert(_ table: String, rows: [[String: Any]], onConflict: String, ignoreDuplicates: Bool = false) async throws {
        guard !rows.isEmpty else { return }
        for start in stride(from: 0, to: rows.count, by: 400) {
            let chunk = Array(rows[start..<min(start + 400, rows.count)])
            let body = (try? JSONSerialization.data(withJSONObject: chunk)) ?? Data("[]".utf8)
            try await send("POST", "rest/v1/\(table)", query: [URLQueryItem(name: "on_conflict", value: onConflict)], body: body,
                           prefer: "resolution=\(ignoreDuplicates ? "ignore" : "merge")-duplicates,return=minimal")
        }
    }

    // MARK: Profile and sync

    /// Sets the username (unique on the server) and the dates friends need to see day and stage.
    func saveProfile(username: String, plan: Plan) async throws {
        struct Profile: Decodable { let username: String }
        let profile: Profile = try await fetch("set_profile", ["p_username": UsernameRule.normalized(username),
                                                               "p_plan_start": plan.start.string, "p_chapter": plan.chapter])
        self.username = profile.username
    }

    func setPrivacy(shareHeatmap: Bool, shareActivity: Bool, nudgesMuted: Bool) async throws {
        try await call("set_privacy", ["p_share_heatmap": shareHeatmap, "p_share_activity": shareActivity, "p_nudges_muted": nudgesMuted])
    }

    /// Uploads the shareable picture of the plan. Idempotent: rows are keyed by habit and day, so repeating
    /// it, or running it after time offline, converges on the local record without duplicates.
    func sync(plan: Plan, today: DayKey) async throws {
        guard let user = session?.userID else { throw Failure.signedOut }
        // Tell the server what this Apple account is entitled to. The server verifies it; it is not taken on trust.
        var entitlement: [String: Any] = [:]
        if let jws = Store.shared.latestTransactionJWS { entitlement["transaction"] = jws }
        _ = try? await send("POST", "functions/v1/sync-entitlement", body: json(entitlement))

        try await saveProfile(username: username ?? plan.username, plan: plan)
        let id = user.uuidString.lowercased()
        let habits = plan.habits
        try await upsert("shared_habits", rows: habits.map {
            ["user_id": id, "habit_id": $0.id.uuidString.lowercased(), "title": String($0.title.prefix(60)),
             "color_hex": HabitPalette.isValidHex($0.colorHex) ? $0.colorHex : HabitPalette.gold, "hidden": $0.sharedHidden]
        }, onConflict: "user_id,habit_id")
        try await upsert("shared_days", rows: SocialSnapshot.rows(for: plan.records, today: today).map {
            ["user_id": id, "habit_id": $0.habitId.uuidString.lowercased(), "day": $0.day, "done": $0.done]
        }, onConflict: "user_id,habit_id,day")
        let events = ActivityBuilder.events(planStart: plan.start, timelines: plan.timelines, chapter: plan.chapter, today: today)
        try await upsert("activity", rows: events.map { ["user_id": id, "kind": $0.kind, "detail": $0.detail, "chapter": $0.chapter] },
                         onConflict: "user_id,kind,detail,chapter", ignoreDuplicates: true)
        lastSync = Date()
    }

    /// Syncs shortly after a change. Failures are silent: the next change or launch tries again.
    func scheduleSync(plan: Plan) {
        guard config != nil, session != nil, !DevSandbox.isActive else { return }
        pendingSync?.cancel()
        pendingSync = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            try? await self?.sync(plan: plan, today: DayKey(date: Date()))
        }
    }
}

// Rows returned by the server functions.
struct FriendRow: Decodable, Identifiable, Equatable {
    let userId: UUID
    let username: String
    let relation: String
    var id: UUID { userId }
}

struct UserHit: Decodable, Identifiable, Equatable {
    let userId: UUID
    let username: String
    var id: UUID { userId }
}

struct HeatmapRow: Decodable, Equatable {
    let habitId: UUID
    let title: String
    let colorHex: String
    let day: String
    let done: Bool
}

struct NudgeRow: Decodable, Equatable {
    let fromUsername: String
    let messageKey: String
    let createdAt: String
}

struct ActivityRow: Decodable, Equatable {
    let username: String
    let kind: String
    let detail: Int
    let createdAt: String
}
