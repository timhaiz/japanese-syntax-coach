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

    static func route(_ url: URL) -> AuthCallback {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false), isTrusted(components) else {
            return .ignored
        }
        let items = (components.queryItems ?? []) + fragmentQueryItems(components.fragment)
        guard Set(items.map(\.name)).count == items.count else { return .malformed }
        let query = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
        if query["error"] != nil || query["error_description"] != nil || query["error_code"] != nil { return .malformed }
        if let accessToken = query["access_token"] {
            guard !accessToken.isEmpty else { return .malformed }
            return .session(accessToken: accessToken, refreshToken: query["refresh_token"]?.nilIfEmpty)
        }
        guard let code = query["code"], !code.isEmpty else { return .malformed }
        switch query["type"]?.lowercased() {
        case "signup": return .signup(code: code)
        case "recovery": return .recovery(code: code)
        case "apple": return .apple(code: code)
        default: return .malformed
        }
    }

    private static func fragmentQueryItems(_ fragment: String?) -> [URLQueryItem] {
        guard let fragment, !fragment.isEmpty,
              let fragmentURL = URLComponents(string: "https://callback.invalid/?\(fragment)") else { return [] }
        return fragmentURL.queryItems ?? []
    }

    private static func isTrusted(_ components: URLComponents) -> Bool {
        if components.scheme == trustedScheme { return components.host == trustedHost && components.path.isEmpty }
        return components.scheme == "https" && components.host == trustedWebHost && components.path == "/auth/callback"
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
