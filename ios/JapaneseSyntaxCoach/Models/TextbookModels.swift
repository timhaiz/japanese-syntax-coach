import CryptoKit
import Foundation

struct TextbookPackage: Decodable {
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
        guard let url = Bundle.main.url(forResource: "builtin-japanese-syntax", withExtension: "json") else {
            throw TextbookLoadError.missingBundledResource
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(TextbookPackage.self, from: data)
    }
}
