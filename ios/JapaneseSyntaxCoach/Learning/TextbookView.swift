import SwiftUI

struct TextbookView: View {
    @ObservedObject var store: LearningStore

    var body: some View {
        List {
            Section { LearningSyncStatusView(store: store) }
            if let textbook = store.textbook {
                Section(textbook.title) {
                    ForEach(textbook.lessons, id: \.id) { lesson in
                        NavigationLink {
                            List {
                                Section("学习目标") {
                                    Text(lesson.goal)
                                    if let description = lesson.description { Text(description) }
                                    NavigationLink("开始整课练习") {
                                        LessonView(store: store, lesson: lesson, questions: LearningStore.orderedQuestions(for: lesson.id, in: textbook))
                                    }
                                }
                                ForEach(Array(lesson.grammar.enumerated()), id: \.offset) { _, point in
                                    Section(point.pattern) {
                                        grammarRow("含义", point.meaning)
                                        grammarRow("例句", point.example)
                                        grammarRow("接续", point.connection)
                                        grammarRow("说明", point.explanation)
                                        if let audio = point.audio, !audio.isEmpty { grammarRow("发音 / 音频提示", audio) }
                                        if let responses = point.responses, !responses.isEmpty {
                                            grammarRow("常见回应", responses.joined(separator: "\n"))
                                        }
                                        if let pitfalls = point.pitfalls, !pitfalls.isEmpty {
                                            grammarRow("易错点", pitfalls.joined(separator: "\n"))
                                        }
                                    }
                                }
                            }
                            .navigationTitle("第 \(lesson.id) 课")
                        } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                Text("第 \(lesson.id) 课 · \(lesson.title)").font(.headline)
                                Text(lesson.goal).font(.subheadline).foregroundStyle(.secondary)
                                Text("\(lesson.grammar.count) 个语法点").font(.caption).foregroundStyle(.secondary)
                            }.padding(.vertical, 4)
                        }
                    }
                }
                if textbook.lessons.isEmpty { Text("教材暂无课程。") }
            } else {
                Text(store.textbookError ?? "正在加载内置教材…")
                Button("重新加载") { Task { await store.loadStudyState() } }
            }
        }
        .navigationTitle("教材")
    }

    private func grammarRow(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).textSelection(.enabled)
        }.padding(.vertical, 3)
    }
}
