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
            AuthCallbackRouter.route(try XCTUnwrap(URL(string: "nihongo://auth-callback?type=APPLE&code=apple-code"))),
            .apple(code: "apple-code")
        )
        XCTAssertEqual(
            AuthCallbackRouter.route(try XCTUnwrap(URL(string: "nihongo://auth-callback?type=session&access_token=access&refresh_token=refresh"))),
            .session(accessToken: "access", refreshToken: "refresh")
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
        XCTAssertEqual(
            AuthCallbackRouter.route(try XCTUnwrap(URL(string: "nihongo://auth-callback/extra?type=signup&code=x"))),
            .ignored
        )
        XCTAssertEqual(
            AuthCallbackRouter.route(try XCTUnwrap(URL(string: "nihongo://user@auth-callback?type=signup&code=x"))),
            .ignored
        )
        XCTAssertEqual(
            AuthCallbackRouter.route(try XCTUnwrap(URL(string: "nihongo://auth-callback:443?type=signup&code=x"))),
            .ignored
        )
    }

    func testCallbackRouterAcceptsOnlyAllowlistedHostCaseVariation() throws {
        XCTAssertEqual(
            AuthCallbackRouter.route(try XCTUnwrap(URL(string: "NiHoNgO://AUTH-CALLBACK?type=signup&code=x"))),
            .signup(code: "x")
        )
        XCTAssertEqual(
            AuthCallbackRouter.route(try XCTUnwrap(URL(string: "https://JAPANESE-SYNTAX-COACH.VERCEL.APP/auth/callback?type=recovery&code=x"))),
            .recovery(code: "x")
        )
        XCTAssertEqual(
            AuthCallbackRouter.route(try XCTUnwrap(URL(string: "nihongo://auth-callback.evil?type=signup&code=x"))),
            .ignored
        )
    }

    func testCallbackRouterRejectsMalformedTrustedCallback() throws {
        let malformedURLs = [
            "nihongo://auth-callback?type=signup",
            "nihongo://auth-callback?type=unknown&code=x",
            "nihongo://auth-callback?type=unknown&access_token=x&refresh_token=r",
            "nihongo://auth-callback?type=session&access_token=x",
            "nihongo://auth-callback?type=session&access_token=x&refresh_token=",
            "nihongo://auth-callback?type=session&access_token=x&refresh_token=r&error=access_denied",
            "nihongo://auth-callback?type=signup&code=x&unexpected=value",
            "nihongo://auth-callback?type=signup&code=x&code=y",
            "nihongo://auth-callback?type=signup&code=x#type=recovery&code=y"
        ]

        for string in malformedURLs {
            XCTAssertEqual(
                AuthCallbackRouter.route(try XCTUnwrap(URL(string: string))),
                .malformed,
                string
            )
        }
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

    func testDefaultAuthSessionStoreDoesNotCrashWithoutSupabaseConfiguration() {
        let store = AuthSessionStore(restoreSession: false)

        XCTAssertEqual(store.phase, .misconfigured)
        XCTAssertNotNil(store.errorMessage)
    }

    func testSignupDeepLinkUsesExactCallbackExchangeWithoutPendingEmail() async throws {
        let service = MockAuthService(currentSession: AuthSession(accessToken: "access", refreshToken: "refresh", email: "user@example.com"))
        let store = AuthSessionStore(service: service, restoreSession: false)
        let url = try XCTUnwrap(URL(string: "nihongo://auth-callback?type=signup&code=signup-code"))

        await store.handle(url: url)

        XCTAssertEqual(service.lastExchangedURL, url)
        XCTAssertEqual(store.session?.accessToken, "access")
        XCTAssertEqual(store.phase, .signedIn)
        XCTAssertEqual(service.verifySignupCodeCount, 0)
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
        defer { MockURLProtocol.reset() }

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

    func testAPIClientMapsNetworkRefreshFailureToOffline() async throws {
        let provider = MockTokenProvider(token: "expired", refreshedToken: nil, refreshError: URLError(.notConnectedToInternet))
        let client = try makeAPIClient(provider: provider, response: (statusCode: 401, body: Data()))

        do {
            let _: TestPayload = try await client.request(makeRequest())
            XCTFail("Expected offline error")
        } catch let error as APIClientError {
            XCTAssertEqual(error, .offline)
        }
    }

    func testAPIClientMapsGenericRefreshFailureToUnauthorized() async throws {
        let provider = MockTokenProvider(token: "expired", refreshedToken: nil, refreshError: TestError.generic)
        let client = try makeAPIClient(provider: provider, response: (statusCode: 401, body: Data()))

        do {
            let _: TestPayload = try await client.request(makeRequest())
            XCTFail("Expected unauthorized error")
        } catch let error as APIClientError {
            XCTAssertEqual(error, .unauthorized)
        }
    }

    func testAPIClientMapsEmptyRefreshedTokenToUnauthorized() async throws {
        let provider = MockTokenProvider(token: "expired", refreshedToken: "")
        let client = try makeAPIClient(provider: provider, response: (statusCode: 401, body: Data()))

        do {
            let _: TestPayload = try await client.request(makeRequest())
            XCTFail("Expected unauthorized error")
        } catch let error as APIClientError {
            XCTAssertEqual(error, .unauthorized)
        }
    }

    func testAPIClientMapsSecond401ToUnauthorizedWithoutRefreshingAgain() async throws {
        let provider = MockTokenProvider(token: "expired", refreshedToken: "refreshed")
        let client = try makeAPIClient(provider: provider, response: (statusCode: 401, body: Data()))

        do {
            let _: TestPayload = try await client.request(makeRequest())
            XCTFail("Expected unauthorized error")
        } catch let error as APIClientError {
            XCTAssertEqual(error, .unauthorized)
        }
        XCTAssertEqual(provider.refreshCount, 1)
    }

    func testAPIClientMapsForbiddenToForbidden() async throws {
        let client = try makeAPIClient(provider: MockTokenProvider(token: "token", refreshedToken: "refreshed"), response: (statusCode: 403, body: Data()))

        do {
            let _: TestPayload = try await client.request(makeRequest())
            XCTFail("Expected forbidden error")
        } catch let error as APIClientError {
            XCTAssertEqual(error, .forbidden)
        }
    }

    func testAPIClientMapsServerFailureToStatus() async throws {
        let client = try makeAPIClient(provider: MockTokenProvider(token: "token", refreshedToken: "refreshed"), response: (statusCode: 500, body: Data()))

        do {
            let _: TestPayload = try await client.request(makeRequest())
            XCTFail("Expected server error")
        } catch let error as APIClientError {
            XCTAssertEqual(error, .server(statusCode: 500))
        }
    }

    func testAPIClientMapsTransportFailureToOffline() async throws {
        let provider = MockTokenProvider(token: "token", refreshedToken: "refreshed")
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: configuration)
        MockURLProtocol.transportError = URLError(.cannotConnectToHost)
        defer { MockURLProtocol.reset() }
        let client = APIClient(session: session, tokenProvider: provider)

        do {
            let _: TestPayload = try await client.request(makeRequest())
            XCTFail("Expected offline error")
        } catch let error as APIClientError {
            XCTAssertEqual(error, .offline)
        }
    }

    private func makeRequest() -> URLRequest {
        URLRequest(url: URL(string: "https://api.example.test/api/study-state")!)
    }

    private func makeAPIClient(
        provider: MockTokenProvider,
        response: (statusCode: Int, body: Data)
    ) throws -> APIClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: configuration)
        MockURLProtocol.handler = { request in
            (
                HTTPURLResponse(url: request.url!, statusCode: response.statusCode, httpVersion: nil, headerFields: nil)!,
                response.body
            )
        }
        MockURLProtocol.transportError = nil
        return APIClient(session: session, tokenProvider: provider)
    }
}

private struct TestPayload: Decodable { let ok: Bool }

private enum TestError: Error { case generic }

@MainActor
private final class MockTokenProvider: APITokenProvider {
    let token: String
    let refreshedToken: String?
    let refreshError: Error?
    private(set) var refreshCount = 0

    init(token: String, refreshedToken: String?, refreshError: Error? = nil) {
        self.token = token
        self.refreshedToken = refreshedToken
        self.refreshError = refreshError
    }

    func accessToken() async throws -> String? { token }
    func refreshSession() async throws -> String? {
        refreshCount += 1
        if let refreshError { throw refreshError }
        return refreshedToken
    }
}

@MainActor
private final class MockAuthService: AuthService {
    var currentSession: AuthSession?
    private(set) var didSignOut = false
    private(set) var lastExchangedURL: URL?
    private(set) var verifySignupCodeCount = 0

    init(currentSession: AuthSession?) { self.currentSession = currentSession }

    func authStateChanges() -> AsyncStream<AuthSession?> { AsyncStream { $0.finish() } }
    func signIn(email: String, password: String) async throws -> AuthSession { try XCTUnwrap(currentSession) }
    func signUp(email: String, password: String, redirectTo: URL) async throws -> AuthSignupResult { .confirmationRequired }
    func verifySignupCode(email: String, code: String, redirectTo: URL) async throws -> AuthSession {
        verifySignupCodeCount += 1
        return try XCTUnwrap(currentSession)
    }
    func requestPasswordReset(email: String, redirectTo: URL) async throws {}
    func exchangeCallback(url: URL) async throws -> AuthSession {
        lastExchangedURL = url
        return try XCTUnwrap(currentSession)
    }
    func signInWithApple(idToken: String, nonce: String?) async throws -> AuthSession { try XCTUnwrap(currentSession) }
    func refreshSession() async throws -> AuthSession { try XCTUnwrap(currentSession) }
    func signOut() async throws { didSignOut = true; currentSession = nil }
}

private final class MockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) -> (HTTPURLResponse, Data))?
    nonisolated(unsafe) static var transportError: Error?

    static func reset() {
        handler = nil
        transportError = nil
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let client else { return }
        if let transportError = Self.transportError {
            client.urlProtocol(self, didFailWithError: transportError)
            return
        }
        guard let handler = Self.handler else { return }
        let (response, data) = handler(request)
        client.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client.urlProtocol(self, didLoad: data)
        client.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
