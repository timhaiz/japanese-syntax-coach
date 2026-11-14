import Foundation
import SwiftUI
import UIKit
import XCTest
@testable import JapaneseSyntaxCoach

/// Home refresh must not let an empty pending queue rewrite a failed study-state read as synced.
///
/// Both home entries call `HomeView.refresh(_:)`, so this exercises the production call sequence
/// against a real `LearningStore`. Network is intercepted only to put the store into the states
/// the bug depends on.
@MainActor
final class HomeRefreshTests: XCTestCase {
    override func setUp() {
        super.setUp()
        HomeRefreshURLProtocol.reset()
    }

    override func tearDown() {
        HomeRefreshURLProtocol.reset()
        super.tearDown()
    }

    func testFreeTextbookCardsExposeMetadataAndFreeOnlyContent() {
        let expected = [
            ("shin-standard-japanese-beginner-lower", "新版标准日本语 初级下册", 24, 480),
            ("shin-standard-japanese-intermediate-upper", "新版标准日本语 中级上册", 16, 320),
            ("shin-standard-japanese-intermediate-lower", "新版标准日本语 中级下册", 16, 320)
        ]

        XCTAssertEqual(FreeTextbookCatalog.items.count, expected.count)
        for (descriptor, expected) in zip(FreeTextbookCatalog.items, expected) {
            let card = FreeTextbookCardPresentation.make(descriptor: descriptor, state: .available)
            XCTAssertEqual(card.id, expected.0)
            XCTAssertEqual(card.title, expected.1)
            XCTAssertEqual(card.lessonCount, expected.2)
            XCTAssertEqual(card.questionCount, expected.3)
            XCTAssertEqual(card.freeLabel, "免费教材")
            let renderedText = card.renderedTexts.joined(separator: "|")
            for forbidden in ["购买", "价格", "¥", "￥", "$"] {
                XCTAssertFalse(renderedText.contains(forbidden), "卡片渲染文案包含禁止元素：\(forbidden)")
            }
        }
    }

    func testFreeTextbookCardActionsBindToEachState() {
        let descriptor = FreeTextbookCatalog.items[0]
        XCTAssertEqual(FreeTextbookCardPresentation.make(descriptor: descriptor, state: .available).actionTitle, "免费下载")
        XCTAssertFalse(FreeTextbookCardPresentation.make(descriptor: descriptor, state: .available).isActionDisabled)
        XCTAssertEqual(FreeTextbookCardPresentation.make(descriptor: descriptor, state: .downloading).actionTitle, "下载中…")
        XCTAssertTrue(FreeTextbookCardPresentation.make(descriptor: descriptor, state: .downloading).isActionDisabled)
        XCTAssertEqual(FreeTextbookCardPresentation.make(descriptor: descriptor, state: .downloaded).actionTitle, "继续学习")
        XCTAssertEqual(FreeTextbookCardPresentation.make(descriptor: descriptor, state: .failed("network")).actionTitle, "重试")
        XCTAssertFalse(FreeTextbookCardPresentation.make(descriptor: descriptor, state: .failed("network")).isActionDisabled)
    }

    func testFailedStudyStateReadKeepsErrorWhenNothingIsPending() async throws {
        let store = try makeSignedInStore(email: "home-refresh-empty@example.com")
        try await primeConfirmedStudyState(store)

        HomeRefreshURLProtocol.handler = { request in
            XCTAssertTrue(request.url?.path.contains("api/study-state") == true)
            return (self.httpResponse(for: request, statusCode: 500), Data("{}".utf8))
        }

        await HomeView.refresh(store)

        XCTAssertEqual(store.pendingCount, 0)
        XCTAssertFalse(store.isShowingCachedStudyState)
        guard case .error = store.syncState else {
            XCTFail("empty pending queue rewrote the failed read as \(store.syncState)")
            return
        }
    }

    func testFailedStudyStateReadStillRetriesQueuedAnswers() async throws {
        let store = try makeSignedInStore(email: "home-refresh-queued@example.com")
        try await primeConfirmedStudyState(store)
        try await seedPendingAnswer(store)

        var requestedPaths: [String] = []
        var writeConfirmed = false
        HomeRefreshURLProtocol.handler = { request in
            let path = request.url?.path ?? ""
            requestedPaths.append(path)
            if path.contains("api/record-answer") {
                writeConfirmed = true
                return (self.httpResponse(for: request, statusCode: 200), Data(#"{"duplicate":true}"#.utf8))
            }
            // retryPending reloads study state after a confirmed write.
            let statusCode = writeConfirmed ? 200 : 500
            let body = writeConfirmed ? Self.studyStateData : Data("{}".utf8)
            return (self.httpResponse(for: request, statusCode: statusCode), body)
        }

        await HomeView.refresh(store)

        XCTAssertEqual(store.pendingCount, 0)
        XCTAssertTrue(requestedPaths.contains { $0.contains("api/record-answer") })
        XCTAssertEqual(store.syncState, .synced)
    }

    private func makeSignedInStore(email: String) throws -> LearningStore {
        let session = AuthSession(accessToken: "access", refreshToken: "refresh", email: email, userID: UUID().uuidString)
        let auth = AuthSessionStore(service: HomeRefreshAuthService(currentSession: session))
        XCTAssertEqual(auth.phase, .signedIn)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [HomeRefreshURLProtocol.self]
        let apiSession = URLSession(configuration: configuration)
        addTeardownBlock { apiSession.invalidateAndCancel() }
        let store = LearningStore(auth: auth, apiSession: apiSession)
        addTeardownBlock { @MainActor in store.clearUserScopedData() }
        return store
    }

    private func primeConfirmedStudyState(_ store: LearningStore) async throws {
        HomeRefreshURLProtocol.handler = { request in
            (self.httpResponse(for: request, statusCode: 200), Self.studyStateData)
        }
        await store.loadStudyState()
        XCTAssertNotNil(store.studyState)
        XCTAssertFalse(store.isShowingCachedStudyState)
        XCTAssertEqual(store.syncState, .synced)
    }

    private func seedPendingAnswer(_ store: LearningStore) async throws {
        HomeRefreshURLProtocol.handler = { request in
            XCTAssertTrue(request.url?.path.contains("api/record-answer") == true)
            return (self.httpResponse(for: request, statusCode: 500), Data("{}".utf8))
        }
        let question = try JSONDecoder().decode(
            TextbookQuestion.self,
            from: Data(#"{"id":"q1","lessonId":1,"type":"选择","prompt":"p","answer":"a","hint":"h"}"#.utf8)
        )
        let evaluation = LocalEvaluation(
            verdict: "correct",
            isCorrect: true,
            expectedAnswer: "a",
            feedback: "ok",
            errorTags: [],
            knowledgeTags: []
        )
        await store.submit(AnswerSubmission(question: question, answer: "a", evaluation: evaluation, mode: "lesson"))
        XCTAssertEqual(store.pendingCount, 1)
        guard case .error = store.syncState else {
            XCTFail("queued answer should remain pending after a failed sync, got \(store.syncState)")
            return
        }
    }

    private func httpResponse(for request: URLRequest, statusCode: Int) -> HTTPURLResponse {
        HTTPURLResponse(url: request.url!, statusCode: statusCode, httpVersion: nil, headerFields: nil)!
    }

    private static let studyStateData = Data(#"""
    {"textbookId":"builtin-japanese-syntax","textbookScopeAvailable":true,"dueQuestionIds":[],"lessons":[],"knowledgePoints":[],"metrics":{"totalAttempts":0,"incorrectAttempts":0,"errorRate":0,"forgettingRate":0,"correctStreak":0,"topErrorTags":[]}}
    """#.utf8)

    private static let richStudyStateData = Data(#"""
    {
      "textbookId": "builtin-japanese-syntax",
      "textbookScopeAvailable": true,
      "dueQuestionIds": ["L01-Q001", "L01-Q003"],
      "lessons": [
        {"lesson_id": 1, "answered_count": 20, "correct_count": 18, "completed_at": "2026-11-06T09:00:00Z"},
        {"lesson_id": 2, "answered_count": 6, "correct_count": 5, "completed_at": null}
      ],
      "knowledgePoints": [],
      "mistakeStateAvailable": true,
      "mistakeStates": [
        {"questionId": "L01-Q002", "isMistake": true, "version": 1},
        {"questionId": "L01-Q005", "isMistake": true, "version": 1}
      ],
      "metrics": {
        "totalAttempts": 42,
        "incorrectAttempts": 4,
        "errorRate": 0.095,
        "forgettingRate": 0.05,
        "correctStreak": 8,
        "topErrorTags": ["助词", "语序"]
      }
    }
    """#.utf8)

    func testRenderCoreScreensAtNativeDisplayResolution() async throws {
        let store = try makeSignedInStore(email: "screenshot-preview@example.com")
        HomeRefreshURLProtocol.handler = { request in
            (self.httpResponse(for: request, statusCode: 200), Self.richStudyStateData)
        }
        await store.loadStudyState()
        let textbook = try XCTUnwrap(store.textbook)
        let lesson2 = try XCTUnwrap(textbook.lessons.first(where: { $0.id == 2 }) ?? textbook.lessons.first)
        let lesson2Questions = LearningStore.orderedQuestions(for: lesson2.id, in: textbook)
        XCTAssertFalse(lesson2Questions.isEmpty)

        let windowScene = try XCTUnwrap(
            UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .first
        )
        let screenBounds = windowScene.screen.bounds
        let screenScale = windowScene.screen.scale
        let pixelWidth = Int((screenBounds.width * screenScale).rounded())
        let pixelHeight = Int((screenBounds.height * screenScale).rounded())

        let window = UIWindow(windowScene: windowScene)
        window.frame = screenBounds
        window.overrideUserInterfaceStyle = .light
        window.makeKeyAndVisible()
        addTeardownBlock {
            window.isHidden = true
            window.rootViewController = nil
        }

        func makeShell<Content: View>(selectedTab: Int, @ViewBuilder tabContent: () -> Content) -> some View {
            TabView(selection: .constant(selectedTab)) {
                tabContent()
                    .tabItem { Label("首页", systemImage: "house") }
                    .tag(0)
                NavigationStack { TextbookView(store: store) }
                    .tabItem { Label("课程", systemImage: "book") }
                    .tag(1)
                NavigationStack { MistakesView(store: store) }
                    .tabItem { Label("错题本", systemImage: "exclamationmark.bubble") }
                    .tag(2)
                NavigationStack { Text("我的") }
                    .tabItem { Label("我的", systemImage: "person.circle") }
                    .tag(3)
            }
            .tint(HomeVisualStyle.accent)
            .toolbarBackground(HomeVisualStyle.card, for: .tabBar)
            .toolbarBackground(.visible, for: .tabBar)
            .preferredColorScheme(.light)
        }

        let screens: [(name: String, view: AnyView)] = [
            (
                "01-home",
                AnyView(makeShell(selectedTab: 0) {
                    NavigationStack { HomeView(store: store) }
                })
            ),
            (
                "02-grammar-detail",
                AnyView(
                    TabView(selection: .constant(1)) {
                        NavigationStack { HomeView(store: store) }
                            .tabItem { Label("首页", systemImage: "house") }
                            .tag(0)
                        NavigationStack {
                            LessonGrammarDetailView(store: store, lesson: lesson2, questions: lesson2Questions)
                        }
                        .tabItem { Label("课程", systemImage: "book") }
                        .tag(1)
                        NavigationStack { MistakesView(store: store) }
                            .tabItem { Label("错题本", systemImage: "exclamationmark.bubble") }
                            .tag(2)
                        NavigationStack { Text("我的") }
                            .tabItem { Label("我的", systemImage: "person.circle") }
                            .tag(3)
                    }
                    .tint(HomeVisualStyle.accent)
                    .toolbarBackground(HomeVisualStyle.card, for: .tabBar)
                    .toolbarBackground(.visible, for: .tabBar)
                    .preferredColorScheme(.light)
                )
            ),
            (
                "03-course-list",
                AnyView(makeShell(selectedTab: 1) {
                    NavigationStack { HomeView(store: store) }
                })
            ),
            (
                "04-question-view",
                AnyView(
                    NavigationStack {
                        LessonView(store: store, lesson: lesson2, questions: lesson2Questions)
                    }
                    .tint(HomeVisualStyle.accent)
                    .preferredColorScheme(.light)
                )
            ),
            (
                "05-mistakes",
                AnyView(makeShell(selectedTab: 2) {
                    NavigationStack { HomeView(store: store) }
                })
            )
        ]

        let exportRoot = ProcessInfo.processInfo.environment["JSC_SCREENSHOT_EXPORT_DIR"]
            ?? (try? String(contentsOfFile: "/tmp/jsc-screenshot-export-dir.txt", encoding: .utf8))?
                .trimmingCharacters(in: .whitespacesAndNewlines)

        for item in screens {
            let host = UIHostingController(rootView: item.view)
            host.overrideUserInterfaceStyle = .light
            window.rootViewController = host
            window.layoutIfNeeded()
            try await Task.sleep(nanoseconds: 350_000_000)
            window.layoutIfNeeded()

            let format = UIGraphicsImageRendererFormat()
            format.scale = screenScale
            format.opaque = true
            let renderer = UIGraphicsImageRenderer(bounds: window.bounds, format: format)
            let image = renderer.image { _ in
                _ = window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }
            let cgImage = try XCTUnwrap(image.cgImage)
            XCTAssertEqual(cgImage.width, pixelWidth)
            XCTAssertEqual(cgImage.height, pixelHeight)

            let pngData = try XCTUnwrap(image.pngData())
            XCTAssertGreaterThan(pngData.count, 10_000)

            if let exportRoot, !exportRoot.isEmpty {
                let dirURL = URL(fileURLWithPath: exportRoot, isDirectory: true)
                try FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true)
                let filename = "\(item.name)-\(pixelWidth)x\(pixelHeight).png"
                try pngData.write(to: dirURL.appendingPathComponent(filename), options: .atomic)
            }
        }
    }

    func testCustomTextbookCatalogSwitchAndLocalProgressIsolation() async throws {
        let store = try makeSignedInStore(email: "textbook-switch@example.com")
        try await primeConfirmedStudyState(store)

        XCTAssertEqual(store.selectedTextbookId, "builtin-japanese-syntax")
        XCTAssertEqual(store.textbooks.count, 1)

        let customJSON = """
        {
          "id": "custom-n4-pack",
          "title": "大家的日语 进阶 N4",
          "shortTitle": "N4 · 进阶",
          "lessons": [
            {
              "id": 1,
              "title": "意向形与计划",
              "goal": "掌握动词意向形",
              "grammar": [
                {
                  "pattern": "～ようと思っています",
                  "meaning": "打算……",
                  "connection": "动词意向形＋と思っています",
                  "explanation": "表示持续的计划或打算",
                  "example": "来年日本へ留学しようと思っています。"
                }
              ],
              "questions": [
                {
                  "id": "C01-Q001",
                  "type": "翻译",
                  "prompt": "我打算明年去日本留学。",
                  "answer": "来年日本へ留学しようと思っています。",
                  "hint": "使用～ようと思っています"
                }
              ]
            },
            {
              "id": 2,
              "title": "授受表现",
              "goal": "掌握～てあげる／～てもらう",
              "grammar": [
                {
                  "pattern": "～てもらう",
                  "meaning": "请别人为自己做……",
                  "connection": "动词て形＋もらう",
                  "explanation": "表示受惠",
                  "example": "友達に本を貸してもらいました。"
                }
              ],
              "questions": [
                {
                  "id": "C02-Q001",
                  "type": "翻译",
                  "prompt": "我请朋友借给我书。",
                  "answer": "友達に本を貸してもらいました。",
                  "hint": "使用～てもらう"
                }
              ]
            }
          ]
        }
        """

        let imported = try store.importTextbook(from: customJSON)
        XCTAssertEqual(imported.id, "custom-n4-pack")
        XCTAssertEqual(store.selectedTextbookId, "custom-n4-pack")
        XCTAssertEqual(store.textbook?.title, "大家的日语 进阶 N4")
        XCTAssertEqual(store.textbooks.count, 2)
        XCTAssertTrue(store.isLessonUnlocked(1, in: imported))
        XCTAssertFalse(store.isLessonUnlocked(2, in: imported))

        let q1 = try XCTUnwrap(imported.questions.first(where: { $0.id == "C01-Q001" }))
        let wrongEval = LocalEvaluation(
            verdict: "needs_fix",
            isCorrect: false,
            expectedAnswer: q1.answer,
            feedback: "请检查句尾",
            errorTags: ["句尾"],
            knowledgeTags: []
        )
        let saved = await store.submit(AnswerSubmission(question: q1, answer: "来年日本へ行く", evaluation: wrongEval, mode: "lesson"))
        XCTAssertTrue(saved)
        // Custom textbook submissions are stored locally and do not pollute the builtin cloud queue
        XCTAssertEqual(store.pendingCount, 0)
        XCTAssertEqual(store.activeMistakeQuestions()?.map(\.id), ["C01-Q001"])
        XCTAssertTrue(store.isLessonUnlocked(2, in: imported))

        store.recordLessonCompletion(lessonId: 1, correct: 0, total: 1, mistakeQuestionIds: ["C01-Q001"], replayed: false)
        XCTAssertEqual(store.lessonSummary?.lessonId, 1)
        XCTAssertEqual(store.lessonSummary?.mistakeQuestionIds, ["C01-Q001"])

        // Switch back to builtin textbook and verify state restoration
        store.selectTextbook("builtin-japanese-syntax")
        XCTAssertEqual(store.selectedTextbookId, "builtin-japanese-syntax")
        XCTAssertEqual(store.textbook?.id, "builtin-japanese-syntax")
        XCTAssertNil(store.lessonSummary)
    }
}

@MainActor
private final class HomeRefreshAuthService: @preconcurrency AuthService {
    var currentSession: AuthSession?

    init(currentSession: AuthSession?) { self.currentSession = currentSession }

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

private final class HomeRefreshURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) -> (HTTPURLResponse, Data))?

    static func reset() { handler = nil }

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
