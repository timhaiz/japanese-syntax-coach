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

    func testUnsupportedSchemaVersionHasReadableError() throws {
        let data = Data(#"{"schemaVersion":2,"contentHash":"hash","textbook":{}}"#.utf8)

        XCTAssertThrowsError(try JSONDecoder().decode(TextbookPackage.self, from: data)) { error in
            XCTAssertEqual(error as? TextbookLoadError, .unsupportedSchemaVersion(2))
            XCTAssertNotNil(error.localizedDescription)
        }
    }

    func testMissingTextbookIDHasReadableError() throws {
        let data = Data(#"{"schemaVersion":1,"contentHash":"hash","textbook":{"title":"Test","lessons":[],"questions":[]}}"#.utf8)

        XCTAssertThrowsError(try JSONDecoder().decode(TextbookPackage.self, from: data)) { error in
            XCTAssertEqual(error as? TextbookLoadError, .missingID(entity: "textbook"))
            XCTAssertNotNil(error.localizedDescription)
        }
    }
}
