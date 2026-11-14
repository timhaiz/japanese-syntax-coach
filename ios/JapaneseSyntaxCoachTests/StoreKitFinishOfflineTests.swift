#if STOREKIT_FINISH_OFFLINE_TEST
import Foundation

enum AppConfiguration {
    static let monthlyProductID = "monthly"
    static let yearlyProductID = "yearly"
    static let productIDs = [monthlyProductID, yearlyProductID]
}
struct MembershipState: Equatable { let isMember: Bool }
enum EntitlementOutcome {
    case accepted(MembershipState), duplicate(MembershipState), accountMismatch(String)
    case rejected(statusCode: Int, message: String), unauthorized, networkFailure(String)
}
@MainActor protocol EntitlementSubmitting: AnyObject {
    func submitOutcome(signedTransaction: String) async -> EntitlementOutcome
    func refreshMembership() async -> MembershipState?
}
extension EntitlementSubmitting {
    func refreshMembership() async -> MembershipState? { nil }
}
@MainActor final class RefreshEntitlements: EntitlementSubmitting {
    var continuations: [CheckedContinuation<MembershipState?, Never>] = []
    func refreshMembership() async -> MembershipState? {
        await withCheckedContinuation { continuations.append($0) }
    }
    func submitOutcome(signedTransaction: String) async -> EntitlementOutcome {
        .accepted(MembershipState(isMember: true))
    }
}
@MainActor final class AcceptedEntitlements: EntitlementSubmitting {
    func submitOutcome(signedTransaction: String) async -> EntitlementOutcome { .accepted(MembershipState(isMember: true)) }
}

@MainActor final class RestoreProvider: StoreKitProductProviding {
    let transactions: [VerifiedTransaction]
    var finished: [String] = []
    var syncCalls = 0
    var entitlementCalls = 0
    var pauseSync = false
    var pauseEntitlements = false
    var pauseFinish = false
    var finishResult = true
    var purchaseTransaction: VerifiedTransaction?
    var purchaseCalls = 0
    var continuation: CheckedContinuation<Void, Never>?
    init(transactions: [VerifiedTransaction]) { self.transactions = transactions }
    func loadProducts() async throws -> [StoreProduct] {
        purchaseTransaction == nil ? [] : [StoreProduct(id: "monthly", displayName: "月度会员", displayPrice: "测试", periodDescription: "每月", isSubscription: true)]
    }
    func purchase(productID: String, appAccountToken: UUID?) async throws -> StorePurchaseOutcome {
        purchaseCalls += 1
        return purchaseTransaction.map(StorePurchaseOutcome.purchased) ?? .cancelled
    }
    func currentEntitlements() async -> [VerifiedTransaction] {
        entitlementCalls += 1
        if pauseEntitlements { await withCheckedContinuation { continuation = $0 } }
        return transactions
    }
    var updatesContinuation: AsyncStream<VerifiedTransaction>.Continuation?
    func transactionUpdates() -> AsyncStream<VerifiedTransaction> { AsyncStream { updatesContinuation = $0 } }
    func sync() async throws {
        syncCalls += 1
        if pauseSync { await withCheckedContinuation { continuation = $0 } }
    }
    func finish(transactionID: String) async -> Bool {
        finished.append(transactionID)
        if pauseFinish { await withCheckedContinuation { continuation = $0 } }
        return finishResult
    }
}
@MainActor final class OfflineFinishProvider: StoreKitProductProviding {
    private let live = LiveStoreKitProductProvider()
    func loadProducts() async throws -> [StoreProduct] { [] }
    func purchase(productID: String, appAccountToken: UUID?) async throws -> StorePurchaseOutcome { .cancelled }
    func currentEntitlements() async -> [VerifiedTransaction] { [] }
    func transactionUpdates() -> AsyncStream<VerifiedTransaction> { AsyncStream { $0.finish() } }
    func sync() async throws {}
    func finish(transactionID: String) async -> Bool { await live.finish(transactionID: transactionID) }
}
@MainActor final class PausedSecondSubmission: EntitlementSubmitting {
    var submitted: [String] = []
    var continuation: CheckedContinuation<Void, Never>?
    func submitOutcome(signedTransaction: String) async -> EntitlementOutcome {
        submitted.append(signedTransaction)
        if submitted.count == 2 { await withCheckedContinuation { continuation = $0 } }
        return .accepted(MembershipState(isMember: true))
    }
}

@MainActor final class RetryEntitlements: EntitlementSubmitting {
    var submitted: [String] = []
    var pause = false
    var continuation: CheckedContinuation<Void, Never>?
    let outcome: EntitlementOutcome
    init(_ outcome: EntitlementOutcome) { self.outcome = outcome }
    func submitOutcome(signedTransaction: String) async -> EntitlementOutcome {
        submitted.append(signedTransaction)
        if pause { await withCheckedContinuation { continuation = $0 } }
        return outcome
    }
}

@MainActor final class ScriptedEntitlements: EntitlementSubmitting {
    let outcomes: [String: EntitlementOutcome]
    var submitted: [String] = []
    init(_ outcomes: [String: EntitlementOutcome]) { self.outcomes = outcomes }
    func submitOutcome(signedTransaction: String) async -> EntitlementOutcome {
        submitted.append(signedTransaction)
        return outcomes[signedTransaction] ?? .accepted(MembershipState(isMember: true))
    }
}

@MainActor final class InspectingEntitlements: EntitlementSubmitting {
    let queue: PendingTransactionQueue
    var submitted: [String] = []
    init(queue: PendingTransactionQueue) { self.queue = queue }
    func submitOutcome(signedTransaction: String) async -> EntitlementOutcome {
        guard queue.peek().contains(where: { $0.signedTransaction == signedTransaction }) else {
            fatalError("transaction was submitted before durable retention")
        }
        submitted.append(signedTransaction)
        return .accepted(MembershipState(isMember: true))
    }
}

@main struct StoreKitFinishOfflineTests {
    @MainActor static func main() async throws {
        let directory = URL(fileURLWithPath: ".build/storekit-finish-offline", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        do {
            let provider = RestoreProvider(transactions: [])
            provider.purchaseTransaction = VerifiedTransaction(transactionID: "enabled-purchase", productID: "monthly", signedTransaction: "jws", appAccountToken: UUID(uuidString: "11111111-2222-3333-4444-555555555555"))
            let queue = PendingTransactionQueue(fileURL: directory.appendingPathComponent("enabled-\(UUID()).json"))
            let manager = StoreKitManager(provider: provider, entitlements: AcceptedEntitlements(), userIDProvider: { "11111111-2222-3333-4444-555555555555" }, queueProvider: { _ in queue })
            let result = await manager.purchase(productID: "monthly")
            guard provider.purchaseCalls == 1 else { print("FAIL: enabled purchase did not call provider.purchase"); exit(1) }
            guard result == .success(MembershipState(isMember: true)) else { print("FAIL: purchase did not succeed"); exit(1) }
            let signedOut = StoreKitManager(provider: provider, entitlements: AcceptedEntitlements(), userIDProvider: { nil }, queueProvider: { _ in queue })
            let signedOutResult = await signedOut.purchase(productID: "monthly")
            guard signedOutResult == .notSignedIn, provider.purchaseCalls == 1 else { print("FAIL: signed-out purchase must report notSignedIn without calling provider"); exit(1) }
            print("PASS: enabled purchase requires sign-in and calls provider.purchase")
        }
        let url = directory.appendingPathComponent("\(UUID().uuidString).json")
        let transaction = PendingTransaction(transactionID: "1000000000001", productID: "monthly", signedTransaction: "signed-jws")
        let queue = PendingTransactionQueue(fileURL: url)
        guard queue.enqueue(transaction) else { fatalError("could not persist test transaction") }
        let manager = StoreKitManager(provider: OfflineFinishProvider(), entitlements: AcceptedEntitlements(), userIDProvider: { "11111111-2222-3333-4444-555555555555" }, queueProvider: { _ in queue })
        await manager.retryPendingTransactions()
        let persisted = PendingTransactionQueue(fileURL: url).peek()
        guard persisted == [transaction] else {
            print("FAIL: replay removed persisted transaction without a StoreKit handle")
            exit(1)
        }
        print("PASS: replay preserves persisted transaction without a StoreKit handle")

        do {
            var authGenerations: AuthGenerationSnapshot? = AuthGenerationSnapshot(account: UUID(), login: UUID())
            let testQueue = PendingTransactionQueue(fileURL: directory.appendingPathComponent("generation-race-\(UUID()).json"))
            let transaction = VerifiedTransaction(transactionID: "generation-race", productID: "monthly", signedTransaction: "generation-jws", appAccountToken: nil)
            let raceProvider = RestoreProvider(transactions: [transaction])
            raceProvider.pauseEntitlements = true
            let raceEntitlements = RetryEntitlements(.accepted(MembershipState(isMember: true)))
            raceEntitlements.pause = true
            guard testQueue.enqueue(PendingTransaction(transactionID: "generation-race", productID: "monthly", signedTransaction: "generation-jws")) else { fatalError("race transaction setup failed") }
            let userID = "11111111-2222-3333-4444-555555555555"
            let generationManager = StoreKitManager(provider: raceProvider, entitlements: raceEntitlements, userIDProvider: { userID }, authGenerationProvider: { authGenerations }, queueProvider: { _ in testQueue })
            let raceTask = Task { await generationManager.retryPendingTransactions() }
            while raceEntitlements.continuation == nil { await Task.yield() }
            authGenerations = AuthGenerationSnapshot(account: UUID(), login: UUID()) // A -> B -> A: the final user ID is unchanged.
            raceEntitlements.continuation?.resume()
            raceEntitlements.continuation = nil
            await raceTask.value
            guard raceProvider.finished.isEmpty && testQueue.peek().count == 1 else { fatalError("generation race must preserve the queued transaction without finishing it") }
            raceEntitlements.pause = false
            await generationManager.retryPendingTransactions()
            guard raceProvider.finished == ["generation-race"] && testQueue.peek().isEmpty else { fatalError("retry after generation rebind must succeed") }

            var reloginGeneration: AuthGenerationSnapshot? = AuthGenerationSnapshot(account: UUID(), login: UUID())
            let reloginQueue = PendingTransactionQueue(fileURL: directory.appendingPathComponent("relogin-race-\(UUID()).json"))
            guard reloginQueue.enqueue(PendingTransaction(transactionID: "relogin-race", productID: "monthly", signedTransaction: "relogin-jws")) else { fatalError("relogin transaction setup failed") }
            let reloginProvider = RestoreProvider(transactions: [])
            let reloginEntitlements = RetryEntitlements(.accepted(MembershipState(isMember: true)))
            reloginEntitlements.pause = true
            let reloginManager = StoreKitManager(provider: reloginProvider, entitlements: reloginEntitlements, userIDProvider: { userID }, authGenerationProvider: { reloginGeneration }, queueProvider: { _ in reloginQueue })
            let reloginTask = Task { await reloginManager.retryPendingTransactions() }
            while reloginEntitlements.continuation == nil { await Task.yield() }
            reloginGeneration = AuthGenerationSnapshot(account: reloginGeneration!.account, login: UUID())
            reloginEntitlements.continuation?.resume()
            reloginEntitlements.continuation = nil
            await reloginTask.value
            guard reloginProvider.finished.isEmpty && reloginQueue.peek().count == 1 else { fatalError("same-account relogin must invalidate stale replay") }
            reloginEntitlements.pause = false
            await reloginManager.retryPendingTransactions()
            guard reloginProvider.finished == ["relogin-race"] && reloginQueue.peek().isEmpty else { fatalError("same-account retry after relogin must succeed") }

            do {
                var snapshot: AuthGenerationSnapshot? = AuthGenerationSnapshot(account: UUID(), login: UUID())
                let refreshEntitlements = RefreshEntitlements()
                let refreshManager = StoreKitManager(provider: RestoreProvider(transactions: []), entitlements: refreshEntitlements, userIDProvider: { "11111111-2222-3333-4444-555555555555" }, authGenerationProvider: { snapshot }, queueProvider: { _ in queue })
                let staleRefresh = Task { await refreshManager.refreshMembership() }
                while refreshEntitlements.continuations.count < 1 { await Task.yield() }
                snapshot = AuthGenerationSnapshot(account: snapshot!.account, login: UUID())
                refreshEntitlements.continuations[0].resume(returning: MembershipState(isMember: false))
                await staleRefresh.value
                guard !refreshManager.isRefreshingMembership else { fatalError("stale refresh must clear its loading state") }
                let currentRefresh = Task { await refreshManager.refreshMembership() }
                while refreshEntitlements.continuations.count < 2 { await Task.yield() }
                refreshEntitlements.continuations[1].resume(returning: MembershipState(isMember: true))
                await currentRefresh.value
                guard refreshManager.membership?.isMember == true else { fatalError("refresh after same-account rebind must succeed") }
            }

            var user: String? = "11111111-2222-3333-4444-555555555555"
            let provider = RestoreProvider(transactions: [])
            let entitlement = RefreshEntitlements()
            let manager = StoreKitManager(provider: provider, entitlements: entitlement, userIDProvider: { user }, queueProvider: { _ in queue })
            let first = Task { await manager.refreshMembership() }
            while entitlement.continuations.count < 1 { await Task.yield() }
            let second = Task { await manager.refreshMembership() }
            while entitlement.continuations.count < 2 { await Task.yield() }
            entitlement.continuations[1].resume(returning: MembershipState(isMember: true))
            await second.value
            entitlement.continuations[0].resume(returning: MembershipState(isMember: false))
            await first.value
            guard manager.membership?.isMember == true else { fatalError("older refresh overwrote newer result") }
            let stale = Task { await manager.refreshMembership() }
            while entitlement.continuations.count < 3 { await Task.yield() }
            user = "99999999-8888-7777-6666-555555555555"
            entitlement.continuations[2].resume(returning: MembershipState(isMember: false))
            await stale.value
            guard manager.membership == nil else { fatalError("old account membership leaked") }
            user = "11111111-2222-3333-4444-555555555555"
            let generation = Task { await manager.refreshMembership() }
            while entitlement.continuations.count < 4 { await Task.yield() }
            manager.activateAccount("99999999-8888-7777-6666-555555555555")
            manager.activateAccount(user)
            entitlement.continuations[3].resume(returning: MembershipState(isMember: true))
            await generation.value
            guard manager.membership == nil else { fatalError("old generation accepted") }
            let failing = Task { await manager.refreshMembership() }
            while entitlement.continuations.count < 5 { await Task.yield() }
            entitlement.continuations[4].resume(returning: nil)
            await failing.value
            guard manager.membership == nil, manager.membershipRefreshError != nil else { fatalError("failed refresh reported a state") }
            user = nil
            await manager.refreshMembership()
            guard manager.membership == nil, entitlement.continuations.count == 5 else { fatalError("missing credentials reused membership") }
            print("PASS: refresh ordering, account generation and failure")
        }
        do {
            let user = "11111111-2222-3333-4444-555555555555"
            let transaction = VerifiedTransaction(transactionID: "refresh-purchase", productID: "monthly", signedTransaction: "jws", appAccountToken: UUID(uuidString: user))
            let provider = RestoreProvider(transactions: [transaction])
            let entitlement = RefreshEntitlements()
            let purchaseQueue = PendingTransactionQueue(fileURL: directory.appendingPathComponent("\(UUID()).json"))
            let manager = StoreKitManager(provider: provider, entitlements: entitlement, userIDProvider: { user }, queueProvider: { _ in purchaseQueue })
            let refresh = Task { await manager.refreshMembership() }
            while entitlement.continuations.isEmpty { await Task.yield() }
            let result = await manager.restorePurchases()
            guard case .restored = result, provider.finished == [transaction.transactionID] else { fatalError("restore did not finish") }
            entitlement.continuations[0].resume(returning: MembershipState(isMember: false))
            await refresh.value
            guard manager.membership?.isMember == true else { fatalError("old refresh overwrote purchase") }
            print("PASS: restore takes precedence over older refresh and finishes")
        }
        do {
            let user = "11111111-2222-3333-4444-555555555555"
            let transaction = VerifiedTransaction(transactionID: "purchase-refresh", productID: "monthly", signedTransaction: "jws", appAccountToken: UUID(uuidString: user))
            let provider = RestoreProvider(transactions: [transaction])
            provider.pauseFinish = true
            let entitlement = RefreshEntitlements()
            let purchaseQueue = PendingTransactionQueue(fileURL: directory.appendingPathComponent("\(UUID()).json"))
            let manager = StoreKitManager(provider: provider, entitlements: entitlement, userIDProvider: { user }, queueProvider: { _ in purchaseQueue })
            let purchase = Task { await manager.restorePurchases() }
            while provider.continuation == nil { await Task.yield() }
            let refresh = Task { await manager.refreshMembership() }
            while entitlement.continuations.isEmpty { await Task.yield() }
            entitlement.continuations[0].resume(returning: MembershipState(isMember: false))
            await refresh.value
            provider.continuation?.resume()
            guard case .restored = await purchase.value, manager.membership?.isMember == false, provider.finished == [transaction.transactionID] else {
                fatalError("older purchase overwrote refresh or failed to finish")
            }
            print("PASS: newer refresh survives older restore finish")
        }
        let accountA = "11111111-2222-3333-4444-555555555555"
        let accountB = "99999999-8888-7777-6666-555555555555"
        var currentUser = accountA
        let transactions = (1...3).map { index in
            VerifiedTransaction(transactionID: "\(index)", productID: "monthly", signedTransaction: "jws-\(index)", appAccountToken: UUID(uuidString: accountA))
        }
        let restoreProvider = RestoreProvider(transactions: transactions)
        let submissions = PausedSecondSubmission()
        let ownerURL = directory.appendingPathComponent("\(UUID().uuidString).json")
        let ownerQueue = PendingTransactionQueue(fileURL: ownerURL)
        let otherQueue = PendingTransactionQueue(fileURL: directory.appendingPathComponent("\(UUID().uuidString).json"))
        let ownerKey = StoreKitManager.accountKey(for: accountA)
        let restoreManager = StoreKitManager(provider: restoreProvider, entitlements: submissions, userIDProvider: { currentUser }, queueProvider: { $0 == ownerKey ? ownerQueue : otherQueue })
        let task = Task { await restoreManager.restorePurchases() }
        while submissions.continuation == nil { await Task.yield() }
        currentUser = accountB
        restoreManager.activateAccount(accountB)
        submissions.continuation?.resume()
        let result = await task.value
        guard case .failed = result else { print("FAIL: restore returned old account success after switching accounts"); exit(1) }
        guard submissions.submitted == ["jws-1", "jws-2"] else { print("FAIL: restore submitted later transactions after switching accounts"); exit(1) }
        guard restoreProvider.finished == ["1"] else { print("FAIL: restore finished a transaction after switching accounts"); exit(1) }
        guard PendingTransactionQueue(fileURL: ownerURL).peek().map(\.signedTransaction) == ["jws-2"] else { print("FAIL: interrupted transaction was not retained for its owner"); exit(1) }
        guard otherQueue.peek().isEmpty && restoreManager.membership == nil else { print("FAIL: restore leaked state to new account"); exit(1) }
        print("PASS: restore stops after account changes during second transaction")

        for pauseSync in [true, false] {
            var user = accountA
            let provider = RestoreProvider(transactions: transactions)
            provider.pauseSync = pauseSync
            provider.pauseEntitlements = !pauseSync
            let entitlement = PausedSecondSubmission()
            let manager = StoreKitManager(provider: provider, entitlements: entitlement, userIDProvider: { user }, queueProvider: { _ in otherQueue })
            let task = Task { await manager.restorePurchases() }
            while provider.continuation == nil { await Task.yield() }
            user = accountB
            manager.activateAccount(user)
            user = accountA
            manager.activateAccount(user)
            provider.continuation?.resume()
            let result = await task.value
            guard case .failed = result, entitlement.submitted.isEmpty, provider.finished.isEmpty else {
                print("FAIL: restore continued after account changed away and back during \(pauseSync ? "sync" : "entitlements")")
                exit(1)
            }
        }
        print("PASS: restore stops after account generation changes during sync or entitlement lookup")

        var failures = 0
        func check(_ condition: Bool, _ label: String) {
            print("\(condition ? "PASS" : "FAIL"): \(label)")
            if !condition { failures += 1 }
        }
        for invalidUser in [nil, "invalid-user-id"] as [String?] {
            for blockedRetry in [false, true] {
                let root = directory.appendingPathComponent(UUID().uuidString, isDirectory: true)
                try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
                let unassignedFile = root.appendingPathComponent("unassigned.json")
                let ownerFile = root.appendingPathComponent("owner.json")
                let invalidFile = root.appendingPathComponent("invalid.json")
                let unassigned = PendingTransactionQueue(fileURL: unassignedFile)
                let owner = PendingTransactionQueue(fileURL: ownerFile)
                var calls: [String?] = []
                var writes = 0
                var user: String? = accountA
                let provider = RestoreProvider(transactions: [transactions[0]])
                let entitlement = RetryEntitlements(.accepted(MembershipState(isMember: true)))
                let manager = StoreKitManager(provider: provider, entitlements: entitlement, userIDProvider: { user }, queueProvider: { key in
                    calls.append(key)
                    if key == nil { return unassigned }
                    if key == ownerKey { return owner }
                    return PendingTransactionQueue(fileURL: invalidFile, writeData: { data, url in writes += 1; try data.write(to: url) })
                })
                _ = await manager.restorePurchases()
                check(manager.membership != nil, "invalid retry setup establishes membership")
                let item = PendingTransaction(transactionID: "inflight", productID: "monthly", signedTransaction: "inflight")
                guard owner.enqueue(item) else { fatalError("could not persist inflight item") }
                entitlement.pause = true
                let task = Task { await manager.retryPendingTransactions() }
                while entitlement.continuation == nil { await Task.yield() }
                let damaged = Data("damaged".utf8)
                try damaged.write(to: unassignedFile)
                try damaged.write(to: invalidFile)
                let before = try Set(FileManager.default.contentsOfDirectory(atPath: root.path))
                let callsBefore = calls.count
                user = invalidUser
                if blockedRetry { await manager.retryBlockedTransactions() } else { await manager.retryPendingTransactions() }
                let after = try Set(FileManager.default.contentsOfDirectory(atPath: root.path))
                let untouched = (try? Data(contentsOf: unassignedFile)) == damaged && (try? Data(contentsOf: invalidFile)) == damaged
                check(calls.count == callsBefore && writes == 0 && before == after && untouched, "invalid retry \(invalidUser ?? "nil") blocked=\(blockedRetry): no queue creation, read recovery, backup or write")
                check(manager.membership == nil && manager.pendingSyncCount == 0 && manager.blockedSyncCount == 0, "invalid retry \(invalidUser ?? "nil") blocked=\(blockedRetry): account state cleared")
                user = accountA
                entitlement.continuation?.resume()
                await task.value
                let finalFiles = try Set(FileManager.default.contentsOfDirectory(atPath: root.path))
                check(provider.finished == ["1"] && owner.peek() == [item] && manager.membership == nil && finalFiles == before && (try? Data(contentsOf: unassignedFile)) == damaged, "invalid retry \(invalidUser ?? "nil") blocked=\(blockedRetry): generation invalidated and no deferred recovery")
            }
        }
        for user in [nil, "", "invalid-user-id"] as [String?] {
            for token in [nil, UUID(uuidString: accountA)] as [UUID?] {
                for blocked in [false, true] {
                    for outcome in [EntitlementOutcome.accepted(MembershipState(isMember: true)), .unauthorized] {
                        let file = directory.appendingPathComponent("\(UUID()).json")
                        let queue = PendingTransactionQueue(fileURL: file)
                        let item = PendingTransaction(transactionID: "unassigned", productID: "monthly", signedTransaction: "unassigned-jws", appAccountToken: token, lastFailureReason: "original", isBlocked: blocked)
                        guard queue.enqueue(item) else { fatalError("could not persist retry test") }
                        let provider = RestoreProvider(transactions: [])
                        let entitlement = RetryEntitlements(outcome)
                        let manager = StoreKitManager(provider: provider, entitlements: entitlement, userIDProvider: { user }, queueProvider: { _ in queue })
                        if blocked { await manager.retryBlockedTransactions() } else { await manager.retryPendingTransactions() }
                        check(entitlement.submitted.isEmpty && provider.finished.isEmpty && queue.peek() == [item] && PendingTransactionQueue(fileURL: file).peek() == [item] && manager.membership == nil, "invalid user \(user ?? "nil") token=\(token != nil) blocked=\(blocked): retry leaves record untouched")
                    }
                }
            }
        }
        do {
            let unassigned = PendingTransactionQueue(fileURL: directory.appendingPathComponent("\(UUID()).json"))
            let account = PendingTransactionQueue(fileURL: directory.appendingPathComponent("\(UUID()).json"))
            let orphan = PendingTransaction(transactionID: "orphan", productID: "monthly", signedTransaction: "orphan")
            let pending = PendingTransaction(transactionID: "pending", productID: "monthly", signedTransaction: "pending")
            let blocked = PendingTransaction(transactionID: "blocked", productID: "monthly", signedTransaction: "blocked", isBlocked: true)
            guard unassigned.enqueue(orphan), account.enqueue(pending), account.enqueue(blocked) else { fatalError("could not persist retry controls") }
            let provider = RestoreProvider(transactions: [])
            let entitlement = RetryEntitlements(.accepted(MembershipState(isMember: true)))
            let manager = StoreKitManager(provider: provider, entitlements: entitlement, userIDProvider: { accountA }, queueProvider: { $0 == nil ? unassigned : account })
            await manager.retryPendingTransactions()
            check(entitlement.submitted == ["pending"] && provider.finished == ["pending"] && account.peek() == [blocked], "valid account: automatic retry skips blocked")
            await manager.retryBlockedTransactions()
            check(entitlement.submitted == ["pending", "blocked"] && provider.finished == ["pending", "blocked"] && account.peek().isEmpty && unassigned.peek() == [orphan], "valid account: blocked retry completes without touching unassigned")
        }
        for blocked in [false, true] {
            var user: String? = accountA
            let owner = PendingTransactionQueue(fileURL: directory.appendingPathComponent("\(UUID()).json"))
            let other = PendingTransactionQueue(fileURL: directory.appendingPathComponent("\(UUID()).json"))
            let item = PendingTransaction(transactionID: "switch", productID: "monthly", signedTransaction: "switch", isBlocked: blocked)
            guard owner.enqueue(item) else { fatalError("could not persist switch control") }
            let provider = RestoreProvider(transactions: [])
            let entitlement = RetryEntitlements(.accepted(MembershipState(isMember: true)))
            entitlement.pause = true
            let manager = StoreKitManager(provider: provider, entitlements: entitlement, userIDProvider: { user }, queueProvider: { $0 == ownerKey ? owner : other })
            let task = Task { if blocked { await manager.retryBlockedTransactions() } else { await manager.retryPendingTransactions() } }
            while entitlement.continuation == nil { await Task.yield() }
            user = accountB
            manager.activateAccount(user)
            entitlement.continuation?.resume()
            await task.value
            check(entitlement.submitted == ["switch"] && provider.finished.isEmpty && owner.peek() == [item] && other.peek().isEmpty && manager.membership == nil, "retry switch blocked=\(blocked): old account record retained without finish")
        }
        do {
            let file = directory.appendingPathComponent("\(UUID()).json")
            let queue = PendingTransactionQueue(fileURL: file)
            let provider = RestoreProvider(transactions: [transactions[0]])
            provider.pauseFinish = true
            let manager = StoreKitManager(provider: provider, entitlements: AcceptedEntitlements(), userIDProvider: { accountA }, queueProvider: { _ in queue })
            let first = Task { await manager.restorePurchases() }
            while provider.continuation == nil { await Task.yield() }
            let second = await manager.restorePurchases()
            check(second == .failed("购买记录未能完成恢复。购买记录正在处理中，请稍后再次恢复购买。"), "concurrent: reports processing, not network: \(second)")
            check(provider.finished == ["1"] && queue.peek().map(\.transactionID) == ["1"], "concurrent: no duplicate finish or queue mutation")
            provider.continuation?.resume()
            check(await first.value == .restored(MembershipState(isMember: true)), "concurrent: original restore completes")
        }
        do {
            let file = directory.appendingPathComponent("\(UUID()).json")
            let queue = PendingTransactionQueue(fileURL: file)
            let provider = RestoreProvider(transactions: [transactions[0]])
            provider.finishResult = false
            let manager = StoreKitManager(provider: provider, entitlements: AcceptedEntitlements(), userIDProvider: { accountA }, queueProvider: { _ in queue })
            let result = await manager.restorePurchases()
            check(result == .failed("购买记录未能完成恢复。购买记录的完成状态暂时无法确认，请稍后再次恢复购买或联系客服。"), "finish false: reports unknown completion, not network: \(result)")
            check(provider.finished == ["1"] && queue.peek().map(\.transactionID) == ["1"] && manager.membership == nil, "finish false: queue and membership unchanged")
        }
        do {
            let file = directory.appendingPathComponent("pre-submit-retained-\(UUID()).json")
            let queue = PendingTransactionQueue(fileURL: file)
            let transaction = VerifiedTransaction(transactionID: "pre-submit-retained", productID: "monthly", signedTransaction: "pre-submit-jws", appAccountToken: UUID(uuidString: accountA))
            let item = PendingTransaction(transactionID: transaction.transactionID, productID: transaction.productID, signedTransaction: transaction.signedTransaction, appAccountToken: transaction.appAccountToken)
            guard queue.enqueue(item) else { fatalError("could not persist pre-submit transaction") }
            let provider = RestoreProvider(transactions: [transaction])
            let entitlement = InspectingEntitlements(queue: queue)
            let manager = StoreKitManager(provider: provider, entitlements: entitlement, userIDProvider: { accountA }, queueProvider: { _ in queue })
            let result = await manager.restorePurchases()
            check(result == .restored(MembershipState(isMember: true)) && entitlement.submitted == [transaction.signedTransaction], "pre-submit: matching on-disk transaction is retained before submission")
            check(provider.finished == [transaction.transactionID], "pre-submit: acknowledged transaction finishes")
        }
        do {
            let file = directory.appendingPathComponent("pre-submit-write-failure-\(UUID()).json")
            let queue = PendingTransactionQueue(fileURL: file, writeData: { _, _ in throw CocoaError(.fileWriteNoPermission) })
            let transaction = VerifiedTransaction(transactionID: "pre-submit-write-failure", productID: "monthly", signedTransaction: "pre-submit-failure-jws", appAccountToken: UUID(uuidString: accountA))
            let provider = RestoreProvider(transactions: [transaction])
            let entitlement = RetryEntitlements(.accepted(MembershipState(isMember: true)))
            let manager = StoreKitManager(provider: provider, entitlements: entitlement, userIDProvider: { accountA }, queueProvider: { _ in queue })
            _ = await manager.restorePurchases()
            check(entitlement.submitted.isEmpty && provider.finished.isEmpty, "pre-submit: persistence failure prevents submission and finish")
            check(manager.queuePersistenceError != nil, "pre-submit: persistence failure remains visible")
        }
        let purchaseCases: [(String, EntitlementOutcome, Bool)] = [
            ("server-disabled", .networkFailure("Apple entitlement writes are disabled"), false),
            ("network", .networkFailure("PRIVATE-NETWORK"), false),
            ("mismatch", .accountMismatch("PRIVATE-ACCOUNT"), false),
            ("rejected", .rejected(statusCode: 403, message: "PRIVATE-REJECTED"), true)
        ]
        for (label, outcome, blocked) in purchaseCases {
            for failWrite in [false, true] {
                let file = directory.appendingPathComponent("\(UUID()).json")
                let owner = PendingTransactionQueue(fileURL: file, writeData: { data, url in
                    if failWrite { throw CocoaError(.fileWriteNoPermission) }
                    try data.write(to: url, options: .atomic)
                })
                let current = PendingTransactionQueue(fileURL: directory.appendingPathComponent("\(UUID()).json"))
                let unassigned = PendingTransactionQueue(fileURL: directory.appendingPathComponent("\(UUID()).json"))
                let item = VerifiedTransaction(transactionID: "purchase-\(label)", productID: "monthly", signedTransaction: "purchase-jws", appAccountToken: UUID(uuidString: accountB))
                let provider = RestoreProvider(transactions: [])
                provider.purchaseTransaction = item
                let entitlement = ScriptedEntitlements([item.signedTransaction: outcome])
                let manager = StoreKitManager(provider: provider, entitlements: entitlement, userIDProvider: { accountA }, queueProvider: { key in
                    key == nil ? unassigned : key == ownerKey ? current : owner
                })
                while provider.updatesContinuation == nil { await Task.yield() }
                provider.updatesContinuation?.yield(item)
                for _ in 0..<1000 where owner.peek().isEmpty { await Task.yield() }
                let queued = owner.peek()
                let raw = label == "server-disabled" ? "Apple entitlement writes are disabled" : label == "network" ? "PRIVATE-NETWORK" : label == "mismatch" ? "PRIVATE-ACCOUNT" : "PRIVATE-REJECTED"
                let expectedReason = failWrite ? "购买记录等待同步。" : raw
                let expectedBlocked = failWrite ? false : blocked
                check(queued.count == 1 && queued[0].signedTransaction == item.signedTransaction && queued[0].appAccountToken == item.appAccountToken && queued[0].lastFailureReason == expectedReason && queued[0].isBlocked == expectedBlocked, "purchase \(label)/write=\(failWrite): owner queue retains original details")
                check(current.peek().isEmpty && unassigned.peek().isEmpty && provider.finished.isEmpty && manager.membership == nil, "purchase \(label)/write=\(failWrite): no wrong ownership or finish")
                check((entitlement.submitted == [item.signedTransaction]) == !failWrite, "purchase \(label)/write=\(failWrite): submission follows durable retention")
                check((manager.queuePersistenceError != nil) == failWrite, "purchase \(label)/write=\(failWrite): persistence risk remains visible")
                if !failWrite {
                    check(PendingTransactionQueue(fileURL: file).peek() == queued, "purchase \(label): owner queue survives reopening")
                }
            }
        }
        let restoreCases: [(String, [EntitlementOutcome], Bool, Bool, String)] = [
            ("unauthorized", [.unauthorized], false, false, "购买记录未能完成恢复。请先登录后重试。"),
            ("mismatch", [.accountMismatch("private account information")], false, false, "购买记录未能完成恢复。请确认当前登录的是购买时使用的账号。"),
            ("rejected", [.rejected(statusCode: 403, message: "private server detail")], false, false, "购买记录未能完成恢复。请联系客服处理。"),
            ("network", [.networkFailure("private network detail")], false, false, "购买记录未能完成恢复。同步暂未完成，请稍后重试或联系客服。"),
            ("server-disabled", [.networkFailure("Apple entitlement writes are disabled")], false, false, "购买记录未能完成恢复。同步暂未完成，请稍后重试或联系客服。"),
            ("write", [.networkFailure("private network detail")], false, true, "购买记录未能完成恢复。本机无法保存购买记录，请检查设备存储后重试或联系客服。"),
            ("accepted-write", [.accepted(MembershipState(isMember: true))], false, true, "购买记录未能完成恢复。本机无法保存购买记录，请检查设备存储后重试或联系客服。"),
            ("partial", [.networkFailure("private network detail")], true, false, "部分购买记录未能完成恢复。同步暂未完成，请稍后重试或联系客服。"),
            ("mixed", [.networkFailure("private network detail"), .unauthorized, .rejected(statusCode: 403, message: "private server detail"), .accountMismatch("private account information")], false, false, "购买记录未能完成恢复。请确认当前登录的是购买时使用的账号。还存在其他问题，请联系客服。"),
            ("mixed-write", [.accountMismatch("private account information"), .unauthorized], true, true, "部分购买记录未能完成恢复。本机无法保存购买记录，请检查设备存储后重试或联系客服。")
        ]
        for (label, outcomes, includeSuccess, failWrite, expected) in restoreCases {
            let queue = PendingTransactionQueue(fileURL: directory.appendingPathComponent("\(UUID()).json"), writeData: { data, url in
                if failWrite { throw CocoaError(.fileWriteNoPermission) }
                try data.write(to: url, options: .atomic)
            })
            var outcomesByJWS: [String: EntitlementOutcome] = [:]
            var items = outcomes.enumerated().map { index, outcome in
                let jws = "case-\(index)"
                outcomesByJWS[jws] = outcome
                return VerifiedTransaction(transactionID: jws, productID: "monthly", signedTransaction: jws, appAccountToken: UUID(uuidString: accountA))
            }
            if includeSuccess {
                items.insert(VerifiedTransaction(transactionID: "success", productID: "monthly", signedTransaction: "success", appAccountToken: UUID(uuidString: accountB)), at: 0)
            }
            let successQueue = PendingTransactionQueue(fileURL: directory.appendingPathComponent("\(UUID()).json"))
            let provider = RestoreProvider(transactions: items)
            let manager = StoreKitManager(provider: provider, entitlements: ScriptedEntitlements(outcomesByJWS), userIDProvider: { accountA }, queueProvider: { key in key == ownerKey ? queue : successQueue })
            let result = await manager.restorePurchases()
            check(result == .failed(expected), "restore message: \(label): \(result)")
        }
        for scenario in ["partial", "partial-reverse", "write", "other", "unassigned"] {
            let ownerFile = directory.appendingPathComponent("\(UUID()).json")
            let otherFile = directory.appendingPathComponent("\(UUID()).json")
            let unassignedFile = directory.appendingPathComponent("\(UUID()).json")
            let owner = PendingTransactionQueue(fileURL: ownerFile, writeData: { data, url in
                if scenario == "write" { throw CocoaError(.fileWriteNoPermission) }
                try data.write(to: url, options: .atomic)
            })
            let other = PendingTransactionQueue(fileURL: otherFile)
            let unassigned = PendingTransactionQueue(fileURL: unassignedFile)
            let token: UUID? = scenario == "other" ? UUID(uuidString: accountB) : scenario == "unassigned" ? nil : UUID(uuidString: accountA)
            let failed = VerifiedTransaction(transactionID: "failed", productID: "monthly", signedTransaction: "failed-jws", appAccountToken: token)
            let good = VerifiedTransaction(transactionID: "good", productID: "monthly", signedTransaction: "good-jws", appAccountToken: UUID(uuidString: accountA))
            if scenario == "other" || scenario == "unassigned" {
                guard owner.enqueue(PendingTransaction(transactionID: "unrelated", productID: "yearly", signedTransaction: "unrelated-jws", appAccountToken: UUID(uuidString: accountA))) else { fatalError("could not persist unrelated test transaction") }
            }
            let restoreTransactions = scenario == "partial" ? [good, failed] : scenario == "partial-reverse" ? [failed, good] : [failed]
            let provider = RestoreProvider(transactions: restoreTransactions)
            let entitlement = ScriptedEntitlements(["failed-jws": .networkFailure("private failure detail")])
            let manager = StoreKitManager(provider: provider, entitlements: entitlement, userIDProvider: { accountA }, queueProvider: { key in
                if key == nil { return unassigned }
                return key == ownerKey ? owner : other
            })
            let result = await manager.restorePurchases()
            if case .failed(let message) = result {
                check(!message.contains("已保留") && !message.contains("自动同步") && !message.contains("private failure detail"), "\(scenario): failure message makes no unsupported or private claim")
            } else {
                check(false, "\(scenario): restore reports failure")
            }
            let target = scenario == "other" ? other : scenario == "unassigned" ? unassigned : owner
            check(target.peek().map(\.transactionID).contains("failed"), "\(scenario): failed transaction stays with its owner")
            if scenario != "write" {
                let targetFile = scenario == "other" ? otherFile : scenario == "unassigned" ? unassignedFile : ownerFile
                let disk = PendingTransactionQueue(fileURL: targetFile).peek()
                check(disk.count == 1 && disk[0].transactionID == "failed" && disk[0].signedTransaction == "failed-jws" && disk[0].appAccountToken == token && disk[0].lastFailureReason == "private failure detail" && !disk[0].isBlocked, "\(scenario): failed transaction and failure details survive reopening")
            }
            if scenario == "other" || scenario == "unassigned" {
                check(owner.peek().map(\.transactionID) == ["unrelated"], "\(scenario): current account queue is unchanged")
            }
            if scenario == "write" {
                check(manager.queuePersistenceError != nil, "write: persistence failure is visible")
            }
        }
        do {
            let file = directory.appendingPathComponent("\(UUID()).json")
            let queue = PendingTransactionQueue(fileURL: file, writeData: { _, _ in throw CocoaError(.fileWriteNoPermission) })
            let provider = RestoreProvider(transactions: [transactions[0]])
            let manager = StoreKitManager(provider: provider, entitlements: AcceptedEntitlements(), userIDProvider: { accountA }, queueProvider: { _ in queue })
            let result = await manager.restorePurchases()
            if case .failed = result { check(true, "accepted/write: restore fails") }
            else { check(false, "accepted/write: restore fails") }
            check(provider.finished.isEmpty, "accepted/write: finish is never called")
            check(manager.queuePersistenceError != nil, "accepted/write: persistence failure is visible")
            check(PendingTransactionQueue(fileURL: file).peek().isEmpty, "accepted/write: failed write is not claimed durable")
        }
        do {
            var writes = 0
            let file = directory.appendingPathComponent("\(UUID()).json")
            let queue = PendingTransactionQueue(fileURL: file, writeData: { data, url in
                writes += 1
                if writes == 3 { throw CocoaError(.fileWriteNoPermission) }
                try data.write(to: url, options: .atomic)
            })
            let provider = RestoreProvider(transactions: [transactions[0]])
            let manager = StoreKitManager(provider: provider, entitlements: AcceptedEntitlements(), userIDProvider: { accountA }, queueProvider: { _ in queue })
            let result = await manager.restorePurchases()
            check(result == .failed("购买记录已处理，但本机购买记录可能未能保存。本机无法保存购买记录，请检查设备存储后重试或联系客服。"), "finished/remove-write: reports persistence problem without misreporting transaction failure")
            check(provider.finished == ["1"] && manager.membership == MembershipState(isMember: true), "finished/remove-write: transaction and membership remain successful")
        }
        do {
            var user = accountA
            let file = directory.appendingPathComponent("\(UUID()).json")
            let owner = PendingTransactionQueue(fileURL: file)
            let other = PendingTransactionQueue(fileURL: directory.appendingPathComponent("\(UUID()).json"))
            let provider = RestoreProvider(transactions: [transactions[0]])
            provider.pauseFinish = true
            let manager = StoreKitManager(provider: provider, entitlements: AcceptedEntitlements(), userIDProvider: { user }, queueProvider: { $0 == ownerKey ? owner : other })
            let task = Task { await manager.restorePurchases() }
            while provider.continuation == nil { await Task.yield() }
            check(PendingTransactionQueue(fileURL: file).peek().map(\.signedTransaction) == ["jws-1"], "finish/switch: owner record is durable before finish completes")
            user = accountB
            manager.activateAccount(user)
            provider.continuation?.resume()
            let result = await task.value
            if case .failed = result { check(true, "finish/switch: restore does not return old account success") }
            else { check(false, "finish/switch: restore does not return old account success") }
            check(provider.finished == ["1"], "finish/switch: already-started finish completes")
            check(PendingTransactionQueue(fileURL: file).peek().map(\.signedTransaction) == ["jws-1"], "finish/switch: owner record remains on disk")
            check(other.peek().isEmpty && manager.membership == nil, "finish/switch: new account receives no record or membership")
        }
        for invalidUser in [nil, "", "not-a-uuid"] as [String?] {
            let root = directory.appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let damaged = Data("damaged-queue".utf8)
            let unassignedFile = root.appendingPathComponent("unassigned.json")
            let invalidFile = root.appendingPathComponent("invalid.json")
            let ownerFile = root.appendingPathComponent("owner.json")
            let provider = RestoreProvider(transactions: transactions)
            let entitlement = AcceptedEntitlements()
            var user: String? = accountA
            var keys: [String?] = []
            let manager = StoreKitManager(provider: provider, entitlements: entitlement, userIDProvider: { user }, queueProvider: { key in
                keys.append(key)
                return PendingTransactionQueue(fileURL: key == nil ? unassignedFile : key == StoreKitManager.accountKey(for: accountA) ? ownerFile : invalidFile)
            })
            _ = await manager.restorePurchases()
            check(manager.membership?.isMember == true, "restore invalid identity setup establishes membership")
            try damaged.write(to: unassignedFile)
            try damaged.write(to: invalidFile)
            let warning = manager.queuePersistenceError
            provider.syncCalls = 0
            provider.entitlementCalls = 0
            provider.finished = []
            let callsBefore = keys
            let filesBefore = try Set(FileManager.default.contentsOfDirectory(atPath: root.path))
            user = invalidUser
            let result = await manager.restorePurchases()
            let filesAfter = try Set(FileManager.default.contentsOfDirectory(atPath: root.path))
            check(result == .failed("请先登录后重试。"), "restore invalid identity returns fixed login prompt: \(invalidUser ?? "nil")")
            check(provider.syncCalls == 0 && provider.entitlementCalls == 0 && provider.finished.isEmpty, "restore invalid identity has no StoreKit calls or finish")
            check(keys == callsBefore && filesAfter == filesBefore && (try? Data(contentsOf: unassignedFile)) == damaged && (try? Data(contentsOf: invalidFile)) == damaged, "restore invalid identity does not create, read-recover, or mutate queues")
            check(manager.membership == nil && manager.pendingSyncCount == 0 && manager.blockedSyncCount == 0 && manager.queuePersistenceError == warning, "restore invalid identity clears account state and preserves device warning")
        }
        for items in [transactions, []] {
            let provider = RestoreProvider(transactions: items)
            let testQueue = PendingTransactionQueue(fileURL: directory.appendingPathComponent("\(UUID()).json"))
            let manager = StoreKitManager(provider: provider, entitlements: AcceptedEntitlements(), userIDProvider: { accountA }, queueProvider: { _ in testQueue })
            let result = await manager.restorePurchases()
            if items.isEmpty {
                check(result == .noEntitlements, "empty: no entitlements")
            } else {
                check(result == .restored(MembershipState(isMember: true)) && provider.finished == ["1", "2", "3"], "success: every transaction is restored")
            }
        }
        do {
            var user: String? = accountA
            var failOwner = true
            var failOther = true
            var failUnassigned = true
            func makeQueue(_ fail: @escaping () -> Bool) -> PendingTransactionQueue {
                PendingTransactionQueue(fileURL: directory.appendingPathComponent("\(UUID()).json"), writeData: { data, url in
                    if fail() { throw NSError(domain: "PRIVATE-PATH-DETAIL", code: 7, userInfo: [NSLocalizedDescriptionKey: "PRIVATE-PATH-DETAIL"]) }
                    try data.write(to: url, options: .atomic)
                })
            }
            let owner = makeQueue { failOwner }
            let other = makeQueue { failOther }
            let unassigned = makeQueue { failUnassigned }
            let provider = RestoreProvider(transactions: [
                VerifiedTransaction(transactionID: "a", productID: "monthly", signedTransaction: "a", appAccountToken: UUID(uuidString: accountA)),
                VerifiedTransaction(transactionID: "b", productID: "monthly", signedTransaction: "b", appAccountToken: UUID(uuidString: accountB)),
                VerifiedTransaction(transactionID: "u", productID: "monthly", signedTransaction: "u", appAccountToken: nil)
            ])
            let manager = StoreKitManager(provider: provider, entitlements: AcceptedEntitlements(), userIDProvider: { user }, queueProvider: { key in
                key == nil ? unassigned : key == ownerKey ? owner : other
            })
            _ = await manager.restorePurchases()
            let warning = manager.queuePersistenceError
            check(warning != nil && !(warning ?? "").contains("PRIVATE-PATH-DETAIL"), "queue warning hides raw persistence error")
            user = nil
            await manager.retryPendingTransactions()
            check(manager.queuePersistenceError == warning, "invalid retry preserves outstanding device-wide warning")
            user = accountB
            manager.activateAccount(user)
            check(manager.queuePersistenceError == warning, "switch: device warning remains generic while other queues have risks")
            failOther = false
            await manager.retryPendingTransactions()
            check(other.lastPersistenceError == nil && manager.queuePersistenceError == warning, "other recovery does not mask owner and unassigned failures")
            user = accountA
            manager.activateAccount(user)
            failOwner = false
            await manager.retryPendingTransactions()
            check(owner.lastPersistenceError == nil && manager.queuePersistenceError == warning, "owner recovery does not mask unassigned failure")
            failUnassigned = false
            _ = await manager.restorePurchases()
            check(unassigned.lastPersistenceError == nil && manager.queuePersistenceError == nil, "warning clears after all queues recover through signed-in restore")
        }
        do {
            let damaged = directory.appendingPathComponent("\(UUID()).json")
            try Data("not-json".utf8).write(to: damaged)
            let unassigned = PendingTransactionQueue(fileURL: damaged)
            let account = PendingTransactionQueue(fileURL: directory.appendingPathComponent("\(UUID()).json"))
            let provider = RestoreProvider(transactions: [transactions[0]])
            let manager = StoreKitManager(provider: provider, entitlements: AcceptedEntitlements(), userIDProvider: { accountA }, queueProvider: { $0 == nil ? unassigned : account })
            check(unassigned.lastPersistenceError != nil && manager.queuePersistenceError != nil, "initial unassigned recovery notice is visible")
            _ = await manager.restorePurchases()
            check(account.lastPersistenceError == nil && unassigned.lastPersistenceError != nil && manager.queuePersistenceError != nil, "successful account writes do not mask unassigned recovery notice")
        }
        for identity in [nil, "invalid", accountA] as [String?] {
            for scenario in ["new-owner", "new-unassigned", "blocked", "conflict", "write-failure", "switch"] {
                var user: String? = scenario == "switch" ? accountA : identity
                let file = directory.appendingPathComponent("\(UUID()).json")
                let unassignedFile = directory.appendingPathComponent("\(UUID()).json")
                let unassigned = PendingTransactionQueue(fileURL: unassignedFile)
                let owner = PendingTransactionQueue(fileURL: file, writeData: { data, url in
                    if scenario == "write-failure" { throw CocoaError(.fileWriteNoPermission) }
                    try data.write(to: url, options: .atomic)
                })
                let token = scenario == "new-unassigned" ? nil : UUID(uuidString: accountA)
                let update = VerifiedTransaction(transactionID: "update", productID: "monthly", signedTransaction: "update-jws", appAccountToken: token)
                let existing = PendingTransaction(transactionID: "update", productID: "monthly", signedTransaction: scenario == "conflict" ? "different-jws" : "update-jws", appAccountToken: token, lastFailureReason: "original", isBlocked: true)
                if scenario == "blocked" || scenario == "conflict" { guard owner.enqueue(existing) else { fatalError("setup") } }
                let provider = RestoreProvider(transactions: [])
                let entitlement = RetryEntitlements(.accepted(MembershipState(isMember: true)))
                let manager = StoreKitManager(provider: provider, entitlements: entitlement, userIDProvider: { user }, queueProvider: { $0 == nil ? unassigned : owner })
                if scenario == "switch" { manager.activateAccount(accountA); user = nil }
                while provider.updatesContinuation == nil { await Task.yield() }
                provider.updatesContinuation?.yield(update)
                for _ in 0..<100 { await Task.yield() }
                let invalid = scenario == "switch" || identity != accountA
                if invalid {
                    let target = token == nil ? unassigned : owner
                    let expectedExisting = scenario == "blocked" || scenario == "conflict"
                    check(entitlement.submitted.isEmpty && provider.finished.isEmpty, "update \(identity ?? "nil") \(scenario): no submit or finish")
                    let records = target.peek()
                    check(expectedExisting ? records.first == existing && (scenario != "conflict" || records.map(\.signedTransaction).contains("update-jws")) : records.map(\.signedTransaction) == ["update-jws"], "update \(identity ?? "nil") \(scenario): preserves transaction")
                    if scenario == "new-owner" || scenario == "new-unassigned" || scenario == "switch" {
                        let disk = PendingTransactionQueue(fileURL: token == nil ? unassignedFile : file).peek()
                        check(disk.map(\.signedTransaction) == ["update-jws"] && disk.first?.appAccountToken == token && (token == nil ? owner.peek().isEmpty : unassigned.peek().isEmpty), "update \(scenario): durable in correct queue")
                    }
                    if scenario == "write-failure" || scenario == "conflict" { check(manager.queuePersistenceError != nil, "update \(scenario) warns") }
                    if expectedExisting { check(PendingTransactionQueue(fileURL: file).peek() == [existing], "update \(scenario): original remains durable") }
                    if scenario == "conflict" {
                        user = accountA
                        await manager.retryBlockedTransactions()
                        check(entitlement.submitted.isEmpty && provider.finished.isEmpty && owner.peek().first == existing, "update conflict: subsequent retry stops")
                    }
                } else if scenario == "new-owner" {
                    check(entitlement.submitted == ["update-jws"] && provider.finished == ["update"], "valid update submits and finishes")
                }
                provider.updatesContinuation?.finish()
            }
        }
        if failures > 0 { exit(1) }
    }
}
#endif
