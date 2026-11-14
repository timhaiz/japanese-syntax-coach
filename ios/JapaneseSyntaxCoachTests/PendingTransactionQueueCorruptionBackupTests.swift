import Foundation

@main
enum PendingTransactionQueueCorruptionBackupTests {
    static func main() throws {
        try existingBackupIsPreservedAndCorruptionGetsAnotherName()
        try unreadableQueueIsNeverOverwritten()
        try failedBackupNeverOverwritesSource()
        print("PASS: corruption backup data-protection tests")
    }

    private static func existingBackupIsPreservedAndCorruptionGetsAnotherName() throws {
        try withTemporaryDirectory { directory in
            let queueURL = directory.appendingPathComponent("queue.json")
            let existingBackupURL = queueURL.appendingPathExtension("corrupted")
            let originalCorruption = Data(#"[{"transactionID":"recoverable","signedTransaction":"signed"},null]"#.utf8)
            let priorBackup = Data("older-corruption".utf8)
            try originalCorruption.write(to: queueURL)
            try priorBackup.write(to: existingBackupURL)

            let queue = PendingTransactionQueue(fileURL: queueURL)

            try expect(try Data(contentsOf: existingBackupURL) == priorBackup, "existing .corrupted backup must survive")
            try expect(try Data(contentsOf: queueURL) != originalCorruption, "recovered queue should be persisted after backup succeeds")
            let preservedCopy = directory.appendingPathComponent("queue.json.corrupted.1")
            try expect(FileManager.default.fileExists(atPath: preservedCopy.path), "original corruption must be preserved under a distinct backup name")
            try expect(try Data(contentsOf: preservedCopy) == originalCorruption, "distinct backup must contain original bytes")
            try expect(queue.recoveredCorruptedFileURL == preservedCopy, "queue must expose the actual backup URL")
        }
    }

    private static func unreadableQueueIsNeverOverwritten() throws {
        try withTemporaryDirectory { directory in
            let queueURL = directory.appendingPathComponent("queue.json")
            try FileManager.default.createDirectory(at: queueURL, withIntermediateDirectories: false)
            let markerURL = queueURL.appendingPathComponent("preserve-me")
            let marker = Data("original".utf8)
            try marker.write(to: markerURL)

            _ = PendingTransactionQueue(fileURL: queueURL)

            try expect(FileManager.default.fileExists(atPath: queueURL.path), "unreadable queue path must remain")
            try expect(try Data(contentsOf: markerURL) == marker, "unreadable queue contents must remain untouched")
        }
    }

    private static func failedBackupNeverOverwritesSource() throws {
        try withTemporaryDirectory { directory in
            let queueURL = directory.appendingPathComponent("queue.json")
            let originalCorruption = Data("not-json".utf8)
            try originalCorruption.write(to: queueURL)
            let backupURL = queueURL.appendingPathExtension("corrupted")
            try FileManager.default.createSymbolicLink(
                at: backupURL,
                withDestinationURL: directory.appendingPathComponent("missing-target")
            )

            let queue = PendingTransactionQueue(fileURL: queueURL)
            queue.enqueue(PendingTransaction(transactionID: "new", productID: "p", signedTransaction: "s"))

            try expect(try Data(contentsOf: queueURL) == originalCorruption, "failed backup must prevent persist from replacing original bytes")
            try expect(queue.lastPersistenceError?.contains("无法备份") == true, "backup failure must be reported")
        }
    }

    private static func withTemporaryDirectory(_ body: (URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PendingTransactionQueueCorruptionTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        try body(directory)
    }

    private static func expect(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
        guard try condition() else { throw TestFailure(description: message) }
    }
}

struct TestFailure: Error, CustomStringConvertible {
    let description: String
}
