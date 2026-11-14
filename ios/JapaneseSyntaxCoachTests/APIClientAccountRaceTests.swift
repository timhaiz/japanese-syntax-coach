import Foundation
#if !ACCOUNT_RACE_STANDALONE
import XCTest
@testable import JapaneseSyntaxCoach
#endif

private let arrived = DispatchSemaphore(value: 0)
private let releaseResponse = DispatchSemaphore(value: 0)
private let observationLock = NSLock()
private var requestCount = 0

private final class RaceURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        observationLock.lock()
        requestCount += 1
        let first = requestCount == 1
        observationLock.unlock()
        if first { arrived.signal(); _ = releaseResponse.wait(timeout: .now() + 5) }
        let response = HTTPURLResponse(url: request.url!, statusCode: first ? 401 : 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("{\"ok\":true}".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@MainActor private final class RaceProvider: APITokenProvider {
    var token = "synthetic-a" { didSet { generation = UUID() } }
    var generation = UUID()
    var loginGeneration = UUID()
    var refreshCount = 0
    func accessToken() async throws -> String? { token }
    func refreshSession() async throws -> String? { refreshCount += 1; return token }
    func requestContext() async throws -> APIRequestContext? {
        APIRequestContext(token: token, generation: generation, loginGeneration: loginGeneration)
    }
    func refreshSession(for context: APIRequestContext) async throws -> String? {
        guard context.generation == generation, context.loginGeneration == loginGeneration else { return nil }
        return try await refreshSession()
    }
}
private struct RacePayload: Decodable { let ok: Bool }
private enum RaceFailure: Error { case timeout, retried, refreshed, unexpectedError }

private func resetCount() { observationLock.lock(); requestCount = 0; observationLock.unlock() }
private func observedCount() -> Int { observationLock.lock(); defer { observationLock.unlock() }; return requestCount }
private func waitForArrival() -> Bool { arrived.wait(timeout: .now() + 5) == .success }

@MainActor private func verifySameLoginRefresh() async throws {
    resetCount()
    let provider = RaceProvider()
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [RaceURLProtocol.self]
    let session = URLSession(configuration: configuration)
    defer { session.invalidateAndCancel() }
    let client = APIClient(session: session, tokenProvider: provider)
    let request = URLRequest(url: URL(string: "https://offline.invalid/test")!)
    let task = Task { () throws -> RacePayload in try await client.request(request) }
    let ready = await Task.detached { waitForArrival() }.value
    guard ready else { releaseResponse.signal(); throw RaceFailure.timeout }
    releaseResponse.signal()
    guard try await task.value.ok else { throw RaceFailure.unexpectedError }
    if provider.refreshCount != 1 || observedCount() != 2 { throw RaceFailure.unexpectedError }
}

@MainActor private func verifyAccountSwitch(returnToA: Bool = false, reloginSameAccount: Bool = false) async throws {
    resetCount()
    let provider = RaceProvider()
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [RaceURLProtocol.self]
    let session = URLSession(configuration: configuration)
    defer { session.invalidateAndCancel() }
    let client = APIClient(session: session, tokenProvider: provider)
    var request = URLRequest(url: URL(string: "https://offline.invalid/test")!)
    request.httpMethod = "POST"
    let task = Task { () throws -> RacePayload in try await client.request(request) }
    let ready = await Task.detached { waitForArrival() }.value
    guard ready else { releaseResponse.signal(); throw RaceFailure.timeout }
    if reloginSameAccount {
        provider.loginGeneration = UUID()
    } else {
        provider.token = "synthetic-b"
        if returnToA { provider.token = "synthetic-a" }
    }
    releaseResponse.signal()
    do { _ = try await task.value; throw RaceFailure.retried }
    catch APIClientError.unauthorized { }
    if provider.refreshCount != 0 { throw RaceFailure.refreshed }
    if observedCount() != 1 { throw RaceFailure.retried }
}

#if ACCOUNT_RACE_STANDALONE
@main struct AccountRaceRunner {
    static func main() async throws {
        try await verifySameLoginRefresh()
        try await verifyAccountSwitch()
        try await verifyAccountSwitch(returnToA: true)
        try await verifyAccountSwitch(reloginSameAccount: true)
        print("PASS: same-login refresh; account switch, A-B-A, and same-account relogin rejected")
    }
}
#else
@MainActor final class APIClientAccountRaceTests: XCTestCase {
    func testSameAccountReloginBefore401DoesNotRefreshOrRetry() async throws {
        try await verifyAccountSwitch(reloginSameAccount: true)
    }
    func testSameLoginRefreshesAndRetries() async throws {
        try await verifySameLoginRefresh()
    }
    func testAccountSwitchBefore401DoesNotRefreshOrRetry() async throws {
        try await verifyAccountSwitch()
    }
    func testAccountSwitchAwayAndBackBefore401DoesNotRefreshOrRetry() async throws {
        try await verifyAccountSwitch(returnToA: true)
    }
}
#endif
