import SwiftUI

/// Native account screen: identity, membership, sync state, sign out and account deletion.
struct AccountView: View {
    @ObservedObject var auth: AuthSessionStore
    @ObservedObject var learning: LearningStore
    @ObservedObject var storeKit: StoreKitManager

    @State private var isConfirmingDeletion = false
    @State private var deletionError: String?
    @State private var isDeleting = false

    var body: some View {
        List {
            Section("已登录账户") {
                Text(auth.userEmail ?? "当前账户")
                    .accessibilityIdentifier("accountEmail")
                if let userID = auth.userID {
                    Text("账户 ID：\(userID)").font(.caption).foregroundStyle(.secondary)
                }
            }

            Section("会员状态") {
                MembershipStatusView(membership: storeKit.membership)
                NavigationLink("订阅与购买") {
                    SubscriptionView(storeKit: storeKit)
                }
                .accessibilityIdentifier("subscriptionEntry")
            }

            Section("学习同步") {
                LearningSyncStatusView(store: learning)
            }

            Section("账户操作") {
                Button("退出登录", role: .destructive) {
                    Task {
                        learning.clearUserScopedData()
                        await auth.signOut()
                    }
                }
                .accessibilityLabel("退出登录")
                .accessibilityIdentifier("signOut")

                Button("删除账号", role: .destructive) {
                    isConfirmingDeletion = true
                }
                .accessibilityLabel("删除账号")
                .accessibilityIdentifier("deleteAccount")
            }

            Section {
                Text("删除账号会清除你的云端学习记录，并清除本机的待同步答案与缓存进度。该操作不可撤销。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let deletionError {
                    Text(deletionError).font(.caption).foregroundStyle(.red)
                        .accessibilityIdentifier("deleteAccountError")
                }
            } header: {
                Text("删除说明")
            }
        }
        .navigationTitle("账户")
        .confirmationDialog(
            "确认删除账号？",
            isPresented: $isConfirmingDeletion,
            titleVisibility: .visible
        ) {
            Button("删除账号", role: .destructive) { Task { await deleteAccount() } }
            Button("取消", role: .cancel) { }
        } message: {
            Text("删除后无法恢复学习进度、错题和复习计划。")
        }
    }

    private func deleteAccount() async {
        guard !isDeleting else { return }
        isDeleting = true
        deletionError = nil
        defer { isDeleting = false }

        do {
            try await learning.deleteAccount()
            learning.clearUserScopedData()
            storeKit.activateAccount(nil)
            await auth.signOut()
        } catch {
            deletionError = error.localizedDescription
        }
    }
}
