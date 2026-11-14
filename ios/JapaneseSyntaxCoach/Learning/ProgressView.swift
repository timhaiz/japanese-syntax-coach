import SwiftUI

// Avoid shadowing SwiftUI.ProgressView used by authentication and loading indicators.
struct LearningProgressView: View {
    @ObservedObject var store: LearningStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: HomeVisualStyle.sectionSpacing) {
                if let state = store.studyState {
                    VStack(alignment: .leading, spacing: 12) {
                        sectionHeader("结构化学习统计")
                        metric("总答题次数", state.metrics.totalAttempts)
                        Divider().overlay(HomeVisualStyle.accent.opacity(0.12))
                        metric("错误次数", state.metrics.incorrectAttempts)
                        Divider().overlay(HomeVisualStyle.accent.opacity(0.12))
                        metric("错误率", state.metrics.errorRate, suffix: "%")
                        Divider().overlay(HomeVisualStyle.accent.opacity(0.12))
                        metric("遗忘率", state.metrics.forgettingRate, suffix: "%")
                        Divider().overlay(HomeVisualStyle.accent.opacity(0.12))
                        metric("连续答对", state.metrics.correctStreak)
                        if !state.textbookScopeAvailable {
                            Text("服务器暂不支持独立教材范围统计。")
                                .font(.caption)
                                .foregroundStyle(HomeVisualStyle.secondaryInk)
                                .padding(.top, 2)
                        }
                    }
                    .homeCardStyle()

                    VStack(alignment: .leading, spacing: 12) {
                        sectionHeader("高频错误")
                        if state.metrics.topErrorTags.isEmpty {
                            Text("暂无已记录的错误标签。")
                                .font(.subheadline)
                                .foregroundStyle(HomeVisualStyle.secondaryInk)
                        } else {
                            ForEach(Array(state.metrics.topErrorTags.enumerated()), id: \.element.id) { index, tag in
                                if index > 0 {
                                    Divider().overlay(HomeVisualStyle.accent.opacity(0.12))
                                }
                                metric(tag.tag, tag.count, suffix: " 次")
                            }
                        }
                    }
                    .homeCardStyle()

                    VStack(alignment: .leading, spacing: 12) {
                        sectionHeader("已完成课程")
                        let completed = state.lessons.filter { $0.completedAt != nil }
                        if completed.isEmpty {
                            Text("暂无云端确认完成的课程。")
                                .font(.subheadline)
                                .foregroundStyle(HomeVisualStyle.secondaryInk)
                        } else {
                            ForEach(Array(completed.enumerated()), id: \.element.id) { index, lesson in
                                if index > 0 {
                                    Divider().overlay(HomeVisualStyle.accent.opacity(0.12))
                                }
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("第 \(lesson.lessonId) 课")
                                        .font(.headline)
                                        .foregroundStyle(HomeVisualStyle.ink)
                                    Text("已答 \(lesson.answeredCount) 题 · 正确 \(lesson.correctCount) 题")
                                        .font(.subheadline)
                                        .foregroundStyle(HomeVisualStyle.secondaryInk)
                                }
                            }
                        }
                    }
                    .homeCardStyle()

                    VStack(alignment: .leading, spacing: 10) {
                        sectionHeader("旧版进度 · 独立保留")
                        Text(state.legacyProgressSummary)
                            .font(.subheadline)
                            .foregroundStyle(HomeVisualStyle.ink)
                        Text("旧版数据不参与上述统计，也不会被本机快照覆盖。")
                            .font(.caption)
                            .foregroundStyle(HomeVisualStyle.secondaryInk)
                        if state.legacyProgressAvailable, let legacy = state.legacyProgress {
                            DisclosureGroup("查看原始旧版进度") {
                                Text(legacyText(legacy))
                                    .font(.caption.monospaced())
                                    .foregroundStyle(HomeVisualStyle.ink)
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(12)
                                    .background(HomeVisualStyle.canvas)
                                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                    .padding(.top, 6)
                            }
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(HomeVisualStyle.accentInk)
                            .tint(HomeVisualStyle.accent)
                        }
                    }
                    .homeCardStyle()
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        sectionHeader("学习进度")
                        Text("尚未取得学习进度。请检查网络并刷新；内置教材仍可学习。")
                            .font(.subheadline)
                            .foregroundStyle(HomeVisualStyle.secondaryInk)
                    }
                    .homeCardStyle()
                }
            }
            .padding(HomeVisualStyle.screenPadding)
        }
        .homeScreenChrome()
        .navigationTitle("进度")
        .refreshable { await store.loadStudyState() }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.headline)
            .foregroundStyle(HomeVisualStyle.ink)
            .accessibilityAddTraits(.isHeader)
    }

    private func metric(_ label: String, _ value: Int, suffix: String = "") -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(HomeVisualStyle.secondaryInk)
            Spacer()
            Text("\(value)\(suffix)")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(HomeVisualStyle.ink)
        }
    }

    private func legacyText(_ value: JSONValue) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(value) else { return "旧版数据暂时无法显示。" }
        return String(data: data, encoding: .utf8) ?? "旧版数据暂时无法显示。"
    }
}
