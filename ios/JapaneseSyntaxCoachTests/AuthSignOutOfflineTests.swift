#if AUTH_SIGNOUT_OFFLINE_TEST
// Standalone executable, not XCTest. Tests only direct cleanup after signOut returns.
// It does not exercise real SDK events, storage, Keychain, or event-ordering races.
import Foundation
import Supabase

struct APIRequestContext { let token: String; let generation: UUID; let loginGeneration: UUID }
struct AuthGenerationSnapshot: Equatable { let account: UUID; let login: UUID }
protocol APITokenProvider {}
enum AppConfiguration {
    enum Setup { case configured, missing(String) }
    static var supabaseSetup: Setup { .missing("offline") }
    static var authCallbackURL: URL { URL(string: "offline://callback")! }
    static func makeSupabaseClient() throws -> SupabaseClient { fatalError("Unexpected client creation") }
}
enum AuthCallbackRouter {
    enum Route { case signup, recovery, apple, session, ignored, malformed }
    static func route(_ url: URL) -> Route { .ignored }
}

// This fake does not model SDK events or persistent storage.
@MainActor
private final class FakeAuthService: AuthService {
    private enum SignOutError: Error { case injected }
    var currentSession: AuthSession?
    var initialSessionState: InitialAuthSessionState?
    var initialSession: InitialAuthSessionState { initialSessionState ?? currentSession.map(InitialAuthSessionState.valid) ?? .none }
    var suspendSignOut = false
    var throwAfterSignOutResumes = false
    var refreshResult: AuthSession?
    var refreshError: Error?
    private(set) var didSignOut = false
    private(set) var didThrowSignOut = false
    private(set) var refreshCount = 0
    private var pending: CheckedContinuation<Void, Never>?
    private var started: CheckedContinuation<Void, Never>?

    private var continuation: AsyncStream<AuthStateEvent>.Continuation?
    private lazy var stream = AsyncStream<AuthStateEvent> { continuation = $0 }
    init(_ session: AuthSession) { currentSession = session }
    func authStateChanges() -> AsyncStream<AuthStateEvent> { stream }
    func emit(_ session: AuthSession?) { _ = stream; continuation?.yield(.changed(session)) }
    func waitForSignOut() async {
        if pending != nil { return }
        await withCheckedContinuation { started = $0 }
    }
    func finishSignOut() { pending!.resume(); pending = nil }
    func signOut() async throws {
        didSignOut = true
        currentSession = nil
        if suspendSignOut {
            await withCheckedContinuation { continuation in
                pending = continuation
                started?.resume()
                started = nil
            }
        }
        if throwAfterSignOutResumes {
            didThrowSignOut = true
            throw SignOutError.injected
        }
    }
    func signIn(email: String, password: String) async throws -> AuthSession {
        guard let currentSession else { fatalError("Missing fake login") }
        return currentSession
    }
    func signUp(email: String, password: String, redirectTo: URL) async throws -> AuthSignupResult { fatalError("Unexpected call") }
    func verifySignupCode(email: String, code: String, redirectTo: URL) async throws -> AuthSession { fatalError("Unexpected call") }
    func requestPasswordReset(email: String, redirectTo: URL) async throws { fatalError("Unexpected call") }
    func exchangeCallback(url: URL) async throws -> AuthSession { fatalError("Unexpected call") }
    func signInWithApple(idToken: String, nonce: String?) async throws -> AuthSession { fatalError("Unexpected call") }
    func refreshSession() async throws -> AuthSession {
        refreshCount += 1
        if let refreshError { throw refreshError }
        guard let refreshResult else { fatalError("Unexpected refresh call") }
        return refreshResult
    }
}

@main
private struct AuthSignOutOfflineTests {
    @MainActor static func main() async {
        print("Standalone offline tests (not XCTest); real SDK events, storage, Keychain, and event races are not covered.")
        let old = AuthSession(accessToken: "old", refreshToken: "old-r", email: "old@example.test", userID: "a")
        var failures = 0
        let expiredService = FakeAuthService(old)
        expiredService.initialSessionState = .expired
        let expiredStore = AuthSessionStore(service: expiredService)
        let expiredPass = expiredStore.phase == .loading && expiredStore.session == nil
        print("\(expiredPass ? "PASS" : "FAIL"): expired cache waits for SDK recovery")
        if !expiredPass { failures += 1 }
        expiredService.emit(old)
        for _ in 0..<100 where expiredStore.phase == .loading { await Task.yield() }
        let recoveredPass = expiredStore.phase == .signedIn && expiredStore.session == old
        print("\(recoveredPass ? "PASS" : "FAIL"): recovery event signs in")
        if !recoveredPass { failures += 1 }
        let nilService = FakeAuthService(old)
        nilService.initialSessionState = .expired
        let nilStore = AuthSessionStore(service: nilService)
        nilService.emit(nil)
        for _ in 0..<100 where nilStore.phase == .loading { await Task.yield() }
        let nilPass = nilStore.phase == .error && nilStore.session == nil
            && nilStore.errorMessage?.contains("待同步数据仍会保留") == true
            && nilStore.errorMessage?.contains("重新登录") == true
            && nilStore.errorMessage?.contains("重试") == false
            && nilService.refreshCount == 0
        print("\(nilPass ? "PASS" : "FAIL"): ambiguous nil recovery preserves local data and directs re-login")
        if !nilPass { failures += 1 }
        let client = SupabaseClient()
        let live = SupabaseAuthServiceLive(client: client)
        let missingPass: Bool
        if case .none = live.initialSession { missingPass = true } else { missingPass = false }
        client.auth.currentSession = Session(accessToken: "cached", refreshToken: "r", user: User(email: nil, id: UUID()), isExpired: true)
        let mappingExpired: Bool
        if case .expired = live.initialSession { mappingExpired = live.currentSession == nil } else { mappingExpired = false }
        client.auth.currentSession?.isExpired = false
        let mappingValid: Bool
        if case .valid(let value) = live.initialSession { mappingValid = value.accessToken == "cached" && live.currentSession == value } else { mappingValid = false }
        let mappingPass = missingPass && mappingExpired && mappingValid
        print("\(mappingPass ? "PASS" : "FAIL"): live SDK snapshot distinguishes missing, expired, and valid")
        if !mappingPass { failures += 1 }
        let eventClient = SupabaseClient()
        let eventService = SupabaseAuthServiceLive(client: eventClient)
        var events = eventService.authStateChanges().makeAsyncIterator()
        let user = User(email: nil, id: UUID())
        eventClient.auth.emit(.initialSession, session: Session(accessToken: "expired", refreshToken: "r", user: user, isExpired: true))
        eventClient.auth.emit(.tokenRefreshed, session: Session(accessToken: "fresh", refreshToken: "r2", user: user, isExpired: false))
        let eventPass: Bool
        if case .changed(let session) = await events.next() { eventPass = session?.accessToken == "fresh" } else { eventPass = false }
        print("\(eventPass ? "PASS" : "FAIL"): expired initial SDK event is skipped until recovery")
        if !eventPass { failures += 1 }
        for userID in ["a", "b"] {
            let login = AuthSession(accessToken: "new", refreshToken: "new-r", email: "new@example.test", userID: userID)
            let service = FakeAuthService(old)
            service.suspendSignOut = true
            let store = AuthSessionStore(service: service)
            let task = Task { await store.signOut() }
            await service.waitForSignOut()
            service.currentSession = login
            await store.signIn(email: "fiction", password: "fiction")
            let loggedInBeforeReturn = store.session == login && store.phase == .signedIn
            service.finishSignOut()
            await task.value
            let passed = service.didSignOut && loggedInBeforeReturn && store.session == login && store.userEmail == login.email && store.userID == login.userID && store.phase == .signedIn
            print("\(passed ? "PASS" : "FAIL"): pending signOut preserves \(userID == "a" ? "same" : "different") account login")
            if !passed { failures += 1 }
        }
        for userID in ["a", "b"] {
            let login = AuthSession(accessToken: "new", refreshToken: "new-r", email: "new@example.test", userID: userID)
            let service = FakeAuthService(old)
            service.suspendSignOut = true
            service.throwAfterSignOutResumes = true
            let store = AuthSessionStore(service: service)
            let task = Task { await store.signOut() }
            await service.waitForSignOut()
            service.currentSession = login
            await store.signIn(email: "fiction", password: "fiction")
            let loggedInBeforeReturn = store.session == login && store.phase == .signedIn && !service.didThrowSignOut
            service.finishSignOut()
            await task.value
            let passed = service.didSignOut && service.didThrowSignOut && loggedInBeforeReturn && store.session == login && store.userEmail == login.email && store.userID == login.userID && store.phase == .signedIn
            print("\(passed ? "PASS" : "FAIL"): throwing pending signOut preserves \(userID == "a" ? "same" : "different") account login")
            if !passed { failures += 1 }
        }
        let service = FakeAuthService(old)
        let store = AuthSessionStore(service: service)
        let initiallySignedIn = store.session == old && store.phase == .signedIn
        await store.signOut()
        let passed = initiallySignedIn && service.didSignOut && service.currentSession == nil && store.session == nil && store.userEmail == nil && store.userID == nil && store.phase == .signedOut
        print("\(passed ? "PASS" : "FAIL"): normal signOut clears state")
        if !passed { failures += 1 }
        if failures > 0 { exit(1) }
    }
}
#endif
