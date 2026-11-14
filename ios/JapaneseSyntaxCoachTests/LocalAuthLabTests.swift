import Foundation
import Supabase
import XCTest
@testable import JapaneseSyntaxCoach

private final class LocalAuthMemoryStorage: AuthLocalStorage, @unchecked Sendable {
    private var values: [String: Data] = [:]
    private let lock = NSLock()

    func store(key: String, value: Data) throws {
        lock.lock()
        values[key] = value
        lock.unlock()
    }

    func retrieve(key: String) throws -> Data? {
        lock.lock()
        defer { lock.unlock() }
        return values[key]
    }

    func remove(key: String) throws {
        lock.lock()
        values.removeValue(forKey: key)
        lock.unlock()
    }
}

final class LocalAuthLabTests: XCTestCase {
    private func makeClient() throws -> SupabaseClient {
        let environment = ProcessInfo.processInfo.environment
        let urlValue = environment["LOCAL_AUTH_LAB_URL"] ?? ""
        let key = environment["LOCAL_AUTH_LAB_ANON_KEY"] ?? ""
        guard let url = URL(string: urlValue), !key.isEmpty else {
            throw XCTSkip("LOCAL_AUTH_LAB_URL and LOCAL_AUTH_LAB_ANON_KEY are not set")
        }
        guard url.scheme == "http", url.host == "127.0.0.1", url.port == 54341 else {
            throw NSError(domain: "LocalAuthLabTests", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Auth lab must use its fixed loopback endpoint"])
        }
        return SupabaseClient(
            supabaseURL: url,
            supabaseKey: key,
            options: SupabaseClientOptions(
                auth: .init(
                    storage: LocalAuthMemoryStorage(),
                    redirectToURL: AppConfiguration.authCallbackURL,
                    storageKey: "local-auth-lab",
                    flowType: .implicit,
                    autoRefreshToken: false
                )
            )
        )
    }

    func testSignupSigninRefreshSignoutAndInitialSessionRestore() async throws {
        let client = try makeClient()
        let service = SupabaseAuthServiceLive(client: client)
        let email = "local-auth-\(UUID().uuidString.lowercased())@example.invalid"
        let password = "LocalAuth-\(UUID().uuidString)!"
        let redirect = AppConfiguration.authCallbackURL

        let signup = try await service.signUp(email: email, password: password, redirectTo: redirect)
        guard case .session(let created) = signup else {
            XCTFail("Expected auto-confirmed signup session")
            return
        }
        XCTAssertFalse(created.accessToken.isEmpty)
        XCTAssertFalse(created.refreshToken.isEmpty)

        try await service.signOut()
        let signedIn = try await service.signIn(email: email, password: password)
        XCTAssertEqual(signedIn.email, email)
        XCTAssertFalse(signedIn.accessToken.isEmpty)

        let refreshed = try await service.refreshSession()
        XCTAssertFalse(refreshed.accessToken.isEmpty)
        XCTAssertFalse(refreshed.refreshToken.isEmpty)

        let restored = SupabaseAuthServiceLive(client: client)
        await MainActor.run {
            let store = AuthSessionStore(service: restored)
            XCTAssertEqual(store.phase, .signedIn)
            XCTAssertEqual(store.session?.userID, refreshed.userID)
        }
        if case .valid(let initial) = restored.initialSession {
            XCTAssertEqual(initial.userID, refreshed.userID)
        } else {
            XCTFail("Expected in-memory auth session to be restored")
        }

        try await restored.signOut()
        XCTAssertNil(restored.currentSession)
    }

    @MainActor
    func testWrongPasswordUsesSafeUserFacingMessage() async throws {
        let client = try makeClient()
        let service = SupabaseAuthServiceLive(client: client)
        let store = AuthSessionStore(service: service, restoreSession: false)
        await store.signIn(email: "missing-\(UUID().uuidString)@example.invalid", password: "wrong-password")
        XCTAssertEqual(store.phase, .error)
        XCTAssertEqual(store.errorMessage, "邮箱或密码未通过验证，请确认登录的是同一账号。")
        XCTAssertFalse(store.errorMessage?.contains("invalid") == true)
        XCTAssertFalse(store.errorMessage?.contains("http") == true)
    }
}
