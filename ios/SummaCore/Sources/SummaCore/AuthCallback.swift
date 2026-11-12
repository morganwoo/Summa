import Foundation

/// Reads the link Supabase sends the app back to after an email is confirmed.
///
/// Only a one-time authorisation code is accepted. It is useless without the verifier this
/// device kept when the request was made (PKCE), so a link crafted by someone else, or caught
/// by another app that claims the same scheme, cannot sign anyone in. Tokens placed directly
/// in a link are refused, and text carried by the link is never shown to the user.
public enum AuthCallback: Equatable, Sendable {
    case code(String)
    case failed(Reason)

    public enum Reason: Equatable, Sendable { case expired, unusable }

    public static let redirectURL = "summa://auth/callback"

    /// Returns nil when the link is not an auth callback at all.
    public static func parse(_ url: URL) -> AuthCallback? {
        guard url.scheme?.lowercased() == "summa", url.host?.lowercased() == "auth",
              url.path == "/callback" || url.path == "/callback/" else { return nil }
        var values: [String: String] = [:]
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        for part in [components?.percentEncodedQuery, components?.percentEncodedFragment] {
            for pair in (part ?? "").split(separator: "&") {
                let pieces = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
                guard pieces.count == 2, let value = String(pieces[1]).removingPercentEncoding else { continue }
                let key = String(pieces[0])
                if values[key] == nil { values[key] = value }
            }
        }
        if values["error"] != nil || values["error_code"] != nil {
            let detail = ((values["error_code"] ?? "") + " " + (values["error_description"] ?? "")).lowercased()
            return .failed(detail.contains("expired") || detail.contains("invalid") ? .expired : .unusable)
        }
        if values["access_token"] != nil || values["refresh_token"] != nil { return .failed(.unusable) }
        guard let code = values["code"], isPlausibleCode(code) else { return .failed(.unusable) }
        return .code(code)
    }

    static func isPlausibleCode(_ code: String) -> Bool {
        let allowed = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.~")
        return (8...512).contains(code.count) && code.allSatisfy { allowed.contains($0) }
    }
}
