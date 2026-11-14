import CryptoKit
import Foundation
import XCTest
@testable import JapaneseSyntaxCoach

@MainActor
final class LearningStoreAuthRaceTests: XCTestCase {
    override func setUp() {
        super.setUp()
        URLProtocol.registerClass(LearningRaceURLProtocol.self)
    }

    override func tearDown() {
        URLProtocol.unregisterClass(LearningRaceURLProtocol.self)
        LearningRaceURLProtocol.handler = nil
        super.tearDown()
    }

    func testStudyStateResponseFromPreviousLoginIsIgnored() async throws {
        let session = AuthSession(accessToken: "fiction-a", refreshToken: "refresh-a", email: "race@example.test", userID: "stable-user")
        let service = LearningRaceAuthService(session: session)
        let auth = AuthSessionStore(service: service)
        let store = LearningStore(auth: auth, supportDirectory: isolatedDirectory())
        let arrived = expectation(description: "study-state request arrived")
        let release = DispatchSemaphore(value: 0)
        LearningRaceURLProtocol.handler = { request in
            arrived.fulfill()
            _ = release.wait(timeout: .now() + 5)
            return (self.response(request), Self.studyState)
        }
        defer { store.clearUserScopedData() }

        let load = Task { await store.loadStudyState() }
        await fulfillment(of: [arrived], timeout: 5)
        await auth.signIn(email: "race@example.test", password: "fiction")
        release.signal()
        await load.value

        XCTAssertNil(store.studyState, "a response from the prior login must not populate current state")
    }

    func testPendingAnswerIsNotSentOrRemovedAfterRelogin() async throws {
        let session = AuthSession(accessToken: "fiction-a", refreshToken: "refresh-a", email: "retry-race@example.test", userID: "stable-user")
        let service = LearningRaceAuthService(session: session)
        let auth = AuthSessionStore(service: service)
        let store = LearningStore(auth: auth, supportDirectory: isolatedDirectory())
        LearningRaceURLProtocol.handler = { request in
            (self.response(request, status: 500), Data("{}".utf8))
        }
        defer { store.clearUserScopedData() }
        let question = try JSONDecoder().decode(TextbookQuestion.self, from: Data(#"{"id":"q1","lessonId":1,"type":"选择","prompt":"p","answer":"a","hint":"h"}"#.utf8))
        let evaluation = LocalEvaluation(verdict: "correct", isCorrect: true, expectedAnswer: "a", feedback: "ok", errorTags: [], knowledgeTags: [])
        let submitted = await store.submit(AnswerSubmission(question: question, answer: "a", evaluation: evaluation, mode: "lesson"))
        XCTAssertTrue(submitted)
        XCTAssertEqual(store.pendingCount, 1)

        let arrived = expectation(description: "answer request arrived")
        let release = DispatchSemaphore(value: 0)
        LearningRaceURLProtocol.handler = { request in
            arrived.fulfill()
            _ = release.wait(timeout: .now() + 5)
            return (self.response(request), Data(#"{"duplicate":true}"#.utf8))
        }
        let retry = Task { await store.retryPending() }
        await fulfillment(of: [arrived], timeout: 5)
        await auth.signIn(email: "retry-race@example.test", password: "fiction")
        release.signal()
        await retry.value

        XCTAssertEqual(store.pendingCount, 1, "an answer acknowledged under a prior login must remain queued")
    }

    func testAtomicMistakeVersionIsCapturedWhenAnswerIsQueued() async throws {
        let root = isolatedDirectory()
        let session = AuthSession(accessToken: "token", refreshToken: "refresh", email: "atomic@example.test", userID: "atomic-user")
        let auth = AuthSessionStore(service: LearningRaceAuthService(session: session))
        let store = LearningStore(auth: auth, supportDirectory: root)
        let atomicState = Data(#"{"textbookId":"builtin-japanese-syntax","textbookScopeAvailable":true,"dueQuestionIds":[],"lessons":[],"knowledgePoints":[],"metrics":{"totalAttempts":0,"incorrectAttempts":0,"errorRate":0,"forgettingRate":0,"correctStreak":0,"topErrorTags":[]},"mistakeStateAvailable":true,"mistakeStates":[]}"#.utf8)
        LearningRaceURLProtocol.handler = { request in
            if request.url?.path.hasSuffix("/api/study-state") == true {
                return (self.response(request), atomicState)
            }
            return (self.response(request, status: 500), Data("{}".utf8))
        }
        defer { store.clearUserScopedData() }
        await store.loadStudyState()
        let question = try JSONDecoder().decode(TextbookQuestion.self, from: Data(#"{"id":"L01-Q001","lessonId":1,"type":"选择","prompt":"p","answer":"a","hint":"h"}"#.utf8))
        let evaluation = LocalEvaluation(verdict: "incorrect", isCorrect: false, expectedAnswer: "a", feedback: "retry", errorTags: [], knowledgeTags: [])

        let saved = await store.submit(AnswerSubmission(question: question, answer: "b", evaluation: evaluation, mode: "lesson"))
        XCTAssertTrue(saved)
        let hash = SHA256.hash(data: Data("atomic-user".utf8)).map { String(format: "%02x", $0) }.joined()
        let queueURL = root.appendingPathComponent("JapaneseSyntaxCoach/Learning/answer-queue-user-v1-\(hash).json")
        let queued = try XCTUnwrap(JSONDecoder().decode([PendingAnswer].self, from: Data(contentsOf: queueURL)).first)
        XCTAssertEqual(queued.expectedMistakeVersion, 0)
    }

    func testInvalidAtomicStudyStateDoesNotReplaceCachedStateOrReportSynced() async throws {
        let root = isolatedDirectory()
        let userID = "invalid-atomic-user"
        let hash = SHA256.hash(data: Data(userID.utf8)).map { String(format: "%02x", $0) }.joined()
        let directory = root.appendingPathComponent("JapaneseSyntaxCoach/Learning", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let cacheURL = directory.appendingPathComponent("study-state-user-v1-\(hash).json")
        try Self.studyState.write(to: cacheURL)
        let cached = try JSONDecoder().decode(StudyState.self, from: Self.studyState)
        let session = AuthSession(accessToken: "token", refreshToken: "refresh", email: "invalid-atomic@example.test", userID: userID)
        let auth = AuthSessionStore(service: LearningRaceAuthService(session: session))
        let store = LearningStore(auth: auth, supportDirectory: root)
        let originalCache = try Data(contentsOf: cacheURL)
        let invalidAtomicState = Data(#"{"textbookId":"builtin-japanese-syntax","textbookScopeAvailable":true,"dueQuestionIds":[],"lessons":[],"knowledgePoints":[],"metrics":{"totalAttempts":0,"incorrectAttempts":0,"errorRate":0,"forgettingRate":0,"correctStreak":0,"topErrorTags":[]},"mistakeStateAvailable":true,"mistakeStates":[{"questionId":"unknown-question","isMistake":true,"version":1}]}"#.utf8)
        LearningRaceURLProtocol.handler = { request in (self.response(request), invalidAtomicState) }
        defer { store.clearUserScopedData() }

        await store.loadStudyState()

        XCTAssertEqual(store.studyState, cached)
        XCTAssertTrue(store.isShowingCachedStudyState)
        XCTAssertEqual(try Data(contentsOf: cacheURL), originalCache)
        guard case .error = store.syncState else { return XCTFail("invalid atomic state must not report synced") }
        XCTAssertTrue(store.pendingCountIsKnown)
    }

    func testLegacyEmailFilesRemainUntouchedAndSameEmailUsersAreIsolated() async throws {
        let root = isolatedDirectory()
        let directory = root.appendingPathComponent("JapaneseSyntaxCoach/Learning", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let email = "same@example.test"
        let hash = SHA256.hash(data: Data(email.utf8)).map { String(format: "%02x", $0) }.joined()
        let legacyQueue = directory.appendingPathComponent("answer-queue-\(hash).json")
        let legacyCache = directory.appendingPathComponent("study-state-\(hash).json")
        let sentinel = Data("legacy data must remain untouched".utf8)
        try sentinel.write(to: legacyQueue)
        try sentinel.write(to: legacyCache)
        let service = LearningRaceAuthService(session: AuthSession(accessToken: "a", refreshToken: "r", email: email, userID: "user-a"))
        let auth = AuthSessionStore(service: service)
        let store = LearningStore(auth: auth, supportDirectory: root)
        LearningRaceURLProtocol.handler = { request in (self.response(request, status: 500), Data("{}".utf8)) }
        let question = try JSONDecoder().decode(TextbookQuestion.self, from: Data(#"{"id":"q1","lessonId":1,"type":"选择","prompt":"p","answer":"a","hint":"h"}"#.utf8))
        let evaluation = LocalEvaluation(verdict: "correct", isCorrect: true, expectedAnswer: "a", feedback: "ok", errorTags: [], knowledgeTags: [])
        let saved = await store.submit(AnswerSubmission(question: question, answer: "a", evaluation: evaluation, mode: "lesson"))
        XCTAssertTrue(saved)
        XCTAssertEqual(store.pendingCount, 1)
        service.currentSession = AuthSession(accessToken: "b", refreshToken: "r", email: email, userID: "user-b")
        await auth.signIn(email: email, password: "fiction")
        XCTAssertEqual(store.pendingCount, 0)
        XCTAssertNil(store.studyState)
        XCTAssertEqual(try Data(contentsOf: legacyQueue), sentinel)
        XCTAssertEqual(try Data(contentsOf: legacyCache), sentinel)
    }

    func testMissingUserIDFailsClosed() async throws {
        let session = AuthSession(accessToken: "a", refreshToken: "r", email: "missing@example.test", userID: "  ")
        let auth = AuthSessionStore(service: LearningRaceAuthService(session: session))
        let store = LearningStore(auth: auth, supportDirectory: isolatedDirectory())
        let question = try JSONDecoder().decode(TextbookQuestion.self, from: Data(#"{"id":"q1","lessonId":1,"type":"选择","prompt":"p","answer":"a","hint":"h"}"#.utf8))
        let evaluation = LocalEvaluation(verdict: "correct", isCorrect: true, expectedAnswer: "a", feedback: "ok", errorTags: [], knowledgeTags: [])
        let saved = await store.submit(AnswerSubmission(question: question, answer: "a", evaluation: evaluation, mode: "lesson"))
        XCTAssertFalse(saved)
        XCTAssertEqual(store.pendingCount, 0)
        XCTAssertNil(store.studyState)
    }

    private func isolatedDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("LearningStoreTests-\(UUID().uuidString)", isDirectory: true)
    }

    private func response(_ request: URLRequest, status: Int = 200) -> HTTPURLResponse {
        HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
    }

    private static let studyState = Data(#"{"textbookId":"builtin-japanese-syntax","textbookScopeAvailable":true,"dueQuestionIds":[],"lessons":[],"knowledgePoints":[],"metrics":{"totalAttempts":0,"incorrectAttempts":0,"errorRate":0,"forgettingRate":0,"correctStreak":0,"topErrorTags":[]}}"#.utf8)
}

@MainActor
private final class LearningRaceAuthService: @preconcurrency AuthService {
    var currentSession: AuthSession?
    init(session: AuthSession) { currentSession = session }
    func authStateChanges() -> AsyncStream<AuthStateEvent> { AsyncStream { $0.finish() } }
    func signIn(email: String, password: String) async throws -> AuthSession { try XCTUnwrap(currentSession) }
    func signUp(email: String, password: String, redirectTo: URL) async throws -> AuthSignupResult { .confirmationRequired }
    func verifySignupCode(email: String, code: String, redirectTo: URL) async throws -> AuthSession { try XCTUnwrap(currentSession) }
    func requestPasswordReset(email: String, redirectTo: URL) async throws {}
    func exchangeCallback(url: URL) async throws -> AuthSession { try XCTUnwrap(currentSession) }
    func signInWithApple(idToken: String, nonce: String?) async throws -> AuthSession { try XCTUnwrap(currentSession) }
    func refreshSession() async throws -> AuthSession { try XCTUnwrap(currentSession) }
    func signOut() async throws { currentSession = nil }
}

private final class LearningRaceURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) -> (HTTPURLResponse, Data))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let client, let handler = Self.handler else { return }
        let (response, data) = handler(request)
        client.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client.urlProtocol(self, didLoad: data)
        client.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
