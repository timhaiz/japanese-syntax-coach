import Combine
import Foundation

struct AuthGenerationSnapshot: Equatable {
    let account: UUID
    let login: UUID
}

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
    /// Every entitlement was acknowledged and finished.
    case restored(MembershipState?)
}

@MainActor
final class StoreKitManager: ObservableObject {
    @Published private(set) var products: [StoreProduct] = []
    @Published private(set) var membership: MembershipState?
    @Published private(set) var isRefreshingMembership = false
    @Published private(set) var membershipRefreshError: String?
    private var membershipRevision = UUID()
    @Published private(set) var pendingSyncCount = 0
    /// Queued purchases an automatic retry cannot fix; they wait for the user.
    @Published private(set) var blockedSyncCount = 0
    /// Set when a queued purchase could not be written to the device.
    @Published private(set) var queuePersistenceError: String?
    @Published private(set) var isLoadingProducts = false

    private let provider: StoreKitProductProviding
    private let entitlements: EntitlementSubmitting
    private let userIDProvider: () -> String?
    private let authGenerationProvider: (() -> AuthGenerationSnapshot?)?
    private var activeAuthGeneration: AuthGenerationSnapshot?
    private let queueProvider: (String?) -> PendingTransactionQueue
    private var queue: PendingTransactionQueue
    private var unassignedQueue: PendingTransactionQueue
    /// One queue per account that made a purchase on this device.
    private var queuesByKey: [String: PendingTransactionQueue] = [:]
    private var accountKey: String?
    /// An invalid retry identity is inactive without loading the unassigned queue.
    private var queueDetached = false
    private var accountGeneration = UUID()
    /// Transactions that are being submitted right now, so two paths cannot submit and
    /// finish the same transaction at the same time.
    private var processingTransactionIDs: Set<String> = []
    private var updatesTask: Task<Void, Never>?

    init(
        provider: StoreKitProductProviding? = nil,
        entitlements: EntitlementSubmitting,
        userIDProvider: @escaping () -> String?,
        authGenerationProvider: (() -> AuthGenerationSnapshot?)? = nil,
        queueProvider: @escaping (String?) -> PendingTransactionQueue = StoreKitManager.makeDefaultQueue
    ) {
        // The provider is created here instead of as a default argument, because a
        // default argument is evaluated outside the main actor.
        self.provider = provider ?? LiveStoreKitProductProvider()
        self.entitlements = entitlements
        self.userIDProvider = userIDProvider
        self.authGenerationProvider = authGenerationProvider
        self.activeAuthGeneration = authGenerationProvider?()
        self.queueProvider = queueProvider
        let unassigned = queueProvider(nil)
        self.unassignedQueue = unassigned
        self.queue = unassigned
        self.accountKey = nil
        refreshQueueState()
        let resolvedProvider = self.provider
        updatesTask = Task { [weak self] in
            for await transaction in resolvedProvider.transactionUpdates() {
                guard let self else { return }
                await self.handleTransactionUpdate(transaction)
            }
        }
        Task { [weak self] in await self?.loadProducts() }
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
        let authGeneration = authGenerationProvider?()
        let authGenerationChanged = authGenerationProvider != nil && authGeneration != activeAuthGeneration
        guard key != accountKey || queueDetached || authGenerationChanged else { return }
        queueDetached = false
        accountKey = key
        accountGeneration = UUID()
        activeAuthGeneration = authGeneration
        membershipRevision = UUID()
        membership = nil
        isRefreshingMembership = false
        membershipRefreshError = nil
        queue = queue(forKey: key)
        refreshQueueState()
    }

    /// Explicitly rechecks the current account without treating a failed lookup as free.
    func refreshMembership() async {
        guard let userID = userIDProvider(), UUID(uuidString: userID) != nil else {
            deactivateAccountWithoutLoadingQueue()
            membershipRefreshError = "请先登录后刷新会员状态。"
            return
        }
        activateAccount(userID)
        let generation = accountGeneration
        let key = accountKey
        let revision = UUID()
        membershipRevision = revision
        isRefreshingMembership = true
        membershipRefreshError = nil
        let state = await entitlements.refreshMembership()
        guard accountIsCurrent(generation: generation, key: key) else {
            // The identity provider can change before the view calls activateAccount.
            if generation == accountGeneration && key == accountKey {
                if let current = userIDProvider(), UUID(uuidString: current) != nil {
                    activateAccount(current)
                } else {
                    deactivateAccountWithoutLoadingQueue()
                }
            }
            return
        }
        guard revision == membershipRevision else { return }
        isRefreshingMembership = false
        membership = state
        if state == nil { membershipRefreshError = "会员状态暂时无法确认，请稍后重试。" }
    }

    // New purchases and entitlement synchronization are enabled.
    static let newPurchasesEnabled = true
    static let purchasePausedMessage = "新订阅暂时暂停，应用内恢复后的会员权益同步也暂不可用；已有订阅仍可在 Apple 账户中管理。"

    func purchase(productID: String) async -> PurchaseState {
        guard Self.newPurchasesEnabled else { return .rejected(Self.purchasePausedMessage) }
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
        guard let userID = userIDProvider(), UUID(uuidString: userID) != nil else {
            deactivateAccountWithoutLoadingQueue()
            return .failed("请先登录后重试。")
        }
        activateAccount(userID)
        let generation = accountGeneration
        let key = accountKey
        let accountChanged = RestoreState.failed("账号已切换，请重新恢复购买。")
        do {
            try await provider.sync()
        } catch {
            guard accountIsCurrent(generation: generation, key: key) else { return accountChanged }
            return .failed("恢复购买失败，请稍后重试。")
        }
        guard accountIsCurrent(generation: generation, key: key) else { return accountChanged }
        let transactions = await provider.currentEntitlements()
            .filter { AppConfiguration.productIDs.contains($0.productID) }
        guard accountIsCurrent(generation: generation, key: key) else { return accountChanged }
        guard !transactions.isEmpty else { return .noEntitlements }

        var confirmed: MembershipState?
        var failedTransactions = 0
        // Lower values have priority; never expose server or filesystem error text.
        var failures: Set<Int> = []
        for transaction in transactions {
            var finishUnavailable = false
            let state = await handle(transaction, onFinishUnavailable: { finishUnavailable = true })
            guard accountIsCurrent(generation: generation, key: key) else { return accountChanged }
            let persistenceFailed = owningQueue(for: transaction).lastPersistenceError != nil
            if persistenceFailed { failures.insert(0) }
            switch state {
            case .success(let membership): confirmed = membership
            case .accountMismatch: failedTransactions += 1; failures.insert(1)
            case .notSignedIn: failedTransactions += 1; failures.insert(2)
            case .rejected: failedTransactions += 1; failures.insert(3)
            case .syncFailed where persistenceFailed: failedTransactions += 1
            case .syncFailed where finishUnavailable: failedTransactions += 1; failures.insert(5)
            case .processing: failedTransactions += 1; failures.insert(6)
            default: failedTransactions += 1; failures.insert(4)
            }
        }
        refreshQueueState()
        if let priority = failures.min() {
            let prefix = failedTransactions == 0 ? "购买记录已处理，但本机购买记录可能未能保存。" : confirmed == nil ? "购买记录未能完成恢复。" : "部分购买记录未能完成恢复。"
            let guidance: String
            switch priority {
            case 0: guidance = "本机无法保存购买记录，请检查设备存储后重试或联系客服。"
            case 1: guidance = "请确认当前登录的是购买时使用的账号。"
            case 2: guidance = "请先登录后重试。"
            case 3: guidance = "请联系客服处理。"
            case 5: guidance = "购买记录的完成状态暂时无法确认，请稍后再次恢复购买或联系客服。"
            case 6: guidance = "购买记录正在处理中，请稍后再次恢复购买。"
            default: guidance = "同步暂未完成，请稍后重试或联系客服。"
            }
            let additional = failures.count > 1 ? "还存在其他问题，请联系客服。" : ""
            return .failed(prefix + guidance + additional)
        }
        return .restored(confirmed)
    }

    /// Replays transactions that the server has not acknowledged yet.
    func retryPendingTransactions() async {
        let userID = userIDProvider()
        guard let userID, UUID(uuidString: userID) != nil else {
            deactivateAccountWithoutLoadingQueue()
            return
        }
        activateAccount(userID)
        await replay(queue.peek(), in: queue, includeBlocked: false)
    }

    /// Retries the queued purchases an automatic retry cannot fix.
    func retryBlockedTransactions() async {
        let userID = userIDProvider()
        guard let userID, UUID(uuidString: userID) != nil else {
            deactivateAccountWithoutLoadingQueue()
            return
        }
        activateAccount(userID)
        await replay(queue.peek().filter(\.isBlocked), in: queue, includeBlocked: true)
    }

    private func deactivateAccountWithoutLoadingQueue() {
        accountKey = nil
        accountGeneration = UUID()
        activeAuthGeneration = authGenerationProvider?()
        membershipRevision = UUID()
        membership = nil
        isRefreshingMembership = false
        membershipRefreshError = nil
        queue = unassignedQueue
        queueDetached = true
        refreshQueueState()
    }

    private func handle(_ transaction: VerifiedTransaction, onFinishUnavailable: () -> Void = {}) async -> PurchaseState {
        let generation = accountGeneration
        let key = accountKey
        let target = owningQueue(for: transaction)
        guard !target.hasUnsafeConflict else {
            target.retainUnsubmitted(pending(transaction, reason: "购买记录等待处理。", isBlocked: false))
            note(target)
            return .syncFailed("本机购买记录存在问题，请联系客服。")
        }
        guard processingTransactionIDs.insert(transaction.transactionID).inserted else { return .processing }
        defer { processingTransactionIDs.remove(transaction.transactionID) }
        guard retainBeforeSubmission(transaction, in: target) else {
            note(target)
            return .syncFailed("本机无法保存购买记录，请检查设备存储后重试或联系客服。")
        }
        let revision = beginMembershipUpdate()
        let outcome = await entitlements.submitOutcome(signedTransaction: transaction.signedTransaction)
        guard accountIsCurrent(generation: generation, key: key), !target.hasUnsafeConflict else {
            let target = owningQueue(for: transaction)
            target.retainUnsubmitted(pending(transaction, reason: "账号已切换，购买记录等待原账号同步。", isBlocked: false))
            note(target)
            return .syncFailed("账号已切换，购买记录等待原账号同步。")
        }
        return await apply(outcome, to: transaction, generation: generation, key: key, revision: revision, onFinishUnavailable: onFinishUnavailable)
    }

    private func beginMembershipUpdate() -> UUID {
        let revision = UUID()
        membershipRevision = revision
        isRefreshingMembership = false
        membershipRefreshError = nil
        return revision
    }

    private func accountIsCurrent(generation: UUID, key: String?) -> Bool {
        let authIsCurrent: Bool
        if let authGenerationProvider {
            guard let activeAuthGeneration, let current = authGenerationProvider() else { return false }
            authIsCurrent = current == activeAuthGeneration
        } else {
            authIsCurrent = true
        }
        return authIsCurrent && generation == accountGeneration && key == accountKey &&
            key == userIDProvider().map(Self.accountKey(for:))
    }

    /// Applies the server's answer. The transaction is only finished when the server
    /// acknowledged it; every other answer keeps the signed transaction on disk.
    private func apply(
        _ outcome: EntitlementOutcome,
        to transaction: VerifiedTransaction,
        generation: UUID,
        key: String?,
        revision: UUID,
        onFinishUnavailable: () -> Void
    ) async -> PurchaseState {
        let target = owningQueue(for: transaction)
        switch outcome {
        case .accepted(let state), .duplicate(let state):
            guard accountIsCurrent(generation: generation, key: key) else {
                target.retainUnsubmitted(pending(transaction, reason: "账号已切换，购买记录等待原账号同步。", isBlocked: false))
                note(target)
                return .syncFailed("账号已切换，购买记录等待原账号同步。")
            }
            guard target.enqueue(pending(transaction, reason: "购买记录等待完成同步。", isBlocked: false)) else {
                note(target)
                return .syncFailed("本机无法保存购买记录，请检查设备存储后重试或联系客服。")
            }
            let finished = await provider.finish(transactionID: transaction.transactionID)
            guard accountIsCurrent(generation: generation, key: key) else {
                note(target)
                return .syncFailed("账号已切换，购买记录等待原账号同步。")
            }
            guard finished else {
                note(target)
                onFinishUnavailable()
                return .syncFailed("购买记录等待完成同步。")
            }
            if revision == membershipRevision { membership = state }
            target.remove(transactionID: transaction.transactionID)
            note(target)
            return .success(state)
        case .accountMismatch(let message):
            // The server will not accept this purchase for the signed-in account. The
            // purchase stays on disk under the account that made it, so it is synced when
            // that account signs in again.
            target.enqueue(pending(transaction, reason: message, isBlocked: false))
            note(target)
            return .accountMismatch("交易账号与当前账号不匹配。")
        case .rejected(_, let message):
            target.enqueue(pending(transaction, reason: message, isBlocked: true))
            note(target)
            return .rejected("购买记录未获确认，请联系客服处理。")
        case .unauthorized:
            target.enqueue(pending(transaction, reason: "请先登录后再同步购买记录。", isBlocked: false))
            note(target)
            return .notSignedIn
        case .networkFailure(let message):
            target.enqueue(pending(transaction, reason: message, isBlocked: false))
            note(target)
            return .syncFailed("购买记录同步失败，请稍后重试或联系客服。")
        }
    }

    /// Replays queued transactions. An item is only removed when the server acknowledged
    /// it; every other answer keeps it queued with the reason it failed.
    private func replay(_ items: [PendingTransaction], in target: PendingTransactionQueue, includeBlocked: Bool) async {
        let generation = accountGeneration
        let key = accountKey
        defer { note(target) }
        guard !target.hasUnsafeConflict else { return }
        func accountIsCurrent() -> Bool {
            self.accountIsCurrent(generation: generation, key: key)
        }
        guard !items.isEmpty else {
            refreshQueueState()
            return
        }
        for item in items {
            guard accountIsCurrent() else { return }
            if item.isBlocked && !includeBlocked { continue }
            let transaction = VerifiedTransaction(
                transactionID: item.transactionID,
                productID: item.productID,
                signedTransaction: item.signedTransaction,
                appAccountToken: item.appAccountToken
            )
            guard processingTransactionIDs.insert(transaction.transactionID).inserted else { continue }
            defer { processingTransactionIDs.remove(transaction.transactionID) }
            let revision = beginMembershipUpdate()
            let outcome = await entitlements.submitOutcome(signedTransaction: transaction.signedTransaction)
            guard accountIsCurrent(), !target.hasUnsafeConflict else { return }
            switch outcome {
            case .accepted(let state), .duplicate(let state):
                guard target.enqueue(item) else {
                    note(target)
                    continue
                }
                let finished = await provider.finish(transactionID: item.transactionID)
                guard accountIsCurrent() else { return }
                guard finished else { continue }
                if revision == membershipRevision { membership = state }
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
    }

    private func retainBeforeSubmission(_ transaction: VerifiedTransaction, in target: PendingTransactionQueue) -> Bool {
        let item = pending(transaction, reason: "购买记录等待同步。", isBlocked: false)
        if target.retainUnsubmitted(item) { return true }
        guard !target.hasUnsafeConflict else { return false }
        let matches = target.peek().filter { $0.transactionID == item.transactionID }
        guard matches.count == 1,
              let existing = matches.first,
              existing.productID == item.productID,
              existing.signedTransaction == item.signedTransaction,
              existing.appAccountToken == item.appAccountToken else { return false }
        return target.enqueue(existing)
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

    /// A purchase belongs to the account identified by its Apple account token. Without
    /// that token, ownership is unknown and the transaction stays unassigned.
    private func owningQueue(for transaction: VerifiedTransaction) -> PendingTransactionQueue {
        guard let token = transaction.appAccountToken else { return unassignedQueue }
        let key = Self.accountKey(for: token.uuidString)
        return queue(forKey: key)
    }

    private func queue(forKey key: String?) -> PendingTransactionQueue {
        guard let key else { return unassignedQueue }
        if let cached = queuesByKey[key] { return cached }
        let created = queueProvider(key)
        queuesByKey[key] = created
        return created
    }

    /// Refreshes current-account counters and the device-wide persistence warning.
    private func note(_ target: PendingTransactionQueue) {
        refreshQueueState()
    }

    private func refreshQueueState() {
        if queueDetached {
            pendingSyncCount = 0
            blockedSyncCount = 0
        } else {
            let items = queue.peek()
            pendingSyncCount = items.count
            blockedSyncCount = items.filter(\.isBlocked).count
        }
        // A different account or an unassigned transaction can still have unsaved
        // changes. Never attribute this device-wide warning to the signed-in account.
        let hasRisk = unassignedQueue.lastPersistenceError != nil ||
            queuesByKey.values.contains { $0.lastPersistenceError != nil }
        queuePersistenceError = hasRisk ? "本机购买记录可能存在保存或恢复问题，请联系客服。" : nil
    }

    private func handleTransactionUpdate(_ transaction: VerifiedTransaction) async {
        // Only the app's own subscriptions are synced; anything else would be
        // rejected by the server and would only fill the pending queue with noise.
        guard AppConfiguration.productIDs.contains(transaction.productID) else { return }
        guard let userID = userIDProvider(), UUID(uuidString: userID) != nil else {
            deactivateAccountWithoutLoadingQueue()
            let target = owningQueue(for: transaction)
            target.retainUnsubmitted(pending(transaction, reason: "请先登录后再同步购买记录。", isBlocked: false))
            note(target)
            return
        }
        activateAccount(userID)
        _ = await handle(transaction)
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
