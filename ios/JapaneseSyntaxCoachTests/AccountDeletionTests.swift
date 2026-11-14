import Foundation
import XCTest
@testable import JapaneseSyntaxCoach

final class AccountDeletionTests: XCTestCase {
    func testDeletionFreezePersistsAndBlocksQueueWritesAndCleanup() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("account-deletion-tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString + ".json")
        let queue = OfflineAnswerQueue(fileURL: url)
        XCTAssertTrue(queue.freezeForDeletionVerification())

        let reopened = OfflineAnswerQueue(fileURL: url)
        XCTAssertTrue(reopened.isDeletionFrozen)
        XCTAssertFalse(reopened.enqueue(Self.answer()))
        XCTAssertFalse(reopened.clearIfEmpty())
        XCTAssertEqual(reopened.deletionStatus(), .unavailable)
    }

    func testRetryLeaseIsSharedByInstancesForSameQueueFile() async {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("account-deletion-tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString + ".json")
        let firstQueue = OfflineAnswerQueue(fileURL: url)
        XCTAssertTrue(firstQueue.enqueue(Self.answer()))
        let secondQueue = OfflineAnswerQueue(fileURL: url)
        let started = expectation(description: "retry started")
        let gate = Gate()
        let retry = Task {
            await firstQueue.retry { _ in
                await gate.wait(started: started)
                return false
            }
        }
        await fulfillment(of: [started], timeout: 5)
        guard case .inProgress = secondQueue.beginDeletion() else {
            await gate.release()
            _ = await retry.value
            return XCTFail("deletion allowed during retry")
        }
        let result = await secondQueue.retry { _ in
            XCTFail("The same queue file must have one retry owner")
            return false
        }
        XCTAssertEqual(result, .alreadyInProgress)
        await gate.release()
        _ = await retry.value
    }

    func testDeletionLeaseBlocksSamePathButNotAnotherAccount() {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let url = directory.appendingPathComponent("first.json")
        let first = OfflineAnswerQueue(fileURL: url)
        let second = OfflineAnswerQueue(fileURL: url)
        let other = OfflineAnswerQueue(fileURL: directory.appendingPathComponent("other.json"))
        let previousEpoch = second.deletionEpoch
        guard case .acquired = first.beginDeletion() else { return XCTFail("lease not acquired") }
        XCTAssertNotEqual(previousEpoch, second.deletionEpoch)
        guard case .inProgress = second.beginDeletion() else { return XCTFail("second deletion allowed") }
        XCTAssertFalse(second.enqueue(Self.answer()))
        XCTAssertTrue(other.enqueue(Self.answer()))
        XCTAssertTrue(first.clearEmptyQueueDuringDeletion())
        XCTAssertTrue(first.endDeletion(unfreeze: true))
        XCTAssertTrue(second.enqueue(Self.answer()))
    }

    func testDeletionRejectsPendingAndCorruptQueues() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let url = directory.appendingPathComponent("queue.json")
        let queue = OfflineAnswerQueue(fileURL: url)
        XCTAssertTrue(queue.enqueue(Self.answer()))
        guard case .pending = queue.beginDeletion() else { return XCTFail("pending queue accepted") }
        try Data("corrupt".utf8).write(to: url)
        guard case .unavailable = queue.beginDeletion() else { return XCTFail("corrupt queue accepted") }
    }

    func testUncertainDeletionStaysFrozenAfterLeaseReleased() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("queue.json")
        let queue = OfflineAnswerQueue(fileURL: url)
        guard case .acquired = queue.beginDeletion() else { return XCTFail("lease not acquired") }
        XCTAssertTrue(queue.endDeletion(unfreeze: false))
        let reopened = OfflineAnswerQueue(fileURL: url)
        XCTAssertTrue(reopened.isDeletionFrozen)
        XCTAssertFalse(reopened.enqueue(Self.answer()))
        guard case .unavailable = reopened.beginDeletion() else { return XCTFail("frozen queue accepted") }
    }

    private static func answer() -> PendingAnswer {
        PendingAnswer(textbookId: "builtin-japanese-syntax", questionId: "L01-Q001", lessonId: 1,
                      questionLimit: 20, answer: "answer", correct: false, verdict: "needs_fix",
                      errorTags: [], knowledgeTags: [], mode: "lesson")
    }

    private actor Gate {
        private var continuation: CheckedContinuation<Void, Never>?
        func wait(started: XCTestExpectation) async {
            await withCheckedContinuation { continuation in
                self.continuation = continuation
                started.fulfill()
            }
        }
        func release() { continuation?.resume(); continuation = nil }
    }
}
