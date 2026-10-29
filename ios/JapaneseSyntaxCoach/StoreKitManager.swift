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
    @Published private(set) var isLoadingProducts = false

    private let provider: StoreKitProductProviding
    private let entitlements: EntitlementSubmitting
    private let userIDProvider: () -> String?
    private let queueProvider: (String?) -> PendingTransactionQueue
    private var queue: PendingTransactionQueue
    private var accountKey: String?
    private var updatesTask: Task<Void, Never>?

    init(
        provider: StoreKitProductProviding = LiveStoreKitProductProvider(),
        entitlements: EntitlementSubmitting,
        userIDProvider: @escaping () -> String?,
        queueProvider: @escaping (String?) -> PendingTransactionQueue = StoreKitManager.makeDefaultQueue
    ) {
        self.provider = provider
        self.entitlements = entitlements
        self.userIDProvider = userIDProvider
        self.queueProvider = queueProvider
        self.queue = queueProvider(nil)
        self.accountKey = nil
        updatesTask = Task { [weak self] in
            await self?.observeTransactionUpdates()
        }
        Task { await loadProducts() }
    }

    /// Nonisolated so it can be used as a default argument.
    nonisolated static func makeDefaultQueue(_ accountKey: String?) -> PendingTransactionQueue {
        guard let accountKey else {
            return PendingTransactionQueue(
                fileURL: FileManager.default.temporaryDirectory
                    .appendingPathComponent("pending-transactions-unassigned.json")
            )
        }
        return PendingTransactionQueue(fileURL: PendingTransactionQueue.defaultFileURL(accountKey: accountKey))
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
        queue = queueProvider(key)
        pendingSyncCount = queue.peek().count
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
        pendingSyncCount = queue.peek().count
        if let confirmed { return .restored(confirmed) }
        if pendingSyncCount > 0 { return .failed("购买记录已保留，联网后会自动同步。") }
        return .failed("没有可同步的购买记录。")
    }

    /// Replays transactions that the server has not acknowledged yet.
    func retryPendingTransactions() async {
        activateAccount(userIDProvider())
        guard !queue.peek().isEmpty else {
            pendingSyncCount = 0
            return
        }
        for item in queue.peek() {
            let outcome = await entitlements.submitOutcome(signedTransaction: item.signedTransaction)
            switch outcome {
            case .accepted(let state), .duplicate(let state):
                membership = state
                await provider.finish(transactionID: item.transactionID)
                queue.remove(id: item.id)
            case .networkFailure, .unauthorized:
                continue
            case .accountMismatch, .rejected:
                // Terminal: retrying cannot succeed, so stop tracking it.
                queue.remove(id: item.id)
            }
        }
        pendingSyncCount = queue.peek().count
    }

    private func handle(_ transaction: VerifiedTransaction) async -> PurchaseState {
        let outcome = await entitlements.submitOutcome(signedTransaction: transaction.signedTransaction)
        switch outcome {
        case .accepted(let state), .duplicate(let state):
            membership = state
            await provider.finish(transactionID: transaction.transactionID)
            return .success(state)
        case .accountMismatch(let message):
            return .accountMismatch(message)
        case .rejected(_, let message):
            return .rejected(message)
        case .unauthorized:
            return .notSignedIn
        case .networkFailure(let message):
            queue.enqueue(
                PendingTransaction(
                    transactionID: transaction.transactionID,
                    productID: transaction.productID,
                    signedTransaction: transaction.signedTransaction
                )
            )
            pendingSyncCount = queue.peek().count
            return .syncFailed(message)
        }
    }

    private func observeTransactionUpdates() async {
        for await transaction in provider.transactionUpdates() {
            _ = await handle(transaction)
        }
    }

    private static func accountKey(for userID: String) -> String {
        let normalized = userID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var hash: UInt64 = 5381
        for byte in normalized.utf8 {
            hash = (hash &* 33) &+ UInt64(byte)
        }
        return String(hash, radix: 16)
    }
}
