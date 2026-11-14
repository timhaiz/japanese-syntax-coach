import SwiftUI

/// Native account screen ("我的") aligned with Web's ProfileOverview:
/// avatar header, 3-column stats summary, detailed learning metrics, membership & StoreKit subscription, sync status, sign out, and account deletion.
struct AccountView: View {
    @ObservedObject var auth: AuthSessionStore
    @ObservedObject var learning: LearningStore
    @ObservedObject var storeKit: StoreKitManager
    @Environment(\.adEligibility) private var adEligibility

    @State private var isConfirmingSignOut = false
    @State private var isConfirmingDeletion = false
    @State private var isDeletingAccount = false
    @State private var deletionError: String?

    private var avatarInitial: String {
        guard let first = auth.userEmail?.trimmingCharacters(in: .whitespacesAndNewlines).first else {
            return "日"
        }
        return String(first).uppercased()
    }

    private var isMemberActive: Bool {
        storeKit.membership?.isMember == true
    }

    private var currentLessonText: String {
        if let lesson = learning.activeCurrentLesson() {
            return "第 \(lesson.id) 课"
        }
        return "第 1 课"
    }

    private var overallProgressText: String {
        guard let textbook = learning.textbook else { return "0%" }
        return "\(learning.textbookProgressPercent(for: textbook))%"
    }

    private var totalAttemptsText: String {
        if let textbook = learning.textbook, !textbook.isBuiltin {
            let local = learning.localProgressByTextbook[textbook.id] ?? LocalTextbookProgress()
            return "\(local.totalAttempts) 题"
        }
        let count = learning.studyState?.metrics.totalAttempts ?? 0
        return "\(count) 题"
    }

    private var streakCountText: String {
        if let textbook = learning.textbook, !textbook.isBuiltin {
            let local = learning.localProgressByTextbook[textbook.id] ?? LocalTextbookProgress()
            return "\(local.correctStreak) 题"
        }
        let streak = learning.studyState?.metrics.correctStreak ?? 0
        return "\(streak) 题"
    }

    private var errorRateText: String {
        if let textbook = learning.textbook, !textbook.isBuiltin {
            let local = learning.localProgressByTextbook[textbook.id] ?? LocalTextbookProgress()
            guard local.totalAttempts > 0 else { return "0%" }
            let rate = Int((Double(local.incorrectAttempts) / Double(local.totalAttempts) * 100.0).rounded())
            return "\(rate)%"
        }
        guard let metrics = learning.studyState?.metrics, metrics.totalAttempts > 0 else { return "0%" }
        return "\(metrics.errorRate)%"
    }

    private var forgetRateText: String {
        guard let metrics = learning.studyState?.metrics, metrics.totalAttempts > 0 else { return "0%" }
        return "\(metrics.forgettingRate)%"
    }

    private var topErrorTagText: String {
        if let textbook = learning.textbook, !textbook.isBuiltin {
            let local = learning.localProgressByTextbook[textbook.id] ?? LocalTextbookProgress()
            return local.topErrorTagCounts.max(by: { $0.value < $1.value })?.key ?? "暂无"
        }
        let tag = learning.studyState?.metrics.topErrorTags.first?.tag.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return tag.isEmpty ? "暂无" : tag
    }

    private var completedLessonsText: String {
        guard let textbook = learning.textbook else { return "0 / 0 课" }
        let done = learning.textbookCompletedLessonCount(for: textbook)
        return "\(done) / \(textbook.lessons.count) 课"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: HomeVisualStyle.sectionSpacing) {
                // Profile Header Card matching Web ProfileOverview
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .center, spacing: 14) {
                        Text(avatarInitial)
                            .font(.title2.bold())
                            .foregroundStyle(HomeVisualStyle.accentInk)
                            .frame(width: 54, height: 54)
                            .background(HomeVisualStyle.mint)
                            .clipShape(Circle())
                            .overlay(
                                Circle()
                                    .stroke(HomeVisualStyle.accent.opacity(0.28), lineWidth: 1)
                            )

                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 8) {
                                Text(auth.userEmail ?? "当前账户")
                                    .font(.headline)
                                    .foregroundStyle(HomeVisualStyle.ink)
                                    .lineLimit(1)
                                    .accessibilityIdentifier("accountEmail")
                                Text(isMemberActive ? "PRO 会员" : "标准账号")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(isMemberActive ? HomeVisualStyle.card : HomeVisualStyle.accentInk)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(isMemberActive ? HomeVisualStyle.accent : HomeVisualStyle.mint)
                                    .clipShape(Capsule())
                            }
                            if let userID = auth.userID {
                                Text("账户 ID：\(userID)")
                                    .font(.caption2)
                                    .foregroundStyle(HomeVisualStyle.secondaryInk)
                                    .lineLimit(1)
                            }
                        }
                        Spacer(minLength: 0)
                    }

                    // 3-column overview stats matching Web .profile-stats-grid
                    HStack(spacing: 10) {
                        profileStatBox(title: "当前课程", value: currentLessonText)
                        profileStatBox(title: "学习进度", value: overallProgressText)
                        profileStatBox(title: "累计练习", value: totalAttemptsText)
                    }
                }
                .homeCardStyle()

                // Detailed learning metrics matching Web .profile-detail-list
                VStack(alignment: .leading, spacing: 12) {
                    sectionHeader("学习数据详情")
                    VStack(spacing: 10) {
                        detailRow(label: "当前教材", value: learning.textbook?.title ?? "大家的日语 初级 I")
                        Divider().overlay(HomeVisualStyle.accent.opacity(0.12))
                        detailRow(label: "已完成课程", value: completedLessonsText)
                        Divider().overlay(HomeVisualStyle.accent.opacity(0.12))
                        detailRow(label: "连续答对", value: streakCountText)
                        Divider().overlay(HomeVisualStyle.accent.opacity(0.12))
                        detailRow(label: "总体错误率", value: errorRateText)
                        Divider().overlay(HomeVisualStyle.accent.opacity(0.12))
                        detailRow(label: "遗忘率", value: forgetRateText)
                        Divider().overlay(HomeVisualStyle.accent.opacity(0.12))
                        detailRow(label: "最常错知识点", value: topErrorTagText)
                    }
                    .padding(12)
                    .background(HomeVisualStyle.canvas.opacity(0.55))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                    NavigationLink {
                        LearningProgressView(store: learning)
                    } label: {
                        Label("查看学习统计", systemImage: "chart.bar")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(HomeVisualStyle.accentInk)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(HomeVisualStyle.accent)
                }
                .homeCardStyle()

                // Membership & Subscription Card
                VStack(alignment: .leading, spacing: 12) {
                    sectionHeader("会员状态")
                    MembershipStatusView(membership: storeKit.membership)
                    NavigationLink {
                        SubscriptionView(storeKit: storeKit)
                    } label: {
                        Text("订阅与购买")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(HomeVisualStyle.accentInk)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(HomeVisualStyle.accent)
                    .accessibilityIdentifier("subscriptionEntry")
                }
                .homeCardStyle()

                AdPlacementBoundary(eligibility: adEligibility)

                if let deletionError {
                    Text(deletionError)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .accessibilityIdentifier("deleteAccountError")
                        .homeCardStyle()
                }
            }
            .padding(HomeVisualStyle.screenPadding)
        }
        .homeScreenChrome()
        .navigationTitle("我的")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button(role: .destructive) {
                        isConfirmingSignOut = true
                    } label: {
                        Label("退出登录", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                    .accessibilityIdentifier("signOut")

                    Button(role: .destructive) {
                        deletionError = nil
                        isConfirmingDeletion = true
                    } label: {
                        Label(isDeletingAccount ? "正在删除账号…" : "删除账号", systemImage: "trash")
                    }
                    .disabled(isDeletingAccount)
                    .accessibilityIdentifier("deleteAccount")
                } label: {
                    Image(systemName: "gearshape")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(HomeVisualStyle.ink)
                }
                .accessibilityLabel("账户设置")
                .accessibilityIdentifier("accountSettingsMenu")
            }
        }
        .confirmationDialog(
            "确认退出当前账号？",
            isPresented: $isConfirmingSignOut,
            titleVisibility: .visible
        ) {
            Button("确认退出登录", role: .destructive) {
                Task {
                    await auth.signOut()
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("退出登录后需重新使用邮箱密码或验证码登录。")
        }
        .confirmationDialog(
            "确认永久删除当前账号？",
            isPresented: $isConfirmingDeletion,
            titleVisibility: .visible
        ) {
            Button("确认删除账号", role: .destructive) {
                Task {
                    await performDeleteAccount()
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("删除账号会永久清理当前账号在服务器上的学习进度、错题记录、个人资料与自定义教材数据，操作不可撤销。若有未同步的离线答题，请先完成同步。删除应用或账号不会自动取消 Apple 订阅。")
        }
    }

    private func profileStatBox(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(HomeVisualStyle.secondaryInk)
            Text(value)
                .font(.subheadline.weight(.bold).monospacedDigit())
                .foregroundStyle(HomeVisualStyle.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(HomeVisualStyle.canvas.opacity(0.65))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func detailRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(HomeVisualStyle.secondaryInk)
            Spacer()
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(HomeVisualStyle.ink)
        }
    }

    private func performDeleteAccount() async {
        guard !isDeletingAccount else { return }
        isDeletingAccount = true
        deletionError = nil
        defer { isDeletingAccount = false }
        do {
            try await learning.deleteAccount()
            await auth.signOut()
        } catch {
            deletionError = error.localizedDescription
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.headline)
            .foregroundStyle(HomeVisualStyle.ink)
            .accessibilityAddTraits(.isHeader)
    }
}
