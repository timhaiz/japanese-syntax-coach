#if SAME_LOGIN_RACE_OFFLINE_TEST
// Standalone regression using the real store and client, not XCTest or the real SDK.
import Foundation
import Supabase

struct AuthGenerationSnapshot: Equatable { let account: UUID; let login: UUID }

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

private let arrived = DispatchSemaphore(value: 0)
private let releaseResponse = DispatchSemaphore(value: 0)
private let lock = NSLock()
private var authorizationHeaders: [String] = []
private let old = AuthSession(accessToken: "fiction-old", refreshToken: "fiction-old-refresh", email: nil, userID: "A")
private let login = AuthSession(accessToken: "fiction-new", refreshToken: "fiction-new-refresh", email: nil, userID: "A")
private let refreshed = AuthSession(accessToken: "fiction-refreshed", refreshToken: "fiction-refreshed-refresh", email: nil, userID: "A")

private final class Intercept: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        lock.lock()
        authorizationHeaders.append(request.value(forHTTPHeaderField: "Authorization") ?? "")
        let first = authorizationHeaders.count == 1
        lock.unlock()
        if first {
            arrived.signal()
            guard releaseResponse.wait(timeout: .now() + 10) == .success else {
                client?.urlProtocol(self, didFailWithError: URLError(.timedOut))
                return
            }
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: first ? 401 : 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("{\"ok\":true}".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@MainActor private final class FakeService: AuthService {
    var currentSession: AuthSession? = old
    var refreshCount = 0
    func authStateChanges() -> AsyncStream<AuthStateEvent> { AsyncStream { $0.finish() } }
    func signIn(email: String, password: String) async throws -> AuthSession { currentSession = login; return login }
    func refreshSession() async throws -> AuthSession { refreshCount += 1; currentSession = refreshed; return refreshed }
    func signUp(email: String, password: String, redirectTo: URL) async throws -> AuthSignupResult { fatalError("Unexpected call") }
    func verifySignupCode(email: String, code: String, redirectTo: URL) async throws -> AuthSession { fatalError("Unexpected call") }
    func requestPasswordReset(email: String, redirectTo: URL) async throws { fatalError("Unexpected call") }
    func exchangeCallback(url: URL) async throws -> AuthSession { fatalError("Unexpected call") }
    func signInWithApple(idToken: String, nonce: String?) async throws -> AuthSession { fatalError("Unexpected call") }
    func signOut() async throws { fatalError("Unexpected call") }
}
private struct Payload: Decodable { let ok: Bool }
private func headers() -> [String] { lock.lock(); defer { lock.unlock() }; return authorizationHeaders }

@main private struct SameLoginRaceOfflineTests {
    @MainActor static func main() async {
        let service = FakeService()
        let store = AuthSessionStore(service: service)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [Intercept.self]
        let transport = URLSession(configuration: config)
        defer { transport.invalidateAndCancel() }
        let client = APIClient(session: transport, tokenProvider: store)
        let task = Task { () throws -> Payload in
            try await client.request(URLRequest(url: URL(string: "https://offline.invalid/test")!))
        }
        let ready = await Task.detached { arrived.wait(timeout: .now() + 5) == .success }.value
        guard ready else { releaseResponse.signal(); print("FAIL: old request did not arrive"); exit(1) }
        await store.signIn(email: "fiction", password: "fiction")
        guard store.session == login else { releaseResponse.signal(); print("FAIL: explicit login did not complete"); exit(1) }
        releaseResponse.signal()
        do { _ = try await task.value; print("FAIL: old request succeeded"); exit(1) }
        catch APIClientError.unauthorized { }
        catch { print("FAIL: unexpected error \(error)"); exit(1) }
        guard service.refreshCount == 0 else { print("FAIL: refreshed \(service.refreshCount) times"); exit(1) }
        guard headers() == ["Bearer \(old.accessToken)"] else { print("FAIL: unexpected request count or authorization"); exit(1) }
        guard store.session == login, service.currentSession == login else { print("FAIL: new session not retained"); exit(1) }
        print("PASS: old 401 after same-account login: no refresh, no retry, new session retained")
    }
}
#endif
