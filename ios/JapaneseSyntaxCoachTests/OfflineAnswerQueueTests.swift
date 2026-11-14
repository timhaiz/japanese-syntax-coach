import Foundation
import XCTest
@testable import JapaneseSyntaxCoach

final class OfflineAnswerQueueTests: XCTestCase {
    func testFIFOOrderAndStableClientRequestIDsAcrossRetry() async {
        let queue = OfflineAnswerQueue(fileURL: temporaryFileURL())
        let first = item("L01-Q001")
        let second = item("L01-Q002")
        queue.enqueue(first)
        queue.enqueue(second)
        XCTAssertEqual(queue.peek().map(\.questionId), ["L01-Q001", "L01-Q002"])

        var submittedIDs: [String] = []
        await queue.retry { answer in
            submittedIDs.append(answer.clientRequestId)
            return true
        }
        XCTAssertEqual(submittedIDs, [first.clientRequestId, second.clientRequestId])
        XCTAssertTrue(queue.peek().isEmpty)

        queue.enqueue(first)
        var retriedID: String?
        await queue.retry { answer in
            retriedID = answer.clientRequestId
            return false
        }
        XCTAssertEqual(retriedID, first.clientRequestId)
        XCTAssertEqual(queue.peek().first?.clientRequestId, first.clientRequestId)
    }

    func testRemovalOnlyAfterSuccessAndFailedItemRetained() async {
        let queue = OfflineAnswerQueue(fileURL: temporaryFileURL())
        let accepted = item("L01-Q001")
        let failed = item("L01-Q002")
        queue.enqueue(accepted)
        queue.enqueue(failed)

        var callCount = 0
        await queue.retry { _ in
            callCount += 1
            if callCount == 1 { return true }
            throw QueueTestError.offline
        }

        XCTAssertEqual(queue.peek().map(\.id), [failed.id])
        XCTAssertEqual(queue.peek().first?.clientRequestId, failed.clientRequestId)
    }

    func testConcurrentRetryReportsInProgressAndDoesNotRunOperation() async {
        let queue = OfflineAnswerQueue(fileURL: temporaryFileURL())
        queue.enqueue(item("L01-Q001"))
        let started = expectation(description: "first retry started")
        let gate = RetryGate()
        let first = Task {
            await queue.retry { _ in
                await gate.wait(started: started)
                return true
            }
        }
        await fulfillment(of: [started], timeout: 5)

        let concurrent = await queue.retry { _ in
            XCTFail("A concurrent retry must not run its operation")
            return false
        }
        XCTAssertEqual(concurrent, .alreadyInProgress)
        XCTAssertEqual(queue.peek().count, 1)
        await gate.release()
        let firstResult = await first.value
        XCTAssertEqual(firstResult, .completed(1))
        XCTAssertTrue(queue.peek().isEmpty)
        let emptyResult = await queue.retry { _ in false }
        XCTAssertEqual(emptyResult, .completed(0))
    }

    func testOldRetryDoesNotOverwriteNewInstanceOrAnotherAccount() async {
        let url = temporaryFileURL()
        let old = OfflineAnswerQueue(fileURL: url)
        let first = item("L01-Q001")
        XCTAssertTrue(old.enqueue(first))
        let started = expectation(description: "old retry suspended")
        let gate = RetryGate()
        let retry = Task {
            await old.retry { answer in
                if answer.id == first.id {
                    await gate.wait(started: started)
                    return true
                }
                return false
            }
        }
        await fulfillment(of: [started], timeout: 5)
        let current = OfflineAnswerQueue(fileURL: url)
        let newAnswer = item("L01-Q002")
        XCTAssertTrue(current.enqueue(newAnswer))
        let other = OfflineAnswerQueue(fileURL: temporaryFileURL())
        let otherAnswer = item("L01-Q003")
        XCTAssertTrue(other.enqueue(otherAnswer))
        await gate.release()
        _ = await retry.value
        XCTAssertEqual(OfflineAnswerQueue(fileURL: url).peek().map(\.id), [newAnswer.id])
        XCTAssertEqual(other.peek().map(\.id), [otherAnswer.id])
    }

    func testDeletionStatusAndCleanupPreservePendingOrCorruptData() throws {
        let url = temporaryFileURL()
        let queue = OfflineAnswerQueue(fileURL: url)
        XCTAssertEqual(queue.deletionStatus(), .empty)
        XCTAssertTrue(queue.enqueue(item("L01-Q001")))
        XCTAssertEqual(queue.deletionStatus(), .pending)
        XCTAssertFalse(queue.clearIfEmpty())
        XCTAssertEqual(queue.peek().count, 1)
        queue.clear()
        XCTAssertTrue(queue.clearIfEmpty())
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        let original = Data("bad json".utf8)
        try original.write(to: url)
        XCTAssertEqual(queue.deletionStatus(), .unavailable)
        XCTAssertNil(queue.knownPendingCount)
        XCTAssertFalse(queue.clearIfEmpty())
        XCTAssertEqual(try Data(contentsOf: url), original)
    }

    private actor RetryGate {
        private var continuation: CheckedContinuation<Void, Never>?

        func wait(started: XCTestExpectation) async {
            await withCheckedContinuation { continuation in
                self.continuation = continuation
                started.fulfill()
            }
        }

        func release() {
            continuation?.resume()
            continuation = nil
        }
    }

    func testCorruptedPersistenceIsPreservedAndRejectsWrites() throws {
        let fileURL = temporaryFileURL()
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let original = Data("not json".utf8)
        try original.write(to: fileURL)
        let queue = OfflineAnswerQueue(fileURL: fileURL)
        XCTAssertFalse(queue.enqueue(item("L01-Q001")))
        queue.clear()
        XCTAssertEqual(try Data(contentsOf: fileURL), original)
    }

    func testExpectedMistakeVersionSurvivesPersistenceAndIsNotRewritten() throws {
        let fileURL = temporaryFileURL()
        let queue = OfflineAnswerQueue(fileURL: fileURL)
        let original = item("L01-Q001", expectedMistakeVersion: 7)
        XCTAssertTrue(queue.enqueue(original))

        let reopened = OfflineAnswerQueue(fileURL: fileURL)
        XCTAssertEqual(reopened.peek().first?.expectedMistakeVersion, 7)
        XCTAssertTrue(reopened.enqueue(item("L01-Q001", expectedMistakeVersion: 99)))
        XCTAssertEqual(reopened.peek().first?.expectedMistakeVersion, 7)
    }

    func testLegacyItemKeepsMissingExpectedMistakeVersion() throws {
        let fileURL = temporaryFileURL()
        let answer = item("L01-Q001")
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode([answer]).write(to: fileURL)

        let reopened = OfflineAnswerQueue(fileURL: fileURL)
        XCTAssertNil(reopened.peek().first?.expectedMistakeVersion)
    }

    func testLegacyMissingRequestIDUsesStableRecordID() throws {
        let fileURL = temporaryFileURL()
        let answer = item("L01-Q001")
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(answer)) as? [String: Any])
        object.removeValue(forKey: "clientRequestId")
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: [object]).write(to: fileURL)
        XCTAssertEqual(OfflineAnswerQueue(fileURL: fileURL).peek().first?.clientRequestId, answer.id.uuidString)
        XCTAssertEqual(OfflineAnswerQueue(fileURL: fileURL).peek().first?.clientRequestId, answer.id.uuidString)
    }

    func testFailedWriteDoesNotEnqueueInMemory() throws {
        let parent = temporaryFileURL()
        try FileManager.default.createDirectory(at: parent.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("file".utf8).write(to: parent)
        let queue = OfflineAnswerQueue(fileURL: parent.appendingPathComponent("queue.json"))
        XCTAssertFalse(queue.enqueue(item("L01-Q001")))
        XCTAssertTrue(queue.peek().isEmpty)
    }

    private func item(_ questionId: String, expectedMistakeVersion: Int? = nil) -> PendingAnswer {
        PendingAnswer(
            textbookId: "builtin-japanese-syntax",
            questionId: questionId,
            lessonId: 1,
            questionLimit: 20,
            answer: "test answer",
            correct: false,
            verdict: "needs_fix",
            errorTags: ["词汇"],
            knowledgeTags: ["句型"],
            mode: "lesson",
            expectedMistakeVersion: expectedMistakeVersion
        )
    }

    private func temporaryFileURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("answer-queue-tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString + ".json")
    }

    private enum QueueTestError: Error { case offline }
}
