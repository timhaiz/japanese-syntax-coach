import XCTest
@testable import JapaneseSyntaxCoach

@MainActor
final class StoreKitStateTests: XCTestCase {
    // MARK: - Purchase states

    func testEnabledPurchasesHandleSessionAvailabilityAndPurchaseOutcomes() async {
        XCTAssertTrue(StoreKitManager.newPurchasesEnabled)

        do {
            let provider = FakeStoreKitProvider(products: [monthlyProduct], purchaseOutcome: .cancelled)
            let entitlements = FakeEntitlements()
            let manager = makeManager(provider: provider, entitlements: entitlements, userID: nil)
            let state = await manager.purchase(productID: AppConfiguration.monthlyProductID)
            XCTAssertEqual(state, .notSignedIn)
            XCTAssertTrue(provider.purchaseAttempts.isEmpty)
        }

        do {
            let provider = FakeStoreKitProvider(products: [], purchaseOutcome: .cancelled)
            let entitlements = FakeEntitlements()
            let manager = makeManager(provider: provider, entitlements: entitlements, userID: signedInUserID)
            let state = await manager.purchase(productID: AppConfiguration.monthlyProductID)
            XCTAssertEqual(state, .unavailable)
            XCTAssertTrue(provider.purchaseAttempts.isEmpty)
        }

        do {
            let provider = FakeStoreKitProvider(products: [monthlyProduct], purchaseOutcome: .purchased(verifiedTransaction))
            let entitlements = FakeEntitlements(outcome: .accepted(memberState))
            let manager = makeManager(provider: provider, entitlements: entitlements, userID: signedInUserID)
            let state = await manager.purchase(productID: AppConfiguration.monthlyProductID)
            XCTAssertEqual(state, .success(memberState))
            XCTAssertEqual(provider.purchaseAttempts.count, 1)
            XCTAssertEqual(provider.finishedTransactionIDs, [verifiedTransaction.transactionID])
            XCTAssertEqual(entitlements.submittedTransactions, [verifiedTransaction.signedTransaction])
        }
    }

    // MARK: - Finish ordering

    func testSuccessfulSyncFinishesTheTransactionAfterAcknowledgement() async {
        let provider = FakeStoreKitProvider(products: [monthlyProduct])
        provider.entitlements = [verifiedTransaction]
        let entitlements = FakeEntitlements(outcome: .accepted(memberState))
        let manager = makeManager(provider: provider, entitlements: entitlements)

        let state = await manager.restorePurchases()

        XCTAssertEqual(state, .restored(memberState))
        XCTAssertEqual(provider.finishedTransactionIDs, [verifiedTransaction.transactionID])
        XCTAssertEqual(entitlements.submittedTransactions, [verifiedTransaction.signedTransaction])
        XCTAssertEqual(manager.pendingSyncCount, 0)
    }

    func testAcknowledgedPurchaseWithoutConfirmedFinishRemainsOnDisk() async {
        let provider = FakeStoreKitProvider(products: [monthlyProduct])
        provider.entitlements = [verifiedTransaction]
        provider.finishSucceeds = false
        let url = makeTemporaryQueueURL()
        let queue = PendingTransactionQueue(fileURL: url)
        let manager = makeManager(provider: provider, entitlements: FakeEntitlements(outcome: .accepted(memberState)), queue: queue)

        let state = await manager.restorePurchases()

        XCTAssertEqual(state, .failed("购买记录未能完成恢复。购买记录的完成状态暂时无法确认，请稍后再次恢复购买或联系客服。"))
        XCTAssertEqual(PendingTransactionQueue(fileURL: url).peek().first?.signedTransaction, verifiedTransaction.signedTransaction)
        XCTAssertEqual(manager.pendingSyncCount, 1)
        XCTAssertNil(manager.membership)
    }

    func testDuplicateAcknowledgementAlsoFinishesTheTransaction() async {
        let provider = FakeStoreKitProvider(products: [monthlyProduct])
        provider.entitlements = [verifiedTransaction]
        let entitlements = FakeEntitlements(outcome: .duplicate(memberState))
        let manager = makeManager(provider: provider, entitlements: entitlements)

        let state = await manager.restorePurchases()

        XCTAssertEqual(state, .restored(memberState))
        XCTAssertEqual(provider.finishedTransactionIDs, [verifiedTransaction.transactionID])
    }

    func testServerSyncFailureDoesNotFinishAndKeepsTheTransactionQueued() async {
        let provider = FakeStoreKitProvider(products: [monthlyProduct])
        provider.entitlements = [verifiedTransaction]
        let entitlements = FakeEntitlements(outcome: .networkFailure("网络不可用"))
        let queue = PendingTransactionQueue(fileURL: makeTemporaryQueueURL())
        let manager = makeManager(provider: provider, entitlements: entitlements, queue: queue)

        let state = await manager.restorePurchases()

        XCTAssertEqual(state, .failed("购买记录未能完成恢复。同步暂未完成，请稍后重试或联系客服。"))
        XCTAssertTrue(provider.finishedTransactionIDs.isEmpty)
        XCTAssertEqual(queue.peek().count, 1)
        XCTAssertEqual(queue.peek().first?.signedTransaction, verifiedTransaction.signedTransaction)
        XCTAssertEqual(manager.pendingSyncCount, 1)
    }

    func testUnauthorizedSubmissionKeepsTheTransactionQueuedForARetry() async {
        let provider = FakeStoreKitProvider(products: [monthlyProduct])
        provider.entitlements = [verifiedTransaction]
        let entitlements = FakeEntitlements(outcome: .unauthorized)
        let queue = PendingTransactionQueue(fileURL: makeTemporaryQueueURL())
        let manager = makeManager(provider: provider, entitlements: entitlements, queue: queue)

        let state = await manager.restorePurchases()

        XCTAssertEqual(state, .failed("购买记录未能完成恢复。请先登录后重试。"))
        XCTAssertTrue(provider.finishedTransactionIDs.isEmpty)
        XCTAssertEqual(queue.peek().count, 1)
        XCTAssertEqual(manager.pendingSyncCount, 1)
        XCTAssertEqual(manager.blockedSyncCount, 0)
    }

    func testAccountMismatchIsNotFinishedAndStaysOnDisk() async {
        let provider = FakeStoreKitProvider(products: [monthlyProduct])
        provider.entitlements = [verifiedTransaction]
        let entitlements = FakeEntitlements(outcome: .accountMismatch("交易账号与当前账号不匹配。"))
        let queue = PendingTransactionQueue(fileURL: makeTemporaryQueueURL())
        let manager = makeManager(provider: provider, entitlements: entitlements, queue: queue)

        let state = await manager.restorePurchases()

        XCTAssertEqual(state, .failed("购买记录未能完成恢复。请确认当前登录的是购买时使用的账号。"))
        XCTAssertTrue(provider.finishedTransactionIDs.isEmpty)
        // The signed transaction is never dropped without a server confirmation.
        XCTAssertEqual(queue.peek().count, 1)
        XCTAssertEqual(queue.peek().first?.lastFailureReason, "交易账号与当前账号不匹配。")
    }

    func testRejectedTransactionIsNotFinishedAndIsMarkedBlocked() async {
        let provider = FakeStoreKitProvider(products: [monthlyProduct])
        provider.entitlements = [verifiedTransaction]
        let entitlements = FakeEntitlements(outcome: .rejected(statusCode: 400, message: "无法验证 Apple 购买记录。"))
        let queue = PendingTransactionQueue(fileURL: makeTemporaryQueueURL())
        let manager = makeManager(provider: provider, entitlements: entitlements, queue: queue)

        let state = await manager.restorePurchases()

        XCTAssertEqual(state, .failed("购买记录未能完成恢复。请联系客服处理。"))
        XCTAssertTrue(provider.finishedTransactionIDs.isEmpty)
        XCTAssertEqual(queue.peek().count, 1)
        XCTAssertEqual(manager.blockedSyncCount, 1)
    }

    func testPurchaseOfAnotherAccountIsFiledUnderTheAccountThatMadeIt() async {
        let provider = FakeStoreKitProvider(products: [monthlyProduct])
        provider.entitlements = [otherAccountTransaction]
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

        let state = await manager.restorePurchases()

        XCTAssertEqual(state, .failed("购买记录未能完成恢复。请确认当前登录的是购买时使用的账号。"))
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
        provider.entitlements = [verifiedTransaction]
        let entitlements = FakeEntitlements(outcome: .networkFailure("网络不可用"))
        let queue = PendingTransactionQueue(fileURL: makeTemporaryQueueURL())
        let manager = makeManager(provider: provider, entitlements: entitlements, queue: queue)

        _ = await manager.restorePurchases()
        XCTAssertEqual(queue.peek().count, 1)

        entitlements.outcome = .accepted(memberState)
        await manager.retryPendingTransactions()

        XCTAssertEqual(queue.peek().count, 0)
        XCTAssertEqual(provider.finishedTransactionIDs, [verifiedTransaction.transactionID])
        XCTAssertEqual(manager.pendingSyncCount, 0)
    }

    func testRetryKeepsTheTransactionQueuedWhenTheServerStillFails() async {
        let provider = FakeStoreKitProvider(products: [monthlyProduct])
        provider.entitlements = [verifiedTransaction]
        let entitlements = FakeEntitlements(outcome: .networkFailure("网络不可用"))
        let queue = PendingTransactionQueue(fileURL: makeTemporaryQueueURL())
        let manager = makeManager(provider: provider, entitlements: entitlements, queue: queue)

        _ = await manager.restorePurchases()
        await manager.retryPendingTransactions()

        XCTAssertEqual(queue.peek().count, 1)
        XCTAssertTrue(provider.finishedTransactionIDs.isEmpty)
    }

    func testRetryDoesNotDropAnItemTheServerNeverAcknowledged() async {
        let provider = FakeStoreKitProvider(products: [monthlyProduct])
        provider.entitlements = [verifiedTransaction]
        let entitlements = FakeEntitlements(outcome: .rejected(statusCode: 400, message: "无法验证 Apple 购买记录。"))
        let queue = PendingTransactionQueue(fileURL: makeTemporaryQueueURL())
        let manager = makeManager(provider: provider, entitlements: entitlements, queue: queue)

        _ = await manager.restorePurchases()
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
        provider.entitlements = [verifiedTransaction]
        let entitlements = FakeEntitlements(outcome: .rejected(statusCode: 400, message: "无法验证 Apple 购买记录。"))
        let queue = PendingTransactionQueue(fileURL: makeTemporaryQueueURL())
        let manager = makeManager(provider: provider, entitlements: entitlements, queue: queue)

        _ = await manager.restorePurchases()
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

    func testStoreKitManagerDeallocatesAndCancelsTransactionUpdatesStreamWhileAwaitingUpdates() async {
        let provider = FakeStoreKitProvider(products: [monthlyProduct])
        let entitlements = FakeEntitlements()
        weak var weakManager: StoreKitManager?

        do {
            let manager = makeManager(provider: provider, entitlements: entitlements)
            weakManager = manager
            let observing = await waitUntil { provider.isObservingUpdates && !manager.isLoadingProducts }
            XCTAssertTrue(observing)
        }

        let releasedAndCancelled = await waitUntil { weakManager == nil && provider.updatesTerminated }
        XCTAssertTrue(releasedAndCancelled)
        XCTAssertNil(weakManager)
        XCTAssertTrue(provider.updatesTerminated)
    }

    func testTransactionUpdateStreamFinishingEndsObservationAndAllowsDeallocation() async {
        let provider = FakeStoreKitProvider(products: [monthlyProduct])
        let entitlements = FakeEntitlements()
        weak var weakManager: StoreKitManager?

        do {
            let manager = makeManager(provider: provider, entitlements: entitlements)
            weakManager = manager
            let observing = await waitUntil { provider.isObservingUpdates && !manager.isLoadingProducts }
            XCTAssertTrue(observing)
            provider.finishUpdatesStream()
            let finished = await waitUntil { provider.updatesTerminated }
            XCTAssertTrue(finished)
        }

        let released = await waitUntil { weakManager == nil }
        XCTAssertTrue(released)
        XCTAssertNil(weakManager)
    }

    // MARK: - Concurrency

    func testConcurrentPathsSubmitAndFinishTheTransactionOnlyOnce() async {
        let provider = FakeStoreKitProvider(products: [monthlyProduct])
        provider.entitlements = [verifiedTransaction]
        let entitlements = FakeEntitlements(outcome: .accepted(memberState))
        entitlements.pauseSubmission = true
        let manager = makeManager(provider: provider, entitlements: entitlements)

        let firstRestore = Task { await manager.restorePurchases() }
        let paused = await waitUntil { entitlements.submissionContinuation != nil }
        XCTAssertTrue(paused)
        guard paused else { return }

        let secondState = await manager.restorePurchases()
        entitlements.submissionContinuation?.resume()
        entitlements.submissionContinuation = nil
        let firstState = await firstRestore.value

        XCTAssertEqual(entitlements.submittedTransactions.count, 1)
        XCTAssertEqual(provider.finishedTransactionIDs, [verifiedTransaction.transactionID])
        XCTAssertEqual(firstState, .restored(memberState))
        XCTAssertEqual(secondState, .failed("购买记录未能完成恢复。购买记录正在处理中，请稍后再次恢复购买。"))
    }

    func testReplayStopsAfterAccountChangesAwayAndBackDuringSubmission() async {
        let provider = FakeStoreKitProvider(products: [])
        let entitlements = FakeEntitlements(outcome: .accepted(memberState))
        entitlements.pauseSubmission = true
        let queue = PendingTransactionQueue(fileURL: makeTemporaryQueueURL())
        for index in 1...2 {
            queue.enqueue(PendingTransaction(transactionID: "race-\(index)", productID: monthlyProduct.id, signedTransaction: "jws-\(index)"))
        }
        var userID = signedInUserID
        let manager = StoreKitManager(provider: provider, entitlements: entitlements, userIDProvider: { userID }, queueProvider: { _ in queue })
        let task = Task { await manager.retryPendingTransactions() }
        let paused = await waitUntil { entitlements.submissionContinuation != nil }
        XCTAssertTrue(paused)
        guard paused else { return }
        userID = otherAccountUserID
        manager.activateAccount(userID)
        userID = signedInUserID
        manager.activateAccount(userID)
        entitlements.submissionContinuation?.resume()
        entitlements.submissionContinuation = nil
        await task.value
        XCTAssertEqual(entitlements.submittedTransactions.count, 1)
        XCTAssertEqual(queue.peek().count, 2)
        XCTAssertTrue(provider.finishedTransactionIDs.isEmpty)
        XCTAssertNil(manager.membership)
    }

    func testReplayKeepsRecordWhenAccountChangesDuringFinish() async {
        let provider = FakeStoreKitProvider(products: [])
        provider.pauseFinish = true
        let entitlements = FakeEntitlements(outcome: .accepted(memberState))
        let queue = PendingTransactionQueue(fileURL: makeTemporaryQueueURL())
        queue.enqueue(PendingTransaction(transactionID: "race", productID: monthlyProduct.id, signedTransaction: "jws"))
        var userID = signedInUserID
        let manager = StoreKitManager(provider: provider, entitlements: entitlements, userIDProvider: { userID }, queueProvider: { _ in queue })
        let task = Task { await manager.retryPendingTransactions() }
        let paused = await waitUntil { provider.finishContinuation != nil }
        XCTAssertTrue(paused)
        guard paused else { return }
        userID = otherAccountUserID
        manager.activateAccount(userID)
        provider.finishContinuation?.resume()
        provider.finishContinuation = nil
        await task.value
        XCTAssertEqual(queue.peek().count, 1)
        XCTAssertNil(manager.membership)
    }

    func testSingleUpdateAfterAccountChangesAwayAndBackIsQueuedUnassigned() async {
        let provider = FakeStoreKitProvider(products: [])
        let entitlements = FakeEntitlements(outcome: .networkFailure("网络不可用"))
        entitlements.pauseSubmission = true
        let aQueue = PendingTransactionQueue(fileURL: makeTemporaryQueueURL())
        let bQueue = PendingTransactionQueue(fileURL: makeTemporaryQueueURL())
        let unassignedQueue = PendingTransactionQueue(fileURL: makeTemporaryQueueURL())
        var userID: String? = signedInUserID
        let aKey = StoreKitManager.accountKey(for: signedInUserID)
        let bKey = StoreKitManager.accountKey(for: otherAccountUserID)
        let manager = StoreKitManager(
            provider: provider,
            entitlements: entitlements,
            userIDProvider: { userID },
            queueProvider: { key in
                switch key {
                case nil: return unassignedQueue
                case aKey: return aQueue
                case bKey: return bQueue
                default: fatalError("Unexpected account key")
                }
            }
        )
        manager.activateAccount(signedInUserID)
        provider.emit(VerifiedTransaction(
            transactionID: "tokenless-race",
            productID: monthlyProduct.id,
            signedTransaction: "tokenless-jws",
            appAccountToken: nil
        ))
        let paused = await waitUntil { entitlements.submissionContinuation != nil }
        XCTAssertTrue(paused)
        guard paused else { return }
        userID = otherAccountUserID
        manager.activateAccount(userID)
        userID = signedInUserID
        manager.activateAccount(userID)
        entitlements.submissionContinuation?.resume()
        entitlements.submissionContinuation = nil
        let queued = await waitUntil { unassignedQueue.peek().count == 1 }
        XCTAssertTrue(queued)
        XCTAssertTrue(aQueue.peek().isEmpty)
        XCTAssertTrue(bQueue.peek().isEmpty)
        XCTAssertNil(manager.membership)
        XCTAssertTrue(provider.finishedTransactionIDs.isEmpty)
    }

    func testSingleUpdateSwitchDuringFinishKeepsRecordAndDoesNotPublishMembership() async {
        let provider = FakeStoreKitProvider(products: [])
        provider.pauseFinish = true
        let entitlements = FakeEntitlements(outcome: .accepted(memberState))
        let ownerQueue = PendingTransactionQueue(fileURL: makeTemporaryQueueURL())
        let otherQueue = PendingTransactionQueue(fileURL: makeTemporaryQueueURL())
        var userID: String? = signedInUserID
        let ownerKey = StoreKitManager.accountKey(for: signedInUserID)
        let otherKey = StoreKitManager.accountKey(for: otherAccountUserID)
        let manager = StoreKitManager(
            provider: provider,
            entitlements: entitlements,
            userIDProvider: { userID },
            queueProvider: { key in key == ownerKey ? ownerQueue : (key == otherKey ? otherQueue : otherQueue) }
        )
        manager.activateAccount(signedInUserID)
        provider.emit(VerifiedTransaction(
            transactionID: "owned-race",
            productID: monthlyProduct.id,
            signedTransaction: "owned-jws",
            appAccountToken: UUID(uuidString: signedInUserID)
        ))
        let paused = await waitUntil { provider.finishContinuation != nil }
        XCTAssertTrue(paused)
        guard paused else { return }
        userID = otherAccountUserID
        manager.activateAccount(userID)
        provider.finishContinuation?.resume()
        provider.finishContinuation = nil
        let retained = await waitUntil { ownerQueue.peek().count == 1 }
        XCTAssertTrue(retained)
        XCTAssertEqual(ownerQueue.peek().first?.signedTransaction, "owned-jws")
        XCTAssertNil(manager.membership)
        XCTAssertEqual(provider.finishedTransactionIDs, ["owned-race"])
    }

    // MARK: - Account deletion contract

    func testAccountDeletionRequiresTheExactConfirmation() async {
        let request = AccountDeletionRequest(confirmation: "delete")
        XCTAssertNotEqual(request.confirmation, AccountDeletionRequest.requiredConfirmation)
        XCTAssertEqual(AccountDeletionRequest.requiredConfirmation, "DELETE")
    }

    func testAccountSwitchPreservesUnacknowledgedPurchaseRecord() throws {
        let firstURL = makeTemporaryQueueURL()
        let secondURL = makeTemporaryQueueURL()
        let unassignedURL = makeTemporaryQueueURL()
        defer {
            for url in [firstURL, secondURL, unassignedURL] {
                try? FileManager.default.removeItem(at: url)
            }
        }
        let firstQueue = PendingTransactionQueue(fileURL: firstURL)
        let secondQueue = PendingTransactionQueue(fileURL: secondURL)
        let unassignedQueue = PendingTransactionQueue(fileURL: unassignedURL)
        let firstRecord = PendingTransaction(
            transactionID: verifiedTransaction.transactionID,
            productID: verifiedTransaction.productID,
            signedTransaction: verifiedTransaction.signedTransaction
        )
        let secondRecord = PendingTransaction(
            transactionID: otherAccountTransaction.transactionID,
            productID: otherAccountTransaction.productID,
            signedTransaction: otherAccountTransaction.signedTransaction
        )
        let secondAdditionalRecord = PendingTransaction(
            transactionID: "another-transaction",
            productID: otherAccountTransaction.productID,
            signedTransaction: "another-signed-jws"
        )
        firstQueue.enqueue(firstRecord)
        secondQueue.enqueue(secondRecord)
        secondQueue.enqueue(secondAdditionalRecord)
        let firstData = try Data(contentsOf: firstURL)
        let secondData = try Data(contentsOf: secondURL)
        let firstKey = StoreKitManager.accountKey(for: signedInUserID)
        let secondKey = StoreKitManager.accountKey(for: otherAccountUserID)
        let manager = makeManager(
            provider: FakeStoreKitProvider(products: [monthlyProduct]),
            entitlements: FakeEntitlements(),
            queueProvider: { key in
                switch key {
                case nil: return unassignedQueue
                case firstKey: return firstQueue
                case secondKey: return secondQueue
                default:
                    XCTFail("Unexpected account key: \(key ?? "nil")")
                    return unassignedQueue
                }
            }
        )

        manager.activateAccount(signedInUserID)
        XCTAssertEqual(manager.pendingSyncCount, 1)
        XCTAssertEqual(firstQueue.peek(), [firstRecord])
        XCTAssertEqual(PendingTransactionQueue(fileURL: secondURL).peek(), [secondRecord, secondAdditionalRecord])
        XCTAssertEqual(try Data(contentsOf: secondURL), secondData)

        manager.activateAccount(otherAccountUserID)
        XCTAssertEqual(manager.pendingSyncCount, 2)
        XCTAssertEqual(secondQueue.peek(), [secondRecord, secondAdditionalRecord])
        XCTAssertEqual(PendingTransactionQueue(fileURL: firstURL).peek(), [firstRecord])
        XCTAssertEqual(try Data(contentsOf: firstURL), firstData)

        manager.activateAccount(signedInUserID)
        XCTAssertEqual(manager.pendingSyncCount, 1)
        XCTAssertEqual(PendingTransactionQueue(fileURL: firstURL).peek(), [firstRecord])
        XCTAssertEqual(try Data(contentsOf: secondURL), secondData)
        XCTAssertTrue(unassignedQueue.peek().isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: unassignedURL.path))
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
    var finishSucceeds = true
    var pauseFinish = false
    var finishContinuation: CheckedContinuation<Void, Never>?

    private var updatesContinuation: AsyncStream<VerifiedTransaction>.Continuation?
    private var bufferedUpdates: [VerifiedTransaction] = []
    private(set) var isObservingUpdates = false
    private(set) var updatesTerminated = false
    private lazy var updates: AsyncStream<VerifiedTransaction> = {
        AsyncStream { continuation in
            updatesContinuation = continuation
            isObservingUpdates = true
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor in
                    self?.updatesTerminated = true
                }
            }
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

    func finishUpdatesStream() {
        updatesContinuation?.finish()
    }

    func sync() async throws { syncCalls += 1 }

    func finish(transactionID: String) async -> Bool {
        guard finishSucceeds else { return false }
        finishedTransactionIDs.append(transactionID)
        if pauseFinish { await withCheckedContinuation { finishContinuation = $0 } }
        return true
    }
}

@MainActor
private final class FakeEntitlements: EntitlementSubmitting {
    var outcome: EntitlementOutcome
    var submittedTransactions: [String] = []
    var membership: MembershipState?
    /// Holds the submission open, so a test can run two paths against one transaction.
    var responseDelay: TimeInterval = 0
    var pauseSubmission = false
    var submissionContinuation: CheckedContinuation<Void, Never>?

    init(outcome: EntitlementOutcome = .networkFailure("网络不可用"), membership: MembershipState? = nil) {
        self.outcome = outcome
        self.membership = membership
    }

    func submitOutcome(signedTransaction: String) async -> EntitlementOutcome {
        submittedTransactions.append(signedTransaction)
        if pauseSubmission { await withCheckedContinuation { submissionContinuation = $0 } }
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
