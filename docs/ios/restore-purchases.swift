import StoreKit

@MainActor
func restorePurchases() async throws {
    // Apple 会重新同步当前 Apple ID 已购买的交易。
    try await AppStore.sync()
    for await result in Transaction.currentEntitlements {
        guard case .verified(let transaction) = result else { continue }
        guard transaction.productID.hasPrefix("com.juxintong.nihongo.") else { continue }
        // 将 signedData 发送到 POST /api/apple/entitlements。
        // 服务端必须再次验签，不能只相信客户端的 expiresDate。
        _ = transaction.jwsRepresentation
    }
}
