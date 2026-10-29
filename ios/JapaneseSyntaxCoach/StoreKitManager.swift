import Combine
import Foundation

/// Result of a purchase attempt.
enum PurchaseState: Equatable {
    /// The product could not be loaded from the App Store.
    case unavailable
    /// The user cancelled the purchase sheet.
    case cancelled
    /// The purchase is waiting for approval or payment confirmation.
    case pending
    /// StoreKit could not verify the transaction.
    case unverified
    /// The transaction is not tied to a signed-in account.
    case notSignedIn
    /// The server did not acknowledge the transaction; it stays queued for a retry.
    case syncFailed(String)
    /// The transaction belongs to a different account.
    case accountMismatch(String)
    /// Apple or the server rejected the transaction.
    case rejected(String)
    /// Another path is already syncing the same transaction.
    case processing
    /// The server acknowledged the transaction and confirmed the membership.
    case success(MembershipState)
}

/// Result of a restore attempt.
enum RestoreState: Equatable {
    /// The App Store has no purchase for this app.
    case noEntitlements
    /// The restore failed or nothing could be acknowledged.
    case failed(String)
    /// At least one entitlement was acknowledged by the server.
    case restored(MembershipState?)
}

@MainActor
final class StoreKitManager: ObservableObject {
    @Published private(set) var products: [StoreProduct] = []
    @Published private(set) var membership: MembershipState?
    @Published private(set) var pendingSyncCount = 0
    /// Queued purchases an automatic retry cannot fix; they wait for the user.
    @Published private(set) var blockedSyncCount = 0
    /// Set when a queued purchase could not be written to the device.
    @Published private(set) var queuePersistenceError: String?
    @Published private(set) var isLoadingProducts = false

    private let provider: StoreKitProductProviding
    private let entitlements: EntitlementSubmitting
    private let userIDProvider: () -> String?
    private let queueProvider: (String?) -> PendingTransactionQueue
    private var queue: PendingTransactionQueue
    private var unassignedQueue: PendingTransactionQueue
    /// One queue per account that made a purchase on this device.
    private var queuesByKey: [String: PendingTransactionQueue] = [:]
    private var accountKey: String?
    /// Transactions that are being submitted right now, so two paths cannot submit and
    /// finish the same transaction at the same time.
    private var processingTransactionIDs: Set<String> = []
    private var updatesTask: Task<Void, Never>?

    init(
        provider: StoreKitProductProviding? = nil,
        entitlements: EntitlementSubmitting,
        userIDProvider: @escaping () -> String?,
        queueProvider: @escaping (String?) -> PendingTransactionQueue = StoreKitManager.makeDefaultQueue
    ) {
        // The provider is created here instead of as a default argument, because a
        // default argument is evaluated outside the main actor.
        self.provider = provider ?? LiveStoreKitProductProvider()
        self.entitlements = entitlements
        self.userIDProvider = userIDProvider
        self.queueProvider = queueProvider
        let unassigned = queueProvider(nil)
        self.unassignedQueue = unassigned
        self.queue = unassigned
        self.accountKey = nil
        updatesTask = Task { [weak self] in
            await self?.observeTransactionUpdates()
        }
        Task { await loadProducts() }
    }

    /// Nonisolated so it can be used as a default argument.
    nonisolated static func makeDefaultQueue(_ accountKey: String?) -> PendingTransactionQueue {
        PendingTransactionQueue(fileURL: PendingTransactionQueue.defaultFileURL(accountKey: accountKey ?? "unassigned"))
    }

    deinit {
        updatesTask?.cancel()
    }

    func loadProducts() async {
        isLoadingProducts = true
        defer { isLoadingProducts = false }
        do {
            products = try await provider.loadProducts()
        } catch {
            products = []
        }
    }

    /// Switches the pending queue to the signed-in account. Transactions that were
    /// never acknowledged stay on disk for that account and are replayed on the next sign-in.
    func activateAccount(_ userID: String?) {
        let key = userID.map(Self.accountKey(for:))
        guard key != accountKey else { return }
        accountKey = key
        queue = queue(forKey: key)
        refreshQueueState()
    }

    func purchase(productID: String) async -> PurchaseState {
        guard let rawUserID = userIDProvider(), let token = UUID(uuidString: rawUserID) else {
            return .notSignedIn
        }
        activateAccount(rawUserID)
        if products.isEmpty { await loadProducts() }
        guard products.contains(where: { $0.id == productID }) else { return .unavailable }

        do {
            let outcome = try await provider.purchase(productID: productID, appAccountToken: token)
            switch outcome {
            case .cancelled: return .cancelled
            case .pending: return .pending
            case .unverified: return .unverified
            case .purchased(let transaction): return await handle(transaction)
            }
        } catch StoreKitProviderError.productUnavailable {
            return .unavailable
        } catch {
            return .syncFailed("购买失败，请检查 Apple 账户后重试。")
        }
    }

    func restorePurchases() async -> RestoreState {
        activateAccount(userIDProvider())
        do {
            try await provider.sync()
        } catch {
            return .failed("恢复购买失败，请稍后重试。")
        }
        let transactions = await provider.currentEntitlements()
            .filter { AppConfiguration.productIDs.contains($0.productID) }
        guard !transactions.isEmpty else { return .noEntitlements }

        var confirmed: MembershipState?
        for transaction in transactions {
            let state = await handle(transaction)
            if case .success(let membership) = state { confirmed = membership }
        }
        refreshQueueState()
        if let confirmed { return .restored(confirmed) }
        if pendingSyncCount > 0 { return .failed("购买记录已保留，联网后会自动同步。") }
        return .failed("没有可同步的购买记录。")
    }

    /// Replays transactions that the server has not acknowledged yet.
    func retryPendingTransactions() async {
        activateAccount(userIDProvider())
        await replay(queue.peek(), in: queue, includeBlocked: false)
    }

    /// Retries the queued purchases an automatic retry cannot fix.
    func retryBlockedTransactions() async {
        activateAccount(userIDProvider())
        await replay(queue.peek().filter(\.isBlocked), in: queue, includeBlocked: true)
    }

    /// Clears every trace of a deleted account: the membership snapshot and every queued
    /// purchase that is still stored on the device.
    func clearAccountData() {
        membership = nil
        for target in queuesByKey.values { target.discardAll() }
        unassignedQueue.discardAll()
        PendingTransactionQueue.removeAllPersistedQueues()
        refreshQueueState()
    }

    private func handle(_ transaction: VerifiedTransaction) async -> PurchaseState {
        guard let outcome = await submitOnce(transaction) else { return .processing }
        return await apply(outcome, to: transaction)
    }

    /// Submits a transaction to the server exactly once. The purchase flow, the
    /// transaction observer and the retry loop can all see the same transaction, but only
    /// one of them may talk to the server and finish it.
    private func submitOnce(_ transaction: VerifiedTransaction) async -> EntitlementOutcome? {
        guard !processingTransactionIDs.contains(transaction.transactionID) else { return nil }
        processingTransactionIDs.insert(transaction.transactionID)
        defer { processingTransactionIDs.remove(transaction.transactionID) }
        return await entitlements.submitOutcome(signedTransaction: transaction.signedTransaction)
    }

    /// Applies the server's answer. The transaction is only finished when the server
    /// acknowledged it; every other answer keeps the signed transaction on disk.
    private func apply(_ outcome: EntitlementOutcome, to transaction: VerifiedTransaction) async -> PurchaseState {
        let target = owningQueue(for: transaction)
        switch outcome {
        case .accepted(let state), .duplicate(let state):
            membership = state
            await provider.finish(transactionID: transaction.transactionID)
            target.remove(transactionID: transaction.transactionID)
            note(target)
            return .success(state)
        case .accountMismatch(let message):
            // The server will not accept this purchase for the signed-in account. The
            // purchase stays on disk under the account that made it, so it is synced when
            // that account signs in again.
            target.enqueue(pending(transaction, reason: message, isBlocked: false))
            note(target)
            return .accountMismatch(message)
        case .rejected(_, let message):
            target.enqueue(pending(transaction, reason: message, isBlocked: true))
            note(target)
            return .rejected(message)
        case .unauthorized:
            target.enqueue(pending(transaction, reason: "请先登录后再同步购买记录。", isBlocked: false))
            note(target)
            return .notSignedIn
        case .networkFailure(let message):
            target.enqueue(pending(transaction, reason: message, isBlocked: false))
            note(target)
            return .syncFailed(message)
        }
    }

    /// Replays queued transactions. An item is only removed when the server acknowledged
    /// it; every other answer keeps it queued with the reason it failed.
    private func replay(_ items: [PendingTransaction], in target: PendingTransactionQueue, includeBlocked: Bool) async {
        guard !items.isEmpty else {
            refreshQueueState()
            return
        }
        for item in items {
            if item.isBlocked && !includeBlocked { continue }
            let transaction = VerifiedTransaction(
                transactionID: item.transactionID,
                productID: item.productID,
                signedTransaction: item.signedTransaction,
                appAccountToken: item.appAccountToken
            )
            guard let outcome = await submitOnce(transaction) else { continue }
            switch outcome {
            case .accepted(let state), .duplicate(let state):
                membership = state
                await provider.finish(transactionID: item.transactionID)
                target.remove(id: item.id)
            case .networkFailure(let message):
                target.markFailure(id: item.id, reason: message, isBlocked: false)
            case .unauthorized:
                target.markFailure(id: item.id, reason: "请先登录后再同步购买记录。", isBlocked: false)
            case .accountMismatch(let message):
                target.markFailure(id: item.id, reason: message, isBlocked: false)
            case .rejected(_, let message):
                target.markFailure(id: item.id, reason: message, isBlocked: true)
            }
        }
        note(target)
    }

    private func pending(
        _ transaction: VerifiedTransaction,
        reason: String,
        isBlocked: Bool
    ) -> PendingTransaction {
        PendingTransaction(
            transactionID: transaction.transactionID,
            productID: transaction.productID,
            signedTransaction: transaction.signedTransaction,
            appAccountToken: transaction.appAccountToken,
            lastFailureReason: reason,
            isBlocked: isBlocked
        )
    }

    /// A purchase belongs to the account that made it, identified by the Apple account
    /// token. A transaction without a token stays with the signed-in account.
    private func owningQueue(for transaction: VerifiedTransaction) -> PendingTransactionQueue {
        guard let token = transaction.appAccountToken else { return queue }
        let key = Self.accountKey(for: token.uuidString)
        if key == accountKey { return queue }
        return queue(forKey: key)
    }

    private func queue(forKey key: String?) -> PendingTransactionQueue {
        guard let key else { return unassignedQueue }
        if let cached = queuesByKey[key] { return cached }
        let created = queueProvider(key)
        queuesByKey[key] = created
        return created
    }

    /// Refreshes the counters and reports a queue that could not be written.
    private func note(_ target: PendingTransactionQueue) {
        if let error = target.lastPersistenceError { queuePersistenceError = error }
        refreshQueueState()
    }

    private func refreshQueueState() {
        let items = queue.peek()
        pendingSyncCount = items.count
        blockedSyncCount = items.filter(\.isBlocked).count
        if let error = queue.lastPersistenceError { queuePersistenceError = error }
    }

    private func observeTransactionUpdates() async {
        for await transaction in provider.transactionUpdates() {
            // Only the app's own subscriptions are synced; anything else would be
            // rejected by the server and would only fill the pending queue with noise.
            guard AppConfiguration.productIDs.contains(transaction.productID) else { continue }
            _ = await handle(transaction)
        }
    }

    /// The file name of the queue that belongs to an account. The user id never appears
    /// on disk, only this hash.
    static func accountKey(for userID: String) -> String {
        let normalized = userID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var hash: UInt64 = 5381
        for byte in normalized.utf8 {
            hash = (hash &* 33) &+ UInt64(byte)
        }
        return String(hash, radix: 16)
    }
}
