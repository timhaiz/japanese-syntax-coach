import Foundation
import Supabase
import XCTest
@testable import JapaneseSyntaxCoach

final class NamespacedAuthLocalStorageTests: XCTestCase {
    func testNamespacesAndSpecialCharactersProduceDistinctKeys() throws {
        let backing = MemoryAuthStorage()
        let first = NamespacedAuthLocalStorage(namespace: "account/a", backing: backing)
        let second = NamespacedAuthLocalStorage(namespace: "account:a", backing: backing)
        let value = Data([0x00, 0x7f, 0xff])

        try first.store(key: "session:/?%#", value: value)
        try second.store(key: "session:/?%#", value: Data([0x01]))

        XCTAssertEqual(try first.retrieve(key: "session:/?%#"), value)
        XCTAssertEqual(try second.retrieve(key: "session:/?%#"), Data([0x01]))
        XCTAssertEqual(backing.values.count, 2)
    }

    func testNamespacedOperationsPreserveLegacyAndOtherNamespaceValues() throws {
        let backing = MemoryAuthStorage()
        let first = NamespacedAuthLocalStorage(namespace: "one", backing: backing)
        let second = NamespacedAuthLocalStorage(namespace: "two", backing: backing)
        let key = "auth-token"
        let legacyValue = Data("legacy".utf8)
        let firstValue = Data("one".utf8)
        let secondValue = Data("two".utf8)
        try backing.store(key: key, value: legacyValue)
        XCTAssertNil(try first.retrieve(key: key))

        try first.store(key: key, value: firstValue)
        XCTAssertEqual(try backing.retrieve(key: key), legacyValue)
        XCTAssertEqual(try first.retrieve(key: key), firstValue)

        try second.store(key: key, value: secondValue)
        XCTAssertEqual(try backing.retrieve(key: key), legacyValue)
        XCTAssertEqual(try first.retrieve(key: key), firstValue)
        XCTAssertEqual(try second.retrieve(key: key), secondValue)

        try first.remove(key: key)
        XCTAssertEqual(try backing.retrieve(key: key), legacyValue)
        XCTAssertNil(try first.retrieve(key: key))
        XCTAssertEqual(try second.retrieve(key: key), secondValue)

        try second.remove(key: key)
        XCTAssertEqual(try backing.retrieve(key: key), legacyValue)
        XCTAssertNil(try second.retrieve(key: key))
    }

    func testBackingErrorsPropagateUnchanged() {
        let storage = NamespacedAuthLocalStorage(namespace: "valid", backing: FailingAuthStorage())

        XCTAssertThrowsError(try storage.retrieve(key: "any")) { error in
            XCTAssertEqual(error as? StorageFailure, .expected)
        }
        XCTAssertThrowsError(try storage.store(key: "any", value: Data([0x01]))) { error in
            XCTAssertEqual(error as? StorageFailure, .expected)
        }
        XCTAssertThrowsError(try storage.remove(key: "any")) { error in
            XCTAssertEqual(error as? StorageFailure, .expected)
        }
    }
}

private final class MemoryAuthStorage: AuthLocalStorage, @unchecked Sendable {
    private(set) var values: [String: Data] = [:]

    func store(key: String, value: Data) throws { values[key] = value }
    func retrieve(key: String) throws -> Data? { values[key] }
    func remove(key: String) throws { values.removeValue(forKey: key) }
}

private enum StorageFailure: Error, Equatable { case expected }

private struct FailingAuthStorage: AuthLocalStorage {
    func store(key: String, value: Data) throws { throw StorageFailure.expected }
    func retrieve(key: String) throws -> Data? { throw StorageFailure.expected }
    func remove(key: String) throws { throw StorageFailure.expected }
}
