import Foundation
import CoreFoundation

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
    private let writeData: (Data, URL) throws -> Void
    private static let lock = NSRecursiveLock()
    // Identity tokens stay alive while an instance has pending work, so generations
    // cannot wrap or be reused even if the file returns to identical bytes.
    private final class PathGeneration {}
    private static var pathGenerations: [String: PathGeneration] = [:]
    private static var activeWrites: Set<String> = []
    private var pendingGeneration: PathGeneration?
    private var hasWriteConflict = false
    private var currentPathGeneration: PathGeneration {
        if let generation = Self.pathGenerations[fileKey] { return generation }
        let generation = PathGeneration()
        Self.pathGenerations[fileKey] = generation
        return generation
    }
    @discardableResult
    private func advancePathGeneration() -> PathGeneration {
        let generation = PathGeneration()
        Self.pathGenerations[fileKey] = generation
        return generation
    }
    // discardAll is the only normal operation that removes the queue file. Share its
    // generation so another instance does not mistake that removal for data loss.
    private static var discardGenerations: [String: UInt64] = [:]
    private static var lastOperationWasDiscard: [String: Bool] = [:]
    private var lock: NSRecursiveLock { Self.lock }
    private var hasSeenFile = false
    private var discardGeneration: UInt64 = 0
    private var fileKey: String { fileURL.standardizedFileURL.path }
    private var items: [PendingTransaction] = []
    // Replay failed mutations against the latest disk state, never an old snapshot.
    private var pendingMutations: [(inout [PendingTransaction]) -> Void] = []
    /// The last write failure. The queue keeps working in memory, but the caller
    /// has to tell the user that pending purchases are no longer durable.
    private var writeError: String?
    /// A damaged queue file that was recovered. It stays visible until the queue is
    /// written again, because records may have been lost.
    private var recoveryNotice: String?
    /// A damaged queue file that was kept aside, so nothing is thrown away silently.
    private var corruptedFileURL: URL?
    /// Prevents a later write from replacing a queue file that could not be preserved.
    private var mustPreserveSourceFile = false

    init(
        fileURL: URL? = nil,
        writeData: @escaping (Data, URL) throws -> Void = { data, url in
            try data.write(to: url, options: .atomic)
        }
    ) {
        // The store manager always creates an account-scoped queue; this default only
        // serves callers that manage the queue themselves.
        self.fileURL = fileURL ?? Self.defaultFileURL(accountKey: "unassigned")
        self.writeData = writeData
        loadFromDisk()
    }

    /// A message about the queue file the user should know: a write that failed, or a
    /// damaged file that was recovered.
    var lastPersistenceError: String? {
        lock.lock()
        defer { lock.unlock() }
        return writeError ?? recoveryNotice
    }

    var hasUnsafeConflict: Bool {
        lock.lock()
        defer { lock.unlock() }
        loadFromDisk()
        return hasWriteConflict || mustPreserveSourceFile
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
    @discardableResult
    func enqueue(_ item: PendingTransaction) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        loadFromDisk()
        guard !mustPreserveSourceFile else { return false }
        let mutation: (inout [PendingTransaction]) -> Void = { items in
            if let index = items.firstIndex(where: { $0.transactionID == item.transactionID }) {
                var merged = items[index]
                merged.appAccountToken = item.appAccountToken ?? merged.appAccountToken
                merged.lastFailureReason = item.lastFailureReason
                merged.isBlocked = item.isBlocked
                items[index] = merged
            } else {
                items.append(item)
            }
        }
        pendingMutations.append(mutation)
        mutation(&items)
        return persist()
    }

    /// Retains an update without changing any existing record or merging conflicts.
    @discardableResult
    func retainUnsubmitted(_ item: PendingTransaction) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        loadFromDisk()
        let matches = items.filter { $0.transactionID == item.transactionID }
        if !matches.isEmpty {
            guard matches.count == 1, let existing = matches.first,
                  existing.productID == item.productID,
                  existing.signedTransaction == item.signedTransaction,
                  existing.appAccountToken == item.appAccountToken else {
                items.append(item)
                hasWriteConflict = true
                writeError = "购买记录存在冲突，未保存的新记录仅保留在内存中，请联系客服。"
                return false
            }
            return !mustPreserveSourceFile && !hasWriteConflict && pendingMutations.isEmpty && lastPersistenceError == nil
        }
        let mutation: (inout [PendingTransaction]) -> Void = { $0.append(item) }
        pendingMutations.append(mutation)
        mutation(&items)
        return persist()
    }

    func peek() -> [PendingTransaction] {
        lock.lock()
        defer { lock.unlock() }
        loadFromDisk()
        return items
    }

    func remove(id: UUID) {
        lock.lock()
        defer { lock.unlock() }
        loadFromDisk()
        guard !mustPreserveSourceFile else { return }
        let mutation: (inout [PendingTransaction]) -> Void = { $0.removeAll { $0.id == id } }
        pendingMutations.append(mutation)
        mutation(&items)
        persist()
    }

    /// Removes the queued transaction with the given StoreKit transaction id.
    func remove(transactionID: String) {
        lock.lock()
        defer { lock.unlock() }
        loadFromDisk()
        guard !mustPreserveSourceFile else { return }
        let mutation: (inout [PendingTransaction]) -> Void = { $0.removeAll { $0.transactionID == transactionID } }
        pendingMutations.append(mutation)
        mutation(&items)
        persist()
    }

    /// Records why a queued transaction could not be synced.
    func markFailure(id: UUID, reason: String, isBlocked: Bool) {
        lock.lock()
        defer { lock.unlock() }
        loadFromDisk()
        guard !mustPreserveSourceFile,
              let index = items.firstIndex(where: { $0.id == id }) else { return }
        _ = index
        let mutation: (inout [PendingTransaction]) -> Void = { items in
            guard let index = items.firstIndex(where: { $0.id == id }) else { return }
            items[index].lastFailureReason = reason
            items[index].isBlocked = isBlocked
        }
        pendingMutations.append(mutation)
        mutation(&items)
        persist()
    }

    func clear() {
        lock.lock()
        defer { lock.unlock() }
        loadFromDisk()
        guard !mustPreserveSourceFile else { return }
        let ids = Set(items.map(\.id))
        let mutation: (inout [PendingTransaction]) -> Void = { $0.removeAll { ids.contains($0.id) } }
        pendingMutations.append(mutation)
        mutation(&items)
        persist()
    }

    /// Drops every queued transaction and removes the backing file from the device.
    func discardAll() {
        lock.lock()
        defer { lock.unlock() }
        loadFromDisk()
        guard !mustPreserveSourceFile, !hasWriteConflict, pendingMutations.isEmpty else { return }
        do {
            if FileManager.default.fileExists(atPath: fileURL.path) {
                advancePathGeneration()
                try FileManager.default.removeItem(at: fileURL)
            }
            items = []
            hasSeenFile = false
            discardGeneration = (Self.discardGenerations[fileKey] ?? 0) &+ 1
            Self.discardGenerations[fileKey] = discardGeneration
            Self.lastOperationWasDiscard[fileKey] = true
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
        if hasWriteConflict || Self.activeWrites.contains(fileKey) || (pendingGeneration != nil && pendingGeneration !== currentPathGeneration) {
            hasWriteConflict = true
            writeError = "待同步购买记录已被其他实例更改，未决更改仅保存在内存中，无法保存。"
            return
        }
        let currentGeneration = Self.discardGenerations[fileKey] ?? 0
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            if currentGeneration != discardGeneration && Self.lastOperationWasDiscard[fileKey] == true {
                hasSeenFile = false
                discardGeneration = currentGeneration
            }
            if hasSeenFile {
                writeError = "本机的待同步购买记录文件意外消失，已保留内存记录，无法保存。"
                mustPreserveSourceFile = true
                return
            }
            items = []
            for mutation in pendingMutations { mutation(&items) }
            return
        }
        hasSeenFile = true
        discardGeneration = currentGeneration
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            writeError = "无法读取本机的待同步购买记录：\(error.localizedDescription)"
            mustPreserveSourceFile = true
            return
        }
        if let decoded = try? JSONDecoder().decode([PendingTransaction].self, from: data) {
            items = decoded
            for mutation in pendingMutations { mutation(&items) }
            return
        }

        // The file is damaged. Every entry that can still be read is recovered, and the
        // original bytes are kept aside so nothing is destroyed without a trace.
        let recovered = Self.lenientDecode(data)
        items = recovered.items
        for mutation in pendingMutations { mutation(&items) }
        if recovered.droppedCount > 0 {
            recoveryNotice = "本机的待同步购买记录已损坏，已恢复 \(recovered.items.count) 笔，其余 \(recovered.droppedCount) 笔无法读取。"
        }
        if recoveryNotice == nil {
            recoveryNotice = "本机的待同步购买记录已损坏，原文件已备份，部分记录可能无法恢复。"
        }
        if moveCorruptedFileAside() {
            // Recovery itself is pending until its replacement is durable.
            let recoveredItems = items
            pendingMutations.append { $0 = recoveredItems }
            persist()
        }
    }

    @discardableResult
    private func persist() -> Bool {
        guard !mustPreserveSourceFile, !hasWriteConflict else { return false }
        if hasSeenFile && !FileManager.default.fileExists(atPath: fileURL.path) {
            writeError = "本机的待同步购买记录文件意外消失，已保留内存记录，无法保存。"
            mustPreserveSourceFile = true
            return false
        }
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder().encode(items)
            // A throwing writer may already have changed the path. Invalidate other
            // instances before calling it, even when this attempt ultimately fails.
            pendingGeneration = advancePathGeneration()
            Self.activeWrites.insert(fileKey)
            defer { Self.activeWrites.remove(fileKey) }
            try writeData(data, fileURL)
            hasSeenFile = true
            Self.lastOperationWasDiscard[fileKey] = false
            // The writer can synchronously reenter this instance. Its snapshot does
            // not include those later mutations, so retain the conflict and all work.
            guard !hasWriteConflict else { return false }
            writeError = nil
            pendingMutations.removeAll()
            pendingGeneration = nil
            return true
        } catch {
            // Keep the in-memory queue usable, but report the failure so the user can be
            // told that the pending purchase is not stored on the device.
            if !pendingMutations.isEmpty && pendingGeneration == nil {
                pendingGeneration = currentPathGeneration
            }
            writeError = "购买记录未能保存到本机（\(error.localizedDescription)）。"
            return false
        }
    }

    /// Keeps the damaged file next to the queue file, so the original bytes survive.
    private func moveCorruptedFileAside() -> Bool {
        let baseBackup = fileURL.appendingPathExtension("corrupted")
        var backup = baseBackup
        var suffix = 1
        while FileManager.default.fileExists(atPath: backup.path) {
            backup = URL(fileURLWithPath: baseBackup.path + ".\(suffix)")
            suffix += 1
        }
        do {
            let generation = advancePathGeneration()
            try FileManager.default.moveItem(at: fileURL, to: backup)
            if pendingGeneration != nil { pendingGeneration = generation }
            hasSeenFile = false
            corruptedFileURL = backup
            return true
        } catch {
            mustPreserveSourceFile = true
            writeError = "损坏的待同步购买记录无法备份：\(error.localizedDescription)"
            return false
        }
    }

    /// Reads a damaged queue file entry by entry, so one broken record does not cost
    /// every other pending purchase.
    private static func lenientDecode(_ data: Data) -> (items: [PendingTransaction], droppedCount: Int) {
        guard let raw = try? JSONSerialization.jsonObject(with: data),
              let entries = raw as? [Any] else {
            return ([], 0)
        }
        var items: [PendingTransaction] = []
        var droppedCount = 0
        for rawEntry in entries {
            guard let entry = rawEntry as? [String: Any],
                  let transactionID = entry["transactionID"] as? String,
                  let signedTransaction = entry["signedTransaction"] as? String else {
                droppedCount += 1
                continue
            }
            let token: UUID?
            if let rawToken = entry["appAccountToken"], !(rawToken is NSNull) {
                guard let text = rawToken as? String, let parsed = UUID(uuidString: text) else {
                    droppedCount += 1
                    continue
                }
                token = parsed
            } else {
                token = nil
            }
            // JSON numbers can bridge to Bool, so check the underlying JSON type.
            // Missing/null fields keep the legacy decodeIfPresent default; malformed
            // values must not turn a potentially blocked transaction into a retry.
            let isBlocked: Bool
            if let value = entry["isBlocked"], !(value is NSNull) {
                if let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() {
                    isBlocked = number.boolValue
                } else {
                    isBlocked = true
                }
            } else {
                isBlocked = false
            }
            items.append(
                PendingTransaction(
                    id: (entry["id"] as? String).flatMap(UUID.init(uuidString:)) ?? UUID(),
                    transactionID: transactionID,
                    productID: entry["productID"] as? String ?? "",
                    signedTransaction: signedTransaction,
                    createdAt: decodeDate(entry["createdAt"]) ?? Date(),
                    appAccountToken: token,
                    lastFailureReason: entry["lastFailureReason"] as? String,
                    isBlocked: isBlocked
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

}
