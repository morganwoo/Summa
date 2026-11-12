import Foundation
import Combine
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
                  let key = (info.object(forInfoDictionaryKey: "SupabaseAnonKey") as? String)?.trimmed, !key.isEmpty else { return nil }
            return Config(url: url, anonKey: key)
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
        case server(Int)

        var errorDescription: String? {
            switch self {
            case .notConfigured: return "Friends is not connected in this build."
            case .signedOut: return "Please sign in again."
            case .usernameTaken: return "That username is taken. Choose another."
            case .proRequired: return "Summa Pro is needed for this."
            case .offline: return "You appear to be offline. Your tracking is saved and will sync later."
            case .server(let code): return "The server did not respond as expected (\(code))."
            }
        }
    }

    let config = Config.current
    @Published private(set) var session: Session?
    @Published private(set) var username: String?
    @Published private(set) var lastSync: Date?

    private static let keychainAccount = "backend-session"
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

    // MARK: Auth (email one-time code)

    func requestCode(email: String) async throws {
        _ = try await send("POST", "auth/v1/otp", body: json(["email": email.trimmed.lowercased(), "create_user": true]), authorized: false)
    }

    func verify(email: String, code: String) async throws {
        let data = try await send("POST", "auth/v1/verify",
                                  body: json(["type": "email", "email": email.trimmed.lowercased(), "token": code.trimmed]), authorized: false)
        try store(tokenResponse: data)
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
            let code = ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any])?["code"] as? String
            if code == "23505" { throw Failure.usernameTaken }
            if code == "42501" { throw Failure.proRequired }
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
        guard config != nil, session != nil, Store.shared.isPro else { return }
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
