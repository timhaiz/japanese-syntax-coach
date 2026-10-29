import SwiftUI

// Avoid shadowing SwiftUI.ProgressView used by authentication and loading indicators.
struct LearningProgressView: View {
    @ObservedObject var store: LearningStore

    var body: some View {
        List {
            Section("同步状态") { LearningSyncStatusView(store: store) }
            if let state = store.studyState {
                Section("结构化学习统计") {
                    metric("总答题次数", state.metrics.totalAttempts)
                    metric("错误次数", state.metrics.incorrectAttempts)
                    metric("错误率", state.metrics.errorRate, suffix: "%")
                    metric("遗忘率", state.metrics.forgettingRate, suffix: "%")
                    metric("连续答对", state.metrics.correctStreak)
                    if !state.textbookScopeAvailable {
                        Text("服务器暂不支持独立教材范围统计。").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Section("高频错误") {
                    if state.metrics.topErrorTags.isEmpty { Text("暂无已记录的错误标签。").foregroundStyle(.secondary) }
                    ForEach(state.metrics.topErrorTags) { tag in metric(tag.tag, tag.count, suffix: " 次") }
                }
                Section("已完成课程") {
                    let completed = state.lessons.filter { $0.completedAt != nil }
                    if completed.isEmpty { Text("暂无云端确认完成的课程。").foregroundStyle(.secondary) }
                    ForEach(completed) { lesson in
                        VStack(alignment: .leading, spacing: 4) {
                            Text("第 \(lesson.lessonId) 课").font(.headline)
                            Text("已答 \(lesson.answeredCount) 题 · 正确 \(lesson.correctCount) 题").font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                }
                Section("旧版进度 · 独立保留") {
                    Text(state.legacyProgressSummary)
                    Text("旧版数据不参与上述统计，也不会被本机快照覆盖。").font(.caption).foregroundStyle(.secondary)
                    if state.legacyProgressAvailable, let legacy = state.legacyProgress {
                        DisclosureGroup("查看原始旧版进度") {
                            Text(legacyText(legacy)).font(.caption.monospaced()).textSelection(.enabled)
                        }
                    }
                }
            } else {
                Section("学习进度") {
                    Text("尚未取得学习进度。请检查网络并刷新；内置教材仍可学习。").foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("进度")
        .refreshable { await store.loadStudyState() }
    }

    private func metric(_ label: String, _ value: Int, suffix: String = "") -> some View {
        HStack { Text(label); Spacer(); Text("\(value)\(suffix)").bold() }
    }

    private func legacyText(_ value: JSONValue) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(value) else { return "旧版数据暂时无法显示。" }
        return String(data: data, encoding: .utf8) ?? "旧版数据暂时无法显示。"
    }
}
