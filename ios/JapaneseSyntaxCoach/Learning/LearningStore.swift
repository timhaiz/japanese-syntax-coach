import Combine
import CryptoKit
import Foundation
import SwiftUI

@MainActor
final class LearningStore: ObservableObject {
    @Published private(set) var textbook: Textbook?
    @Published private(set) var textbookError: String?
    @Published private(set) var studyState: StudyState?
    @Published private(set) var isShowingCachedStudyState = false
    @Published private(set) var pendingCount = 0
    @Published private(set) var syncState: LearningSyncState = .notSignedIn

    private let auth: AuthSessionStore
    private let api: APIClient
    private var activeUserKey: String?
    private var queue: OfflineAnswerQueue?
    private let fileManager: FileManager
    private var accountGeneration = UUID()
    private var authSubscription: AnyCancellable?

    init(auth: AuthSessionStore, fileManager: FileManager = .default) {
        self.auth = auth
        self.api = APIClient(tokenProvider: auth)
        self.fileManager = fileManager
        authSubscription = auth.$userEmail.sink { [weak self] email in
            guard let self else { return }
            if let email { self.activateAccount(email: email) }
            else { self.clearUserScopedData() }
        }
    }

    func loadStudyState() async {
        loadTextbook()
        guard auth.phase == .signedIn, let email = auth.userEmail else {
            syncState = .notSignedIn
            return
        }
        activateAccount(email: email)
        guard activeUserKey != nil else { return }

        let generation = accountGeneration
        syncState = .loading
        do {
            let request = try makeStudyStateRequest()
            let confirmed: StudyState = try await api.request(request)
            guard generation == accountGeneration, auth.phase == .signedIn else { return }
            studyState = confirmed
            isShowingCachedStudyState = false
            persist(confirmed, to: studyStateURL)
            syncState = pendingCount > 0 ? .pending : .synced
        } catch {
            guard generation == accountGeneration, auth.phase == .signedIn else { return }
            if studyState == nil { loadCachedStudyState() }
            syncState = isOffline(error) ? .offline : .error("云端学习进度暂时无法读取。")
        }
    }

    func submit(_ answer: AnswerSubmission) async {
        guard auth.phase == .signedIn, let email = auth.userEmail else {
            syncState = .notSignedIn
            return
        }
        activateAccount(email: email)
        let item = answer.pendingAnswer()
        queue?.enqueue(item)
        pendingCount = queue?.peek().count ?? 0
        syncState = .pending
        await retryPending()
    }

    func retryPending() async {
        guard auth.phase == .signedIn, let email = auth.userEmail else {
            syncState = .notSignedIn
            return
        }
        activateAccount(email: email)
        guard let queue, !queue.peek().isEmpty else {
            pendingCount = 0
            if studyState != nil { syncState = isShowingCachedStudyState ? .offline : .synced }
            return
        }

        let generation = accountGeneration
        syncState = .syncing
        var submissionError: Error?
        let sentCount = await queue.retry { [weak self, api] item in
            guard let self, generation == self.accountGeneration, self.auth.phase == .signedIn else { return false }
            do {
                let request = try Self.makeRecordRequest(item)
                let response: RecordAnswerResponse = try await api.request(request)
                guard generation == self.accountGeneration, self.auth.phase == .signedIn else { return false }
                return response.confirmsWrite
            } catch {
                submissionError = error
                throw error
            }
        }
        guard generation == accountGeneration, auth.phase == .signedIn else { return }
        pendingCount = queue.peek().count
        if pendingCount > 0 {
            if let submissionError {
                syncState = isOffline(submissionError) ? .offline : .error("同步失败，答案仍保留在待同步队列，请稍后重试。")
            } else {
                syncState = .error("服务器尚未确认写入，答案已保留，请重试。")
            }
            return
        }

        syncState = .synced
        if sentCount > 0 { await loadStudyState() }
    }

    func activateAccount(email: String) {
        let key = Self.accountKey(email)
        guard key != activeUserKey else { return }

        if let previous = activeUserKey {
            removeUserFiles(for: previous)
        }
        accountGeneration = UUID()
        activeUserKey = key
        queue = OfflineAnswerQueue(fileURL: queueURL(for: key))
        pendingCount = queue?.peek().count ?? 0
        studyState = nil
        isShowingCachedStudyState = false
        if pendingCount > 0 { syncState = .pending }
        loadCachedStudyState()
    }

    func clearUserScopedData() {
        accountGeneration = UUID()
        if let activeUserKey {
            queue?.clear()
            removeUserFiles(for: activeUserKey)
        }
        activeUserKey = nil
        queue = nil
        pendingCount = 0
        studyState = nil
        isShowingCachedStudyState = false
        syncState = .notSignedIn
    }

    func deleteAccount() async throws {
        guard auth.phase == .signedIn else { throw LearningStoreError.notSignedIn }
        let deletion = AccountDeletionRequest()
        guard deletion.isConfirmed else { throw LearningStoreError.accountDeleteNotConfirmed }
        var request = URLRequest(url: AppConfiguration.webURL.appendingPathComponent("api/account/delete"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(deletion)
        let response: AccountDeleteResponse = try await api.request(request)
        guard response.deleted else { throw LearningStoreError.accountDeleteNotConfirmed }
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
        if textbook != nil { return }
        do {
            let bundled = try TextbookRepository.loadBundled()
            textbook = bundled.textbook
            textbookError = nil
            persist(CachedTextbook(schemaVersion: bundled.schemaVersion, contentHash: bundled.contentHash, textbook: bundled.textbook), to: textbookURL)
        } catch {
            do {
                let cached = try JSONDecoder().decode(CachedTextbook.self, from: Data(contentsOf: textbookURL))
                textbook = cached.textbook
                textbookError = nil
            } catch {
                textbookError = "教材无法从安装包或本机缓存中读取。"
            }
        }
    }

    private func makeStudyStateRequest() throws -> URLRequest {
        let url = AppConfiguration.webURL.appendingPathComponent("api/study-state")
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw LearningStoreError.invalidURL
        }
        components.queryItems = [URLQueryItem(name: "textbookId", value: "builtin-japanese-syntax")]
        guard let requestURL = components.url else { throw LearningStoreError.invalidURL }
        return URLRequest(url: requestURL)
    }

    private static func makeRecordRequest(_ item: PendingAnswer) throws -> URLRequest {
        var request = URLRequest(url: AppConfiguration.webURL.appendingPathComponent("api/record-answer"))
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
        (try? fileManager.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
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

    private func queueURL(for key: String) -> URL {
        supportDirectory.appendingPathComponent("JapaneseSyntaxCoach", isDirectory: true)
            .appendingPathComponent("Learning", isDirectory: true)
            .appendingPathComponent("answer-queue-\(key).json")
    }

    private func removeUserFiles(for key: String) {
        try? fileManager.removeItem(at: queueURL(for: key))
        let progressURL = supportDirectory.appendingPathComponent("JapaneseSyntaxCoach", isDirectory: true)
            .appendingPathComponent("Learning", isDirectory: true)
            .appendingPathComponent("study-state-\(key).json")
        try? fileManager.removeItem(at: progressURL)
    }

    private func isOffline(_ error: Error) -> Bool {
        if let apiError = error as? APIClientError { return apiError == .offline }
        return (error as? URLError) != nil
    }

    private static func accountKey(_ email: String) -> String {
        let normalized = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return SHA256.hash(data: Data(normalized.utf8)).map { String(format: "%02x", $0) }.joined()
    }
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

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "学习服务地址无效。"
        case .notSignedIn: return "请先登录后再删除账号。"
        case .accountDeleteNotConfirmed: return "服务端未确认账号删除。"
        }
    }
}
