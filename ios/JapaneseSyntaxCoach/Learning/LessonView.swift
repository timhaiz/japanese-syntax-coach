import SwiftUI

struct LessonView: View {
    @ObservedObject var store: LearningStore
    let lesson: TextbookLesson
    let questions: [TextbookQuestion]
    var mode = "lesson"
    @State private var index = 0
    @State private var evaluation: LocalEvaluation?
    @State private var correctCount = 0
    @State private var isSubmitting = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                LearningSyncStatusView(store: store)
                if questions.isEmpty {
                    Text("本课暂无可用题目，请返回教材重试。").foregroundStyle(.secondary)
                } else if index >= questions.count {
                    Label(mode == "review" ? "本次复习完成" : "整课练习完成", systemImage: "checkmark.circle.fill")
                        .font(.title2.bold()).foregroundStyle(.green)
                    Text("本次答对 \(correctCount) / \(questions.count) 题")
                    Text(store.pendingCount > 0 ? "答案仍有待同步；云端完成状态将在服务器确认后更新。" : "云端统计以服务器返回的学习进度为准。")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Button("返回") { dismiss() }.buttonStyle(.borderedProminent)
                } else {
                    Text("第 \(index + 1) / \(questions.count) 题").font(.headline)
                    SwiftUI.ProgressView(value: Double(index), total: Double(questions.count))
                    QuestionView(question: questions[index], isSubmitted: evaluation != nil) { answer in
                        let question = questions[index]
                        let result = AnswerEvaluator.evaluate(question: question, answer: answer)
                        evaluation = result
                        if result.isCorrect { correctCount += 1 }
                        isSubmitting = true
                        Task {
                            await store.submit(AnswerSubmission(question: question, answer: answer, evaluation: result, mode: mode))
                            isSubmitting = false
                        }
                    }
                    .id(questions[index].id)
                    if let evaluation {
                        VStack(alignment: .leading, spacing: 10) {
                            Label(verdictTitle(evaluation), systemImage: evaluation.isCorrect ? "checkmark.circle" : "exclamationmark.circle")
                                .font(.headline).foregroundStyle(evaluation.isCorrect ? .green : .orange)
                            Text(evaluation.feedback)
                            Text("参考答案：\(evaluation.expectedAnswer)").textSelection(.enabled)
                            Text("本机规则评分；未调用 AI 评分。").font(.caption).foregroundStyle(.secondary)
                            if isSubmitting { Text("答案已入队，正在尝试同步…").font(.caption) }
                            Button(index + 1 == questions.count ? "完成练习" : "下一题") {
                                index += 1
                                self.evaluation = nil
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(isSubmitting)
                        }
                        .padding().background(Color.secondary.opacity(0.08)).cornerRadius(12)
                    }
                }
            }.padding()
        }
        .navigationTitle("第 \(lesson.id) 课")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func verdictTitle(_ result: LocalEvaluation) -> String {
        result.isCorrect ? "回答正确" : (result.verdict == "needs_fix" ? "接近正确，请订正" : "需要再练习")
    }
}
