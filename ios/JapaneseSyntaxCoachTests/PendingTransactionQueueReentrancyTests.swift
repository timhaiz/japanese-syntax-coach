import Foundation

@main
enum PendingTransactionQueueReentrancyTests {
    static func main() throws {
        let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileURL = directory.appendingPathComponent("queue.json")
        let outer = PendingTransaction(transactionID: "outer", productID: "p", signedTransaction: "outer-signed")
        let inner = PendingTransaction(transactionID: "inner", productID: "p", signedTransaction: "inner-signed")
        var queue: PendingTransactionQueue!
        var innerResult: Bool?
        queue = PendingTransactionQueue(fileURL: fileURL) { data, url in
            innerResult = queue.enqueue(inner)
            try data.write(to: url, options: .atomic)
        }

        let outerResult = queue.enqueue(outer)
        let error = queue.lastPersistenceError
        let memory = queue.peek().map(\.transactionID)
        let disk = try JSONDecoder().decode([PendingTransaction].self, from: Data(contentsOf: fileURL)).map(\.transactionID)
        var failures = 0
        func check(_ condition: Bool, _ message: String) {
            if !condition { print("FAIL: \(message)"); failures += 1 }
        }
        check(innerResult == false, "reentrant enqueue must report failure")
        check(outerResult == false, "outer enqueue must report unresolved reentrant conflict")
        check(error != nil, "reentrant conflict must remain visible")
        check(memory == ["outer", "inner"], "both operations must remain in memory; got \(memory)")
        check(disk == ["outer"], "disk contains only the outer snapshot; got \(disk)")
        queue.discardAll()
        check(FileManager.default.fileExists(atPath: fileURL.path), "discard must not remove data during conflict")
        check(queue.peek().map(\.transactionID) == ["outer", "inner"], "discard must preserve pending memory")

        let normalURL = directory.appendingPathComponent("normal.json")
        let normal = PendingTransactionQueue(fileURL: normalURL)
        check(normal.enqueue(outer), "normal enqueue must succeed")
        check(normal.enqueue(inner), "subsequent normal enqueue must succeed")
        check(PendingTransactionQueue(fileURL: normalURL).peek().map(\.transactionID) == ["outer", "inner"], "normal writes must survive reopening")
        check(normal.lastPersistenceError == nil, "normal writes must not report errors")

        let retryURL = directory.appendingPathComponent("retry.json")
        var failWrite = true
        let retry = PendingTransactionQueue(fileURL: retryURL) { data, url in
            if failWrite { throw CocoaError(.fileWriteUnknown) }
            try data.write(to: url, options: .atomic)
        }
        check(!retry.enqueue(outer), "failed write must report failure")
        check(retry.lastPersistenceError != nil, "failed write must report an error")
        failWrite = false
        check(retry.enqueue(inner), "subsequent write must retry pending work")
        check(PendingTransactionQueue(fileURL: retryURL).peek().map(\.transactionID) == ["outer", "inner"], "retry must persist both operations")
        check(retry.lastPersistenceError == nil, "successful retry must clear the error")
        if failures > 0 { exit(1) }
        print("PASS: same-instance reentrant write preserves pending memory and conflict")
    }
}
