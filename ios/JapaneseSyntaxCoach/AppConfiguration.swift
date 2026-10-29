import Foundation
import Supabase

enum AppConfiguration {
    static let webURL = URL(string: "https://japanese-syntax-coach.vercel.app/")!
    static let authCallbackURL = URL(string: "nihongo://auth-callback")!
    static let monthlyProductID = "com.juxintong.nihongo.monthly"
    static let yearlyProductID = "com.juxintong.nihongo.yearly"
    static let productIDs: Set<String> = [monthlyProductID, yearlyProductID]

    enum SupabaseSetup: Equatable {
        case configured(url: URL, anonKey: String)
        case missing(String)
    }

    enum ConfigurationError: LocalizedError {
        case missing(String)

        var errorDescription: String? {
            switch self {
            case .missing(let reason):
                return reason
            }
        }
    }

    /// Reads the public Supabase coordinates from the app bundle.
    ///
    /// The values come from the `SUPABASE_URL` / `SUPABASE_ANON_KEY` build settings, which are
    /// intentionally empty by default so no credential is ever committed. An unresolved
    /// `$(...)` placeholder or an empty value is reported as "not configured" instead of
    /// crashing the app on launch.
    static var supabaseSetup: SupabaseSetup {
        guard let rawURL = bundleValue(for: "SUPABASE_URL") else {
            return .missing("尚未配置 SUPABASE_URL，请在构建设置中填入 Supabase 项目地址。")
        }
        guard let url = URL(string: rawURL),
              let scheme = url.scheme?.lowercased(),
              scheme == "https",
              !(url.host ?? "").isEmpty else {
            return .missing("SUPABASE_URL 配置无效，请填写 https 开头的 Supabase 项目地址。")
        }
        guard let anonKey = bundleValue(for: "SUPABASE_ANON_KEY") else {
            return .missing("尚未配置 SUPABASE_ANON_KEY，请在构建设置中填入 anon key。")
        }
        return .configured(url: url, anonKey: anonKey)
    }

    static func makeSupabaseClient() throws -> SupabaseClient {
        guard case let .configured(url, anonKey) = supabaseSetup else {
            throw ConfigurationError.missing(missingReason)
        }
        return SupabaseClient(
            supabaseURL: url,
            supabaseKey: anonKey,
            options: SupabaseClientOptions(
                auth: .init(
                    redirectToURL: authCallbackURL,
                    storageKey: "com.juxintong.nihongo.auth",
                    flowType: .pkce,
                    autoRefreshToken: true
                )
            )
        )
    }

    private static var missingReason: String {
        switch supabaseSetup {
        case .configured:
            return ""
        case .missing(let reason):
            return reason
        }
    }

    private static func bundleValue(for key: String) -> String? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: key) as? String else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains("$(") else { return nil }
        return trimmed
    }
}
