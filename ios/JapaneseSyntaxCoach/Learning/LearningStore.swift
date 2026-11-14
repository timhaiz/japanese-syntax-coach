import Combine
import CryptoKit
import Foundation
import SwiftUI

@MainActor
final class LearningStore: ObservableObject {
    @Published private(set) var textbook: Textbook?
    @Published private(set) var builtinTextbook: Textbook?
    @Published private(set) var availableTextbooks: [Textbook] = []
    @Published private(set) var customTextbooks: [Textbook] = []
    @Published private(set) var selectedTextbookId: String = "builtin-japanese-syntax"
    @Published private(set) var localProgressByTextbook: [String: LocalTextbookProgress] = [:]
    @Published var lessonSummary: LessonCompletionSummary?
    @Published private(set) var textbookError: String?
    @Published private(set) var studyState: StudyState?
    @Published private(set) var isShowingCachedStudyState = false
    @Published private(set) var pendingCount = 0
    @Published private(set) var pendingCountIsKnown = true
    @Published private(set) var hasPossibleLegacyQueue = false
    @Published private(set) var syncState: LearningSyncState = .notSignedIn

    var textbooks: [Textbook] {
        var result: [Textbook] = []
        if let builtinTextbook {
            result.append(builtinTextbook)
        } else if let textbook, textbook.isBuiltin {
            result.append(textbook)
        }
        for item in customTextbooks where !result.contains(where: { $0.id == item.id }) {
            result.append(item)
        }
        return result
    }

    var userEmail: String? {
        auth.userEmail
    }

    var learnerDisplayName: String {
        guard let email = auth.userEmail?.trimmingCharacters(in: .whitespacesAndNewlines), !email.isEmpty else {
            return "学习者"
        }
        return email.components(separatedBy: "@").first ?? email
    }

    private let auth: AuthSessionStore
    private let api: APIClient
    private let apiBaseURL: URL
    private var activeUserKey: String?
    private var activeAuthGeneration: AuthGenerationSnapshot?
    private var queue: OfflineAnswerQueue?
    private let fileManager: FileManager
    private let supportDirectoryOverride: URL?
    private var accountGeneration = UUID()
    private var authSubscription: AnyCancellable?

    init(
        auth: AuthSessionStore,
        fileManager: FileManager = .default,
        supportDirectory: URL? = nil,
        apiSession: URLSession = .shared,
        apiBaseURL: URL = AppConfiguration.webURL
    ) {
        self.auth = auth
        self.api = APIClient(session: apiSession, tokenProvider: auth)
        self.apiBaseURL = apiBaseURL
        self.fileManager = fileManager
        self.supportDirectoryOverride = supportDirectory
        authSubscription = auth.$session.sink { [weak self] session in
            guard let self else { return }
            self.activateAccount(session: session)
        }
    }

    func loadStudyState() async {
        loadTextbook()
        guard auth.phase == .signedIn, let session = auth.session, Self.accountKey(session.userID) != nil else {
            syncState = .notSignedIn
            return
        }
        activateAccount(session: session)
        guard activeUserKey != nil, let queue else { return }
        let deletionFrozen = queue.isDeletionFrozen
        refreshPendingCount(from: queue)
        guard !deletionFrozen else { return }

        let generation = accountGeneration
        let deletionEpoch = queue.deletionEpoch
        syncState = .loading
        let context: APIRequestContext
        do {
            guard let captured = try await api.requestContext() else {
                if generation == accountGeneration {
                    refreshPendingCount(from: queue)
                    syncState = .error("无法确认登录账号，云端学习进度未读取。")
                }
                return
            }
            guard generation == accountGeneration, isCurrent(captured) else { return }
            context = captured
        } catch {
            if generation == accountGeneration {
                refreshPendingCount(from: queue)
                syncState = .error("无法确认登录账号，云端学习进度未读取。")
            }
            return
        }
        do {
            let request = try makeStudyStateRequest()
            let confirmed: StudyState = try await api.request(request, boundTo: context)
            guard generation == accountGeneration, auth.phase == .signedIn, isCurrent(context) else { return }
            let becameFrozen = queue.isDeletionFrozen
            let currentDeletionEpoch = queue.deletionEpoch
            refreshPendingCount(from: queue)
            guard !becameFrozen, currentDeletionEpoch == deletionEpoch else { return }
            let canonicalTextbook = builtinTextbook ?? textbook
            guard confirmed.mistakeStateAvailable != true ||
                    (canonicalTextbook.map { confirmed.mistakeQuestions(in: $0) != nil } == true) else {
                syncState = pendingCountIsKnown
                    ? .error("云端原子错题状态无效，已保留现有学习进度。")
                    : .error("待同步队列无法读取，原文件已保留，请勿清除数据。")
                return
            }
            studyState = confirmed
            isShowingCachedStudyState = false
            refreshPendingCount(from: queue)
            persist(confirmed, to: studyStateURL)
            if !pendingCountIsKnown {
                syncState = .error("待同步队列无法读取，原文件已保留，请勿清除数据。")
            } else {
                syncState = pendingCount > 0 ? .pending : .synced
            }
        } catch {
            guard generation == accountGeneration, auth.phase == .signedIn, isCurrent(context) else { return }
            refreshPendingCount(from: queue)
            if studyState == nil { loadCachedStudyState() }
            if !pendingCountIsKnown {
                syncState = .error("待同步队列无法读取，原文件已保留，请勿清除数据。")
            } else {
                syncState = isOffline(error) ? .offline : .error("云端学习进度暂时无法读取。")
            }
        }
    }

    @discardableResult
    func submit(_ answer: AnswerSubmission) async -> Bool {
        guard auth.phase == .signedIn, let session = auth.session, Self.accountKey(session.userID) != nil else {
            syncState = .notSignedIn
            return false
        }
        activateAccount(session: session)
        loadTextbook()
        let activeTextbookId = textbook?.id ?? selectedTextbookId
        recordLocalProgress(for: activeTextbookId, submission: answer)
        if activeTextbookId != "builtin-japanese-syntax" {
            return true
        }
        guard let queue else {
            pendingCountIsKnown = false
            syncState = .error("答案无法保存到待同步队列，未上传，请保留答案并稍后重试。")
            return false
        }
        refreshPendingCount(from: queue)
        let expectedVersion: Int?
        if studyState?.mistakeStateAvailable == true {
            expectedVersion = nextMistakeVersion(for: answer.question.id, in: queue)
            guard let expectedVersion else {
                syncState = .error("原子错题状态不可用，答案未入队或上传。请先重新读取学习进度。")
                return false
            }
        } else {
            expectedVersion = nil
        }
        let item = answer.pendingAnswer(expectedMistakeVersion: expectedVersion)
        guard queue.enqueue(item) else {
            refreshPendingCount(from: queue)
            syncState = .error("答案无法保存到待同步队列，未上传，请保留答案并稍后重试。")
            return false
        }
        refreshPendingCount(from: queue)
        syncState = .pending
        await retryPending()
        return true
    }

    func retryPending() async {
        guard auth.phase == .signedIn, let session = auth.session, Self.accountKey(session.userID) != nil else {
            syncState = .notSignedIn
            return
        }
        activateAccount(session: session)
        guard let queue else {
            pendingCountIsKnown = false
            syncState = .error("待同步队列无法读取，原文件已保留，请勿清除数据。")
            return
        }
        refreshPendingCount(from: queue)
        guard pendingCountIsKnown else {
            syncState = .error("待同步队列无法读取，原文件已保留，请勿清除数据。")
            return
        }
        guard !queue.peek().isEmpty else {
            refreshPendingCount(from: queue)
            if studyState != nil { syncState = isShowingCachedStudyState ? .offline : .synced }
            return
        }

        let generation = accountGeneration
        let requestContext: APIRequestContext?
        do {
            requestContext = try await api.requestContext()
        } catch {
            if generation == accountGeneration { syncState = .error("无法确认登录账号，答案仍保留在待同步队列。") }
            return
        }
        guard generation == accountGeneration else { return }
        guard let context = requestContext, isCurrent(context) else {
            syncState = .error("无法确认登录账号，答案仍保留在待同步队列。")
            return
        }
        var submissionError: Error?
        let result = await queue.retry(shouldRemove: { [weak self] in
            guard let self else { return false }
            return generation == self.accountGeneration && self.isCurrent(context)
        }) { [weak self, api] item in
            guard let self, generation == self.accountGeneration, self.auth.phase == .signedIn,
                  self.isCurrent(context) else { return false }
            if self.studyState?.mistakeStateAvailable == true, item.expectedMistakeVersion == nil {
                submissionError = MistakeSyncError.legacyItemRequiresReview
                return false
            }
            self.syncState = .syncing
            do {
                let request = try makeRecordRequest(item)
                let response: RecordAnswerResponse = try await api.request(request, boundTo: context)
                guard generation == self.accountGeneration, self.auth.phase == .signedIn,
                      self.isCurrent(context) else { return false }
                return response.confirms(item)
            } catch {
                submissionError = error
                throw error
            }
        }
        guard generation == accountGeneration, auth.phase == .signedIn else { return }
        guard case let .completed(sentCount) = result else { return }
        refreshPendingCount(from: queue)
        if pendingCount > 0 {
            if let submissionError {
                syncState = retryErrorState(submissionError)
            } else {
                syncState = .error("服务器尚未确认写入，答案已保留，请重试。")
            }
            return
        }

        syncState = .synced
        if sentCount > 0 { await loadStudyState() }
    }

    private func nextMistakeVersion(for questionId: String, in queue: OfflineAnswerQueue) -> Int? {
        let canonical = builtinTextbook ?? textbook
        guard let canonical, studyState?.mistakeQuestions(in: canonical) != nil,
              canonical.questions.contains(where: { $0.id == questionId }) else { return nil }
        if let latest = queue.peek().last(where: { $0.questionId == questionId }) {
            guard let version = latest.expectedMistakeVersion, version < 9_007_199_254_740_991 else { return nil }
            return version + 1
        }
        guard let version = studyState?.mistakeVersion(for: questionId), version <= 9_007_199_254_740_991 else { return nil }
        return version
    }

    private func refreshPendingCount(from queue: OfflineAnswerQueue) {
        guard let count = queue.knownPendingCount else {
            pendingCountIsKnown = false
            return
        }
        pendingCountIsKnown = true
        pendingCount = count
    }

    private func retryErrorState(_ error: Error) -> LearningSyncState {
        if error as? MistakeSyncError == .legacyItemRequiresReview {
            return .error("队列中有旧答案缺少原子版本，已保留且不会自动写入。请人工核对后处理。")
        }
        switch LearningSyncFailure.classify(error) {
        case .offline: return .offline
        case let .message(message): return .error(message)
        }
    }

    private func activateAccount(session: AuthSession?) {
        guard let key = Self.accountKey(session?.userID) else {
            clearUserScopedData()
            return
        }
        hasPossibleLegacyQueue = legacyQueueExists(email: session?.email)
        let authGeneration = auth.generationSnapshot()
        guard key != activeUserKey || authGeneration != activeAuthGeneration else { return }

        accountGeneration = UUID()
        activeAuthGeneration = authGeneration
        activeUserKey = key
        queue = OfflineAnswerQueue(fileURL: queueURL(for: key))
        if let queue { refreshPendingCount(from: queue) }
        studyState = nil
        isShowingCachedStudyState = false
        lessonSummary = nil
        if queue?.isAvailable == false {
            syncState = .error("待同步队列无法读取，原文件已保留，请勿清除数据。")
        } else if pendingCount > 0 {
            syncState = .pending
        } else {
            syncState = .loading
        }
        loadTextbook()
        loadUserTextbookCatalogAndProgress()
        loadCachedStudyState()
    }

    func clearUserScopedData() {
        accountGeneration = UUID()
        activeUserKey = nil
        activeAuthGeneration = nil
        queue = nil
        pendingCount = 0
        pendingCountIsKnown = true
        hasPossibleLegacyQueue = false
        studyState = nil
        isShowingCachedStudyState = false
        customTextbooks = []
        selectedTextbookId = "builtin-japanese-syntax"
        localProgressByTextbook = [:]
        lessonSummary = nil
        if let builtinTextbook {
            textbook = builtinTextbook
        }
        syncState = .notSignedIn
    }

    func activateTextbook(id: String) {
        loadTextbook()
        guard let matched = (textbooks + availableTextbooks).first(where: { $0.id == id }) else { return }
        selectedTextbookId = matched.id
        textbook = matched
        lessonSummary = nil
        persist(matched.id, to: selectedTextbookURL)
    }

    func selectTextbook(_ id: String) {
        activateTextbook(id: id)
    }

    @discardableResult
    func importTextbook(from rawJSON: String) throws -> Textbook {
        loadTextbook()
        let imported = try TextbookImporter.parseTextbookPackageJSON(rawJSON)
        var updated = customTextbooks.filter { $0.id != imported.id }
        updated.insert(imported, at: 0)
        customTextbooks = updated
        selectedTextbookId = imported.id
        textbook = imported
        lessonSummary = nil
        persist(updated, to: customTextbooksURL)
        persist(imported.id, to: selectedTextbookURL)
        return imported
    }

    func textbookProgressPercent(for targetTextbook: Textbook) -> Int {
        let counts = targetTextbook.questionCountsPerLesson()
        let total = counts.reduce(0, +)
        guard total > 0 else { return 0 }
        let answered = targetTextbook.lessons.enumerated().reduce(0) { sum, item in
            let maxCount = counts[item.offset]
            let done = lessonAnsweredCount(for: item.element.id, in: targetTextbook)
            return sum + min(max(0, done), maxCount)
        }
        return min(100, Int((Double(answered) / Double(total) * 100.0).rounded()))
    }

    func textbookCompletedLessonCount(for targetTextbook: Textbook) -> Int {
        let completedSet = completedLessonIDs(in: targetTextbook)
        return targetTextbook.lessons.filter { completedSet.contains($0.id) }.count
    }

    func lessonAnsweredCount(for lessonId: Int, in targetTextbook: Textbook? = nil) -> Int {
        let resolved = targetTextbook ?? textbook
        guard let resolved else { return 0 }
        let localDone = localProgressByTextbook[resolved.id]?.lessonDone[lessonId] ?? 0
        if resolved.isBuiltin, let cloudDone = studyState?.lessons.first(where: { $0.lessonId == lessonId })?.answeredCount {
            return max(localDone, cloudDone)
        }
        return localDone
    }

    func lessonCorrectCount(for lessonId: Int, in targetTextbook: Textbook? = nil) -> Int {
        let resolved = targetTextbook ?? textbook
        guard let resolved else { return 0 }
        let localCorrect = localProgressByTextbook[resolved.id]?.lessonCorrect[lessonId] ?? 0
        if resolved.isBuiltin, let cloudCorrect = studyState?.lessons.first(where: { $0.lessonId == lessonId })?.correctCount {
            return max(localCorrect, cloudCorrect)
        }
        return localCorrect
    }

    func completedLessonIDs(in targetTextbook: Textbook? = nil) -> Set<Int> {
        let resolved = targetTextbook ?? textbook
        guard let resolved else { return [] }
        var ids = Set(localProgressByTextbook[resolved.id]?.completedLessonIds ?? [])
        if resolved.isBuiltin, let cloudLessons = studyState?.lessons {
            for item in cloudLessons where item.completedAt != nil {
                ids.insert(item.lessonId)
            }
        }
        for lesson in resolved.lessons {
            let maxQuestions = max(1, Self.orderedQuestions(for: lesson.id, in: resolved).count)
            if lessonAnsweredCount(for: lesson.id, in: resolved) >= maxQuestions {
                ids.insert(lesson.id)
            }
        }
        return ids
    }

    func lessonProgressPercent(for lessonId: Int, in targetTextbook: Textbook? = nil) -> Int {
        let resolved = targetTextbook ?? textbook
        guard let resolved else { return 0 }
        let total = max(1, Self.orderedQuestions(for: lessonId, in: resolved).count)
        let answered = min(total, lessonAnsweredCount(for: lessonId, in: resolved))
        return min(100, Int((Double(answered) / Double(total) * 100.0).rounded()))
    }

    func isLessonUnlocked(_ lessonId: Int, in targetTextbook: Textbook? = nil) -> Bool {
        let resolved = targetTextbook ?? textbook
        guard let resolved else { return true }
        guard let index = resolved.lessons.firstIndex(where: { $0.id == lessonId }) else { return true }
        if index == 0 { return true }
        let completed = completedLessonIDs(in: resolved)
        if completed.contains(lessonId) || lessonAnsweredCount(for: lessonId, in: resolved) > 0 {
            return true
        }
        let previousLessonId = resolved.lessons[index - 1].id
        return completed.contains(previousLessonId)
    }

    func activeCurrentLesson() -> TextbookLesson? {
        guard let textbook else { return nil }
        let completed = completedLessonIDs(in: textbook)
        return textbook.lessons.first { !completed.contains($0.id) } ?? textbook.lessons.last
    }

    func activeMistakeQuestions() -> [TextbookQuestion]? {
        guard let textbook else { return nil }
        if textbook.isBuiltin {
            if let cloudMistakes = studyState?.mistakeQuestions(in: textbook) {
                let localIds = localProgressByTextbook[textbook.id]?.mistakeQuestionIds ?? []
                if localIds.isEmpty { return cloudMistakes }
                var combined = cloudMistakes
                for id in localIds where !combined.contains(where: { $0.id == id }) {
                    if let q = textbook.questions.first(where: { $0.id == id }) {
                        combined.append(q)
                    }
                }
                return combined
            }
            if let local = localProgressByTextbook[textbook.id] {
                return local.mistakeQuestionIds.compactMap { id in
                    textbook.questions.first(where: { $0.id == id })
                }
            }
            return nil
        }
        let ids = localProgressByTextbook[textbook.id]?.mistakeQuestionIds ?? []
        return ids.compactMap { id in
            textbook.questions.first(where: { $0.id == id })
        }
    }

    func mixedPracticeQuestions(limit: Int = 20) -> [TextbookQuestion] {
        guard let textbook else { return [] }
        let completed = completedLessonIDs(in: textbook)
        var pool: [TextbookQuestion] = []
        if textbook.isBuiltin, let dueIds = studyState?.dueQuestionIds, !dueIds.isEmpty {
            let dueSet = Set(dueIds)
            pool.append(contentsOf: textbook.questions.filter { dueSet.contains($0.id) })
        }
        for lessonId in completed.sorted() {
            for q in Self.orderedQuestions(for: lessonId, in: textbook) where !pool.contains(where: { $0.id == q.id }) {
                pool.append(q)
            }
        }
        if pool.isEmpty, let firstLesson = textbook.lessons.first {
            pool = Self.orderedQuestions(for: firstLesson.id, in: textbook)
        }
        return Array(pool.prefix(max(1, limit)))
    }

    func dueReviewQuestions(limit: Int = 20) -> [TextbookQuestion] {
        guard let textbook, textbook.isBuiltin, let dueIds = studyState?.dueQuestionIds, !dueIds.isEmpty else {
            return []
        }
        let dueSet = Set(dueIds)
        let matched = textbook.questions.filter { dueSet.contains($0.id) }
        return Array(matched.prefix(max(1, limit)))
    }

    func recordLessonCompletion(
        lessonId: Int,
        correct: Int,
        total: Int,
        mistakeQuestionIds: [String],
        replayed: Bool
    ) {
        let activeId = textbook?.id ?? selectedTextbookId
        var progress = localProgressByTextbook[activeId] ?? LocalTextbookProgress()
        if !replayed, !progress.completedLessonIds.contains(lessonId) {
            progress.completedLessonIds.append(lessonId)
            progress.completedLessonIds.sort()
        }
        progress.lessonDone[lessonId] = max(progress.lessonDone[lessonId] ?? 0, total)
        progress.lessonCorrect[lessonId] = max(progress.lessonCorrect[lessonId] ?? 0, correct)
        localProgressByTextbook[activeId] = progress
        persist(localProgressByTextbook, to: localProgressURL)
        lessonSummary = LessonCompletionSummary(
            lessonId: lessonId,
            correct: correct,
            total: total,
            mistakeQuestionIds: mistakeQuestionIds,
            replayed: replayed
        )
    }

    func requestAIGrade(question: TextbookQuestion, answer: String) async -> AIGradeResponse? {
        guard let context = try? await api.requestContext() else { return nil }
        var request = URLRequest(url: apiBaseURL.appendingPathComponent("api/grade-answer"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let payload: [String: Any] = [
            "answer": answer,
            "standardAnswer": question.answer,
            "acceptedAnswers": question.acceptedAnswers ?? [],
            "hint": question.hint
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        return try? await api.request(request, boundTo: context)
    }

    func requestAIAnalysis(question: TextbookQuestion, answer: String) async -> AIAnalysisResponse {
        let payload: [String: String] = [
            "prompt": question.prompt,
            "answer": answer,
            "standardAnswer": question.answer,
            "hint": question.hint
        ]
        var request = URLRequest(url: apiBaseURL.appendingPathComponent("api/analyze-answer"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = auth.session?.accessToken, !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let httpStatus = (response as? HTTPURLResponse)?.statusCode ?? 200
            let contentType = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Type")?.lowercased() ?? ""
            if httpStatus >= 400 {
                if let decoded = try? JSONDecoder().decode(AIAnalysisResponse.self, from: data) {
                    return AIAnalysisResponse(
                        analysis: decoded.error ?? decoded.analysis ?? "AI 深度分析仅对会员开放。",
                        words: nil,
                        pitfalls: nil,
                        source: "membership",
                        memberRequired: decoded.memberRequired ?? (httpStatus == 401 || httpStatus == 403),
                        error: decoded.error
                    )
                }
                return AIAnalysisResponse(
                    analysis: httpStatus == 403 ? "AI 深度分析仅对会员开放。" : "AI 深度分析暂不可用。",
                    words: nil,
                    pitfalls: nil,
                    source: "membership",
                    memberRequired: httpStatus == 401 || httpStatus == 403,
                    error: nil
                )
            }
            if contentType.contains("text/event-stream"), let rawStream = String(data: data, encoding: .utf8) {
                var combinedDelta = ""
                for frame in rawStream.components(separatedBy: "\n\n") {
                    guard let dataLine = frame.components(separatedBy: "\n").first(where: { $0.hasPrefix("data: ") }) else {
                        continue
                    }
                    let jsonSlice = String(dataLine.dropFirst(6))
                    if let eventData = jsonSlice.data(using: .utf8),
                       let eventObj = try? JSONSerialization.jsonObject(with: eventData) as? [String: Any],
                       (eventObj["type"] as? String) == "delta",
                       let deltaText = eventObj["text"] as? String {
                        combinedDelta += deltaText
                    }
                }
                let cleaned = combinedDelta
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .replacingOccurrences(of: "^```(?:json)?\\s*", with: "", options: .regularExpression)
                    .replacingOccurrences(of: "\\s*```$", with: "", options: .regularExpression)
                if let finalData = cleaned.data(using: .utf8),
                   let parsed = try? JSONDecoder().decode(AIAnalysisResponse.self, from: finalData) {
                    return parsed
                }
            }
            if let decoded = try? JSONDecoder().decode(AIAnalysisResponse.self, from: data) {
                return decoded
            }
        } catch {
            // Fall through to local coaching fallback.
        }
        return AIAnalysisResponse(
            analysis: "AI 分析暂时不可用，请对照标准答案「\(question.answer)」拆分词语和句型记忆。提示：\(question.hint)",
            words: nil,
            pitfalls: nil,
            source: "fallback",
            memberRequired: false,
            error: nil
        )
    }

    private func recordLocalProgress(for textbookId: String, submission: AnswerSubmission) {
        var progress = localProgressByTextbook[textbookId] ?? LocalTextbookProgress()
        let limit = textbook.map { Self.orderedQuestions(for: submission.question.lessonId, in: $0).count } ?? 20
        progress.record(
            question: submission.question,
            isCorrect: submission.evaluation.isCorrect,
            errorTags: submission.evaluation.errorTags,
            mode: submission.mode,
            questionLimit: max(1, limit)
        )
        localProgressByTextbook[textbookId] = progress
        persist(localProgressByTextbook, to: localProgressURL)
    }

    private func loadUserTextbookCatalogAndProgress() {
        if let url = customTextbooksURL,
           let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode([Textbook].self, from: data) {
            customTextbooks = decoded
        } else {
            customTextbooks = []
        }

        if let url = localProgressURL,
           let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode([String: LocalTextbookProgress].self, from: data) {
            localProgressByTextbook = decoded
        } else {
            localProgressByTextbook = [:]
        }

        if let url = selectedTextbookURL,
           let data = try? Data(contentsOf: url),
           let savedId = try? JSONDecoder().decode(String.self, from: data),
           let matched = (textbooks + availableTextbooks).first(where: { $0.id == savedId }) {
            selectedTextbookId = matched.id
            textbook = matched
        } else {
            selectedTextbookId = "builtin-japanese-syntax"
            if let builtinTextbook {
                textbook = builtinTextbook
            }
        }
    }

    func deleteAccount() async throws {
        try await deleteAccountWhenSafe()
    }

    private func deleteAccountWhenSafe() async throws {
        guard auth.phase == .signedIn, let session = auth.session, Self.accountKey(session.userID) != nil else { throw LearningStoreError.notSignedIn }
        activateAccount(session: session)
        guard let key = activeUserKey, let queue else { throw LearningStoreError.queueUnavailable }
        guard let deletionToken = auth.session?.accessToken, !deletionToken.isEmpty else {
            throw LearningStoreError.notSignedIn
        }
        let deletion = AccountDeletionRequest()
        var request = URLRequest(url: apiBaseURL.appendingPathComponent("api/account/delete"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(deletion)
        switch queue.beginDeletion() {
        case .unavailable:
            throw queue.isDeletionFrozen ? LearningStoreError.deletionOutcomeUnknown : LearningStoreError.queueUnavailable
        case .pending: throw LearningStoreError.pendingAnswers
        case .inProgress: throw LearningStoreError.deletionInProgress
        case .acquired: break
        }
        accountGeneration = UUID()
        let generation = accountGeneration
        var leaseEnded = false
        defer {
            if !leaseEnded { _ = queue.endDeletion(unfreeze: false) }
        }
        let response: AccountDeleteResponse
        do {
            response = try await api.request(request, fixedBearerToken: deletionToken)
        } catch APIClientError.unauthorized {
            leaseEnded = true
            guard queue.endDeletion(unfreeze: true) else { throw LearningStoreError.deletionUnfreezeFailed }
            throw LearningStoreError.accountDeleteNotConfirmed
        } catch APIClientError.forbidden {
            leaseEnded = true
            guard queue.endDeletion(unfreeze: true) else { throw LearningStoreError.deletionUnfreezeFailed }
            throw LearningStoreError.accountDeleteNotConfirmed
        } catch {
            throw LearningStoreError.deletionOutcomeUnknown
        }
        guard response.deleted else {
            leaseEnded = true
            guard queue.endDeletion(unfreeze: true) else { throw LearningStoreError.deletionUnfreezeFailed }
            throw LearningStoreError.accountDeleteNotConfirmed
        }
        guard queue.clearEmptyQueueDuringDeletion(), removeUserFiles(for: key) else { throw LearningStoreError.queueCleanupFailed }
        leaseEnded = true
        guard queue.endDeletion(unfreeze: true) else { throw LearningStoreError.queueCleanupFailed }
        guard generation == accountGeneration, activeUserKey == key, auth.phase == .signedIn else {
            throw LearningStoreError.accountChanged
        }
        clearUserScopedData()
    }

    static func orderedQuestions(for lessonId: Int, in textbook: Textbook) -> [TextbookQuestion] {
        let order = ["选择": 0, "助词": 1, "翻译": 2, "问答": 3]
        return textbook.questions.enumerated()
            .filter { $0.element.lessonId == lessonId }
            .sorted { lhs, rhs in
                let leftOrder = order[lhs.element.type] ?? Int.max
                let rightOrder = order[rhs.element.type] ?? Int.max
                return leftOrder == rightOrder ? lhs.offset < rhs.offset : leftOrder < rightOrder
            }
            .prefix(20)
            .map(\.element)
    }

    private func loadTextbook() {
        if builtinTextbook == nil {
            do {
                let bundled = try TextbookRepository.loadBundled()
                builtinTextbook = bundled.textbook
                textbookError = nil
                persist(CachedTextbook(schemaVersion: bundled.schemaVersion, contentHash: bundled.contentHash, textbook: bundled.textbook), to: textbookURL)
            } catch {
                do {
                    let cached = try JSONDecoder().decode(CachedTextbook.self, from: Data(contentsOf: textbookURL))
                    builtinTextbook = cached.textbook
                    textbookError = nil
                } catch {
                    textbookError = "教材无法从安装包或本机缓存中读取。"
                }
            }
        }
        if availableTextbooks.isEmpty {
            availableTextbooks = FreeTextbookCatalog.items.compactMap { descriptor in
                try? TextbookRepository.loadBundled(id: descriptor.id).textbook
            }
        }
        if let matched = (textbooks + availableTextbooks).first(where: { $0.id == selectedTextbookId }) {
            textbook = matched
        } else {
            selectedTextbookId = builtinTextbook?.id ?? "builtin-japanese-syntax"
            textbook = builtinTextbook
        }
    }

    private func makeStudyStateRequest() throws -> URLRequest {
        let url = apiBaseURL.appendingPathComponent("api/study-state")
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw LearningStoreError.invalidURL
        }
        components.queryItems = [URLQueryItem(name: "textbookId", value: "builtin-japanese-syntax")]
        guard let requestURL = components.url else { throw LearningStoreError.invalidURL }
        return URLRequest(url: requestURL)
    }

    private func makeRecordRequest(_ item: PendingAnswer) throws -> URLRequest {
        var request = URLRequest(url: apiBaseURL.appendingPathComponent("api/record-answer"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(RecordAnswerRequest(item))
        return request
    }

    private func loadCachedStudyState() {
        guard studyState == nil, let url = studyStateURL,
              let data = try? Data(contentsOf: url),
              let cached = try? JSONDecoder().decode(StudyState.self, from: data) else { return }
        studyState = cached
        isShowingCachedStudyState = true
    }

    private func persist<T: Encodable>(_ value: T, to url: URL?) {
        guard let url, let data = try? JSONEncoder().encode(value) else { return }
        do {
            try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
        } catch {
            // Cloud and bundled content remain usable if local cache storage is unavailable.
        }
    }

    private var supportDirectory: URL {
        supportDirectoryOverride ?? (try? fileManager.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
            ?? fileManager.temporaryDirectory
    }

    private var textbookURL: URL {
        supportDirectory.appendingPathComponent("JapaneseSyntaxCoach", isDirectory: true)
            .appendingPathComponent("Learning", isDirectory: true)
            .appendingPathComponent("textbook-cache.json")
    }

    private var studyStateURL: URL? {
        guard let activeUserKey else { return nil }
        return supportDirectory.appendingPathComponent("JapaneseSyntaxCoach", isDirectory: true)
            .appendingPathComponent("Learning", isDirectory: true)
            .appendingPathComponent("study-state-\(activeUserKey).json")
    }

    private var customTextbooksURL: URL? {
        guard let activeUserKey else { return nil }
        return supportDirectory.appendingPathComponent("JapaneseSyntaxCoach", isDirectory: true)
            .appendingPathComponent("Learning", isDirectory: true)
            .appendingPathComponent("custom-textbooks-\(activeUserKey).json")
    }

    private var selectedTextbookURL: URL? {
        guard let activeUserKey else { return nil }
        return supportDirectory.appendingPathComponent("JapaneseSyntaxCoach", isDirectory: true)
            .appendingPathComponent("Learning", isDirectory: true)
            .appendingPathComponent("selected-textbook-\(activeUserKey).json")
    }

    private var localProgressURL: URL? {
        guard let activeUserKey else { return nil }
        return supportDirectory.appendingPathComponent("JapaneseSyntaxCoach", isDirectory: true)
            .appendingPathComponent("Learning", isDirectory: true)
            .appendingPathComponent("local-progress-\(activeUserKey).json")
    }

    private func legacyQueueExists(email: String?) -> Bool {
        guard let email else { return false }
        let normalized = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return false }
        let digest = SHA256.hash(data: Data(normalized.utf8)).map { String(format: "%02x", $0) }.joined()
        do {
            _ = try fileManager.attributesOfItem(atPath: queueURL(for: digest).path)
            return true
        } catch let error as NSError where error.domain == NSCocoaErrorDomain &&
            (error.code == NSFileNoSuchFileError || error.code == NSFileReadNoSuchFileError) {
            return false
        } catch { return true }
    }

    private func queueURL(for key: String) -> URL {
        supportDirectory.appendingPathComponent("JapaneseSyntaxCoach", isDirectory: true)
            .appendingPathComponent("Learning", isDirectory: true)
            .appendingPathComponent("answer-queue-\(key).json")
    }

    private func removeUserFiles(for key: String) -> Bool {
        let baseDir = supportDirectory.appendingPathComponent("JapaneseSyntaxCoach", isDirectory: true)
            .appendingPathComponent("Learning", isDirectory: true)
        let filenames = [
            "study-state-\(key).json",
            "custom-textbooks-\(key).json",
            "selected-textbook-\(key).json",
            "local-progress-\(key).json"
        ]
        for filename in filenames {
            let fileURL = baseDir.appendingPathComponent(filename)
            do {
                try fileManager.removeItem(at: fileURL)
            } catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileNoSuchFileError {
                continue
            } catch {
                return false
            }
        }
        return true
    }

    private func isCurrent(_ context: APIRequestContext) -> Bool {
        let current = auth.generationSnapshot()
        return auth.phase == .signedIn && current.account == context.generation && current.login == context.loginGeneration
    }

    private func isOffline(_ error: Error) -> Bool {
        if let apiError = error as? APIClientError { return apiError == .offline }
        return (error as? URLError) != nil
    }

    private static func accountKey(_ userID: String?) -> String? {
        guard let userID, !userID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        // A separate namespace ensures legacy email-derived files are never opened.
        let digest = SHA256.hash(data: Data(userID.utf8)).map { String(format: "%02x", $0) }.joined()
        return "user-v1-\(digest)"
    }
}

private enum MistakeSyncError: Error, Equatable {
    case legacyItemRequiresReview
}

private struct CachedTextbook: Codable {
    let schemaVersion: Int
    let contentHash: String
    let textbook: Textbook
}

enum LearningStoreError: LocalizedError {
    case invalidURL
    case notSignedIn
    case accountDeleteNotConfirmed
    case accountDeletionUnavailable
    case queueUnavailable, pendingAnswers, deletionInProgress, accountChanged, queueCleanupFailed
    case deletionOutcomeUnknown, deletionOutcomeUnknownFreezeFailed, deletionUnfreezeFailed

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "学习服务地址无效。"
        case .notSignedIn: return "请先登录后再删除账号。"
        case .accountDeleteNotConfirmed: return "服务端未确认账号删除。"
        case .accountDeletionUnavailable: return "账号删除暂不可用，账号及数据未更改。"
        case .queueUnavailable: return "待同步队列无法读取，原文件已保留，暂不能删除账号。"
        case .pendingAnswers: return "还有答案尚未同步，请先同步后再删除账号。"
        case .deletionInProgress: return "账号删除正在进行中。"
        case .accountChanged: return "账号已在删除期间切换，请检查原账号的删除状态。"
        case .queueCleanupFailed: return "云端账号已删除，但本机队列或学习进度缓存未能安全清理，请保留数据并联系支持。"
        case .deletionUnfreezeFailed: return "服务端未确认删除，但本机队列无法解除冻结，请联系支持。"
        case .deletionOutcomeUnknown: return "无法确认账号删除结果。原账号本机队列已冻结，请核实云端状态；应用不会自动重试删除。"
        case .deletionOutcomeUnknownFreezeFailed: return "无法确认账号删除结果，且未能持久冻结本机队列。请勿重试删除并立即核实云端状态。"
        }
    }
}
