import Foundation

struct TextbookPackage: Decodable {
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
        contentHash = try container.decode(String.self, forKey: .contentHash)
        textbook = try container.decode(Textbook.self, forKey: .textbook)
    }
}

struct Textbook: Decodable {
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

struct TextbookLesson: Decodable {
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

struct TextbookGrammarPoint: Decodable {
    let pattern: String
    let meaning: String
    let example: String
    let connection: String
    let explanation: String
    let audio: String?
    let responses: [String]?
    let pitfalls: [String]?
}

struct TextbookQuestion: Decodable {
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
        return try decode(T.self, forKey: key)
    }
}

enum TextbookLoadError: LocalizedError, Equatable {
    case unsupportedSchemaVersion(Int)
    case missingID(entity: String)
    case missingBundledResource

    var errorDescription: String? {
        switch self {
        case .unsupportedSchemaVersion(let version):
            return "Unsupported textbook schema version: \(version)."
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
