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

    func pendingAnswer(clientRequestId: String = UUID().uuidString, expectedMistakeVersion: Int? = nil) -> PendingAnswer {
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
            clientRequestId: clientRequestId,
            expectedMistakeVersion: expectedMistakeVersion
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
    let expectedMistakeVersion: Int?

    enum CodingKeys: String, CodingKey {
        case id, textbookId, questionId, lessonId, questionLimit, answer, correct, verdict
        case errorTags, knowledgeTags, mode, clientRequestId, expectedMistakeVersion
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        textbookId = try container.decode(String.self, forKey: .textbookId)
        questionId = try container.decode(String.self, forKey: .questionId)
        lessonId = try container.decode(Int.self, forKey: .lessonId)
        questionLimit = try container.decode(Int.self, forKey: .questionLimit)
        answer = try container.decode(String.self, forKey: .answer)
        correct = try container.decode(Bool.self, forKey: .correct)
        verdict = try container.decode(String.self, forKey: .verdict)
        errorTags = try container.decode([String].self, forKey: .errorTags)
        knowledgeTags = try container.decode([String].self, forKey: .knowledgeTags)
        mode = try container.decode(String.self, forKey: .mode)
        clientRequestId = container.contains(.clientRequestId)
            ? try container.decode(String.self, forKey: .clientRequestId)
            : id.uuidString
        expectedMistakeVersion = try container.decodeIfPresent(Int.self, forKey: .expectedMistakeVersion)
    }

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
        clientRequestId: String? = nil,
        expectedMistakeVersion: Int? = nil
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
        self.expectedMistakeVersion = expectedMistakeVersion
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
    let expectedMistakeVersion: Int?

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
        expectedMistakeVersion = item.expectedMistakeVersion
    }
}

struct RecordAnswerResponse: Decodable {
    let duplicate: Bool?
    let record: JSONValue?
    let textbookScopeAvailable: Bool?
    let localOnly: Bool?
    let mistakeStateAvailable: Bool?
    let mistakeState: AtomicMistakeState?

    func confirms(_ item: PendingAnswer) -> Bool {
        guard localOnly != true else { return false }
        if let version = item.expectedMistakeVersion {
            guard version >= 0, version < 9_007_199_254_740_991,
                  mistakeStateAvailable == true, let mistakeState, mistakeState.isValid,
                  duplicate != nil, let record, record != .null,
                  mistakeState.questionId == item.questionId,
                  mistakeState.version == version + 1 else { return false }
            if !item.correct { return mistakeState.isMistake }
            if ["mistakes", "lesson_replay"].contains(item.mode) { return !mistakeState.isMistake }
            return true
        }
        guard mistakeStateAvailable != true, mistakeState == nil else { return false }
        return confirmsLegacyWrite
    }

    // Retained for legacy callers; atomic responses always need the original operation.
    var confirmsWrite: Bool {
        mistakeStateAvailable != true && mistakeState == nil && localOnly != true && confirmsLegacyWrite
    }

    private var confirmsLegacyWrite: Bool {
        if duplicate == true { return true }
        guard localOnly != true else { return false }
        if textbookScopeAvailable == true { return true }
        if let record, record != .null { return true }
        return false
    }
}

struct AtomicMistakeState: Codable, Equatable {
    let questionId: String
    let isMistake: Bool
    let version: Int

    var isValid: Bool {
        let pattern = "^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$"
        return questionId.range(of: pattern, options: .regularExpression) != nil && version > 0 && version <= 9_007_199_254_740_991
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
    let mistakeStateAvailable: Bool?
    let mistakeStates: [JSONValue]?

    func mistakeVersion(for questionId: String) -> Int? {
        guard let rows = validatedMistakeStates else { return nil }
        return rows.first(where: { $0.questionId == questionId })?.version ?? 0
    }

    private var validatedMistakeStates: [AtomicMistakeState]? {
        guard mistakeStateAvailable == true, let mistakeStates else { return nil }
        var seen = Set<String>()
        var result: [AtomicMistakeState] = []
        for value in mistakeStates {
            guard case let .object(fields) = value,
                  case let .string(questionId)? = fields["questionId"],
                  case let .bool(isMistake)? = fields["isMistake"],
                  case let .integer(version)? = fields["version"] else { return nil }
            let row = AtomicMistakeState(questionId: questionId, isMistake: isMistake, version: version)
            guard row.isValid, seen.insert(questionId).inserted else { return nil }
            result.append(row)
        }
        return result
    }

    /// Nil means that no supported snapshot is available; an empty array is a confirmed empty list.
    /// Resolve IDs against the bundled textbook so stale metadata cannot supply question content.
    func mistakeQuestions(in textbook: Textbook) -> [TextbookQuestion]? {
        guard textbookId == "builtin-japanese-syntax", textbook.id == textbookId else { return nil }
        if mistakeStateAvailable == true {
            guard let rows = validatedMistakeStates else { return nil }
            let canonicalIDs = Set(textbook.questions.map(\.id))
            guard rows.allSatisfy({ canonicalIDs.contains($0.questionId) }) else { return nil }
            return rows.filter(\.isMistake).compactMap { row in textbook.questions.first { $0.id == row.questionId } }
        }
        guard legacyProgressAvailable,
              case let .object(snapshot) = legacyProgress,
              snapshot["status"] == nil,
              case let .integer(version) = snapshot["version"], [2, 3].contains(version),
              case let .array(mistakes) = snapshot["mistakes"] else { return nil }
        var seen = Set<String>()
        return mistakes.compactMap { item in
            guard case let .object(fields) = item,
                  case let .string(id) = fields["id"],
                  seen.insert(id).inserted else { return nil }
            return textbook.questions.first { $0.id == id }
        }
    }

    enum CodingKeys: String, CodingKey {
        case textbookId, textbookScopeAvailable, dueQuestionIds, lessons, knowledgePoints, metrics
        case legacyProgressAvailable, legacyProgress, mistakeStateAvailable, mistakeStates
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        textbookId = try container.decode(String.self, forKey: .textbookId)
        textbookScopeAvailable = try container.decode(Bool.self, forKey: .textbookScopeAvailable)
        dueQuestionIds = try container.decode([String].self, forKey: .dueQuestionIds)
        lessons = try container.decode([StudyLessonProgress].self, forKey: .lessons)
        knowledgePoints = try container.decode([JSONValue].self, forKey: .knowledgePoints)
        metrics = try container.decode(StudyMetrics.self, forKey: .metrics)
        legacyProgressAvailable = try container.decodeIfPresent(Bool.self, forKey: .legacyProgressAvailable) ?? false
        legacyProgress = try container.decodeIfPresent(JSONValue.self, forKey: .legacyProgress)
        mistakeStateAvailable = try container.decodeIfPresent(Bool.self, forKey: .mistakeStateAvailable)
        mistakeStates = try container.decodeIfPresent([JSONValue].self, forKey: .mistakeStates)
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

struct LocalTextbookProgress: Codable, Equatable {
    var lessonDone: [Int: Int] = [:]
    var lessonCorrect: [Int: Int] = [:]
    var completedLessonIds: [Int] = []
    var mistakeQuestionIds: [String] = []
    var totalAttempts: Int = 0
    var incorrectAttempts: Int = 0
    var correctStreak: Int = 0
    var topErrorTagCounts: [String: Int] = [:]

    mutating func record(
        question: TextbookQuestion,
        isCorrect: Bool,
        errorTags: [String],
        mode: String,
        questionLimit: Int = 20
    ) {
        totalAttempts += 1
        if isCorrect {
            correctStreak += 1
        } else {
            incorrectAttempts += 1
            correctStreak = 0
            for tag in errorTags where !tag.isEmpty {
                topErrorTagCounts[tag, default: 0] += 1
            }
        }

        if mode == "lesson" {
            let currentDone = lessonDone[question.lessonId] ?? 0
            let nextDone = min(max(1, questionLimit), currentDone + 1)
            lessonDone[question.lessonId] = nextDone
            if isCorrect {
                let currentCorrect = lessonCorrect[question.lessonId] ?? 0
                lessonCorrect[question.lessonId] = min(max(1, questionLimit), currentCorrect + 1)
            }
            if nextDone >= max(1, questionLimit), !completedLessonIds.contains(question.lessonId) {
                completedLessonIds.append(question.lessonId)
                completedLessonIds.sort()
            }
        } else if mode == "lesson_replay", isCorrect {
            let currentCorrect = lessonCorrect[question.lessonId] ?? 0
            lessonCorrect[question.lessonId] = min(max(1, questionLimit), currentCorrect + 1)
        }

        if !isCorrect {
            if !mistakeQuestionIds.contains(question.id) {
                mistakeQuestionIds.append(question.id)
            }
        } else if mode == "mistakes" || mode == "lesson_replay" {
            mistakeQuestionIds.removeAll { $0 == question.id }
        }
    }
}

struct LessonCompletionSummary: Equatable {
    let lessonId: Int
    let correct: Int
    let total: Int
    let mistakeQuestionIds: [String]
    let replayed: Bool
}

struct AIAnalysisWord: Codable, Equatable, Identifiable {
    var id: String { "\(word)-\(kana)" }
    let word: String
    let kana: String
    let meaning: String
    let memory: String
}

struct AIAnalysisResponse: Codable, Equatable {
    let analysis: String?
    let words: [AIAnalysisWord]?
    let pitfalls: [String]?
    let source: String?
    let memberRequired: Bool?
    let error: String?
}

struct AIGradeResponse: Codable, Equatable {
    let verdict: String?
    let correctedAnswer: String?
    let errorTags: [String]?
    let explanation: String?
    let source: String?
    let memberRequired: Bool?
    let error: String?
}
