import Foundation

final class OfflineAnswerQueue {
    typealias RetryOperation = (PendingAnswer) async throws -> Bool

    private let fileURL: URL
    private let lock = NSRecursiveLock()
    private var items: [PendingAnswer] = []
    private var isRetrying = false

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? Self.defaultFileURL
        loadFromDisk()
    }

    func enqueue(_ item: PendingAnswer) {
        lock.lock()
        defer { lock.unlock() }
        guard !items.contains(where: { $0.id == item.id || $0.clientRequestId == item.clientRequestId }) else { return }
        items.append(item)
        persist()
    }

    func peek() -> [PendingAnswer] {
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

    func retry(using operation: RetryOperation) async -> Int {
        lock.lock()
        guard !isRetrying else {
            lock.unlock()
            return 0
        }
        isRetrying = true
        lock.unlock()
        var removedCount = 0
        defer {
            lock.lock()
            isRetrying = false
            lock.unlock()
        }

        while let item = peek().first {
            do {
                guard try await operation(item) else { break }
                remove(id: item.id)
                removedCount += 1
            } catch {
                break
            }
        }
        return removedCount
    }

    func clear() {
        lock.lock()
        defer { lock.unlock() }
        items = []
        persist()
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
            items = try JSONDecoder().decode([PendingAnswer].self, from: Data(contentsOf: fileURL))
        } catch {
            // Treat corrupt queue data as an empty recoverable queue; the next persist repairs it.
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
            // Keep the in-memory queue usable; pending count remains visible for this process.
        }
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
