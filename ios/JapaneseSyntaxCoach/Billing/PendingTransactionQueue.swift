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
    /// The Apple account token the purchase was made with. It identifies the account
    /// that owns the purchase, so a queued transaction is always stored for its owner.
    var appAccountToken: UUID?
    /// The last failure the server reported, empty while the item has not failed yet.
    var lastFailureReason: String?
    /// True when an automatic retry cannot succeed, so the item waits for the user.
    var isBlocked: Bool

    init(
        id: UUID = UUID(),
        transactionID: String,
        productID: String,
        signedTransaction: String,
        createdAt: Date = Date(),
        appAccountToken: UUID? = nil,
        lastFailureReason: String? = nil,
        isBlocked: Bool = false
    ) {
        self.id = id
        self.transactionID = transactionID
        self.productID = productID
        self.signedTransaction = signedTransaction
        self.createdAt = createdAt
        self.appAccountToken = appAccountToken
        self.lastFailureReason = lastFailureReason
        self.isBlocked = isBlocked
    }

    private enum CodingKeys: String, CodingKey {
        case id, transactionID, productID, signedTransaction, createdAt
        case appAccountToken, lastFailureReason, isBlocked
    }

    /// Queue files written by an earlier build do not carry the newer fields, so they
    /// are read with defaults instead of failing the whole file.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        transactionID = try container.decode(String.self, forKey: .transactionID)
        productID = try container.decode(String.self, forKey: .productID)
        signedTransaction = try container.decode(String.self, forKey: .signedTransaction)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        appAccountToken = try container.decodeIfPresent(UUID.self, forKey: .appAccountToken)
        lastFailureReason = try container.decodeIfPresent(String.self, forKey: .lastFailureReason)
        isBlocked = try container.decodeIfPresent(Bool.self, forKey: .isBlocked) ?? false
    }
}

/// Durable, user-scoped FIFO queue of transactions waiting for a server acknowledgement.
///
/// A queued transaction is only removed once the server accepted it. Every other
/// answer keeps the signed transaction on disk so it can be replayed later.
final class PendingTransactionQueue {
    typealias RetryOperation = (PendingTransaction) async -> Bool

    private let fileURL: URL
    private let lock = NSRecursiveLock()
    private var items: [PendingTransaction] = []
    /// The last write failure. The queue keeps working in memory, but the caller
    /// has to tell the user that pending purchases are no longer durable.
    private var writeError: String?
    /// A damaged queue file that was recovered. It stays visible until the queue is
    /// written again, because records may have been lost.
    private var recoveryNotice: String?
    /// A damaged queue file that was kept aside, so nothing is thrown away silently.
    private var corruptedFileURL: URL?

    init(fileURL: URL? = nil) {
        // The store manager always creates an account-scoped queue; this default only
        // serves callers that manage the queue themselves.
        self.fileURL = fileURL ?? Self.defaultFileURL(accountKey: "unassigned")
        loadFromDisk()
    }

    /// A message about the queue file the user should know: a write that failed, or a
    /// damaged file that was recovered.
    var lastPersistenceError: String? {
        lock.lock()
        defer { lock.unlock() }
        return writeError ?? recoveryNotice
    }

    /// The damaged file that was moved aside during recovery, if there was one.
    var recoveredCorruptedFileURL: URL? {
        lock.lock()
        defer { lock.unlock() }
        return corruptedFileURL
    }

    /// The number of queued transactions an automatic retry cannot fix.
    var blockedCount: Int { peek().filter(\.isBlocked).count }

    /// Adds a transaction, or refreshes the failure information of a transaction that is
    /// already queued. The signed transaction is never dropped while it is unacknowledged.
    func enqueue(_ item: PendingTransaction) {
        lock.lock()
        defer { lock.unlock() }
        if let index = items.firstIndex(where: { $0.transactionID == item.transactionID }) {
            var merged = items[index]
            merged.appAccountToken = item.appAccountToken ?? merged.appAccountToken
            merged.lastFailureReason = item.lastFailureReason
            merged.isBlocked = item.isBlocked
            items[index] = merged
        } else {
            items.append(item)
        }
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

    /// Removes the queued transaction with the given StoreKit transaction id.
    func remove(transactionID: String) {
        lock.lock()
        defer { lock.unlock() }
        items.removeAll { $0.transactionID == transactionID }
        persist()
    }

    /// Records why a queued transaction could not be synced.
    func markFailure(id: UUID, reason: String, isBlocked: Bool) {
        lock.lock()
        defer { lock.unlock() }
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].lastFailureReason = reason
        items[index].isBlocked = isBlocked
        persist()
    }

    func clear() {
        lock.lock()
        defer { lock.unlock() }
        items = []
        persist()
    }

    /// Drops every queued transaction and removes the backing file from the device.
    func discardAll() {
        lock.lock()
        defer { lock.unlock() }
        items = []
        do {
            if FileManager.default.fileExists(atPath: fileURL.path) {
                try FileManager.default.removeItem(at: fileURL)
            }
        } catch {
            writeError = "无法删除本机的待同步购买记录：\(error.localizedDescription)"
        }
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
            return
        }
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            writeError = "无法读取本机的待同步购买记录：\(error.localizedDescription)"
            items = []
            return
        }
        if let decoded = try? JSONDecoder().decode([PendingTransaction].self, from: data) {
            items = decoded
            return
        }

        // The file is damaged. Every entry that can still be read is recovered, and the
        // original bytes are kept aside so nothing is destroyed without a trace.
        let recovered = Self.lenientDecode(data)
        items = recovered.items
        if recovered.droppedCount > 0 {
            recoveryNotice = "本机的待同步购买记录已损坏，已恢复 \(recovered.items.count) 笔，其余 \(recovered.droppedCount) 笔无法读取。"
        }
        moveCorruptedFileAside()
        persist()
    }

    private func persist() {
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder().encode(items)
            try data.write(to: fileURL, options: .atomic)
            writeError = nil
        } catch {
            // Keep the in-memory queue usable, but report the failure so the user can be
            // told that the pending purchase is not stored on the device.
            writeError = "购买记录未能保存到本机（\(error.localizedDescription)）。"
        }
    }

    /// Keeps the damaged file next to the queue file, so the original bytes survive.
    private func moveCorruptedFileAside() {
        let backup = fileURL.appendingPathExtension("corrupted")
        do {
            if FileManager.default.fileExists(atPath: backup.path) {
                try FileManager.default.removeItem(at: backup)
            }
            try FileManager.default.moveItem(at: fileURL, to: backup)
            corruptedFileURL = backup
        } catch {
            writeError = "损坏的待同步购买记录无法备份：\(error.localizedDescription)"
        }
    }

    /// Reads a damaged queue file entry by entry, so one broken record does not cost
    /// every other pending purchase.
    private static func lenientDecode(_ data: Data) -> (items: [PendingTransaction], droppedCount: Int) {
        guard let raw = try? JSONSerialization.jsonObject(with: data),
              let entries = raw as? [[String: Any]] else {
            return ([], 0)
        }
        var items: [PendingTransaction] = []
        var droppedCount = 0
        for entry in entries {
            guard let transactionID = entry["transactionID"] as? String,
                  let signedTransaction = entry["signedTransaction"] as? String else {
                droppedCount += 1
                continue
            }
            items.append(
                PendingTransaction(
                    id: (entry["id"] as? String).flatMap(UUID.init(uuidString:)) ?? UUID(),
                    transactionID: transactionID,
                    productID: entry["productID"] as? String ?? "",
                    signedTransaction: signedTransaction,
                    createdAt: decodeDate(entry["createdAt"]) ?? Date(),
                    appAccountToken: (entry["appAccountToken"] as? String).flatMap(UUID.init(uuidString:)),
                    lastFailureReason: entry["lastFailureReason"] as? String,
                    isBlocked: entry["isBlocked"] as? Bool ?? false
                )
            )
        }
        return (items, droppedCount)
    }

    private static func decodeDate(_ value: Any?) -> Date? {
        if let seconds = value as? Double { return Date(timeIntervalSinceReferenceDate: seconds) }
        if let seconds = value as? Int { return Date(timeIntervalSinceReferenceDate: Double(seconds)) }
        if let text = value as? String {
            if let seconds = Double(text) { return Date(timeIntervalSinceReferenceDate: seconds) }
            return ISO8601DateFormatter().date(from: text)
        }
        return nil
    }

    static func billingDirectory() -> URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return support
            .appendingPathComponent("JapaneseSyntaxCoach", isDirectory: true)
            .appendingPathComponent("Billing", isDirectory: true)
    }

    static func defaultFileURL(accountKey: String) -> URL {
        billingDirectory()
            .appendingPathComponent("pending-transactions-\(accountKey).json")
    }

    /// Removes every account-scoped queue file from the device. Used when an account is
    /// deleted, so no purchase record of a removed account stays on the device.
    static func removeAllPersistedQueues() {
        let directory = billingDirectory()
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ) else { return }
        for url in contents where url.lastPathComponent.hasPrefix("pending-transactions-") {
            try? FileManager.default.removeItem(at: url)
        }
    }
}
