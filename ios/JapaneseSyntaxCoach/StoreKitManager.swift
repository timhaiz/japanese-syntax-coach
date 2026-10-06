import Foundation
import StoreKit
import Combine

struct StoreKitResult: Encodable {
    let success: Bool
    let signedTransaction: String?
    let productID: String?
    let message: String?
}

@MainActor
final class StoreKitManager: ObservableObject {
    @Published private(set) var products: [Product] = []

    private var transactionUpdatesTask: Task<Void, Never>?

    init() {
        transactionUpdatesTask = Task { [weak self] in
            await self?.observeTransactionUpdates()
        }
        Task { await loadProducts() }
    }

    deinit {
        transactionUpdatesTask?.cancel()
    }

    func loadProducts() async {
        do {
            products = try await Product.products(for: AppConfiguration.productIDs)
                .sorted { $0.id == AppConfiguration.monthlyProductID && $1.id != AppConfiguration.monthlyProductID }
        } catch {
            products = []
        }
    }

    func purchase(productID: String, userID: String) async -> StoreKitResult {
        if products.isEmpty { await loadProducts() }
        guard let product = products.first(where: { $0.id == productID }) else {
            return StoreKitResult(success: false, signedTransaction: nil, productID: productID, message: "订阅商品暂时不可用，请稍后重试。")
        }

        do {
            var options = Set<Product.PurchaseOption>()
            if let accountToken = UUID(uuidString: userID) {
                options.insert(.appAccountToken(accountToken))
            }
            let result = try await product.purchase(options: options)
            switch result {
            case .success(let verification):
                guard case .verified(let transaction) = verification else {
                    return StoreKitResult(success: false, signedTransaction: nil, productID: productID, message: "Apple 无法验证这笔交易，请稍后重试。")
                }
                let signedTransaction = verification.jwsRepresentation
                await transaction.finish()
                return StoreKitResult(success: true, signedTransaction: signedTransaction, productID: productID, message: nil)
            case .userCancelled:
                return StoreKitResult(success: false, signedTransaction: nil, productID: productID, message: "你已取消购买。")
            case .pending:
                return StoreKitResult(success: false, signedTransaction: nil, productID: productID, message: "购买正在等待 Apple 审核或付款确认。")
            @unknown default:
                return StoreKitResult(success: false, signedTransaction: nil, productID: productID, message: "购买状态未知，请稍后重试。")
            }
        } catch {
            return StoreKitResult(success: false, signedTransaction: nil, productID: productID, message: "购买失败，请检查 Apple 账户后重试。")
        }
    }

    func restorePurchases() async -> [StoreKitResult] {
        do {
            try await AppStore.sync()
        } catch {
            return [StoreKitResult(success: false, signedTransaction: nil, productID: nil, message: "恢复购买失败，请稍后重试。")]
        }

        var results: [StoreKitResult] = []
        for await verification in Transaction.currentEntitlements {
            guard case .verified(let transaction) = verification,
                  AppConfiguration.productIDs.contains(transaction.productID) else { continue }
            results.append(StoreKitResult(success: true, signedTransaction: verification.jwsRepresentation, productID: transaction.productID, message: nil))
        }
        if results.isEmpty {
            results.append(StoreKitResult(success: false, signedTransaction: nil, productID: nil, message: "没有找到可恢复的会员购买记录。"))
        }
        return results
    }

    private func observeTransactionUpdates() async {
        for await verification in Transaction.updates {
            guard case .verified(let transaction) = verification else { continue }
            await transaction.finish()
        }
    }
}
