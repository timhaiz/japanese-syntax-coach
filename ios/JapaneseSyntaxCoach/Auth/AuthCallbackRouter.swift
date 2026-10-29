import Foundation

enum AuthCallback: Equatable {
    case signup(code: String)
    case recovery(code: String)
    case apple(code: String)
    case session(accessToken: String, refreshToken: String?)
    case ignored
    case malformed
}

enum AuthCallbackRouter {
    static let trustedScheme = "nihongo"
    static let trustedHost = "auth-callback"
    static let trustedWebHost = "japanese-syntax-coach.vercel.app"

    private static let allowedParameterNames: Set<String> = [
        "code", "type", "access_token", "refresh_token", "expires_in", "token_type",
        "error", "error_code", "error_description", "state", "flow_type", "hash", "token_hash"
    ]

    static func route(_ url: URL) -> AuthCallback {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false), isTrusted(components) else {
            return .ignored
        }

        let items = (components.queryItems ?? []) + fragmentQueryItems(components.fragment)
        guard Set(items.map(\.name)).count == items.count else { return .malformed }
        let query = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
        guard query.keys.allSatisfy({ allowedParameterNames.contains($0) }) else { return .malformed }
        if query["error"] != nil || query["error_description"] != nil || query["error_code"] != nil {
            return .malformed
        }

        if let code = query["code"] {
            guard !code.isEmpty, query["access_token"] == nil, query["refresh_token"] == nil else {
                return .malformed
            }
            switch query["type"]?.lowercased() {
            case "signup": return .signup(code: code)
            case "recovery": return .recovery(code: code)
            case "apple": return .apple(code: code)
            default: return .malformed
            }
        }

        if let accessToken = query["access_token"] {
            guard !accessToken.isEmpty,
                  let refreshToken = query["refresh_token"], !refreshToken.isEmpty,
                  let type = query["type"]?.lowercased(),
                  ["session", "implicit", "refresh_token"].contains(type) else {
                return .malformed
            }
            return .session(accessToken: accessToken, refreshToken: refreshToken)
        }

        return .malformed
    }

    private static func fragmentQueryItems(_ fragment: String?) -> [URLQueryItem] {
        guard let fragment, !fragment.isEmpty,
              let fragmentURL = URLComponents(string: "https://callback.invalid/?\(fragment)") else { return [] }
        return fragmentURL.queryItems ?? []
    }

    private static func isTrusted(_ components: URLComponents) -> Bool {
        guard components.user == nil, components.password == nil, components.port == nil,
              let scheme = components.scheme?.lowercased(), let host = components.host else {
            return false
        }

        if scheme == trustedScheme {
            return host.caseInsensitiveCompare(trustedHost) == .orderedSame && components.path.isEmpty
        }
        return scheme == "https"
            && host.caseInsensitiveCompare(trustedWebHost) == .orderedSame
            && components.path == "/auth/callback"
    }
}
