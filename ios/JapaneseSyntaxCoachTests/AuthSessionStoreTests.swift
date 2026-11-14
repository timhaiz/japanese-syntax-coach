import Combine
import Foundation
import XCTest
import Supabase
@testable import JapaneseSyntaxCoach

@MainActor
final class AuthSessionStoreTests: XCTestCase {
    func testSignInClassifiesFailuresWithoutExposingRawErrors() async throws {
        let responseURL = try XCTUnwrap(URL(string: "https://auth.example.test/token"))
        func api(_ status: Int, _ code: ErrorCode) -> AuthError {
            .api(message: "raw-sensitive-response", errorCode: code,
                 underlyingData: Data("raw-sensitive-response".utf8),
                 underlyingResponse: HTTPURLResponse(url: responseURL, statusCode: status, httpVersion: nil, headerFields: nil)!)
        }
        let cases: [(Error, String)] = [
            (URLError(.notConnectedToInternet), "网络连接不可用，请检查网络后重试。"),
            (URLError(.timedOut), "认证请求超时，请稍后重试。"),
            (api(400, .invalidCredentials), "邮箱或密码未通过验证，请确认登录的是同一账号。"),
            (api(400, .emailNotConfirmed), "邮箱尚未验证，请先完成邮箱验证后再登录。"),
            (api(429, .overRequestRateLimit), "认证请求过于频繁，请稍后重试。"),
            (api(503, .unexpectedFailure), "认证服务暂时不可用，请稍后重试。"),
            (api(401, .unknown), "认证服务配置异常，请联系支持人员。"),
            (api(400, .emailProviderDisabled), "认证服务配置异常，请联系支持人员。"),
            (NSError(domain: "raw-sensitive-response", code: 1), "暂时无法完成认证，请重试；若持续失败，请联系支持人员。")
        ]
        for (error, message) in cases {
            let service = MockAuthService(currentSession: nil)
            service.signInError = error
            let store = AuthSessionStore(service: service, restoreSession: false)
            await store.signIn(email: "fixture@example.test", password: "fictional-test-password")
            XCTAssertEqual(store.phase, .error)
            XCTAssertNil(store.session)
            XCTAssertEqual(store.errorMessage, message)
            XCTAssertFalse(store.errorMessage?.contains("raw-sensitive-response") == true)
        }
    }

    func testSignInWithAppleForwardsCredentialsAndUpdatesSessionAndGeneration() async {
        let appleSession = AuthSession(
            accessToken: "apple-access",
            refreshToken: "apple-refresh",
            email: "privaterelay@appleid.example.test",
            userID: "22222222-3333-4444-5555-666666666666"
        )
        let service = MockAuthService(currentSession: appleSession)
        let store = AuthSessionStore(service: service, restoreSession: false)
        let initialGeneration = store.studyLoadGeneration

        await store.signInWithApple(idToken: "apple-id-token", nonce: "raw-nonce")

        XCTAssertEqual(service.lastAppleIDToken, "apple-id-token")
        XCTAssertEqual(service.lastAppleNonce, "raw-nonce")
        XCTAssertEqual(store.phase, .signedIn)
        XCTAssertEqual(store.session, appleSession)
        XCTAssertEqual(store.userEmail, "privaterelay@appleid.example.test")
        XCTAssertEqual(store.userID, "22222222-3333-4444-5555-666666666666")
        XCTAssertNil(store.errorMessage)
        XCTAssertNotEqual(store.studyLoadGeneration, initialGeneration)
    }

    func testSignInWithAppleClassifiesFailuresWithoutExposingRawErrors() async throws {
        let responseURL = try XCTUnwrap(URL(string: "https://auth.example.test/token?grant_type=id_token"))
        func api(_ status: Int, _ code: ErrorCode) -> AuthError {
            .api(message: "raw-apple-jwt-secret", errorCode: code,
                 underlyingData: Data("raw-apple-jwt-secret".utf8),
                 underlyingResponse: HTTPURLResponse(url: responseURL, statusCode: status, httpVersion: nil, headerFields: nil)!)
        }
        let cases: [(Error, String)] = [
            (URLError(.notConnectedToInternet), "网络连接不可用，请检查网络后重试。"),
            (URLError(.timedOut), "认证请求超时，请稍后重试。"),
            (api(400, .providerDisabled), "认证服务配置异常，请联系支持人员。"),
            (api(401, .badJWT), "认证服务配置异常，请联系支持人员。"),
            (api(401, .invalidJWT), "认证服务配置异常，请联系支持人员。"),
            (api(403, .noAuthorization), "认证服务配置异常，请联系支持人员。"),
            (NSError(domain: "raw-apple-jwt-secret", code: 1), "暂时无法完成认证，请重试；若持续失败，请联系支持人员。")
        ]
        for (error, message) in cases {
            let service = MockAuthService(currentSession: nil)
            service.signInError = error
            let store = AuthSessionStore(service: service, restoreSession: false)
            await store.signInWithApple(idToken: "fixture-id-token", nonce: nil)
            XCTAssertEqual(store.phase, .error)
            XCTAssertNil(store.session)
            XCTAssertEqual(store.errorMessage, message)
            XCTAssertFalse(store.errorMessage?.contains("raw-apple-jwt-secret") == true)
        }
    }

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

    func testLateInitialSessionCannotReplaceExplicitLoginWhenNilOrNonNil() async {
        let stale = AuthSession(accessToken: "stale", refreshToken: "stale-r", email: nil, userID: "old")
        let login = AuthSession(accessToken: "login", refreshToken: "login-r", email: nil, userID: "new")

        for lateInitial in [AuthSession?.none, stale] {
            let service = MockAuthService(currentSession: login)
            let store = AuthSessionStore(service: service)
            await store.signIn(email: "new", password: "fiction")
            service.emitInitialSession(lateInitial)
            await Task.yield()
            XCTAssertEqual(store.session, login)
            XCTAssertEqual(store.phase, .signedIn)
        }
    }

    func testSignedOutEventStillClearsSessionAfterExplicitLogin() async {
        let login = AuthSession(accessToken: "login", refreshToken: "login-r", email: nil, userID: "new")
        let service = MockAuthService(currentSession: login)
        let store = AuthSessionStore(service: service)
        await store.signIn(email: "new", password: "fiction")

        service.emitSignedOut()
        await waitForSession(nil, in: store)

        XCTAssertEqual(store.phase, .signedOut)
    }

    func testExpiredCacheWaitsForRecoveryEvent() async {
        let service = MockAuthService(currentSession: nil)
        service.initialSessionState = .expired
        let store = AuthSessionStore(service: service)
        XCTAssertEqual(store.phase, .loading)
        XCTAssertNil(store.session)
        let recovered = AuthSession(accessToken: "new", refreshToken: "new-r", email: nil, userID: "a")
        service.emitAuthState(recovered)
        await waitForSession(recovered, in: store)
        XCTAssertEqual(store.phase, .signedIn)
    }

    func testExpiredCacheNilRecoveryEventPreservesConservativeError() async {
        let service = MockAuthService(currentSession: nil)
        service.initialSessionState = .expired
        let store = AuthSessionStore(service: service)
        XCTAssertEqual(store.phase, .loading)
        service.emitInitialSession(nil)
        for _ in 0..<100 where store.phase == .loading { await Task.yield() }
        XCTAssertEqual(store.phase, .error)
        XCTAssertNil(store.session)
        XCTAssertEqual(service.refreshCount, 0)
        XCTAssertTrue(store.errorMessage?.contains("待同步数据仍会保留") == true)
        XCTAssertTrue(store.errorMessage?.contains("重新登录") == true)
        XCTAssertFalse(store.errorMessage?.contains("重试") == true)
    }

    func testNoCacheAndRestoreDisabledStartSignedOut() {
        let service = MockAuthService(currentSession: nil)
        XCTAssertEqual(AuthSessionStore(service: service).phase, .signedOut)
        service.initialSessionState = .expired
        XCTAssertEqual(AuthSessionStore(service: service, restoreSession: false).phase, .signedOut)
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

    func testPendingSignOutPreservesDifferentAccountLogin() async {
        await assertPendingSignOutPreservesLogin(userID: "b")
    }

    func testPendingSignOutPreservesSameAccountLogin() async {
        await assertPendingSignOutPreservesLogin(userID: "a")
    }

    private func assertPendingSignOutPreservesLogin(userID: String) async {
        let old = AuthSession(accessToken: "old", refreshToken: "old-r", email: "old@example.test", userID: "a")
        let login = AuthSession(accessToken: "new", refreshToken: "new-r", email: "new@example.test", userID: userID)
        let service = MockAuthService(currentSession: old)
        service.suspendSignOut = true
        let store = AuthSessionStore(service: service)
        let task = Task { await store.signOut() }
        await service.waitForSignOut()
        service.currentSession = login
        await store.signIn(email: "fiction", password: "fiction")
        XCTAssertEqual(store.session, login)
        service.finishSignOut()
        await task.value
        XCTAssertEqual(store.session, login)
        XCTAssertEqual(store.userEmail, login.email)
        XCTAssertEqual(store.userID, login.userID)
        XCTAssertEqual(store.phase, .signedIn)
    }

    func testUnconfiguredServiceSurfacesMisconfiguredPhaseInsteadOfCrashing() {
        let store = AuthSessionStore(service: UnconfiguredAuthService(reason: "缺少 SUPABASE_URL 配置。"))

        XCTAssertEqual(store.phase, .misconfigured)
        XCTAssertNil(store.session)
        XCTAssertEqual(store.errorMessage, "缺少 SUPABASE_URL 配置。")
    }

    func testDefaultAuthSessionStoreReflectsSupabaseConfiguration() {
        let store = AuthSessionStore(restoreSession: false)

        switch AppConfiguration.supabaseSetup {
        case .configured:
            XCTAssertEqual(store.phase, .signedOut)
            XCTAssertNil(store.errorMessage)
        case .missing:
            XCTAssertEqual(store.phase, .misconfigured)
            XCTAssertNotNil(store.errorMessage)
        }
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

    func testStudyLoadGenerationChangesForSameEmailAccountSwitchAndRelogin() async {
        let initial = AuthSession(accessToken: "a", refreshToken: "r-a", email: "same@example.test", userID: "a")
        let service = MockAuthService(currentSession: initial)
        let store = AuthSessionStore(service: service)
        let initialGeneration = store.studyLoadGeneration

        service.currentSession = AuthSession(accessToken: "b", refreshToken: "r-b", email: initial.email, userID: "b")
        await store.signIn(email: initial.email!, password: "fiction")
        let switchedGeneration = store.studyLoadGeneration
        XCTAssertNotEqual(switchedGeneration, initialGeneration, "same-email account switches must trigger account-scoped loading")

        service.currentSession = AuthSession(accessToken: "b2", refreshToken: "r-b2", email: initial.email, userID: "b")
        await store.signIn(email: initial.email!, password: "fiction")
        XCTAssertNotEqual(store.studyLoadGeneration, switchedGeneration, "an explicit relogin must trigger another load even for the same user ID")
    }

    func testStudyLoadGenerationDoesNotChangeOnTokenRefresh() async throws {
        let initial = AuthSession(accessToken: "a", refreshToken: "r-a", email: "same@example.test", userID: "a")
        let service = MockAuthService(currentSession: initial)
        let store = AuthSessionStore(service: service)
        let loginGeneration = store.studyLoadGeneration
        service.currentSession = AuthSession(accessToken: "a2", refreshToken: "r-a2", email: initial.email, userID: "a")

        _ = try await store.refreshSession()

        XCTAssertEqual(store.studyLoadGeneration, loginGeneration, "token refreshes must not trigger study reloads")
    }

    func testStudyLoadGenerationTracksAuthEventsAndLogout() async {
        let accountA = AuthSession(accessToken: "a", refreshToken: "r-a", email: "same@example.test", userID: "a")
        let accountB = AuthSession(accessToken: "b", refreshToken: "r-b", email: accountA.email, userID: "b")
        let service = MockAuthService(currentSession: accountA)
        let store = AuthSessionStore(service: service)
        let initial = store.studyLoadGeneration
        var sessionAtGenerationPublication: AuthSession?
        let generationObservation = store.$studyLoadGeneration.dropFirst().sink { _ in
            sessionAtGenerationPublication = store.session
        }

        service.emitAuthState(accountB)
        await waitForSession(accountB, in: store)
        let switched = store.studyLoadGeneration
        XCTAssertEqual(sessionAtGenerationPublication, accountB, "the task ID must publish after the new session is visible")
        XCTAssertNotEqual(switched.account, initial.account, "auth events changing user ID must publish a new account generation")
        XCTAssertEqual(switched.login, initial.login, "an auth event must not impersonate an explicit login")

        service.emitSignedOut()
        await waitForSession(nil, in: store)
        XCTAssertEqual(store.phase, .signedOut)
        XCTAssertNotEqual(store.studyLoadGeneration.account, switched.account, "logout must publish a new account generation")

        let restored = AuthSession(accessToken: "b2", refreshToken: "r-b2", email: accountB.email, userID: "b")
        service.emitAuthState(restored)
        await waitForSession(restored, in: store)
        let restoredGeneration = store.studyLoadGeneration
        service.emitAuthState(AuthSession(accessToken: "b3", refreshToken: "r-b3", email: accountB.email, userID: "b"))
        await waitForSession(AuthSession(accessToken: "b3", refreshToken: "r-b3", email: accountB.email, userID: "b"), in: store)
        XCTAssertEqual(store.studyLoadGeneration, restoredGeneration, "same-account token events must not restart study loading")
        withExtendedLifetime(generationObservation) {}
    }

    private func waitForSession(_ expected: AuthSession?, in store: AuthSessionStore) async {
        for _ in 0..<100 where store.session != expected { await Task.yield() }
        XCTAssertEqual(store.session, expected, "auth state event should be applied")
    }

    func testRequestContextInvalidatedByAccountSwitchAwayAndBack() async throws {
        let a = AuthSession(accessToken: "a", refreshToken: "r-a", email: nil, userID: "a")
        let b = AuthSession(accessToken: "b", refreshToken: "r-b", email: nil, userID: "b")
        let service = MockAuthService(currentSession: a)
        let store = AuthSessionStore(service: service)
        let capturedContext = try await store.requestContext()
        let context = try XCTUnwrap(capturedContext)
        service.currentSession = b
        await store.signIn(email: "b", password: "")
        service.currentSession = a
        await store.signIn(email: "a", password: "")
        let token = try await store.refreshSession(for: context)
        XCTAssertNil(token)
        XCTAssertEqual(service.refreshCount, 0)
    }

    func testRequestContextAllowsSameAccountRefresh() async throws {
        let a = AuthSession(accessToken: "a", refreshToken: "r-a", email: nil, userID: "a")
        let service = MockAuthService(currentSession: a)
        let store = AuthSessionStore(service: service)
        let capturedContext = try await store.requestContext()
        let context = try XCTUnwrap(capturedContext)
        service.currentSession = AuthSession(accessToken: "new-a", refreshToken: "new-r", email: nil, userID: "a")
        let token = try await store.refreshSession(for: context)
        XCTAssertEqual(token, "new-a")
        XCTAssertEqual(service.refreshCount, 1)
    }

    func testUnscopedRefreshDoesNotOverwriteSameAccountRelogin() async throws {
        try await assertPendingRefreshPreservesLogin(userID: "a")
    }

    func testUnscopedRefreshDoesNotOverwriteDifferentAccountLogin() async throws {
        try await assertPendingRefreshPreservesLogin(userID: "b")
    }

    private func assertPendingRefreshPreservesLogin(userID: String) async throws {
        let old = AuthSession(accessToken: "old", refreshToken: "old-r", email: nil, userID: "a")
        let login = AuthSession(accessToken: "login", refreshToken: "login-r", email: nil, userID: userID)
        let service = MockAuthService(currentSession: old)
        service.suspendRefresh = true
        let store = AuthSessionStore(service: service)
        let task = Task { try await store.refreshSession() }
        await service.waitForRefresh()
        service.currentSession = login
        await store.signIn(email: "fiction", password: "fiction")
        service.finishRefresh(with: old)
        let result = try await task.value
        XCTAssertNil(result)
        XCTAssertTrue(store.session == login)
    }

    func testUnscopedRefreshAppliesNormally() async throws {
        let old = AuthSession(accessToken: "old", refreshToken: "old-r", email: nil, userID: "a")
        let updated = AuthSession(accessToken: "updated", refreshToken: "updated-r", email: nil, userID: "a")
        let service = MockAuthService(currentSession: old)
        service.suspendRefresh = true
        let store = AuthSessionStore(service: service)
        let task = Task { try await store.refreshSession() }
        await service.waitForRefresh()
        service.finishRefresh(with: updated)
        let result = try await task.value
        XCTAssertTrue(result == updated.accessToken)
        XCTAssertTrue(store.session == updated)
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
    private let generation = UUID()

    func requestContext() async throws -> APIRequestContext? { APIRequestContext(token: token, generation: generation) }
    func refreshSession(for context: APIRequestContext) async throws -> String? {
        guard context.generation == generation else { return nil }
        return try await refreshSession()
    }

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
private final class MockAuthService: @preconcurrency AuthService {
    var initialSessionState: InitialAuthSessionState?
    var initialSession: InitialAuthSessionState { initialSessionState ?? currentSession.map(InitialAuthSessionState.valid) ?? .none }
    var currentSession: AuthSession?
    private(set) var didSignOut = false
    private(set) var lastExchangedURL: URL?
    private(set) var lastAppleIDToken: String?
    private(set) var lastAppleNonce: String?
    private(set) var verifySignupCodeCount = 0
    private(set) var refreshCount = 0
    var suspendRefresh = false
    var suspendSignOut = false
    private var signOutContinuation: CheckedContinuation<Void, Never>?
    private var signOutStarted: CheckedContinuation<Void, Never>?

    func waitForSignOut() async {
        if signOutContinuation != nil { return }
        await withCheckedContinuation { signOutStarted = $0 }
    }

    func finishSignOut() {
        signOutContinuation?.resume()
        signOutContinuation = nil
    }

    private var refreshContinuation: CheckedContinuation<AuthSession, Never>?
    private var refreshStarted: CheckedContinuation<Void, Never>?
    private let authStream: AsyncStream<AuthStateEvent>
    private let authStateContinuation: AsyncStream<AuthStateEvent>.Continuation?

    func waitForRefresh() async {
        if refreshContinuation != nil { return }
        await withCheckedContinuation { refreshStarted = $0 }
    }

    func finishRefresh(with session: AuthSession) {
        refreshContinuation?.resume(returning: session)
        refreshContinuation = nil
    }

    init(currentSession: AuthSession?) {
        self.currentSession = currentSession
        var continuation: AsyncStream<AuthStateEvent>.Continuation?
        authStream = AsyncStream { continuation = $0 }
        authStateContinuation = continuation
    }

    func authStateChanges() -> AsyncStream<AuthStateEvent> { authStream }
    func emitAuthState(_ session: AuthSession?) { authStateContinuation?.yield(.changed(session)) }
    func emitInitialSession(_ session: AuthSession?) { authStateContinuation?.yield(.initialSession(session)) }
    func emitSignedOut() { authStateContinuation?.yield(.signedOut) }
    var signInError: Error?
    func signIn(email: String, password: String) async throws -> AuthSession {
        if let signInError { throw signInError }
        return try XCTUnwrap(currentSession)
    }
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
    func signInWithApple(idToken: String, nonce: String?) async throws -> AuthSession {
        lastAppleIDToken = idToken
        lastAppleNonce = nonce
        if let signInError { throw signInError }
        return try XCTUnwrap(currentSession)
    }
    func refreshSession() async throws -> AuthSession {
        refreshCount += 1
        if suspendRefresh {
            return await withCheckedContinuation { continuation in
                refreshContinuation = continuation
                refreshStarted?.resume()
                refreshStarted = nil
            }
        }
        return try XCTUnwrap(currentSession)
    }
    func signOut() async throws {
        didSignOut = true
        currentSession = nil
        if suspendSignOut {
            await withCheckedContinuation { continuation in
                signOutContinuation = continuation
                signOutStarted?.resume()
                signOutStarted = nil
            }
        }
    }
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
