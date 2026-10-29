import SwiftUI

struct HomeView: View {
    @ObservedObject var store: LearningStore

    var body: some View {
        List {
            Section("同步状态") { LearningSyncStatusView(store: store) }
            if let textbook = store.textbook {
                Section("继续学习") {
                    if let lesson = currentLesson(in: textbook) {
                        Text("第 \(lesson.id) 课 · \(lesson.title)").font(.headline)
                        Text(lesson.goal).foregroundStyle(.secondary)
                        NavigationLink("开始 / 继续本课") {
                            LessonView(store: store, lesson: lesson, questions: LearningStore.orderedQuestions(for: lesson.id, in: textbook))
                        }
                        Text("每次从本课第 1 题开始；已确认的云端进度会保留。").font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text("教材暂无课程。")
                    }
                }
                Section("到期复习") {
                    if let state = store.studyState {
                        Text("待复习 \(state.dueQuestionIds.count) 题")
                        let due = Set(state.dueQuestionIds)
                        ForEach(textbook.lessons.filter { lesson in
                            textbook.questions.contains { $0.lessonId == lesson.id && due.contains($0.id) }
                        }, id: \.id) { lesson in
                            NavigationLink("复习第 \(lesson.id) 课") {
                                LessonView(store: store, lesson: lesson, questions: textbook.questions.filter { $0.lessonId == lesson.id && due.contains($0.id) }, mode: "review")
                            }
                        }
                        if state.dueQuestionIds.isEmpty { Text("当前没有到期题目。").foregroundStyle(.secondary) }
                    } else { Text("尚未取得云端复习计划。可先学习内置教材。").foregroundStyle(.secondary) }
                }
            } else {
                Section("教材") { Text(store.textbookError ?? "正在加载内置教材…") }
            }
        }
        .navigationTitle("日句")
        .refreshable { await store.loadStudyState(); await store.retryPending() }
    }

    private func currentLesson(in textbook: Textbook) -> TextbookLesson? {
        let completed = Set(store.studyState?.lessons.filter { $0.completedAt != nil }.map(\.lessonId) ?? [])
        return textbook.lessons.first { !completed.contains($0.id) } ?? textbook.lessons.last
    }
}

struct LearningSyncStatusView: View {
    @ObservedObject var store: LearningStore

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(store.syncState.title).font(.subheadline)
            Text("待同步答案：\(store.pendingCount)").font(.caption).accessibilityIdentifier("pendingAnswerCount")
            if store.isShowingCachedStudyState {
                Text("显示本机缓存进度，可能不是最新状态。").font(.caption).foregroundStyle(.secondary)
            }
            if store.syncState == .loading || store.syncState == .syncing {
                SwiftUI.ProgressView()
            } else {
                Button("刷新 / 重试同步") {
                    Task { await store.loadStudyState(); await store.retryPending() }
                }.font(.subheadline)
            }
        }
    }
}
