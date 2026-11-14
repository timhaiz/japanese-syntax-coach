#if ENTITLEMENT_RACE_OFFLINE_TEST
import Foundation

enum AppConfiguration { static let webURL = URL(string: "https://offline.invalid")! }
private let arrived = DispatchSemaphore(value: 0)
private let releaseResponse = DispatchSemaphore(value: 0)
private let lock = NSLock()
private var paths: [String] = []
private var headers: [String] = []
private var pausePath = ""
private var first401 = false

private final class Intercept: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        lock.lock()
        let path = request.url!.path
        paths.append(path)
        headers.append(request.value(forHTTPHeaderField: "Authorization") ?? "")
        let pause = path == pausePath
        let unauthorized = first401 && paths.count == 1
        lock.unlock()
        if pause {
            arrived.signal()
            guard releaseResponse.wait(timeout: .now() + 5) == .success else {
                client?.urlProtocol(self, didFailWithError: URLError(.timedOut)); return
            }
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: unauthorized ? 401 : 200, httpVersion: nil, headerFields: nil)!
        let body = path.contains("entitlements") ? "{\"updated\":true}" : "{\"authenticated\":true,\"status\":\"member\",\"isMember\":true}"
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
@MainActor private final class Provider: APITokenProvider {
    var token = "a"
    var generation = UUID()
    var login = UUID()
    func accessToken() async throws -> String? { token }
    func refreshSession() async throws -> String? { token = "refreshed"; return token }
    func requestContext() async throws -> APIRequestContext? { APIRequestContext(token: token, generation: generation, loginGeneration: login) }
    func refreshSession(for context: APIRequestContext) async throws -> String? {
        guard context.generation == generation, context.loginGeneration == login else { return nil }
        return try await refreshSession()
    }
}
private func reset(_ path: String, unauthorized: Bool = false) {
    lock.lock(); defer { lock.unlock() }
    paths = []; headers = []; pausePath = path; first401 = unauthorized
}
private func observed() -> ([String], [String]) { lock.lock(); defer { lock.unlock() }; return (paths, headers) }
private func check(_ condition: Bool, _ message: String) { if !condition { print("FAIL: \(message)"); exit(1) } }
private func waitForArrival() -> Bool { arrived.wait(timeout: .now() + 5) == .success }

@main private struct Runner {
    @MainActor static func main() async {
        let provider = Provider()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [Intercept.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        let sync = EntitlementSync(api: APIClient(session: session, tokenProvider: provider))
        for (path, relogin) in [("/api/apple/entitlements", false), ("/api/membership", true)] {
            provider.token = "a"
            reset(path)
            let task = Task { await sync.submitOutcome(signedTransaction: "fiction") }
            let ready = await Task.detached { waitForArrival() }.value
            guard ready else { releaseResponse.signal(); check(false, "request timeout"); return }
            if relogin { provider.login = UUID() } else { provider.generation = UUID(); provider.token = "b" }
            releaseResponse.signal()
            let outcome = await task.value
            check(outcome == .unauthorized, "stale result accepted")
            let seen = observed()
            check(seen.0.count == (relogin ? 2 : 1), "unexpected follow-up request")
            check(!seen.1.contains("Bearer b"), "used new account")
        }
        reset("", unauthorized: true)
        let result = await sync.submitOutcome(signedTransaction: "fiction")
        check(result == .accepted(MembershipState(authenticated: true, status: .member, isMember: true, endsAt: nil)), "same-login refresh failed")
        check(observed().1 == ["Bearer a", "Bearer refreshed", "Bearer refreshed"], "refresh headers")
        print("PASS: account switch during POST; same-account relogin during GET; same-login token refresh")
    }
}
#endif
