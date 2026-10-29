import Foundation

/// A signed transaction that the server has not acknowledged yet.
///
/// The transaction stays queued until the server accepts it, so the StoreKit
/// transaction is never finished while the membership is unconfirmed.
struct PendingTransaction: Codable, Equatable, Identifiable {
    let id: UUID
    let transactionID: String
    let productID: String
    let signedTransaction: String
    let createdAt: Date

    init(
        id: UUID = UUID(),
        transactionID: String,
        productID: String,
        signedTransaction: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.transactionID = transactionID
        self.productID = productID
        self.signedTransaction = signedTransaction
        self.createdAt = createdAt
    }
}

/// Durable, user-scoped FIFO queue of transactions waiting for a server acknowledgement.
final class PendingTransactionQueue {
    typealias RetryOperation = (PendingTransaction) async -> Bool

    private let fileURL: URL
    private let lock = NSRecursiveLock()
    private var items: [PendingTransaction] = []

    init(fileURL: URL? = nil) {
        // The store manager always creates an account-scoped queue; this default only
        // serves callers that manage the queue themselves.
        self.fileURL = fileURL ?? Self.defaultFileURL(accountKey: "unassigned")
        loadFromDisk()
    }

    func enqueue(_ item: PendingTransaction) {
        lock.lock()
        defer { lock.unlock() }
        guard !items.contains(where: { $0.transactionID == item.transactionID }) else { return }
        items.append(item)
        persist()
    }

    func peek() -> [PendingTransaction] {
        lock.lock()
        defer { lock.unlock() }
        return items
    }

    func remove(id: UUID) {
        lock.lock()
        defer { lock.unlock() }
        items.removeAll { $0.id == id }
        persist()
    }

    func clear() {
        lock.lock()
        defer { lock.unlock() }
        items = []
        persist()
    }

    /// Removes every item the operation confirmed; the rest stays queued.
    func retry(using operation: RetryOperation) async -> Int {
        var removedCount = 0
        for item in peek() {
            guard await operation(item) else { break }
            remove(id: item.id)
            removedCount += 1
        }
        return removedCount
    }

    private func loadFromDisk() {
        lock.lock()
        defer { lock.unlock() }
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            items = []
            persist()
            return
        }
        do {
            items = try JSONDecoder().decode([PendingTransaction].self, from: Data(contentsOf: fileURL))
        } catch {
            // A corrupted queue must not break the app; the next write repairs the file.
            items = []
            persist()
        }
    }

    private func persist() {
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder().encode(items)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            // Keep the in-memory queue usable; the pending count stays visible.
        }
    }

    static func defaultFileURL(accountKey: String) -> URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return support
            .appendingPathComponent("JapaneseSyntaxCoach", isDirectory: true)
            .appendingPathComponent("Billing", isDirectory: true)
            .appendingPathComponent("pending-transactions-\(accountKey).json")
    }
}
