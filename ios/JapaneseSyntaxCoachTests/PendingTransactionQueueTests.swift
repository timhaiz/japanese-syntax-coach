import XCTest
@testable import JapaneseSyntaxCoach

final class PendingTransactionQueueTests: XCTestCase {
    // MARK: - Queueing

    func testEnqueueKeepsOneEntryPerTransaction() {
        let queue = PendingTransactionQueue(fileURL: makeTemporaryQueueFileURL())

        queue.enqueue(makeItem(transactionID: "1", signedTransaction: "jws-1"))
        queue.enqueue(makeItem(transactionID: "1", signedTransaction: "jws-1"))

        XCTAssertEqual(queue.peek().count, 1)
    }

    func testRepeatedDeliveryRefreshesTheFailureReason() {
        let queue = PendingTransactionQueue(fileURL: makeTemporaryQueueFileURL())

        queue.enqueue(makeItem(transactionID: "1", signedTransaction: "jws-1", reason: "网络不可用", isBlocked: false))
        queue.enqueue(makeItem(transactionID: "1", signedTransaction: "jws-1", reason: "服务器未确认这笔购买。", isBlocked: true))

        XCTAssertEqual(queue.peek().count, 1)
        XCTAssertEqual(queue.peek().first?.lastFailureReason, "服务器未确认这笔购买。")
        XCTAssertEqual(queue.peek().first?.isBlocked, true)
    }

    func testMarkFailureKeepsTheTransactionQueued() {
        let queue = PendingTransactionQueue(fileURL: makeTemporaryQueueFileURL())
        let item = makeItem(transactionID: "1", signedTransaction: "jws-1")
        queue.enqueue(item)

        queue.markFailure(id: item.id, reason: "无法验证 Apple 购买记录。", isBlocked: true)

        XCTAssertEqual(queue.peek().count, 1)
        XCTAssertEqual(queue.peek().first?.lastFailureReason, "无法验证 Apple 购买记录。")
        XCTAssertEqual(queue.blockedCount, 1)
    }

    func testRemoveByTransactionID() {
        let queue = PendingTransactionQueue(fileURL: makeTemporaryQueueFileURL())
        queue.enqueue(makeItem(transactionID: "1", signedTransaction: "jws-1"))

        queue.remove(transactionID: "1")

        XCTAssertEqual(queue.peek().count, 0)
    }

    // MARK: - Durability

    func testQueueSurvivesANewInstance() {
        let fileURL = makeTemporaryQueueFileURL()
        let queue = PendingTransactionQueue(fileURL: fileURL)
        queue.enqueue(makeItem(transactionID: "1", signedTransaction: "jws-1", reason: "网络不可用", isBlocked: false))

        let reopened = PendingTransactionQueue(fileURL: fileURL)

        XCTAssertEqual(reopened.peek().count, 1)
        XCTAssertEqual(reopened.peek().first?.signedTransaction, "jws-1")
        XCTAssertEqual(reopened.peek().first?.lastFailureReason, "网络不可用")
    }

    func testDamagedQueueFileKeepsTheOriginalBytesAndRecoversReadableEntries() throws {
        let fileURL = makeTemporaryQueueFileURL()
        var entries = try JSONSerialization.jsonObject(
            with: JSONEncoder().encode([makeItem(transactionID: "1", signedTransaction: "jws-1")])
        ) as? [[String: Any]] ?? []
        // A second entry without a signed transaction cannot be used and is dropped.
        entries.append(["transactionID": "2", "productID": AppConfiguration.monthlyProductID])
        let original = try JSONSerialization.data(withJSONObject: entries)
        try original.write(to: fileURL)

        let queue = PendingTransactionQueue(fileURL: fileURL)

        XCTAssertEqual(queue.peek().count, 1)
        XCTAssertEqual(queue.peek().first?.transactionID, "1")
        XCTAssertNotNil(queue.lastPersistenceError)

        let backup = queue.recoveredCorruptedFileURL
        XCTAssertNotNil(backup)
        XCTAssertTrue(FileManager.default.fileExists(atPath: backup!.path))
        // The original file is preserved instead of being overwritten silently.
        let preserved = try Data(contentsOf: backup!)
        XCTAssertEqual(preserved.count, original.count)
    }

    func testWriteFailureIsReportedInsteadOfSwallowed() {
        let blocker = FileManager.default.temporaryDirectory
            .appendingPathComponent("queue-blocker-\(UUID().uuidString)")
        FileManager.default.createFile(atPath: blocker.path, contents: Data("x".utf8))
        defer { try? FileManager.default.removeItem(at: blocker) }

        let queue = PendingTransactionQueue(fileURL: blocker.appendingPathComponent("queue.json"))
        queue.enqueue(makeItem(transactionID: "1", signedTransaction: "jws-1"))

        XCTAssertEqual(queue.peek().count, 1)
        XCTAssertNotNil(queue.lastPersistenceError)
    }

    func testDiscardAllRemovesTheFile() {
        let fileURL = makeTemporaryQueueFileURL()
        let queue = PendingTransactionQueue(fileURL: fileURL)
        queue.enqueue(makeItem(transactionID: "1", signedTransaction: "jws-1"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))

        queue.discardAll()

        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
        XCTAssertEqual(queue.peek().count, 0)
    }

    func testRemoveAllPersistedQueuesRemovesEveryAccountFile() throws {
        let first = PendingTransactionQueue.defaultFileURL(accountKey: "unit-test-a")
        let second = PendingTransactionQueue.defaultFileURL(accountKey: "unit-test-b")
        try FileManager.default.createDirectory(
            at: first.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("[]".utf8).write(to: first)
        try Data("[]".utf8).write(to: second)
        defer {
            try? FileManager.default.removeItem(at: first)
            try? FileManager.default.removeItem(at: second)
        }

        PendingTransactionQueue.removeAllPersistedQueues()

        XCTAssertFalse(FileManager.default.fileExists(atPath: first.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: second.path))
    }

    // MARK: - Helpers

    private func makeItem(
        transactionID: String,
        signedTransaction: String,
        reason: String? = nil,
        isBlocked: Bool = false
    ) -> PendingTransaction {
        PendingTransaction(
            transactionID: transactionID,
            productID: AppConfiguration.monthlyProductID,
            signedTransaction: signedTransaction,
            appAccountToken: UUID(uuidString: "11111111-2222-3333-4444-555555555555"),
            lastFailureReason: reason,
            isBlocked: isBlocked
        )
    }
}

private func makeTemporaryQueueFileURL() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("PendingTransactionQueueTests-\(UUID().uuidString).json")
}
