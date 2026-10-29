import XCTest
@testable import JapaneseSyntaxCoach

@MainActor
final class StoreKitStateTests: XCTestCase {
    // MARK: - Purchase states

    func testPurchaseWithUnavailableProductReportsUnavailable() async {
        let provider = FakeStoreKitProvider(products: [])
        let manager = makeManager(provider: provider, entitlements: FakeEntitlements())

        let state = await manager.purchase(productID: AppConfiguration.monthlyProductID)

        XCTAssertEqual(state, .unavailable)
        XCTAssertTrue(provider.finishedTransactionIDs.isEmpty)
    }

    func testPurchaseWithoutSignedInUserDoesNotPurchase() async {
        let provider = FakeStoreKitProvider(products: [monthlyProduct])
        let manager = makeManager(provider: provider, entitlements: FakeEntitlements(), userID: nil)

        let state = await manager.purchase(productID: AppConfiguration.monthlyProductID)

        XCTAssertEqual(state, .notSignedIn)
        XCTAssertTrue(provider.purchaseAttempts.isEmpty)
        XCTAssertTrue(provider.finishedTransactionIDs.isEmpty)
    }

    func testUserCancellationIsReportedAndNothingIsFinished() async {
        let provider = FakeStoreKitProvider(products: [monthlyProduct])
        provider.purchaseOutcome = .cancelled
        let manager = makeManager(provider: provider, entitlements: FakeEntitlements())

        let state = await manager.purchase(productID: AppConfiguration.monthlyProductID)

        XCTAssertEqual(state, .cancelled)
        XCTAssertTrue(provider.finishedTransactionIDs.isEmpty)
    }

    func testPendingPurchaseIsReportedAndNothingIsFinished() async {
        let provider = FakeStoreKitProvider(products: [monthlyProduct])
        provider.purchaseOutcome = .pending
        let manager = makeManager(provider: provider, entitlements: FakeEntitlements())

        let state = await manager.purchase(productID: AppConfiguration.monthlyProductID)

        XCTAssertEqual(state, .pending)
        XCTAssertTrue(provider.finishedTransactionIDs.isEmpty)
    }

    func testUnverifiedTransactionIsRejectedAndNotFinished() async {
        let provider = FakeStoreKitProvider(products: [monthlyProduct])
        provider.purchaseOutcome = .unverified
        let manager = makeManager(provider: provider, entitlements: FakeEntitlements())

        let state = await manager.purchase(productID: AppConfiguration.monthlyProductID)

        XCTAssertEqual(state, .unverified)
        XCTAssertTrue(provider.finishedTransactionIDs.isEmpty)
    }

    // MARK: - Finish ordering

    func testSuccessfulSyncFinishesTheTransactionAfterAcknowledgement() async {
        let provider = FakeStoreKitProvider(products: [monthlyProduct])
        provider.purchaseOutcome = .purchased(verifiedTransaction)
        let entitlements = FakeEntitlements(outcome: .accepted(memberState))
        let manager = makeManager(provider: provider, entitlements: entitlements)

        let state = await manager.purchase(productID: AppConfiguration.monthlyProductID)

        XCTAssertEqual(state, .success(memberState))
        XCTAssertEqual(provider.finishedTransactionIDs, [verifiedTransaction.transactionID])
        XCTAssertEqual(entitlements.submittedTransactions, [verifiedTransaction.signedTransaction])
        XCTAssertEqual(manager.pendingSyncCount, 0)
    }

    func testDuplicateAcknowledgementAlsoFinishesTheTransaction() async {
        let provider = FakeStoreKitProvider(products: [monthlyProduct])
        provider.purchaseOutcome = .purchased(verifiedTransaction)
        let entitlements = FakeEntitlements(outcome: .duplicate(memberState))
        let manager = makeManager(provider: provider, entitlements: entitlements)

        let state = await manager.purchase(productID: AppConfiguration.monthlyProductID)

        XCTAssertEqual(state, .success(memberState))
        XCTAssertEqual(provider.finishedTransactionIDs, [verifiedTransaction.transactionID])
    }

    func testServerSyncFailureDoesNotFinishAndKeepsTheTransactionQueued() async {
        let provider = FakeStoreKitProvider(products: [monthlyProduct])
        provider.purchaseOutcome = .purchased(verifiedTransaction)
        let entitlements = FakeEntitlements(outcome: .networkFailure("网络不可用"))
        let queue = PendingTransactionQueue(fileURL: makeTemporaryQueueURL())
        let manager = makeManager(provider: provider, entitlements: entitlements, queue: queue)

        let state = await manager.purchase(productID: AppConfiguration.monthlyProductID)

        XCTAssertEqual(state, .syncFailed("网络不可用"))
        XCTAssertTrue(provider.finishedTransactionIDs.isEmpty)
        XCTAssertEqual(queue.peek().count, 1)
        XCTAssertEqual(queue.peek().first?.signedTransaction, verifiedTransaction.signedTransaction)
        XCTAssertEqual(manager.pendingSyncCount, 1)
    }

    func testUnauthorizedSubmissionKeepsTheTransactionQueuedForARetry() async {
        let provider = FakeStoreKitProvider(products: [monthlyProduct])
        provider.purchaseOutcome = .purchased(verifiedTransaction)
        let entitlements = FakeEntitlements(outcome: .unauthorized)
        let queue = PendingTransactionQueue(fileURL: makeTemporaryQueueURL())
        let manager = makeManager(provider: provider, entitlements: entitlements, queue: queue)

        let state = await manager.purchase(productID: AppConfiguration.monthlyProductID)

        XCTAssertEqual(state, .notSignedIn)
        XCTAssertTrue(provider.finishedTransactionIDs.isEmpty)
        XCTAssertEqual(queue.peek().count, 1)
        XCTAssertEqual(manager.pendingSyncCount, 1)
        XCTAssertEqual(manager.blockedSyncCount, 0)
    }

    func testAccountMismatchIsNotFinishedAndStaysOnDisk() async {
        let provider = FakeStoreKitProvider(products: [monthlyProduct])
        provider.purchaseOutcome = .purchased(verifiedTransaction)
        let entitlements = FakeEntitlements(outcome: .accountMismatch("交易账号与当前账号不匹配。"))
        let queue = PendingTransactionQueue(fileURL: makeTemporaryQueueURL())
        let manager = makeManager(provider: provider, entitlements: entitlements, queue: queue)

        let state = await manager.purchase(productID: AppConfiguration.monthlyProductID)

        XCTAssertEqual(state, .accountMismatch("交易账号与当前账号不匹配。"))
        XCTAssertTrue(provider.finishedTransactionIDs.isEmpty)
        // The signed transaction is never dropped without a server confirmation.
        XCTAssertEqual(queue.peek().count, 1)
        XCTAssertEqual(queue.peek().first?.lastFailureReason, "交易账号与当前账号不匹配。")
    }

    func testRejectedTransactionIsNotFinishedAndIsMarkedBlocked() async {
        let provider = FakeStoreKitProvider(products: [monthlyProduct])
        provider.purchaseOutcome = .purchased(verifiedTransaction)
        let entitlements = FakeEntitlements(outcome: .rejected(statusCode: 400, message: "无法验证 Apple 购买记录。"))
        let queue = PendingTransactionQueue(fileURL: makeTemporaryQueueURL())
        let manager = makeManager(provider: provider, entitlements: entitlements, queue: queue)

        let state = await manager.purchase(productID: AppConfiguration.monthlyProductID)

        XCTAssertEqual(state, .rejected("无法验证 Apple 购买记录。"))
        XCTAssertTrue(provider.finishedTransactionIDs.isEmpty)
        XCTAssertEqual(queue.peek().count, 1)
        XCTAssertEqual(manager.blockedSyncCount, 1)
    }

    func testPurchaseOfAnotherAccountIsFiledUnderTheAccountThatMadeIt() async {
        let provider = FakeStoreKitProvider(products: [monthlyProduct])
        provider.purchaseOutcome = .purchased(otherAccountTransaction)
        let entitlements = FakeEntitlements(outcome: .accountMismatch("交易账号与当前账号不匹配。"))
        var queues: [String: PendingTransactionQueue] = [:]
        let manager = makeManager(
            provider: provider,
            entitlements: entitlements,
            queueProvider: { key in
                let resolved = key ?? "unassigned"
                if let existing = queues[resolved] { return existing }
                let created = PendingTransactionQueue(fileURL: makeTemporaryQueueURL())
                queues[resolved] = created
                return created
            }
        )

        let state = await manager.purchase(productID: AppConfiguration.monthlyProductID)

        XCTAssertEqual(state, .accountMismatch("交易账号与当前账号不匹配。"))
        XCTAssertTrue(provider.finishedTransactionIDs.isEmpty)
        let ownerKey = StoreKitManager.accountKey(for: otherAccountUserID)
        XCTAssertEqual(queues[ownerKey]?.peek().count, 1)
        XCTAssertEqual(queues[ownerKey]?.peek().first?.appAccountToken, otherAccountTransaction.appAccountToken)
        // The signed-in account does not inherit the other account's purchase.
        let signedInKey = StoreKitManager.accountKey(for: signedInUserID)
        XCTAssertEqual(queues[signedInKey]?.peek().count, 0)
    }

    // MARK: - Retry and restore

    func testRetryFinishesTheTransactionOnceTheServerAcknowledges() async {
        let provider = FakeStoreKitProvider(products: [monthlyProduct])
        provider.purchaseOutcome = .purchased(verifiedTransaction)
        let entitlements = FakeEntitlements(outcome: .networkFailure("网络不可用"))
        let queue = PendingTransactionQueue(fileURL: makeTemporaryQueueURL())
        let manager = makeManager(provider: provider, entitlements: entitlements, queue: queue)

        _ = await manager.purchase(productID: AppConfiguration.monthlyProductID)
        XCTAssertEqual(queue.peek().count, 1)

        entitlements.outcome = .accepted(memberState)
        await manager.retryPendingTransactions()

        XCTAssertEqual(queue.peek().count, 0)
        XCTAssertEqual(provider.finishedTransactionIDs, [verifiedTransaction.transactionID])
        XCTAssertEqual(manager.pendingSyncCount, 0)
    }

    func testRetryKeepsTheTransactionQueuedWhenTheServerStillFails() async {
        let provider = FakeStoreKitProvider(products: [monthlyProduct])
        provider.purchaseOutcome = .purchased(verifiedTransaction)
        let entitlements = FakeEntitlements(outcome: .networkFailure("网络不可用"))
        let queue = PendingTransactionQueue(fileURL: makeTemporaryQueueURL())
        let manager = makeManager(provider: provider, entitlements: entitlements, queue: queue)

        _ = await manager.purchase(productID: AppConfiguration.monthlyProductID)
        await manager.retryPendingTransactions()

        XCTAssertEqual(queue.peek().count, 1)
        XCTAssertTrue(provider.finishedTransactionIDs.isEmpty)
    }

    func testRetryDoesNotDropAnItemTheServerNeverAcknowledged() async {
        let provider = FakeStoreKitProvider(products: [monthlyProduct])
        provider.purchaseOutcome = .purchased(verifiedTransaction)
        let entitlements = FakeEntitlements(outcome: .rejected(statusCode: 400, message: "无法验证 Apple 购买记录。"))
        let queue = PendingTransactionQueue(fileURL: makeTemporaryQueueURL())
        let manager = makeManager(provider: provider, entitlements: entitlements, queue: queue)

        _ = await manager.purchase(productID: AppConfiguration.monthlyProductID)
        await manager.retryPendingTransactions()

        // The transaction is neither finished nor thrown away: it stays on disk with
        // the reason the server gave.
        XCTAssertEqual(queue.peek().count, 1)
        XCTAssertEqual(queue.peek().first?.lastFailureReason, "无法验证 Apple 购买记录。")
        XCTAssertTrue(queue.peek().first?.isBlocked == true)
        XCTAssertTrue(provider.finishedTransactionIDs.isEmpty)
        XCTAssertEqual(manager.blockedSyncCount, 1)
    }

    func testBlockedTransactionsAreOnlyRetriedOnRequest() async {
        let provider = FakeStoreKitProvider(products: [monthlyProduct])
        provider.purchaseOutcome = .purchased(verifiedTransaction)
        let entitlements = FakeEntitlements(outcome: .rejected(statusCode: 400, message: "无法验证 Apple 购买记录。"))
        let queue = PendingTransactionQueue(fileURL: makeTemporaryQueueURL())
        let manager = makeManager(provider: provider, entitlements: entitlements, queue: queue)

        _ = await manager.purchase(productID: AppConfiguration.monthlyProductID)
        entitlements.outcome = .accepted(memberState)
        await manager.retryPendingTransactions()
        XCTAssertEqual(queue.peek().count, 1)
        XCTAssertTrue(provider.finishedTransactionIDs.isEmpty)

        await manager.retryBlockedTransactions()

        XCTAssertEqual(queue.peek().count, 0)
        XCTAssertEqual(provider.finishedTransactionIDs, [verifiedTransaction.transactionID])
    }

    func testRestoreWithoutEntitlementsReportsNoEntitlements() async {
        let provider = FakeStoreKitProvider(products: [monthlyProduct])
        provider.entitlements = []
        let manager = makeManager(provider: provider, entitlements: FakeEntitlements())

        let state = await manager.restorePurchases()

        XCTAssertEqual(state, .noEntitlements)
        XCTAssertTrue(provider.finishedTransactionIDs.isEmpty)
    }

    func testRestoreSubmitsAndFinishesEveryOwnedTransaction() async {
        let provider = FakeStoreKitProvider(products: [monthlyProduct])
        provider.entitlements = [verifiedTransaction]
        let entitlements = FakeEntitlements(outcome: .accepted(memberState))
        let manager = makeManager(provider: provider, entitlements: entitlements)

        let state = await manager.restorePurchases()

        XCTAssertEqual(state, .restored(memberState))
        XCTAssertEqual(entitlements.submittedTransactions, [verifiedTransaction.signedTransaction])
        XCTAssertEqual(provider.finishedTransactionIDs, [verifiedTransaction.transactionID])
    }

    // MARK: - Transaction observer

    func testTransactionUpdateFailureIsQueuedForARetry() async {
        let provider = FakeStoreKitProvider(products: [monthlyProduct])
        let entitlements = FakeEntitlements(outcome: .networkFailure("网络不可用"))
        let queue = PendingTransactionQueue(fileURL: makeTemporaryQueueURL())
        let manager = makeManager(provider: provider, entitlements: entitlements, queue: queue)

        provider.emit(verifiedTransaction)

        let queued = await waitUntil { queue.peek().count == 1 }
        XCTAssertTrue(queued)
        XCTAssertTrue(provider.finishedTransactionIDs.isEmpty)
        XCTAssertEqual(manager.pendingSyncCount, 1)
    }

    func testTransactionUpdateWithoutASessionIsQueuedForARetry() async {
        let provider = FakeStoreKitProvider(products: [monthlyProduct])
        let entitlements = FakeEntitlements(outcome: .unauthorized)
        let queue = PendingTransactionQueue(fileURL: makeTemporaryQueueURL())
        let manager = makeManager(provider: provider, entitlements: entitlements, queue: queue)

        provider.emit(verifiedTransaction)

        let queued = await waitUntil { queue.peek().count == 1 }
        XCTAssertTrue(queued)
        XCTAssertTrue(provider.finishedTransactionIDs.isEmpty)
    }

    // MARK: - Concurrency

    func testConcurrentPathsSubmitAndFinishTheTransactionOnlyOnce() async {
        let provider = FakeStoreKitProvider(products: [monthlyProduct])
        provider.purchaseOutcome = .purchased(verifiedTransaction)
        provider.entitlements = [verifiedTransaction]
        let entitlements = FakeEntitlements(outcome: .accepted(memberState))
        entitlements.responseDelay = 0.3
        let manager = makeManager(provider: provider, entitlements: entitlements)

        let purchaseTask = Task { await manager.purchase(productID: AppConfiguration.monthlyProductID) }
        let submitted = await waitUntil { !entitlements.submittedTransactions.isEmpty }
        XCTAssertTrue(submitted)

        let restoreState = await manager.restorePurchases()
        let purchaseState = await purchaseTask.value

        XCTAssertEqual(entitlements.submittedTransactions.count, 1)
        XCTAssertEqual(provider.finishedTransactionIDs, [verifiedTransaction.transactionID])
        XCTAssertEqual(purchaseState, .success(memberState))
        if case .restored = restoreState {
            XCTFail("the same transaction must not be confirmed twice")
        }
    }

    // MARK: - Account deletion contract

    func testAccountDeletionRequiresTheExactConfirmation() async {
        let request = AccountDeletionRequest(confirmation: "delete")
        XCTAssertNotEqual(request.confirmation, AccountDeletionRequest.requiredConfirmation)
        XCTAssertEqual(AccountDeletionRequest.requiredConfirmation, "DELETE")
    }

    func testClearingTheAccountRemovesThePersistedQueueFile() async {
        let fileURL = makeTemporaryQueueURL()
        let queue = PendingTransactionQueue(fileURL: fileURL)
        queue.enqueue(
            PendingTransaction(
                transactionID: verifiedTransaction.transactionID,
                productID: verifiedTransaction.productID,
                signedTransaction: verifiedTransaction.signedTransaction
            )
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))

        let manager = makeManager(
            provider: FakeStoreKitProvider(products: [monthlyProduct]),
            entitlements: FakeEntitlements(),
            queue: queue
        )
        manager.clearAccountData()

        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
        XCTAssertEqual(queue.peek().count, 0)
    }

    // MARK: - Helpers

    private var signedInUserID: String { "11111111-2222-3333-4444-555555555555" }
    private var otherAccountUserID: String { "99999999-8888-7777-6666-555555555555" }

    private var monthlyProduct: StoreProduct {
        StoreProduct(
            id: AppConfiguration.monthlyProductID,
            displayName: "月度会员",
            displayPrice: "¥18",
            periodDescription: "每月",
            isSubscription: true
        )
    }

    private var verifiedTransaction: VerifiedTransaction {
        VerifiedTransaction(
            transactionID: "1000000000001",
            productID: AppConfiguration.monthlyProductID,
            signedTransaction: "signed-jws",
            appAccountToken: UUID(uuidString: signedInUserID)
        )
    }

    private var otherAccountTransaction: VerifiedTransaction {
        VerifiedTransaction(
            transactionID: "1000000000002",
            productID: AppConfiguration.monthlyProductID,
            signedTransaction: "signed-jws-other",
            appAccountToken: UUID(uuidString: otherAccountUserID)
        )
    }

    private var memberState: MembershipState {
        MembershipState(authenticated: true, status: .member, isMember: true, endsAt: "2026-12-31T00:00:00.000Z")
    }

    private func makeManager(
        provider: FakeStoreKitProvider,
        entitlements: FakeEntitlements,
        userID: String? = "11111111-2222-3333-4444-555555555555",
        queue: PendingTransactionQueue = PendingTransactionQueue(fileURL: makeTemporaryQueueURL()),
        queueProvider: ((String?) -> PendingTransactionQueue)? = nil
    ) -> StoreKitManager {
        StoreKitManager(
            provider: provider,
            entitlements: entitlements,
            userIDProvider: { userID },
            queueProvider: queueProvider ?? { _ in queue }
        )
    }

    /// Waits until the condition holds, so tests never depend on a fixed sleep.
    private func waitUntil(
        _ condition: @MainActor () -> Bool,
        timeout: TimeInterval = 3
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        return condition()
    }
}

@MainActor
private final class FakeStoreKitProvider: StoreKitProductProviding {
    var products: [StoreProduct]
    var purchaseOutcome: StorePurchaseOutcome
    var entitlements: [VerifiedTransaction] = []
    var purchaseAttempts: [(productID: String, appAccountToken: UUID?)] = []
    var finishedTransactionIDs: [String] = []
    var syncCalls = 0

    private var updatesContinuation: AsyncStream<VerifiedTransaction>.Continuation?
    private var bufferedUpdates: [VerifiedTransaction] = []
    private lazy var updates: AsyncStream<VerifiedTransaction> = {
        AsyncStream { continuation in
            updatesContinuation = continuation
            for transaction in bufferedUpdates { continuation.yield(transaction) }
            bufferedUpdates = []
        }
    }()

    init(products: [StoreProduct], purchaseOutcome: StorePurchaseOutcome = .cancelled) {
        self.products = products
        self.purchaseOutcome = purchaseOutcome
    }

    func loadProducts() async throws -> [StoreProduct] { products }

    func purchase(productID: String, appAccountToken: UUID?) async throws -> StorePurchaseOutcome {
        purchaseAttempts.append((productID, appAccountToken))
        return purchaseOutcome
    }

    func currentEntitlements() async -> [VerifiedTransaction] { entitlements }

    func transactionUpdates() -> AsyncStream<VerifiedTransaction> { updates }

    /// Delivers a transaction the way StoreKit does, outside of a purchase.
    func emit(_ transaction: VerifiedTransaction) {
        if let continuation = updatesContinuation {
            continuation.yield(transaction)
        } else {
            bufferedUpdates.append(transaction)
        }
    }

    func sync() async throws { syncCalls += 1 }

    func finish(transactionID: String) async {
        finishedTransactionIDs.append(transactionID)
    }
}

@MainActor
private final class FakeEntitlements: EntitlementSubmitting {
    var outcome: EntitlementOutcome
    var submittedTransactions: [String] = []
    var membership: MembershipState?
    /// Holds the submission open, so a test can run two paths against one transaction.
    var responseDelay: TimeInterval = 0

    init(outcome: EntitlementOutcome = .networkFailure("网络不可用"), membership: MembershipState? = nil) {
        self.outcome = outcome
        self.membership = membership
    }

    func submitOutcome(signedTransaction: String) async -> EntitlementOutcome {
        submittedTransactions.append(signedTransaction)
        if responseDelay > 0 {
            try? await Task.sleep(nanoseconds: UInt64(responseDelay * 1_000_000_000))
        }
        return outcome
    }

    func refreshMembership() async -> MembershipState? { membership }
}

/// Default arguments cannot call main-actor-isolated members, so the helper lives at file scope.
private func makeTemporaryQueueURL() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("StoreKitStateTests-\(UUID().uuidString).json")
}
