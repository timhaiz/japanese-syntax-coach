import Foundation
import XCTest
@testable import JapaneseSyntaxCoach

@MainActor
final class AuthSessionStoreTests: XCTestCase {
    func testCallbackRouterClassifiesTrustedCallbacks() throws {
        XCTAssertEqual(
            AuthCallbackRouter.route(try XCTUnwrap(URL(string: "nihongo://auth-callback?type=signup&code=signup-code"))),
            .signup(code: "signup-code")
        )
        XCTAssertEqual(
            AuthCallbackRouter.route(try XCTUnwrap(URL(string: "https://japanese-syntax-coach.vercel.app/auth/callback?type=recovery&code=recovery-code"))),
            .recovery(code: "recovery-code")
        )
        XCTAssertEqual(
            AuthCallbackRouter.route(try XCTUnwrap(URL(string: "nihongo://auth-callback?type=apple&code=apple-code"))),
            .apple(code: "apple-code")
        )
    }

    func testCallbackRouterRejectsUntrustedURL() throws {
        XCTAssertEqual(
            AuthCallbackRouter.route(try XCTUnwrap(URL(string: "https://example.com/?code=x"))),
            .ignored
        )
        XCTAssertEqual(
            AuthCallbackRouter.route(try XCTUnwrap(URL(string: "http://japanese-syntax-coach.vercel.app/auth/callback?type=signup&code=x"))),
            .ignored
        )
    }

    func testCallbackRouterRejectsMalformedTrustedCallback() throws {
        XCTAssertEqual(
            AuthCallbackRouter.route(try XCTUnwrap(URL(string: "nihongo://auth-callback?type=signup"))),
            .malformed
        )
        XCTAssertEqual(
            AuthCallbackRouter.route(try XCTUnwrap(URL(string: "nihongo://auth-callback?type=unknown&code=x"))),
            .malformed
        )
        XCTAssertEqual(
            AuthCallbackRouter.route(try XCTUnwrap(URL(string: "nihongo://auth-callback?type=signup&code=x&code=y"))),
            .malformed
        )
    }

    func testLogoutClearsSessionState() async throws {
        let service = MockAuthService(currentSession: AuthSession(accessToken: "access", refreshToken: "refresh", email: "user@example.com"))
        let store = AuthSessionStore(service: service)
        XCTAssertEqual(store.phase, .signedIn)
        XCTAssertEqual(store.userEmail, "user@example.com")

        await store.signOut()

        XCTAssertTrue(service.didSignOut)
        XCTAssertNil(service.currentSession)
        XCTAssertNil(store.session)
        XCTAssertNil(store.userEmail)
        XCTAssertEqual(store.phase, .signedOut)
    }

    func testUnconfiguredServiceSurfacesMisconfiguredPhaseInsteadOfCrashing() {
        let store = AuthSessionStore(service: UnconfiguredAuthService(reason: "缺少 SUPABASE_URL 配置。"))

        XCTAssertEqual(store.phase, .misconfigured)
        XCTAssertNil(store.session)
        XCTAssertEqual(store.errorMessage, "缺少 SUPABASE_URL 配置。")
    }

    func testAPIClientInjectsBearerAndRetriesOnceAfter401() async throws {
        let provider = MockTokenProvider(token: "first-token", refreshedToken: "refreshed-token")
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: configuration)
        var requests: [URLRequest] = []
        MockURLProtocol.handler = { request in
            requests.append(request)
            let status = requests.count == 1 ? 401 : 200
            let body = Data(#"{"ok":true}"#.utf8)
            return (HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!, body)
        }
        defer { MockURLProtocol.handler = nil }

        var request = URLRequest(url: try XCTUnwrap(URL(string: "https://api.example.test/api/study-state")))
        request.setValue("website-session=must-not-be-sent", forHTTPHeaderField: "Cookie")
        let client = APIClient(session: session, tokenProvider: provider)
        let payload: TestPayload = try await client.request(request)

        XCTAssertTrue(payload.ok)
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(requests[0].value(forHTTPHeaderField: "Authorization"), "Bearer first-token")
        XCTAssertEqual(requests[1].value(forHTTPHeaderField: "Authorization"), "Bearer refreshed-token")
        XCTAssertNil(requests[0].value(forHTTPHeaderField: "Cookie"))
        XCTAssertEqual(provider.refreshCount, 1)
    }
}

private struct TestPayload: Decodable { let ok: Bool }

@MainActor
private final class MockTokenProvider: APITokenProvider {
    let token: String
    let refreshedToken: String
    private(set) var refreshCount = 0

    init(token: String, refreshedToken: String) {
        self.token = token
        self.refreshedToken = refreshedToken
    }

    func accessToken() async throws -> String? { token }
    func refreshSession() async throws -> String? { refreshCount += 1; return refreshedToken }
}

@MainActor
private final class MockAuthService: AuthService {
    var currentSession: AuthSession?
    private(set) var didSignOut = false

    init(currentSession: AuthSession?) { self.currentSession = currentSession }

    func authStateChanges() -> AsyncStream<AuthSession?> { AsyncStream { $0.finish() } }
    func signIn(email: String, password: String) async throws -> AuthSession { try XCTUnwrap(currentSession) }
    func signUp(email: String, password: String, redirectTo: URL) async throws -> AuthSignupResult { .confirmationRequired }
    func verifySignupCode(email: String, code: String, redirectTo: URL) async throws -> AuthSession { try XCTUnwrap(currentSession) }
    func requestPasswordReset(email: String, redirectTo: URL) async throws {}
    func exchangeCallback(url: URL) async throws -> AuthSession { try XCTUnwrap(currentSession) }
    func signInWithApple(idToken: String, nonce: String?) async throws -> AuthSession { try XCTUnwrap(currentSession) }
    func refreshSession() async throws -> AuthSession { try XCTUnwrap(currentSession) }
    func signOut() async throws { didSignOut = true; currentSession = nil }
}

private final class MockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let handler = Self.handler, let client else { return }
        let (response, data) = handler(request)
        client.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client.urlProtocol(self, didLoad: data)
        client.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
