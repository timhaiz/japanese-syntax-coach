import Foundation
import Supabase
import SwiftUI

enum AuthPhase: Equatable { case loading, signedOut, signedIn, needsEmailVerification, error, misconfigured }

struct AuthSession: Codable, Equatable {
    let accessToken: String
    let refreshToken: String
    let email: String?
    let userID: String?

    init(accessToken: String, refreshToken: String, email: String?, userID: String? = nil) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.email = email
        self.userID = userID
    }

    init(_ session: Session) {
        self.init(
            accessToken: session.accessToken,
            refreshToken: session.refreshToken,
            email: session.user.email,
            userID: session.user.id.uuidString
        )
    }

    private enum CodingKeys: String, CodingKey {
        case accessToken, refreshToken, email, userID
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        accessToken = try container.decode(String.self, forKey: .accessToken)
        refreshToken = try container.decode(String.self, forKey: .refreshToken)
        email = try container.decodeIfPresent(String.self, forKey: .email)
        userID = try container.decodeIfPresent(String.self, forKey: .userID)
    }
}

enum AuthSignupResult: Equatable {
    case session(AuthSession)
    case confirmationRequired
}

protocol AuthService: AnyObject {
    var currentSession: AuthSession? { get }
    /// Non-nil when the service cannot reach a backend (for example missing build configuration).
    var configurationProblem: String? { get }
    func authStateChanges() -> AsyncStream<AuthSession?>
    func signIn(email: String, password: String) async throws -> AuthSession
    func signUp(email: String, password: String, redirectTo: URL) async throws -> AuthSignupResult
    func verifySignupCode(email: String, code: String, redirectTo: URL) async throws -> AuthSession
    func requestPasswordReset(email: String, redirectTo: URL) async throws
    func exchangeCallback(url: URL) async throws -> AuthSession
    func signInWithApple(idToken: String, nonce: String?) async throws -> AuthSession
    func refreshSession() async throws -> AuthSession
    func signOut() async throws
}

extension AuthService {
    /// Services that can actually reach a backend report no configuration problem.
    var configurationProblem: String? { nil }
}

final class SupabaseAuthServiceLive: AuthService {
    private let client: SupabaseClient

    init(client: SupabaseClient) {
        self.client = client
    }

    var currentSession: AuthSession? { client.auth.currentSession.map(AuthSession.init) }

    func authStateChanges() -> AsyncStream<AuthSession?> {
        AsyncStream { continuation in
            let task = Task {
                for await (_, value) in client.auth.authStateChanges {
                    continuation.yield(value.map(AuthSession.init))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func signIn(email: String, password: String) async throws -> AuthSession {
        AuthSession(try await client.auth.signIn(email: email, password: password))
    }

    func signUp(email: String, password: String, redirectTo: URL) async throws -> AuthSignupResult {
        let response = try await client.auth.signUp(email: email, password: password, redirectTo: redirectTo)
        if let session = response.session { return .session(AuthSession(session)) }
        return .confirmationRequired
    }

    func verifySignupCode(email: String, code: String, redirectTo: URL) async throws -> AuthSession {
        let response = try await client.auth.verifyOTP(email: email, token: code, type: .signup, redirectTo: redirectTo)
        guard case let .session(session) = response else { throw AuthServiceError.invalidResponse }
        return AuthSession(session)
    }

    func requestPasswordReset(email: String, redirectTo: URL) async throws {
        try await client.auth.resetPasswordForEmail(email, redirectTo: redirectTo)
    }

    func exchangeCallback(url: URL) async throws -> AuthSession {
        AuthSession(try await client.auth.session(from: url))
    }

    func signInWithApple(idToken: String, nonce: String?) async throws -> AuthSession {
        let credentials = OpenIDConnectCredentials(provider: .apple, idToken: idToken, nonce: nonce)
        return AuthSession(try await client.auth.signInWithIdToken(credentials: credentials))
    }

    func refreshSession() async throws -> AuthSession {
        AuthSession(try await client.auth.refreshSession())
    }

    func signOut() async throws { try await client.auth.signOut() }
}

enum AuthServiceError: Error { case invalidResponse, notConfigured(String) }

/// Used when the app has no usable Supabase coordinates, so the UI can explain the problem
/// instead of crashing on launch.
final class UnconfiguredAuthService: AuthService {
    let reason: String

    init(reason: String) {
        self.reason = reason
    }

    var currentSession: AuthSession? { nil }
    var configurationProblem: String? { reason }

    func authStateChanges() -> AsyncStream<AuthSession?> { AsyncStream { $0.finish() } }
    func signIn(email: String, password: String) async throws -> AuthSession { throw AuthServiceError.notConfigured(reason) }
    func signUp(email: String, password: String, redirectTo: URL) async throws -> AuthSignupResult { throw AuthServiceError.notConfigured(reason) }
    func verifySignupCode(email: String, code: String, redirectTo: URL) async throws -> AuthSession { throw AuthServiceError.notConfigured(reason) }
    func requestPasswordReset(email: String, redirectTo: URL) async throws { throw AuthServiceError.notConfigured(reason) }
    func exchangeCallback(url: URL) async throws -> AuthSession { throw AuthServiceError.notConfigured(reason) }
    func signInWithApple(idToken: String, nonce: String?) async throws -> AuthSession { throw AuthServiceError.notConfigured(reason) }
    func refreshSession() async throws -> AuthSession { throw AuthServiceError.notConfigured(reason) }
    func signOut() async throws {}
}

@MainActor
final class AuthSessionStore: ObservableObject, APITokenProvider {
    @Published private(set) var phase: AuthPhase = .loading
    @Published private(set) var session: AuthSession?
    @Published private(set) var userEmail: String?
    /// Supabase user id. StoreKit needs it as `appAccountToken`, and the server
    /// rejects a transaction whose token does not match the signed-in account.
    @Published private(set) var userID: String?
    @Published var errorMessage: String?

    private let service: AuthService
    private var authEventsTask: Task<Void, Never>?

    public init(service: AuthService? = nil, restoreSession: Bool = true) {
        let resolved: AuthService
        if let service {
            resolved = service
        } else {
            switch AppConfiguration.supabaseSetup {
            case .configured:
                do {
                    resolved = SupabaseAuthServiceLive(client: try AppConfiguration.makeSupabaseClient())
                } catch {
                    resolved = UnconfiguredAuthService(reason: error.localizedDescription)
                }
            case .missing(let reason):
                resolved = UnconfiguredAuthService(reason: reason)
            }
        }
        self.service = resolved

        if let problem = resolved.configurationProblem {
            phase = .misconfigured
            errorMessage = problem
            return
        }

        if restoreSession, let saved = resolved.currentSession {
            setSession(saved)
        } else {
            phase = .signedOut
        }
        authEventsTask = Task { [weak self, resolved] in
            for await value in resolved.authStateChanges() {
                await MainActor.run {
                    if let value { self?.setSession(value) }
                    else { self?.clearSession() }
                }
            }
        }
    }

    deinit { authEventsTask?.cancel() }

    public func accessToken() async throws -> String? { session?.accessToken }

    public func refreshSession() async throws -> String? {
        let refreshed = try await service.refreshSession()
        setSession(refreshed)
        return refreshed.accessToken
    }

    public func signIn(email: String, password: String) async {
        await run { try await self.service.signIn(email: email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), password: password) }
    }

    public func signUp(email: String, password: String) async {
        do {
            let result = try await service.signUp(email: email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), password: password, redirectTo: AppConfiguration.authCallbackURL)
            switch result {
            case .session(let value): setSession(value)
            case .confirmationRequired: phase = .needsEmailVerification; errorMessage = "验证码已发送，请检查邮箱。"
            }
        } catch { showError("注册失败，请稍后重试。") }
    }

    public func verifySignupCode(email: String, code: String) async {
        do { setSession(try await service.verifySignupCode(email: email, code: code, redirectTo: AppConfiguration.authCallbackURL)) }
        catch { showError("验证码无效或已过期，请重新获取。") }
    }

    public func requestPasswordReset(email: String) async {
        do {
            try await service.requestPasswordReset(email: email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), redirectTo: AppConfiguration.authCallbackURL)
            errorMessage = "重置密码邮件已发送。"
        } catch { showError("无法发送重置邮件，请稍后重试。") }
    }

    public func signInWithApple(idToken: String, nonce: String? = nil) async {
        await run { try await self.service.signInWithApple(idToken: idToken, nonce: nonce) }
    }

    public func handle(url: URL) async {
        switch AuthCallbackRouter.route(url) {
        case .signup, .recovery, .apple, .session:
            do { setSession(try await service.exchangeCallback(url: url)) }
            catch { showError("登录回调无效或已过期。") }
        case .ignored: break
        case .malformed: showError("登录回调无效或已过期。")
        }
    }

    public func signOut() async {
        try? await service.signOut()
        clearSession()
    }

    private func run(_ operation: @escaping () async throws -> AuthSession) async {
        do { setSession(try await operation()) }
        catch { showError("认证失败，请检查信息后重试。") }
    }

    private func setSession(_ value: AuthSession) {
        session = value; userEmail = value.email; userID = value.userID; phase = .signedIn; errorMessage = nil
    }

    private func clearSession() { session = nil; userEmail = nil; userID = nil; phase = .signedOut }
    private func showError(_ message: String) { phase = .error; errorMessage = message }
}
