import Foundation
import Supabase
import XCTest
@testable import JapaneseSyntaxCoach

private final class DualClientMemoryStorage: AuthLocalStorage, @unchecked Sendable {
    private var values: [String: Data] = [:]
    private let lock = NSLock()

    func store(key: String, value: Data) throws {
        lock.lock(); defer { lock.unlock() }
        values[key] = value
    }
    func retrieve(key: String) throws -> Data? {
        lock.lock(); defer { lock.unlock() }
        return values[key]
    }
    func remove(key: String) throws {
        lock.lock(); defer { lock.unlock() }
        values.removeValue(forKey: key)
    }
}

final class DualClientLabTests: XCTestCase {
    private func environment() throws -> (SupabaseClient, URL, String, String) {
        let values = ProcessInfo.processInfo.environment
        guard let authURL = URL(string: values["LOCAL_DUAL_AUTH_URL"] ?? ""),
              let webURL = URL(string: values["LOCAL_DUAL_WEB_URL"] ?? ""),
              let key = values["LOCAL_DUAL_ANON_KEY"], !key.isEmpty,
              let email = values["LOCAL_DUAL_EMAIL"], !email.isEmpty,
              let password = values["LOCAL_DUAL_PASSWORD"], !password.isEmpty else {
            throw XCTSkip("Local dual-client backend credentials are not set")
        }
        guard authURL.absoluteString == "http://127.0.0.1:54351",
              webURL.absoluteString == "http://127.0.0.1:3219" else {
            throw NSError(domain: "DualClientLabTests", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Dual-client lab must use its fixed loopback endpoints"])
        }
        let client = SupabaseClient(
            supabaseURL: authURL,
            supabaseKey: key,
            options: SupabaseClientOptions(auth: .init(
                storage: DualClientMemoryStorage(), redirectToURL: AppConfiguration.authCallbackURL,
                storageKey: "local-dual-client", flowType: .implicit, autoRefreshToken: false
            ))
        )
        return (client, webURL, email, password)
    }

    @MainActor
    func testInjectedLearningBaseURLIsUsedForSnapshotAndAnswerRequests() async throws {
        let (client, webURL, email, password) = try environment()
        let auth = AuthSessionStore(service: SupabaseAuthServiceLive(client: client), restoreSession: false)
        await auth.signIn(email: email, password: password)
        XCTAssertEqual(auth.phase, .signedIn, auth.errorMessage ?? "Login failed")
        let session = URLSession.shared
        let store = LearningStore(auth: auth, supportDirectory: isolatedDirectory(), apiSession: session, apiBaseURL: webURL)
        defer { store.clearUserScopedData() }
        await store.loadStudyState()
        XCTAssertNotNil(store.studyState)
        XCTAssertNil(store.textbookError)
    }

    @MainActor
    func testRealAnswerReplayClearsMistakeAndConflictKeepsQueue() async throws {
        let (client, webURL, email, password) = try environment()
        let auth = AuthSessionStore(service: SupabaseAuthServiceLive(client: client), restoreSession: false)
        await auth.signIn(email: email, password: password)
        XCTAssertEqual(auth.phase, .signedIn, auth.errorMessage ?? "Login failed")

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [DualClientFaultURLProtocol.self]
        let webSession = URLSession(configuration: configuration)
        let store = LearningStore(auth: auth, supportDirectory: isolatedDirectory(), apiSession: webSession, apiBaseURL: webURL)
        defer {
            store.clearUserScopedData()
            webSession.invalidateAndCancel()
            DualClientFaultURLProtocol.failNextRecord = false
        }

        await store.loadStudyState()
        XCTAssertNotNil(store.studyState)
        let question = try XCTUnwrap(store.textbook?.questions.first(where: { $0.id == "L01-Q002" }))
        let initialVersion = try XCTUnwrap(store.studyState?.mistakeVersion(for: question.id))
        let incorrect = LocalEvaluation(verdict: "incorrect", isCorrect: false, expectedAnswer: question.answer, feedback: "retry", errorTags: ["lab"], knowledgeTags: [])

        DualClientFaultURLProtocol.failNextRecord = true
        let queuedOffline = await store.submit(AnswerSubmission(question: question, answer: "lab offline attempt", evaluation: incorrect, mode: "new"))
        XCTAssertTrue(queuedOffline)
        XCTAssertEqual(store.pendingCount, 1, "a real transport failure must leave the answer on disk")

        await store.retryPending()
        XCTAssertEqual(store.pendingCount, 0, "real server confirmation should remove the replayed answer")
        XCTAssertEqual(store.studyState?.mistakeVersion(for: question.id), initialVersion + 1)
        XCTAssertEqual(store.studyState?.mistakeQuestions(in: try XCTUnwrap(store.textbook))?.map(\.id), [question.id])

        let correct = LocalEvaluation(verdict: "correct", isCorrect: true, expectedAnswer: question.answer, feedback: "ok", errorTags: [], knowledgeTags: [])
        let clearedMistake = await store.submit(AnswerSubmission(question: question, answer: question.answer, evaluation: correct, mode: "mistakes"))
        XCTAssertTrue(clearedMistake)
        XCTAssertEqual(store.pendingCount, 0)
        XCTAssertEqual(store.studyState?.mistakeVersion(for: question.id), initialVersion + 2)
        XCTAssertEqual(store.studyState?.mistakeQuestions(in: try XCTUnwrap(store.textbook))?.map(\.id), [])

        let token = try XCTUnwrap(auth.session?.accessToken)
        var competingRequest = URLRequest(url: webURL.appendingPathComponent("api/record-answer"))
        competingRequest.httpMethod = "POST"
        competingRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        competingRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        competingRequest.httpBody = try JSONSerialization.data(withJSONObject: [
            "textbookId": "builtin-japanese-syntax", "questionId": question.id, "lessonId": question.lessonId,
            "questionLimit": 20, "answer": "competing write", "correct": false, "verdict": "incorrect",
            "errorTags": ["lab"], "knowledgeTags": [], "mode": "new", "clientRequestId": "dual-compete-\(UUID().uuidString)",
            "expectedMistakeVersion": initialVersion + 2,
        ])
        let (_, competingResponse) = try await URLSession.shared.data(for: competingRequest)
        XCTAssertEqual((competingResponse as? HTTPURLResponse)?.statusCode, 200)

        let conflictQueued = await store.submit(AnswerSubmission(question: question, answer: "stale version", evaluation: incorrect, mode: "new"))
        XCTAssertTrue(conflictQueued)
        XCTAssertEqual(store.pendingCount, 1, "a 409 version conflict must keep the queued answer")
        guard case .error(let message) = store.syncState else { return XCTFail("expected a visible version conflict") }
        XCTAssertTrue(message.contains("版本冲突"))
    }

    @MainActor
    func testSameVersionRaceReleasesWebAndLearningStoreTogether() async throws {
        let (client, webURL, email, password) = try environment()
        guard let gateURL = URL(string: ProcessInfo.processInfo.environment["LOCAL_DUAL_GATE_URL"] ?? ""),
              let resultPath = ProcessInfo.processInfo.environment["LOCAL_DUAL_RACE_RESULT"] else {
            throw XCTSkip("Concurrent race gate is available only in --cross-client mode")
        }
        let auth = AuthSessionStore(service: SupabaseAuthServiceLive(client: client), restoreSession: false)
        await auth.signIn(email: email, password: password)
        XCTAssertEqual(auth.phase, .signedIn, auth.errorMessage ?? "Login failed")
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [DualClientRaceURLProtocol.self]
        let session = URLSession(configuration: configuration)
        DualClientRaceURLProtocol.reset()
        let store = LearningStore(auth: auth, supportDirectory: isolatedDirectory(), apiSession: session, apiBaseURL: webURL)
        defer { store.clearUserScopedData(); session.invalidateAndCancel() }
        await store.loadStudyState()
        let textbook = try XCTUnwrap(store.textbook)
        let question = try XCTUnwrap(textbook.questions.first(where: { $0.id == "L01-Q008" }))
        XCTAssertEqual(store.studyState?.mistakeVersion(for: question.id), 0)
        let incorrect = LocalEvaluation(verdict: "incorrect", isCorrect: false, expectedAnswer: question.answer, feedback: "retry", errorTags: ["lab-race"], knowledgeTags: [])
        let submission = AnswerSubmission(question: question, answer: "concurrent iOS answer", evaluation: incorrect, mode: "new")
        var gateRequest = URLRequest(url: gateURL.appendingPathComponent("ready/ios"))
        gateRequest.httpMethod = "POST"
        let (_, gateResponse) = try await URLSession.shared.data(for: gateRequest)
        XCTAssertEqual((gateResponse as? HTTPURLResponse)?.statusCode, 204)
        let submitted = await store.submit(submission)
        XCTAssertTrue(submitted)
        let result = try XCTUnwrap(DualClientRaceURLProtocol.result())
        XCTAssertEqual(result.status, 409)
        XCTAssertEqual(store.pendingCount, 1)
        guard case .error(let message) = store.syncState else { return XCTFail("expected a visible version conflict") }
        XCTAssertTrue(message.contains("版本冲突"))
        let data = try JSONSerialization.data(withJSONObject: ["status": result.status, "start": result.start, "end": result.end])
        try data.write(to: URL(fileURLWithPath: resultPath), options: .atomic)
    }

    @MainActor
    func testBrowserCreatedMistakeCanBeClearedByLearningStore() async throws {
        let (client, webURL, email, password) = try environment()
        let auth = AuthSessionStore(service: SupabaseAuthServiceLive(client: client), restoreSession: false)
        await auth.signIn(email: email, password: password)
        XCTAssertEqual(auth.phase, .signedIn, auth.errorMessage ?? "Login failed")
        let store = LearningStore(auth: auth, supportDirectory: isolatedDirectory(), apiBaseURL: webURL)
        defer { store.clearUserScopedData() }
        await store.loadStudyState()
        let textbook = try XCTUnwrap(store.textbook)
        guard let markerPath = ProcessInfo.processInfo.environment["LOCAL_DUAL_QUESTION_MARKER"] else {
            throw XCTSkip("Cross-client mistake marker is supplied only by --cross-client")
        }
        let questionId = try String(contentsOfFile: markerPath, encoding: .utf8)
        XCTAssertEqual(store.studyState?.mistakeQuestions(in: textbook)?.map(\.id), [questionId])
        let question = try XCTUnwrap(textbook.questions.first(where: { $0.id == questionId }))
        let correct = LocalEvaluation(verdict: "correct", isCorrect: true, expectedAnswer: question.answer, feedback: "ok", errorTags: [], knowledgeTags: [])
        let cleared = await store.submit(AnswerSubmission(question: question, answer: question.answer, evaluation: correct, mode: "mistakes"))
        XCTAssertTrue(cleared)
        XCTAssertEqual(store.pendingCount, 0)
        XCTAssertEqual(store.studyState?.mistakeVersion(for: question.id), 2)
        XCTAssertEqual(store.studyState?.mistakeQuestions(in: textbook)?.map(\.id), [])
    }

    @MainActor
    func testRealAuthSignOutAndSessionRestore() async throws {
        let (client, _, email, password) = try environment()
        let service = SupabaseAuthServiceLive(client: client)
        let auth = AuthSessionStore(service: service, restoreSession: false)
        await auth.signIn(email: email, password: "incorrect-dual-client-password")
        XCTAssertEqual(auth.phase, .error)
        await auth.signIn(email: email, password: password)
        XCTAssertEqual(auth.phase, .signedIn, auth.errorMessage ?? "Retry login failed")
        let userID = auth.session?.userID
        await auth.signOut()
        XCTAssertEqual(auth.phase, .signedOut)
        XCTAssertNil(auth.session)
        await auth.signIn(email: email, password: password)
        XCTAssertEqual(auth.session?.userID, userID)
        let restored = AuthSessionStore(service: service)
        XCTAssertEqual(restored.session?.userID, userID)
    }

    private func isolatedDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("DualClientLearning-\(UUID().uuidString)", isDirectory: true)
    }
}

private final class DualClientRaceURLProtocol: URLProtocol {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var observation: (status: Int, start: Double, end: Double)?

    static func reset() { lock.lock(); defer { lock.unlock() }; observation = nil }
    static func result() -> (status: Int, start: Double, end: Double)? {
        lock.lock(); defer { lock.unlock() }; return observation
    }
    private static func record(status: Int, start: Double, end: Double) {
        lock.lock(); defer { lock.unlock() }; observation = (status, start, end)
    }
    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.path == "/api/record-answer"
    }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let currentRequest = request
        Task {
            let start = Date().timeIntervalSince1970 * 1000
            do {
                let (data, response) = try await URLSession.shared.data(for: currentRequest)
                let end = Date().timeIntervalSince1970 * 1000
                if let http = response as? HTTPURLResponse { Self.record(status: http.statusCode, start: start, end: end) }
                guard let client else { return }
                client.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client.urlProtocol(self, didLoad: data)
                client.urlProtocolDidFinishLoading(self)
            } catch {
                client?.urlProtocol(self, didFailWithError: error)
            }
        }
    }
    override func stopLoading() {}
}

private final class DualClientFaultURLProtocol: URLProtocol {
    nonisolated(unsafe) static var failNextRecord = false
    private static let lock = NSLock()

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        if request.url?.path.hasSuffix("/api/record-answer") == true {
            Self.lock.lock()
            let shouldFail = Self.failNextRecord
            Self.failNextRecord = false
            Self.lock.unlock()
            if shouldFail {
                client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
                return
            }
        }
        let currentRequest = request
        Task {
            do {
                let (data, response) = try await URLSession.shared.data(for: currentRequest)
                guard let client else { return }
                client.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client.urlProtocol(self, didLoad: data)
                client.urlProtocolDidFinishLoading(self)
            } catch {
                client?.urlProtocol(self, didFailWithError: error)
            }
        }
    }

    override func stopLoading() {}
}
