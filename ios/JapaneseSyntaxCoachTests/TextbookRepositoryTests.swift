import XCTest
@testable import JapaneseSyntaxCoach

final class TextbookRepositoryTests: XCTestCase {
    func testBundledPackageSchemaCountsHashAndQuestionOrder() throws {
        let package = try TextbookRepository.loadBundled()

        XCTAssertEqual(package.schemaVersion, 1)
        XCTAssertEqual(package.textbook.id, "builtin-japanese-syntax")
        XCTAssertEqual(package.textbook.lessons.count, 24)
        XCTAssertEqual(package.textbook.questions.count, 548)
        XCTAssertEqual(package.contentHash, "cc676f54dd8c5ed427a6b7105932aa6c07d61e0ed343a347f5f577273a9794a5")
        XCTAssertEqual(package.textbook.questions.first?.id, "L01-Q001")
        XCTAssertEqual(package.textbook.questions.last?.id, "L24-Q023")
    }

    func testFreeBundledTextbooksMatchCatalogAndCounts() throws {
        let expected: [(String, Int, Int)] = [
            ("shin-standard-japanese-beginner-lower", 24, 480),
            ("shin-standard-japanese-intermediate-upper", 16, 320),
            ("shin-standard-japanese-intermediate-lower", 16, 320)
        ]

        for (id, lessonCount, questionCount) in expected {
            let package = try TextbookRepository.loadBundled(id: id)
            XCTAssertEqual(package.textbook.id, id)
            XCTAssertEqual(package.textbook.lessons.count, lessonCount)
            XCTAssertEqual(package.textbook.questions.count, questionCount)
            XCTAssertEqual(FreeTextbookCatalog.items.first(where: { $0.id == id })?.lessonCount, lessonCount)
            XCTAssertEqual(FreeTextbookCatalog.items.first(where: { $0.id == id })?.questionCount, questionCount)
        }
    }

    func testUnsupportedSchemaVersionHasReadableError() throws {
        let data = Data(#"{"schemaVersion":2,"contentHash":"hash","textbook":{}}"#.utf8)

        XCTAssertThrowsError(try JSONDecoder().decode(TextbookPackage.self, from: data)) { error in
            XCTAssertEqual(error as? TextbookLoadError, .unsupportedSchemaVersion(2))
            XCTAssertNotNil(error.localizedDescription)
        }
    }

    func testMissingTextbookIDHasReadableError() throws {
        let data = Data(#"{"schemaVersion":1,"contentHash":"0000000000000000000000000000000000000000000000000000000000000000","textbook":{"title":"Test","lessons":[],"questions":[]}}"#.utf8)

        XCTAssertThrowsError(try JSONDecoder().decode(TextbookPackage.self, from: data)) { error in
            XCTAssertEqual(error as? TextbookLoadError, .missingID(entity: "textbook"))
            XCTAssertNotNil(error.localizedDescription)
        }
    }

    func testInvalidContentHashIsRejected() throws {
        let data = Data(#"{"schemaVersion":1,"contentHash":"NOT-A-HASH","textbook":{}}"#.utf8)

        XCTAssertThrowsError(try JSONDecoder().decode(TextbookPackage.self, from: data)) { error in
            XCTAssertEqual(error as? TextbookLoadError, .invalidContentHash)
        }
    }

    func testMismatchedContentHashIsRejected() throws {
        var object = try bundledPackageObject()
        object["contentHash"] = String(repeating: "0", count: 64)
        let data = try JSONSerialization.data(withJSONObject: object)

        XCTAssertThrowsError(try JSONDecoder().decode(TextbookPackage.self, from: data)) { error in
            XCTAssertEqual(error as? TextbookLoadError, .contentHashMismatch)
        }
    }

    func testEmptyTextbookIDHasReadableError() throws {
        var object = try bundledPackageObject()
        var textbook = try XCTUnwrap(object["textbook"] as? [String: Any])
        textbook["id"] = ""
        object["textbook"] = textbook

        XCTAssertThrowsError(try JSONDecoder().decode(TextbookPackage.self, from: try JSONSerialization.data(withJSONObject: object))) { error in
            XCTAssertEqual(error as? TextbookLoadError, .missingID(entity: "textbook"))
        }
    }

    func testEmptyQuestionIDHasReadableError() throws {
        var object = try bundledPackageObject()
        var textbook = try XCTUnwrap(object["textbook"] as? [String: Any])
        var questions = try XCTUnwrap(textbook["questions"] as? [[String: Any]])
        questions[0]["id"] = ""
        textbook["questions"] = questions
        object["textbook"] = textbook

        XCTAssertThrowsError(try JSONDecoder().decode(TextbookPackage.self, from: try JSONSerialization.data(withJSONObject: object))) { error in
            XCTAssertEqual(error as? TextbookLoadError, .missingID(entity: "question"))
        }
    }

    func testCustomTextbookImporterParsesFlatAndEmbeddedLessonQuestions() throws {
        let rawJSON = """
        {
          "title": "新完全掌握 N3 句型",
          "lessons": [
            {
              "id": 1,
              "title": "原因与理由",
              "goal": "掌握～おかげで与～せいで",
              "grammar": [
                {
                  "pattern": "～おかげで",
                  "meaning": "多亏了……",
                  "connection": "普通形＋おかげで",
                  "explanation": "表示积极原因",
                  "example": "先生のおかげで合格しました。"
                }
              ],
              "questions": [
                {
                  "type": "translate",
                  "prompt": "多亏了老师，我合格了。",
                  "standardAnswer": "先生のおかげで合格しました。",
                  "hint": "使用～おかげで"
                }
              ]
            }
          ]
        }
        """
        let imported = try TextbookImporter.parseTextbookPackageJSON(rawJSON)
        XCTAssertFalse(imported.isBuiltin)
        XCTAssertEqual(imported.title, "新完全掌握 N3 句型")
        XCTAssertEqual(imported.lessons.count, 1)
        XCTAssertEqual(imported.questions.count, 1)
        XCTAssertEqual(imported.questions.first?.lessonId, 1)
        XCTAssertEqual(imported.questions.first?.answer, "先生のおかげで合格しました。")
    }

    private func bundledPackageObject() throws -> [String: Any] {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "builtin-japanese-syntax", withExtension: "json"))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    }
}
