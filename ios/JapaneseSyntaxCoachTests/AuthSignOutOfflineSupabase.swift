#if AUTH_SIGNOUT_OFFLINE_TEST
// Compile-only Supabase substitute. No SDK, network, persistence, or Keychain.
import Foundation
public struct User { public var email: String?; public var id: UUID; public init(email: String?, id: UUID) { self.email = email; self.id = id } }
public struct Session {
    public var accessToken: String; public var refreshToken: String; public var user: User; public var isExpired: Bool
    public init(accessToken: String, refreshToken: String, user: User, isExpired: Bool) {
        self.accessToken = accessToken; self.refreshToken = refreshToken; self.user = user; self.isExpired = isExpired
    }
}
public struct OpenIDConnectCredentials { public enum Provider { case apple }; public init(provider: Provider, idToken: String, nonce: String?) {} }
public enum OTPType { case signup }
public enum AuthChangeEvent { case initialSession, passwordRecovery, signedIn, signedOut, tokenRefreshed, userUpdated, userDeleted, mfaChallengeVerified }
public enum OTPResponse { case session(Session), other }
public struct SignupResponse { public var session: Session? }
public final class AuthClient {
    public var currentSession: Session?
    public let authStateChanges: AsyncStream<(AuthChangeEvent, Session?)>
    private let continuation: AsyncStream<(AuthChangeEvent, Session?)>.Continuation
    public init() {
        var captured: AsyncStream<(AuthChangeEvent, Session?)>.Continuation!
        authStateChanges = AsyncStream { captured = $0 }
        continuation = captured
    }
    public func emit(_ event: AuthChangeEvent, session: Session?) { continuation.yield((event, session)) }
    public func signIn(email: String, password: String) async throws -> Session { fatalError("Unexpected SDK call") }
    public func signUp(email: String, password: String, redirectTo: URL) async throws -> SignupResponse { fatalError("Unexpected SDK call") }
    public func verifyOTP(email: String, token: String, type: OTPType, redirectTo: URL) async throws -> OTPResponse { fatalError("Unexpected SDK call") }
    public func resetPasswordForEmail(_ email: String, redirectTo: URL) async throws { fatalError("Unexpected SDK call") }
    public func session(from: URL) async throws -> Session { fatalError("Unexpected SDK call") }
    public func signInWithIdToken(credentials: OpenIDConnectCredentials) async throws -> Session { fatalError("Unexpected SDK call") }
    public func refreshSession() async throws -> Session { fatalError("Unexpected SDK call") }
    public func signOut() async throws { fatalError("Unexpected SDK call") }
}
public final class SupabaseClient { public let auth = AuthClient(); public init() {} }
#endif
