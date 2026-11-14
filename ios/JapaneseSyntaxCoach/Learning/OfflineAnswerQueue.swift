import Foundation

final class OfflineAnswerQueue {
    typealias RetryOperation = (PendingAnswer) async throws -> Bool

    enum RetryResult: Equatable {
        case alreadyInProgress
        case completed(Int)
    }

    private let fileURL: URL
    // All instances must serialize their read-modify-write transactions, including
    // instances recreated for the same account while an old retry is suspended.
    private static let lock = NSRecursiveLock()
    private static var retryingFiles = Set<String>()
    private static var deletingFiles = Set<String>()
    private static var deletionEpochs: [String: UUID] = [:]
    var deletionEpoch: UUID? {
        lock.lock()
        defer { lock.unlock() }
        return Self.deletionEpochs[pathKey]
    }
    private var deletionLeaseOwned = false
    private var pathKey: String { fileURL.standardizedFileURL.resolvingSymlinksInPath().path }
    private var lock: NSRecursiveLock { Self.lock }
    private var items: [PendingAnswer] = []
    private var loadFailed = false
    private var frozenForDeletion = false

    var isDeletionFrozen: Bool {
        lock.lock()
        defer { lock.unlock() }
        loadFromDisk()
        return frozenForDeletion
    }

    @discardableResult
    func freezeForDeletionVerification() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Data("verification-required".utf8).write(to: deletionFreezeURL, options: .atomic)
            frozenForDeletion = true
            return true
        } catch {
            return false
        }
    }

    enum DeletionLeaseResult {
        case acquired, unavailable, pending, inProgress
    }

    func beginDeletion() -> DeletionLeaseResult {
        lock.lock()
        defer { lock.unlock() }
        guard !Self.deletingFiles.contains(pathKey), !Self.retryingFiles.contains(pathKey) else { return .inProgress }
        loadFromDisk()
        guard !loadFailed, !frozenForDeletion else { return .unavailable }
        guard items.isEmpty else { return .pending }
        guard freezeForDeletionVerification() else { return .unavailable }
        Self.deletingFiles.insert(pathKey)
        Self.deletionEpochs[pathKey] = UUID()
        deletionLeaseOwned = true
        return .acquired
    }

    // Only the lease holder may clear the persistent marker. On failure it stays
    // frozen, including after process restart.
    func endDeletion(unfreeze: Bool) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard deletionLeaseOwned else { return false }
        var success = true
        if unfreeze {
            do { try FileManager.default.removeItem(at: deletionFreezeURL) }
            catch { success = false }
        }
        deletionLeaseOwned = false
        Self.deletingFiles.remove(pathKey)
        return success
    }

    func clearEmptyQueueDuringDeletion() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard deletionLeaseOwned else { return false }
        loadFromDisk()
        guard !loadFailed, items.isEmpty else { return false }
        do {
            if FileManager.default.fileExists(atPath: fileURL.path) {
                try FileManager.default.removeItem(at: fileURL)
            }
            return true
        } catch { return false }
    }

    var isAvailable: Bool {
        lock.lock()
        defer { lock.unlock() }
        loadFromDisk()
        return !loadFailed
    }

    var knownPendingCount: Int? {
        lock.lock()
        defer { lock.unlock() }
        loadFromDisk()
        return loadFailed ? nil : items.count
    }

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? Self.defaultFileURL
        loadFromDisk()
    }

    @discardableResult
    func enqueue(_ item: PendingAnswer) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        loadFromDisk()
        guard !loadFailed, !frozenForDeletion else { return false }
        if items.contains(where: { $0.id == item.id || $0.clientRequestId == item.clientRequestId }) { return true }
        let updated = items + [item]
        guard persist(updated) else { return false }
        items = updated
        return true
    }

    func peek() -> [PendingAnswer] {
        lock.lock()
        defer { lock.unlock() }
        loadFromDisk()
        return items
    }

    @discardableResult
    func remove(id: UUID) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        loadFromDisk()
        guard !loadFailed, !frozenForDeletion else { return false }
        let updated = items.filter { $0.id != id }
        guard persist(updated) else { return false }
        items = updated
        return true
    }

    @MainActor
    @discardableResult
    func retry(shouldRemove: () -> Bool = { true }, using operation: RetryOperation) async -> RetryResult {
        guard beginRetry() else { return .alreadyInProgress }
        defer { endRetry() }
        var removedCount = 0
        while let item = peek().first {
            do {
                guard try await operation(item) else { break }
                guard shouldRemove(), remove(id: item.id) else { break }
                removedCount += 1
            } catch {
                break
            }
        }
        return .completed(removedCount)
    }

    func clear() {
        lock.lock()
        defer { lock.unlock() }
        loadFromDisk()
        guard !loadFailed, !frozenForDeletion, persist([]) else { return }
        items = []
    }

    enum DeletionStatus: Equatable {
        case unavailable, pending, empty
    }

    func deletionStatus() -> DeletionStatus {
        lock.lock()
        defer { lock.unlock() }
        loadFromDisk()
        guard !loadFailed, !frozenForDeletion else { return .unavailable }
        return items.isEmpty ? .empty : .pending
    }

    // Never erase answers that appeared while an account deletion was in flight.
    @discardableResult
    func clearIfEmpty() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        loadFromDisk()
        guard !loadFailed, !frozenForDeletion, items.isEmpty else { return false }
        do {
            if FileManager.default.fileExists(atPath: fileURL.path) {
                try FileManager.default.removeItem(at: fileURL)
            }
            return true
        } catch {
            return false
        }
    }

    /// Claims the retry slot. Returns false when another retry is already running.
    /// The lock is taken inside a synchronous function, so it is never held across an
    /// await.
    private func beginRetry() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        loadFromDisk()
        guard !loadFailed, !frozenForDeletion, !Self.retryingFiles.contains(pathKey) else { return false }
        Self.retryingFiles.insert(pathKey)
        return true
    }

    private func endRetry() {
        lock.lock()
        defer { lock.unlock() }
        Self.retryingFiles.remove(pathKey)
    }

    private func loadFromDisk() {
        lock.lock()
        defer { lock.unlock() }
        frozenForDeletion = FileManager.default.fileExists(atPath: deletionFreezeURL.path)
        do {
            let data = try Data(contentsOf: fileURL)
            items = try JSONDecoder().decode([PendingAnswer].self, from: data)
            loadFailed = false
        } catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoSuchFileError {
            items = []
            loadFailed = false
        } catch {
            loadFailed = true
        }
    }

    private func persist(_ updated: [PendingAnswer]) -> Bool {
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder().encode(updated)
            try data.write(to: fileURL, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    private var deletionFreezeURL: URL {
        fileURL.appendingPathExtension("deletion-check-required")
    }

    private static var defaultFileURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return support
            .appendingPathComponent("JapaneseSyntaxCoach", isDirectory: true)
            .appendingPathComponent("Learning", isDirectory: true)
            .appendingPathComponent("answer-queue.json")
    }
}
