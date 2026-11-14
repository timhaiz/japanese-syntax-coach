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

enum InitialAuthSessionState {
    case none, expired
    case valid(AuthSession)
}

protocol AuthService: AnyObject {
    var currentSession: AuthSession? { get }
    var initialSession: InitialAuthSessionState { get }
    /// Non-nil when the service cannot reach a backend (for example missing build configuration).
    var configurationProblem: String? { get }
    func authStateChanges() -> AsyncStream<AuthStateEvent>
    func signIn(email: String, password: String) async throws -> AuthSession
    func signUp(email: String, password: String, redirectTo: URL) async throws -> AuthSignupResult
    func verifySignupCode(email: String, code: String, redirectTo: URL) async throws -> AuthSession
    func requestPasswordReset(email: String, redirectTo: URL) async throws
    func exchangeCallback(url: URL) async throws -> AuthSession
    func signInWithApple(idToken: String, nonce: String?) async throws -> AuthSession
    func refreshSession() async throws -> AuthSession
    func signOut() async throws
}

enum AuthStateEvent {
    case initialSession(AuthSession?)
    case changed(AuthSession?)
    case signedOut
}

extension AuthService {
    /// Services that can actually reach a backend report no configuration problem.
    var configurationProblem: String? { nil }
    var initialSession: InitialAuthSessionState { currentSession.map(InitialAuthSessionState.valid) ?? .none }
}

final class SupabaseAuthServiceLive: AuthService {
    private let client: SupabaseClient

    init(client: SupabaseClient) {
        self.client = client
    }

    var initialSession: InitialAuthSessionState {
        guard let session = client.auth.currentSession else { return .none }
        guard !session.isExpired else { return .expired }
        return .valid(AuthSession(session))
    }

    var currentSession: AuthSession? {
        if case let .valid(session) = initialSession { return session }
        return nil
    }

    func authStateChanges() -> AsyncStream<AuthStateEvent> {
        AsyncStream { continuation in
            let task = Task {
                for await (event, value) in client.auth.authStateChanges {
                    if case .initialSession = event, value?.isExpired == true { continue }
                    let session = value.map(AuthSession.init)
                    switch event {
                    case .initialSession: continuation.yield(.initialSession(session))
                    case .signedOut: continuation.yield(.signedOut)
                    default: continuation.yield(.changed(session))
                    }
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

    func authStateChanges() -> AsyncStream<AuthStateEvent> { AsyncStream { $0.finish() } }
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
    private var awaitingInitialRecovery = false
    private var accountGeneration = UUID()
    // Explicit authentication creates a new login even when the user ID is unchanged.
    private var loginGeneration = UUID()
    @Published private(set) var studyLoadGeneration = AuthGenerationSnapshot(account: UUID(), login: UUID())

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

        if restoreSession {
            switch resolved.initialSession {
            case .valid(let saved): setSession(saved)
            case .expired:
                awaitingInitialRecovery = true // Never expose the expired access token.
            case .none: phase = .signedOut
            }
        } else {
            phase = .signedOut
        }
        let subscriptionLoginGeneration = loginGeneration
        authEventsTask = Task { [weak self, resolved] in
            for await event in resolved.authStateChanges() {
                await MainActor.run {
                    guard let self else { return }
                    switch event {
                    case .initialSession(let value):
                        guard self.loginGeneration == subscriptionLoginGeneration else { return }
                        self.applySessionEvent(value)
                    case .changed(let value):
                        self.applySessionEvent(value)
                    case .signedOut:
                        self.clearSession()
                    }
                }
            }
        }
    }

    deinit { authEventsTask?.cancel() }

    public func accessToken() async throws -> String? { session?.accessToken }

    func generationSnapshot() -> AuthGenerationSnapshot {
        AuthGenerationSnapshot(account: accountGeneration, login: loginGeneration)
    }

    func requestContext() async throws -> APIRequestContext? {
        guard let session, !session.accessToken.isEmpty, session.userID != nil else { return nil }
        return APIRequestContext(token: session.accessToken, generation: accountGeneration, loginGeneration: loginGeneration)
    }

    func refreshSession(for context: APIRequestContext) async throws -> String? {
        guard accountGeneration == context.generation, loginGeneration == context.loginGeneration,
              let userID = session?.userID else { return nil }
        let login = context.loginGeneration
        let refreshed = try await service.refreshSession()
        guard accountGeneration == context.generation, loginGeneration == login, refreshed.userID == userID else { return nil }
        setSession(refreshed)
        return refreshed.accessToken
    }

    public func refreshSession() async throws -> String? {
        let account = accountGeneration
        let login = loginGeneration
        let refreshed = try await service.refreshSession()
        guard accountGeneration == account, loginGeneration == login else { return nil }
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
            case .session(let value): setAuthenticatedSession(value)
            case .confirmationRequired: phase = .needsEmailVerification; errorMessage = "验证码已发送，请检查邮箱。"
            }
        } catch { showError("注册失败，请稍后重试。") }
    }

    public func verifySignupCode(email: String, code: String) async {
        do { setAuthenticatedSession(try await service.verifySignupCode(email: email, code: code, redirectTo: AppConfiguration.authCallbackURL)) }
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
            do { setAuthenticatedSession(try await service.exchangeCallback(url: url)) }
            catch { showError("登录回调无效或已过期。") }
        case .ignored: break
        case .malformed: showError("登录回调无效或已过期。")
        }
    }

    public func signOut() async {
        let account = accountGeneration
        let login = loginGeneration
        try? await service.signOut()
        guard accountGeneration == account, loginGeneration == login else { return }
        clearSession()
    }

    private func run(_ operation: @escaping () async throws -> AuthSession) async {
        do { setAuthenticatedSession(try await operation()) }
        catch { showError(Self.authenticationMessage(for: error)) }
    }

    /// Use structured codes only: SDK messages and response bodies may contain private data.
    private static func authenticationMessage(for error: Error) -> String {
        if let error = error as? URLError {
            if error.code == .timedOut { return "认证请求超时，请稍后重试。" }
            return "网络连接不可用，请检查网络后重试。"
        }
        if case let AuthServiceError.notConfigured(reason) = error { return reason }
        if let error = error as? AuthError,
           case let .api(_, code, _, response) = error {
            if response.statusCode == 429 { return "认证请求过于频繁，请稍后重试。" }
            if response.statusCode >= 500 { return "认证服务暂时不可用，请稍后重试。" }
            switch code {
            case .invalidCredentials:
                return "邮箱或密码未通过验证，请确认登录的是同一账号。"
            case .emailNotConfirmed:
                return "邮箱尚未验证，请先完成邮箱验证后再登录。"
            case .overRequestRateLimit, .overEmailSendRateLimit:
                return "认证请求过于频繁，请稍后重试。"
            case .emailProviderDisabled, .providerDisabled, .badJWT, .invalidJWT, .noAuthorization:
                return "认证服务配置异常，请联系支持人员。"
            default:
                if response.statusCode == 401 || response.statusCode == 403 {
                    return "认证服务配置异常，请联系支持人员。"
                }
            }
        }
        return "暂时无法完成认证，请重试；若持续失败，请联系支持人员。"
    }

    private func applySessionEvent(_ value: AuthSession?) {
        if let value {
            setSession(value)
        } else if awaitingInitialRecovery {
            awaitingInitialRecovery = false
            phase = .error
            errorMessage = "登录状态暂时无法恢复。你的本地待同步数据仍会保留，请重新登录。"
        } else {
            clearSession()
        }
    }

    private func setAuthenticatedSession(_ value: AuthSession) {
        awaitingInitialRecovery = false
        loginGeneration = UUID()
        setSession(value)
    }

    private func setSession(_ value: AuthSession) {
        awaitingInitialRecovery = false
        if session?.userID == nil || value.userID == nil || session?.userID != value.userID {
            accountGeneration = UUID()
        }
        session = value; userEmail = value.email; userID = value.userID; phase = .signedIn; errorMessage = nil
        publishStudyLoadGenerationIfChanged()
    }

    private func clearSession() {
        awaitingInitialRecovery = false
        accountGeneration = UUID()
        session = nil; userEmail = nil; userID = nil; phase = .signedOut
        publishStudyLoadGenerationIfChanged()
    }

    private func publishStudyLoadGenerationIfChanged() {
        let current = AuthGenerationSnapshot(account: accountGeneration, login: loginGeneration)
        if studyLoadGeneration != current { studyLoadGeneration = current }
    }
    private func showError(_ message: String) { phase = .error; errorMessage = message }
}
