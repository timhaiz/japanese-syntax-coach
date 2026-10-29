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

    func testCorruptedPersistenceRecoversAsEmptyQueue() throws {
        let fileURL = temporaryFileURL()
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: fileURL)

        let queue = OfflineAnswerQueue(fileURL: fileURL)
        XCTAssertTrue(queue.peek().isEmpty)
        let answer = item("L01-Q001")
        queue.enqueue(answer)

        let recovered = OfflineAnswerQueue(fileURL: fileURL)
        XCTAssertEqual(recovered.peek().map(\.clientRequestId), [answer.clientRequestId])
    }

    private func item(_ questionId: String) -> PendingAnswer {
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
            mode: "lesson"
        )
    }

    private func temporaryFileURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("answer-queue-tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString + ".json")
    }

    private enum QueueTestError: Error { case offline }
}
