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

    func testAccountMismatchIsNotFinishedAndNotRetriedForever() async {
        let provider = FakeStoreKitProvider(products: [monthlyProduct])
        provider.purchaseOutcome = .purchased(verifiedTransaction)
        let entitlements = FakeEntitlements(outcome: .accountMismatch("交易账号与当前账号不匹配。"))
        let queue = PendingTransactionQueue(fileURL: makeTemporaryQueueURL())
        let manager = makeManager(provider: provider, entitlements: entitlements, queue: queue)

        let state = await manager.purchase(productID: AppConfiguration.monthlyProductID)

        XCTAssertEqual(state, .accountMismatch("交易账号与当前账号不匹配。"))
        XCTAssertTrue(provider.finishedTransactionIDs.isEmpty)
        XCTAssertEqual(queue.peek().count, 0)
    }

    func testRejectedTransactionIsNotFinished() async {
        let provider = FakeStoreKitProvider(products: [monthlyProduct])
        provider.purchaseOutcome = .purchased(verifiedTransaction)
        let entitlements = FakeEntitlements(outcome: .rejected(statusCode: 400, message: "无法验证 Apple 购买记录。"))
        let manager = makeManager(provider: provider, entitlements: entitlements)

        let state = await manager.purchase(productID: AppConfiguration.monthlyProductID)

        XCTAssertEqual(state, .rejected("无法验证 Apple 购买记录。"))
        XCTAssertTrue(provider.finishedTransactionIDs.isEmpty)
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

    // MARK: - Account deletion contract

    func testAccountDeletionRequiresTheExactConfirmation() async {
        let request = AccountDeletionRequest(confirmation: "delete")
        XCTAssertNotEqual(request.confirmation, AccountDeletionRequest.requiredConfirmation)
        XCTAssertEqual(AccountDeletionRequest.requiredConfirmation, "DELETE")
    }

    // MARK: - Helpers

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
            appAccountToken: UUID(uuidString: "11111111-2222-3333-4444-555555555555")
        )
    }

    private var memberState: MembershipState {
        MembershipState(authenticated: true, status: .member, isMember: true, endsAt: "2026-12-31T00:00:00.000Z")
    }

    private func makeManager(
        provider: FakeStoreKitProvider,
        entitlements: FakeEntitlements,
        userID: String? = "11111111-2222-3333-4444-555555555555",
        queue: PendingTransactionQueue = PendingTransactionQueue(fileURL: makeTemporaryQueueURL())
    ) -> StoreKitManager {
        StoreKitManager(
            provider: provider,
            entitlements: entitlements,
            userIDProvider: { userID },
            queueProvider: { _ in queue }
        )
    }

}

private final class FakeStoreKitProvider: StoreKitProductProviding {
    var products: [StoreProduct]
    var purchaseOutcome: StorePurchaseOutcome
    var entitlements: [VerifiedTransaction] = []
    var purchaseAttempts: [(productID: String, appAccountToken: UUID?)] = []
    var finishedTransactionIDs: [String] = []
    var syncCalls = 0

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

    func transactionUpdates() -> AsyncStream<VerifiedTransaction> {
        AsyncStream { $0.finish() }
    }

    func sync() async throws { syncCalls += 1 }

    func finish(transactionID: String) async {
        finishedTransactionIDs.append(transactionID)
    }
}

private final class FakeEntitlements: EntitlementSubmitting {
    var outcome: EntitlementOutcome
    var submittedTransactions: [String] = []
    var membership: MembershipState?

    init(outcome: EntitlementOutcome = .networkFailure("网络不可用"), membership: MembershipState? = nil) {
        self.outcome = outcome
        self.membership = membership
    }

    func submitOutcome(signedTransaction: String) async -> EntitlementOutcome {
        submittedTransactions.append(signedTransaction)
        return outcome
    }

    func refreshMembership() async -> MembershipState? { membership }
}

/// Default arguments cannot call main-actor-isolated members, so the helper lives at file scope.
private func makeTemporaryQueueURL() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("StoreKitStateTests-\(UUID().uuidString).json")
}
