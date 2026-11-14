import XCTest
@testable import JapaneseSyntaxCoach

final class FreeTextbookCatalogTests: XCTestCase {
    func testCatalogMetadata() {
        let items = FreeTextbookCatalog.items
        XCTAssertEqual(items.map(\.id), ["shin-standard-japanese-beginner-lower", "shin-standard-japanese-intermediate-upper", "shin-standard-japanese-intermediate-lower"])
        XCTAssertEqual(items.map(\.lessonCount), [24, 16, 16])
        XCTAssertEqual(items.map(\.questionCount), [480, 320, 320])
        XCTAssertEqual(items.map(\.resourceName), items.map(\.id))
        XCTAssertTrue(items.allSatisfy { !$0.title.isEmpty && !$0.shortTitle.isEmpty })
    }

    func testSaveLoadRemoveAndRejectCorruption() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = DownloadedTextbookStore(directory: directory)
        let package = try TextbookRepository.loadBundled()
        let id = package.textbook.id
        XCTAssertNil(try store.load(id: id))
        try store.save(package)
        XCTAssertTrue(store.contains(id: id))
        XCTAssertEqual(try store.load(id: id)?.contentHash, package.contentHash)
        try Data("broken".utf8).write(to: directory.appendingPathComponent("\(id).json"))
        XCTAssertThrowsError(try store.load(id: id))
        try store.remove(id: id)
        XCTAssertFalse(store.contains(id: id))
    }

    func testInvalidReplacementPreservesExistingCache() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = DownloadedTextbookStore(directory: directory)
        let package = try TextbookRepository.loadBundled()
        try store.save(package)
        let invalid = TextbookPackage(schemaVersion: 1, contentHash: String(repeating: "0", count: 64), textbook: package.textbook)
        XCTAssertThrowsError(try store.save(invalid))
        XCTAssertEqual(try store.load(id: package.textbook.id)?.contentHash, package.contentHash)
        try store.save(package)
        XCTAssertEqual(try store.load(id: package.textbook.id)?.contentHash, package.contentHash)
    }
}
