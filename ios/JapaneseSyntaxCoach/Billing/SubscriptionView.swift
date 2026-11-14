import SwiftUI
import UIKit

/// Native subscription screen. Prices and periods always come from StoreKit,
/// never from hard-coded values, and membership is only shown once the server confirmed it.
struct SubscriptionView: View {
    @ObservedObject var storeKit: StoreKitManager
    @State private var message: String?
    @State private var errorMessage: String?
    @State private var busyProductID: String?
    @State private var isRestoring = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: HomeVisualStyle.sectionSpacing) {
                VStack(alignment: .leading, spacing: 12) {
                    sectionHeader("会员状态")
                    MembershipStatusView(membership: storeKit.membership)
                    Button {
                        Task { await storeKit.refreshMembership() }
                    } label: {
                        HStack(spacing: 8) {
                            Text(storeKit.isRefreshingMembership ? "正在刷新会员状态…" : "刷新会员状态")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(HomeVisualStyle.accentInk)
                            if storeKit.isRefreshingMembership {
                                SwiftUI.ProgressView()
                                    .tint(HomeVisualStyle.accent)
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(HomeVisualStyle.accent)
                    .disabled(storeKit.isRefreshingMembership)
                    .accessibilityIdentifier("refreshMembership")

                    if let error = storeKit.membershipRefreshError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .accessibilityIdentifier("membershipRefreshError")
                    }
                    if storeKit.pendingSyncCount > 0 {
                        Text("有 \(storeKit.pendingSyncCount) 笔购买记录等待同步。")
                            .font(.caption)
                            .foregroundStyle(HomeVisualStyle.secondaryInk)
                            .accessibilityIdentifier("pendingEntitlementCount")
                    }
                    if storeKit.blockedSyncCount > 0 {
                        Text("其中 \(storeKit.blockedSyncCount) 笔无法自动同步，请保留记录。")
                            .font(.caption)
                            .foregroundStyle(HomeVisualStyle.secondaryInk)
                            .accessibilityIdentifier("blockedEntitlementCount")
                        Button {
                            Task { await storeKit.retryBlockedTransactions() }
                        } label: {
                            Text("重新尝试同步")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(HomeVisualStyle.accentInk)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .tint(HomeVisualStyle.accent)
                        .accessibilityLabel("重新尝试同步无法自动同步的购买记录")
                        .accessibilityIdentifier("retryBlockedEntitlements")
                    }
                    if let queueError = storeKit.queuePersistenceError {
                        Text(queueError)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .accessibilityIdentifier("queuePersistenceError")
                    }
                    if let message {
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(HomeVisualStyle.ink)
                            .accessibilityIdentifier("subscriptionMessage")
                    }
                    if let errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .accessibilityIdentifier("subscriptionError")
                    }
                }
                .homeCardStyle()

                VStack(alignment: .leading, spacing: 12) {
                    sectionHeader("订阅方案")
                    if !StoreKitManager.newPurchasesEnabled {
                        Text(StoreKitManager.purchasePausedMessage)
                            .font(.subheadline)
                            .foregroundStyle(HomeVisualStyle.secondaryInk)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(HomeVisualStyle.canvas)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(HomeVisualStyle.accent.opacity(0.22), lineWidth: 1)
                            )
                            .accessibilityIdentifier("purchasePausedMessage")
                    }
                    if storeKit.products.isEmpty {
                        if storeKit.isLoadingProducts {
                            HStack(spacing: 10) {
                                SwiftUI.ProgressView()
                                    .tint(HomeVisualStyle.accent)
                                Text("正在读取 App Store 商品…")
                                    .font(.subheadline)
                                    .foregroundStyle(HomeVisualStyle.secondaryInk)
                            }
                        } else {
                            Text("暂时无法读取订阅商品，请稍后重试。")
                                .font(.subheadline)
                                .foregroundStyle(HomeVisualStyle.secondaryInk)
                            Button {
                                Task { await storeKit.loadProducts() }
                            } label: {
                                Text("重新加载商品")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(HomeVisualStyle.accentInk)
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .tint(HomeVisualStyle.accent)
                        }
                    } else {
                        ForEach(storeKit.products, id: \.id) { product in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(product.displayName)
                                    .font(.headline)
                                    .foregroundStyle(HomeVisualStyle.ink)
                                Text(product.displayPrice)
                                    .font(.title3.bold())
                                    .foregroundStyle(HomeVisualStyle.accentInk)
                                if !product.periodDescription.isEmpty {
                                    Text(product.periodDescription)
                                        .font(.caption)
                                        .foregroundStyle(HomeVisualStyle.secondaryInk)
                                }
                                Button {
                                    Task { await purchase(product) }
                                } label: {
                                    HStack(spacing: 8) {
                                        Spacer()
                                        Text(busyProductID == product.id ? "处理中…" : "订阅")
                                            .font(.subheadline.weight(.semibold))
                                        if busyProductID == product.id {
                                            SwiftUI.ProgressView()
                                                .tint(HomeVisualStyle.card)
                                        }
                                        Spacer()
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(HomeVisualStyle.accent)
                                .disabled(!StoreKitManager.newPurchasesEnabled || busyProductID != nil || isRestoring)
                                .accessibilityLabel("订阅\(product.displayName)，\(product.displayPrice)\(product.periodDescription)")
                                .accessibilityIdentifier("subscribe_\(product.id)")
                            }
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(HomeVisualStyle.canvas)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(HomeVisualStyle.accent.opacity(0.16), lineWidth: 1)
                            )
                        }
                    }
                }
                .homeCardStyle()

                VStack(alignment: .leading, spacing: 12) {
                    sectionHeader("购买管理")
                    Button {
                        Task { await restore() }
                    } label: {
                        HStack(spacing: 8) {
                            Spacer()
                            Text(isRestoring ? "恢复中…" : "恢复购买")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(HomeVisualStyle.accentInk)
                            if isRestoring {
                                SwiftUI.ProgressView()
                                    .tint(HomeVisualStyle.accent)
                            }
                            Spacer()
                        }
                    }
                    .buttonStyle(.bordered)
                    .tint(HomeVisualStyle.accent)
                    .disabled(busyProductID != nil || isRestoring)
                    .accessibilityLabel("恢复购买")
                    .accessibilityIdentifier("restorePurchases")

                    Button {
                        openSubscriptionSettings()
                    } label: {
                        Text("管理 Apple 订阅")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(HomeVisualStyle.accentInk)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(HomeVisualStyle.accent)
                    .accessibilityLabel("在 Apple 账户设置中管理订阅")
                    .accessibilityIdentifier("manageSubscriptions")

                    Text("付款由 Apple 处理，订阅会自动续期。你可以随时在 Apple 账户的订阅设置中取消。")
                        .font(.caption)
                        .foregroundStyle(HomeVisualStyle.secondaryInk)
                }
                .homeCardStyle()

                VStack(alignment: .leading, spacing: 10) {
                    sectionHeader("条款与隐私")
                    Link("隐私政策", destination: AppConfiguration.webURL.appendingPathComponent("privacy"))
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(HomeVisualStyle.accentInk)
                    Link("服务条款", destination: AppConfiguration.webURL.appendingPathComponent("terms"))
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(HomeVisualStyle.accentInk)
                    Text("购买与订阅由 Apple 处理，本应用不会接触你的付款信息。")
                        .font(.caption)
                        .foregroundStyle(HomeVisualStyle.secondaryInk)
                }
                .homeCardStyle()
            }
            .padding(HomeVisualStyle.screenPadding)
        }
        .homeScreenChrome()
        .navigationTitle("会员订阅")
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.headline)
            .foregroundStyle(HomeVisualStyle.ink)
            .accessibilityAddTraits(.isHeader)
    }

    private func purchase(_ product: StoreProduct) async {
        guard busyProductID == nil else { return }
        busyProductID = product.id
        message = nil
        errorMessage = nil
        defer { busyProductID = nil }

        switch await storeKit.purchase(productID: product.id) {
        case .success(let membership):
            message = membership.isMember ? "会员已开通。" : "购买已确认，会员状态稍后同步。"
        case .unavailable:
            errorMessage = "订阅商品暂时不可用，请稍后重试。"
        case .cancelled:
            break
        case .pending:
            message = "购买正在等待 Apple 确认。"
        case .unverified:
            errorMessage = "Apple 无法验证这笔交易，请稍后重试。"
        case .notSignedIn:
            errorMessage = "请先登录后再购买会员。"
        case .processing:
            message = "这笔购买记录正在同步中，请稍候。"
        case .accountMismatch(let text):
            errorMessage = text
        case .rejected(let text):
            errorMessage = text
        case .syncFailed(let text):
            errorMessage = text
        }
    }

    private func restore() async {
        guard !isRestoring else { return }
        isRestoring = true
        message = nil
        errorMessage = nil
        defer { isRestoring = false }

        switch await storeKit.restorePurchases() {
        case .restored(let membership):
            message = membership?.isMember == true ? "会员已恢复。" : "购买记录已同步。"
        case .noEntitlements:
            errorMessage = "没有找到可恢复的会员购买记录。"
        case .failed(let text):
            errorMessage = text
        }
    }

    private func openSubscriptionSettings() {
        guard let url = URL(string: "https://apps.apple.com/account/subscriptions") else { return }
        UIApplication.shared.open(url)
    }
}

/// Shows the membership exactly as the server confirmed it.
struct MembershipStatusView: View {
    let membership: MembershipState?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(HomeVisualStyle.ink)
            if let endsAt = membership?.endsAt {
                Text("有效期至 \(endsAt)")
                    .font(.caption)
                    .foregroundStyle(HomeVisualStyle.secondaryInk)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("membershipStatus")
    }

    private var title: String {
        guard let membership else { return "会员状态：尚未确认" }
        switch membership.status {
        case .member: return "会员状态：已开通会员"
        case .free: return "会员状态：免费用户"
        case .anonymous: return "会员状态：未登录"
        case .unknown: return "会员状态：服务器未确认"
        }
    }
}
