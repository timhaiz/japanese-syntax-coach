import Foundation
import StoreKit

/// A purchasable subscription as shown to the user.
struct StoreProduct: Equatable {
    let id: String
    let displayName: String
    /// Localized price, for example "¥18". Never hard-code a price in the UI.
    let displayPrice: String
    /// Human readable renewal period, for example "每月".
    let periodDescription: String
    let isSubscription: Bool
}

/// A transaction StoreKit has already verified.
struct VerifiedTransaction: Equatable {
    let transactionID: String
    let productID: String
    /// The JWS the server verifies with Apple.
    let signedTransaction: String
    let appAccountToken: UUID?
}

enum StorePurchaseOutcome: Equatable {
    case purchased(VerifiedTransaction)
    case cancelled
    case pending
    case unverified
}

enum StoreKitProviderError: Error {
    case productUnavailable
}

/// Narrow seam over StoreKit 2 so the purchase state machine can be unit-tested
/// without a live StoreKit session or an Apple sandbox account.
///
/// The protocol is main-actor isolated, so the live implementation can keep its
/// transaction table without a data race and finish a transaction only once.
@MainActor
protocol StoreKitProductProviding: AnyObject {
    func loadProducts() async throws -> [StoreProduct]
    func purchase(productID: String, appAccountToken: UUID?) async throws -> StorePurchaseOutcome
    func currentEntitlements() async -> [VerifiedTransaction]
    func transactionUpdates() -> AsyncStream<VerifiedTransaction>
    func sync() async throws
    func finish(transactionID: String) async
}

@MainActor
final class LiveStoreKitProductProvider: StoreKitProductProviding {
    /// Real transactions are kept so a verified transaction can be finished later,
    /// after the server acknowledged the entitlement.
    private var pendingTransactions: [UInt64: Transaction] = [:]

    func loadProducts() async throws -> [StoreProduct] {
        let products = try await Product.products(for: AppConfiguration.productIDs)
        return products
            .sorted { lhs, rhs in
                let order: [String: Int] = [
                    AppConfiguration.monthlyProductID: 0,
                    AppConfiguration.yearlyProductID: 1
                ]
                return (order[lhs.id] ?? Int.max) < (order[rhs.id] ?? Int.max)
            }
            .map { product in
                StoreProduct(
                    id: product.id,
                    displayName: product.displayName,
                    displayPrice: product.displayPrice,
                    periodDescription: Self.periodDescription(for: product),
                    isSubscription: product.type == .autoRenewable
                )
            }
    }

    func purchase(productID: String, appAccountToken: UUID?) async throws -> StorePurchaseOutcome {
        guard let product = try await Product.products(for: [productID]).first else {
            throw StoreKitProviderError.productUnavailable
        }
        var options: Set<Product.PurchaseOption> = []
        if let appAccountToken { options.insert(.appAccountToken(appAccountToken)) }
        let result = try await product.purchase(options: options)
        switch result {
        case .success(let verification):
            switch verification {
            case .verified(let transaction):
                pendingTransactions[transaction.id] = transaction
                return .purchased(
                    VerifiedTransaction(
                        transactionID: String(transaction.id),
                        productID: transaction.productID,
                        signedTransaction: verification.jwsRepresentation,
                        appAccountToken: transaction.appAccountToken
                    )
                )
            case .unverified:
                return .unverified
            }
        case .userCancelled:
            return .cancelled
        case .pending:
            return .pending
        @unknown default:
            return .pending
        }
    }

    func currentEntitlements() async -> [VerifiedTransaction] {
        var results: [VerifiedTransaction] = []
        for await verification in Transaction.currentEntitlements {
            guard case .verified(let transaction) = verification else { continue }
            pendingTransactions[transaction.id] = transaction
            results.append(
                VerifiedTransaction(
                    transactionID: String(transaction.id),
                    productID: transaction.productID,
                    signedTransaction: verification.jwsRepresentation,
                    appAccountToken: transaction.appAccountToken
                )
            )
        }
        return results
    }

    func transactionUpdates() -> AsyncStream<VerifiedTransaction> {
        AsyncStream { continuation in
            let task = Task {
                for await verification in Transaction.updates {
                    guard case .verified(let transaction) = verification else { continue }
                    pendingTransactions[transaction.id] = transaction
                    continuation.yield(
                        VerifiedTransaction(
                            transactionID: String(transaction.id),
                            productID: transaction.productID,
                            signedTransaction: verification.jwsRepresentation,
                            appAccountToken: transaction.appAccountToken
                        )
                    )
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func sync() async throws {
        try await AppStore.sync()
    }

    func finish(transactionID: String) async {
        guard let raw = UInt64(transactionID), let transaction = pendingTransactions[raw] else { return }
        // The entry is removed before the await, so a second finish for the same
        // transaction is a no-op instead of a second StoreKit call.
        pendingTransactions[raw] = nil
        await transaction.finish()
    }

    private static func periodDescription(for product: Product) -> String {
        guard let period = product.subscription?.subscriptionPeriod else { return "" }
        switch period.unit {
        case .day: return period.value == 1 ? "每天" : "每 \(period.value) 天"
        case .week: return period.value == 1 ? "每周" : "每 \(period.value) 周"
        case .month: return period.value == 1 ? "每月" : "每 \(period.value) 个月"
        case .year: return period.value == 1 ? "每年" : "每 \(period.value) 年"
        @unknown default: return ""
        }
    }
}
