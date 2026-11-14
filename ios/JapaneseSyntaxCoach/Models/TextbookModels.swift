import CryptoKit
import Foundation

struct TextbookPackage: Codable {
    private static let contentHashLength = 64

    private static func canonicalTextbookData(_ textbook: Textbook) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(textbook)
    }

    private static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
    let schemaVersion: Int
    let contentHash: String
    let textbook: Textbook

    enum CodingKeys: String, CodingKey {
        case schemaVersion
        case contentHash
        case textbook
    }

    init(schemaVersion: Int, contentHash: String, textbook: Textbook) {
        self.schemaVersion = schemaVersion
        self.contentHash = contentHash
        self.textbook = textbook
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let version = try container.decode(Int.self, forKey: .schemaVersion)
        guard version == 1 else {
            throw TextbookLoadError.unsupportedSchemaVersion(version)
        }

        schemaVersion = version
        let decodedHash = try container.decode(String.self, forKey: .contentHash)
        guard decodedHash.utf8.count == Self.contentHashLength,
              decodedHash.utf8.allSatisfy({
                  ($0 >= 48 && $0 <= 57) || ($0 >= 97 && $0 <= 102)
              }) else {
            throw TextbookLoadError.invalidContentHash
        }
        let decodedTextbook = try container.decode(Textbook.self, forKey: .textbook)
        guard let canonicalData = try? Self.canonicalTextbookData(decodedTextbook),
              Self.sha256Hex(canonicalData) == decodedHash else {
            throw TextbookLoadError.contentHashMismatch
        }
        contentHash = decodedHash
        textbook = decodedTextbook
    }
}

struct Textbook: Codable {
    let id: String
    let title: String
    let shortTitle: String?
    let cover: String?
    let description: String?
    let lessons: [TextbookLesson]
    let questions: [TextbookQuestion]

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case shortTitle
        case cover
        case description
        case lessons
        case questions
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encodeIfPresent(shortTitle, forKey: .shortTitle)
        try container.encodeIfPresent(cover, forKey: .cover)
        try container.encodeIfPresent(description, forKey: .description)
        try container.encode(lessons, forKey: .lessons)
        try container.encode(questions, forKey: .questions)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeRequiredID(String.self, forKey: .id, entity: "textbook")
        title = try container.decode(String.self, forKey: .title)
        shortTitle = try container.decodeIfPresent(String.self, forKey: .shortTitle)
        cover = try container.decodeIfPresent(String.self, forKey: .cover)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        lessons = try container.decode([TextbookLesson].self, forKey: .lessons)
        questions = try container.decode([TextbookQuestion].self, forKey: .questions)
    }
}

struct TextbookLesson: Codable {
    let id: Int
    let title: String
    let goal: String
    let description: String?
    let grammar: [TextbookGrammarPoint]

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case goal
        case description
        case grammar
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeRequiredID(Int.self, forKey: .id, entity: "lesson")
        title = try container.decode(String.self, forKey: .title)
        goal = try container.decode(String.self, forKey: .goal)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        grammar = try container.decode([TextbookGrammarPoint].self, forKey: .grammar)
    }
}

struct TextbookGrammarPoint: Codable {
    let pattern: String
    let meaning: String
    let example: String
    let connection: String
    let explanation: String
    let audio: String?
    let responses: [String]?
    let pitfalls: [String]?
}

struct TextbookQuestion: Codable {
    let id: String
    let lessonId: Int
    let type: String
    let prompt: String
    let answer: String
    let hint: String
    let options: [String]?
    let acceptedAnswers: [String]?

    enum CodingKeys: String, CodingKey {
        case id
        case lessonId
        case type
        case prompt
        case answer
        case hint
        case options
        case acceptedAnswers
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeRequiredID(String.self, forKey: .id, entity: "question")
        lessonId = try container.decode(Int.self, forKey: .lessonId)
        type = try container.decode(String.self, forKey: .type)
        prompt = try container.decode(String.self, forKey: .prompt)
        answer = try container.decode(String.self, forKey: .answer)
        hint = try container.decode(String.self, forKey: .hint)
        options = try container.decodeIfPresent([String].self, forKey: .options)
        acceptedAnswers = try container.decodeIfPresent([String].self, forKey: .acceptedAnswers)
    }
}

private extension KeyedDecodingContainer {
    func decodeRequiredID<T: Decodable>(
        _ type: T.Type,
        forKey key: Key,
        entity: String
    ) throws -> T {
        guard contains(key), try decodeNil(forKey: key) == false else {
            throw TextbookLoadError.missingID(entity: entity)
        }
        let value = try decode(T.self, forKey: key)
        if let stringValue = value as? String, stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw TextbookLoadError.missingID(entity: entity)
        }
        return value
    }
}

enum TextbookLoadError: LocalizedError, Equatable {
    case unsupportedSchemaVersion(Int)
    case invalidContentHash
    case contentHashMismatch
    case missingID(entity: String)
    case missingBundledResource

    var errorDescription: String? {
        switch self {
        case .unsupportedSchemaVersion(let version):
            return "Unsupported textbook schema version: \(version)."
        case .invalidContentHash:
            return "The bundled textbook contains an invalid content hash."
        case .contentHashMismatch:
            return "The bundled textbook content hash does not match its contents."
        case .missingID(let entity):
            return "The bundled textbook contains an item without a \(entity) ID."
        case .missingBundledResource:
            return "The bundled Japanese syntax textbook could not be found."
        }
    }
}

struct TextbookRepository {
    static func loadBundled() throws -> TextbookPackage {
        try loadBundled(id: "builtin-japanese-syntax")
    }

    static func loadBundled(id: String) throws -> TextbookPackage {
        guard let url = Bundle.main.url(forResource: id, withExtension: "json") else {
            throw TextbookLoadError.missingBundledResource
        }
        let data = try Data(contentsOf: url)
        let package = try JSONDecoder().decode(TextbookPackage.self, from: data)
        guard package.textbook.id == id else {
            throw TextbookLoadError.contentHashMismatch
        }
        return package
    }
}

extension Textbook: Equatable {
    static func == (lhs: Textbook, rhs: Textbook) -> Bool {
        lhs.id == rhs.id && lhs.title == rhs.title && lhs.lessons.count == rhs.lessons.count && lhs.questions.count == rhs.questions.count
    }

    var isBuiltin: Bool {
        id == "builtin-japanese-syntax"
    }

    var displaySubtitle: String {
        if let description, !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return description
        }
        return isBuiltin ? "24 课渐进式句型训练 · 每课 20 道主动输出练习" : "自定义导入教材"
    }

    var displayLevel: String {
        if isBuiltin { return "N5 · 入门输出" }
        if let shortTitle, !shortTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return shortTitle
        }
        return "自定义"
    }

    var coverTitle: String {
        isBuiltin ? "N5" : "导入"
    }

    var coverSubtitle: String {
        isBuiltin ? "句型" : "教材"
    }

    var displayTags: [String] {
        isBuiltin ? ["句型", "主动输出", "助词", "造句"] : ["自定义", displayLevel]
    }

    var effectiveQuestionLimit: Int {
        20
    }

    func questionCountsPerLesson(limit: Int = 20) -> [Int] {
        lessons.map { lesson in
            let count = questions.filter { $0.lessonId == lesson.id }.count
            return min(max(1, limit), count)
        }
    }
}

enum TextbookImportError: LocalizedError, Equatable {
    case invalidJSON
    case unsupportedSchemaVersion
    case invalidFormat(String)

    var errorDescription: String? {
        switch self {
        case .invalidJSON:
            return "教材文件不是有效的 JSON。"
        case .unsupportedSchemaVersion:
            return "教材包版本不支持，请使用 schemaVersion 为 1 的教材文件。"
        case .invalidFormat(let detail):
            return detail
        }
    }
}

enum TextbookImporter {
    private static let validIdPattern = "^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$"
    private static let validTypes: Set<String> = ["选择", "助词", "翻译", "问答"]
    private static let typeAliases: [String: String] = [
        "choice": "选择",
        "particle": "助词",
        "fill": "助词",
        "translation": "翻译",
        "translate": "翻译",
        "qa": "问答"
    ]

    static func parseTextbookPackageJSON(_ rawText: String) throws -> Textbook {
        guard let rawData = rawText.data(using: .utf8),
              let parsed = try? JSONSerialization.jsonObject(with: rawData) as? [String: Any] else {
            throw TextbookImportError.invalidJSON
        }

        if let schemaVersion = parsed["schemaVersion"] {
            guard let version = schemaVersion as? Int, version == 1 else {
                throw TextbookImportError.unsupportedSchemaVersion
            }
        }

        let textbookObject: [String: Any]
        if let nested = parsed["textbook"] as? [String: Any] {
            textbookObject = nested
        } else {
            textbookObject = parsed
        }

        guard let rawTitle = (textbookObject["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawTitle.isEmpty else {
            throw TextbookImportError.invalidFormat("教材缺少标题（title）。")
        }

        guard let rawLessons = textbookObject["lessons"] as? [[String: Any]], !rawLessons.isEmpty else {
            throw TextbookImportError.invalidFormat("教材至少需要包含 1 课（lessons）。")
        }

        var normalizedLessons: [[String: Any]] = []
        var flattenedQuestions: [[String: Any]] = []

        for (lessonIdx, lesson) in rawLessons.enumerated() {
            let lessonId = (lesson["id"] as? Int) ?? (lessonIdx + 1)
            guard lessonId > 0 else {
                throw TextbookImportError.invalidFormat("课程 ID 必须是正整数。")
            }
            let title = (lesson["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !title.isEmpty else {
                throw TextbookImportError.invalidFormat("第 \(lessonId) 课缺少标题（title）。")
            }
            let goal = (lesson["goal"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let resolvedGoal = (goal?.isEmpty == false) ? goal! : title
            let description = (lesson["description"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)

            let rawGrammar = (lesson["grammar"] as? [[String: Any]]) ?? []
            var normalizedGrammar: [[String: Any]] = []
            for point in rawGrammar {
                guard let pattern = (point["pattern"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !pattern.isEmpty,
                      let meaning = (point["meaning"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !meaning.isEmpty,
                      let example = (point["example"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !example.isEmpty else {
                    throw TextbookImportError.invalidFormat("第 \(lessonId) 课存在缺少 pattern、meaning 或 example 的语法点。")
                }
                var g: [String: Any] = [
                    "pattern": pattern,
                    "meaning": meaning,
                    "example": example,
                    "connection": (point["connection"] as? String) ?? "按课内句型接续",
                    "explanation": (point["explanation"] as? String) ?? meaning
                ]
                if let audio = point["audio"] as? String, !audio.isEmpty { g["audio"] = audio }
                if let responses = point["responses"] as? [String] { g["responses"] = responses }
                if let pitfalls = point["pitfalls"] as? [String] { g["pitfalls"] = pitfalls }
                normalizedGrammar.append(g)
            }

            var lessonDict: [String: Any] = [
                "id": lessonId,
                "title": title,
                "goal": resolvedGoal,
                "grammar": normalizedGrammar
            ]
            if let description, !description.isEmpty {
                lessonDict["description"] = description
            }
            normalizedLessons.append(lessonDict)

            if textbookObject["questions"] == nil, let embedded = lesson["questions"] as? [[String: Any]] {
                for (qIdx, q) in embedded.enumerated() {
                    var copy = q
                    if copy["lessonId"] == nil { copy["lessonId"] = lessonId }
                    if copy["id"] == nil {
                        copy["id"] = String(format: "L%02d-Q%03d", lessonId, qIdx + 1)
                    }
                    flattenedQuestions.append(copy)
                }
            }
        }

        let rawQuestions = (textbookObject["questions"] as? [[String: Any]]) ?? flattenedQuestions
        guard !rawQuestions.isEmpty else {
            throw TextbookImportError.invalidFormat("教材至少需要包含 1 道练习题（questions）。")
        }

        let lessonIdSet = Set(normalizedLessons.compactMap { $0["id"] as? Int })
        var normalizedQuestions: [[String: Any]] = []
        for (qIdx, q) in rawQuestions.enumerated() {
            let lessonId = (q["lessonId"] as? Int) ?? 1
            guard lessonIdSet.contains(lessonId) else {
                throw TextbookImportError.invalidFormat("题目引用了不存在的课次（lessonId: \(lessonId)）。")
            }
            let qId = ((q["id"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 }
                ?? String(format: "L%02d-Q%03d", lessonId, qIdx + 1)
            let rawType = (q["type"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let mappedType = typeAliases[rawType] ?? rawType
            guard validTypes.contains(mappedType) else {
                throw TextbookImportError.invalidFormat("题目 \(qId) 的题型无效（需为 选择/助词/翻译/问答）。")
            }
            let rawAnswer = ((q["answer"] as? String) ?? (q["standardAnswer"] as? String))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard let prompt = (q["prompt"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !prompt.isEmpty,
                  !rawAnswer.isEmpty else {
                throw TextbookImportError.invalidFormat("题目 \(qId) 缺少题干（prompt）或答案（answer）。")
            }
            let answer = rawAnswer
            let hint = ((q["hint"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 }
                ?? ((q["explanation"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 }
                ?? "根据本课句型作答"

            var qDict: [String: Any] = [
                "id": qId,
                "lessonId": lessonId,
                "type": mappedType,
                "prompt": prompt,
                "answer": answer,
                "hint": hint
            ]
            if let options = q["options"] as? [String], !options.isEmpty {
                qDict["options"] = options
            }
            if let accepted = q["acceptedAnswers"] as? [String], !accepted.isEmpty {
                qDict["acceptedAnswers"] = accepted
            }
            normalizedQuestions.append(qDict)
        }

        let rawId = (textbookObject["id"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let resolvedId = slugifyTextbookId(rawId.isEmpty ? rawTitle : rawId)
        let shortTitle = ((textbookObject["level"] as? String) ?? (textbookObject["shortTitle"] as? String))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let subtitle = ((textbookObject["subtitle"] as? String) ?? (textbookObject["description"] as? String))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let cover = ((textbookObject["coverImage"] as? String) ?? (textbookObject["cover"] as? String))?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        var finalObject: [String: Any] = [
            "id": resolvedId,
            "title": rawTitle,
            "lessons": normalizedLessons,
            "questions": normalizedQuestions
        ]
        if let shortTitle, !shortTitle.isEmpty { finalObject["shortTitle"] = shortTitle }
        if let subtitle, !subtitle.isEmpty { finalObject["description"] = subtitle }
        if let cover, !cover.isEmpty { finalObject["cover"] = cover }

        let finalData = try JSONSerialization.data(withJSONObject: finalObject)
        return try JSONDecoder().decode(Textbook.self, from: finalData)
    }

    private static func slugifyTextbookId(_ raw: String) -> String {
        if raw != "builtin-japanese-syntax",
           raw.range(of: validIdPattern, options: .regularExpression) != nil {
            return raw
        }
        let lowered = raw.lowercased()
        let replaced = lowered.replacingOccurrences(
            of: "[^a-z0-9._-]+",
            with: "-",
            options: .regularExpression
        ).trimmingCharacters(in: CharacterSet(charactersIn: "-._"))
        let base = replaced.isEmpty ? "custom-\(Int(Date().timeIntervalSince1970))" : replaced
        let candidate = base == "builtin-japanese-syntax" ? "custom-\(base)" : base
        return String(candidate.prefix(120))
    }
}
