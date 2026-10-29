import Foundation

struct LocalEvaluation: Equatable {
    let verdict: String
    let isCorrect: Bool
    let expectedAnswer: String
    let feedback: String
    let errorTags: [String]
    let knowledgeTags: [String]
}

struct AnswerSubmission {
    let question: TextbookQuestion
    let answer: String
    let evaluation: LocalEvaluation
    let mode: String

    func pendingAnswer(clientRequestId: String = UUID().uuidString) -> PendingAnswer {
        PendingAnswer(
            textbookId: "builtin-japanese-syntax",
            questionId: question.id,
            lessonId: question.lessonId,
            questionLimit: 20,
            answer: answer,
            correct: evaluation.isCorrect,
            verdict: evaluation.verdict,
            errorTags: evaluation.errorTags,
            knowledgeTags: evaluation.knowledgeTags,
            mode: mode,
            clientRequestId: clientRequestId
        )
    }
}

struct PendingAnswer: Codable, Equatable, Identifiable {
    let id: UUID
    let textbookId: String
    let questionId: String
    let lessonId: Int
    let questionLimit: Int
    let answer: String
    let correct: Bool
    let verdict: String
    let errorTags: [String]
    let knowledgeTags: [String]
    let mode: String
    let clientRequestId: String

    init(
        id: UUID = UUID(),
        textbookId: String,
        questionId: String,
        lessonId: Int,
        questionLimit: Int,
        answer: String,
        correct: Bool,
        verdict: String,
        errorTags: [String],
        knowledgeTags: [String],
        mode: String,
        clientRequestId: String? = nil
    ) {
        self.id = id
        self.textbookId = textbookId
        self.questionId = questionId
        self.lessonId = lessonId
        self.questionLimit = questionLimit
        self.answer = answer
        self.correct = correct
        self.verdict = verdict
        self.errorTags = errorTags
        self.knowledgeTags = knowledgeTags
        self.mode = mode
        self.clientRequestId = clientRequestId ?? id.uuidString
    }
}

struct RecordAnswerRequest: Encodable {
    let textbookId: String
    let questionId: String
    let lessonId: Int
    let questionLimit: Int
    let answer: String
    let correct: Bool
    let verdict: String
    let errorTags: [String]
    let knowledgeTags: [String]
    let mode: String
    let clientRequestId: String

    init(_ item: PendingAnswer) {
        textbookId = item.textbookId
        questionId = item.questionId
        lessonId = item.lessonId
        questionLimit = item.questionLimit
        answer = item.answer
        correct = item.correct
        verdict = item.verdict
        errorTags = item.errorTags
        knowledgeTags = item.knowledgeTags
        mode = item.mode
        clientRequestId = item.clientRequestId
    }
}

struct RecordAnswerResponse: Decodable {
    let duplicate: Bool?
    let record: JSONValue?
    let textbookScopeAvailable: Bool?
    let localOnly: Bool?

    var confirmsWrite: Bool {
        if duplicate == true { return true }
        guard localOnly != true else { return false }
        if textbookScopeAvailable == true { return true }
        if let record, record != .null { return true }
        return false
    }
}

struct AccountDeleteResponse: Decodable {
    let deleted: Bool
}

struct StudyState: Codable, Equatable {
    let textbookId: String
    let textbookScopeAvailable: Bool
    let dueQuestionIds: [String]
    let lessons: [StudyLessonProgress]
    let knowledgePoints: [JSONValue]
    let metrics: StudyMetrics
    let legacyProgressAvailable: Bool
    let legacyProgress: JSONValue?

    enum CodingKeys: String, CodingKey {
        case textbookId, textbookScopeAvailable, dueQuestionIds, lessons, knowledgePoints, metrics
        case legacyProgressAvailable, legacyProgress
    }
}

struct StudyLessonProgress: Codable, Equatable, Identifiable {
    var id: Int { lessonId }
    let lessonId: Int
    let answeredCount: Int
    let correctCount: Int
    let completedAt: String?

    enum CodingKeys: String, CodingKey {
        case lessonId = "lesson_id"
        case answeredCount = "answered_count"
        case correctCount = "correct_count"
        case completedAt = "completed_at"
    }
}

struct StudyMetrics: Codable, Equatable {
    let totalAttempts: Int
    let incorrectAttempts: Int
    let errorRate: Int
    let forgettingRate: Int
    let correctStreak: Int
    let topErrorTags: [TopErrorTag]

    enum CodingKeys: String, CodingKey {
        case totalAttempts, incorrectAttempts, errorRate, forgettingRate, correctStreak, topErrorTags
    }
}

struct TopErrorTag: Codable, Equatable, Identifiable {
    var id: String { tag }
    let tag: String
    let count: Int
}

enum LearningSyncState: Equatable {
    case notSignedIn
    case loading
    case syncing
    case synced
    case pending
    case offline
    case error(String)

    var title: String {
        switch self {
        case .notSignedIn: return "未登录，云端进度不可用"
        case .loading: return "正在读取学习进度…"
        case .syncing: return "正在同步…"
        case .synced: return "已与云端同步"
        case .pending: return "有答案等待同步"
        case .offline: return "离线：答案已暂存"
        case .error(let message): return message
        }
    }
}

enum JSONValue: Codable, Equatable {
    case string(String)
    case integer(Int)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(Int.self) { self = .integer(value) }
        else if let value = try? container.decode(Double.self) { self = .number(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode([String: JSONValue].self) { self = .object(value) }
        else if let value = try? container.decode([JSONValue].self) { self = .array(value) }
        else { throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value") }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .integer(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }

    var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    var objectValue: [String: JSONValue]? {
        if case .object(let value) = self { return value }
        return nil
    }
}

extension StudyState {
    var legacyProgressSummary: String {
        guard legacyProgressAvailable else { return "没有独立的旧版进度。" }
        guard let legacyProgress else { return "旧版进度为空；与结构化进度分开保留。" }
        if legacyProgress.objectValue?["status"]?.stringValue == "unsupported" {
            return "检测到暂不支持解析的旧版进度；未合并到结构化统计。"
        }
        return "检测到独立旧版进度；未合并到结构化统计。"
    }
}
