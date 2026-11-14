import SwiftUI

struct LessonView: View {
    @ObservedObject var store: LearningStore
    let lesson: TextbookLesson
    let questions: [TextbookQuestion]
    var mode = "lesson"

    @State private var activeQuestions: [TextbookQuestion] = []
    @State private var activeMode: String = "lesson"
    @State private var index = 0
    @State private var lastAnswer = ""
    @State private var evaluation: LocalEvaluation?
    @State private var aiGrade: AIGradeResponse?
    @State private var isAIGrading = false
    @State private var aiAnalysis: AIAnalysisResponse?
    @State private var aiAnalysisError: String?
    @State private var isAnalyzing = false
    @State private var correctCount = 0
    @State private var sessionMistakes: [TextbookQuestion] = []
    @State private var isSubmitting = false
    @State private var didRecordCompletion = false
    @AppStorage("nihongo.kana.enabled") private var showKana = true
    @Environment(\.dismiss) private var dismiss

    private var currentQuestions: [TextbookQuestion] {
        activeQuestions.isEmpty ? questions : activeQuestions
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: HomeVisualStyle.sectionSpacing) {
                if currentQuestions.isEmpty {
                    Text("本课暂无可用题目，请返回教材重试。")
                        .font(.subheadline)
                        .foregroundStyle(HomeVisualStyle.secondaryInk)
                        .homeCardStyle()
                } else if index >= currentQuestions.count {
                    completionCard
                } else {
                    let question = currentQuestions[index]
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("第 \(index + 1) / \(currentQuestions.count) 题")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(HomeVisualStyle.secondaryInk)
                            Spacer()
                            Button {
                                showKana.toggle()
                            } label: {
                                Text(showKana ? "假名：开" : "假名：关")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(HomeVisualStyle.accentInk)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(HomeVisualStyle.mint)
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                        SwiftUI.ProgressView(value: Double(index), total: Double(currentQuestions.count))
                            .tint(HomeVisualStyle.accent)
                    }

                    QuestionView(question: question, isSubmitted: evaluation != nil) { answer in
                        submitAnswer(answer, for: question)
                    }
                    .id("\(activeMode)-\(index)-\(question.id)")

                    if let evaluation {
                        feedbackCard(for: question, evaluation: evaluation)
                    }
                }
            }
            .padding(HomeVisualStyle.screenPadding)
        }
        .homeScreenChrome()
        .navigationTitle(navigationTitleText)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if activeQuestions.isEmpty {
                activeQuestions = questions
                activeMode = mode
            }
        }
        .onDisappear {
            JapaneseSpeechPlayer.shared.stop()
        }
    }

    private var navigationTitleText: String {
        switch activeMode {
        case "mistakes":
            return "错题练习"
        case "review":
            return "综合复习"
        default:
            return "第 \(lesson.id) 课"
        }
    }

    private var completionCard: some View {
        let total = max(currentQuestions.count, 1)
        let accuracy = Int((Double(correctCount) / Double(total) * 100.0).rounded())

        return VStack(alignment: .leading, spacing: 14) {
            Label(
                activeMode == "mistakes" ? "本次错题练习完成" : activeMode == "review" ? "本次复习完成" : "整课练习完成",
                systemImage: "checkmark.circle.fill"
            )
            .font(.title2.bold())
            .foregroundStyle(HomeVisualStyle.accent)

            Text("本次答对 \(correctCount) / \(currentQuestions.count) 题（正确率 \(accuracy)%）")
                .font(.headline)
                .foregroundStyle(HomeVisualStyle.ink)

            HStack(spacing: 10) {
                statPill(label: "答对", value: "\(correctCount) 题")
                statPill(label: "需巩固", value: "\(sessionMistakes.count) 题")
                statPill(label: "正确率", value: "\(accuracy)%")
            }

            Text(
                store.textbook?.isBuiltin == false
                    ? "当前自定义教材进度已保存在本机。"
                    : (store.pendingCount > 0 ? "答案仍有待同步；云端完成状态将在服务器确认后更新。" : "云端统计以服务器返回的学习进度为准。")
            )
            .font(.subheadline)
            .foregroundStyle(HomeVisualStyle.secondaryInk)

            if !sessionMistakes.isEmpty {
                Button {
                    let mistakesToReplay = sessionMistakes
                    activeQuestions = mistakesToReplay
                    activeMode = "mistakes"
                    index = 0
                    correctCount = 0
                    sessionMistakes = []
                    evaluation = nil
                    aiGrade = nil
                    aiAnalysis = nil
                    aiAnalysisError = nil
                    didRecordCompletion = false
                } label: {
                    Label("重练本轮错题（\(sessionMistakes.count) 题）", systemImage: "arrow.counterclockwise")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(HomeVisualStyle.accentInk)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(HomeVisualStyle.accent)
            }

            Button {
                dismiss()
            } label: {
                Text("返回")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(HomeVisualStyle.card)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(HomeVisualStyle.accent)
        }
        .homeCardStyle()
        .onAppear {
            guard !didRecordCompletion else { return }
            didRecordCompletion = true
            store.recordLessonCompletion(
                lessonId: lesson.id,
                correct: correctCount,
                total: currentQuestions.count,
                mistakeQuestionIds: sessionMistakes.map(\.id),
                replayed: activeMode == "mistakes" || activeMode == "lesson_replay"
            )
        }
    }

    private func statPill(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.caption)
                .foregroundStyle(HomeVisualStyle.secondaryInk)
            Text(value)
                .font(.subheadline.weight(.bold).monospacedDigit())
                .foregroundStyle(HomeVisualStyle.ink)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(HomeVisualStyle.canvas.opacity(0.65))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func feedbackCard(for question: TextbookQuestion, evaluation: LocalEvaluation) -> some View {
        let effectiveCorrect = aiGrade != nil
            ? (aiGrade?.verdict == "correct" || aiGrade?.verdict == "mostly_correct")
            : evaluation.isCorrect
        let effectiveVerdict = aiGrade?.verdict ?? evaluation.verdict
        let effectiveFeedback = aiGrade?.explanation ?? evaluation.feedback
        let effectiveExpected = aiGrade?.correctedAnswer ?? evaluation.expectedAnswer
        let effectiveTags = aiGrade?.errorTags ?? evaluation.errorTags
        let gradingSourceLabel = aiGrade?.source == "ai" ? "AI 智能判分" : "本机规则评分"

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(
                    verdictTitle(verdict: effectiveVerdict, isCorrect: effectiveCorrect),
                    systemImage: effectiveCorrect ? "checkmark.circle.fill" : "exclamationmark.circle.fill"
                )
                .font(.headline)
                .foregroundStyle(effectiveCorrect ? HomeVisualStyle.accentInk : .orange)
                Spacer()
                if isAIGrading {
                    HStack(spacing: 4) {
                        SwiftUI.ProgressView()
                            .controlSize(.mini)
                        Text("AI 判分中…")
                            .font(.caption2)
                            .foregroundStyle(HomeVisualStyle.secondaryInk)
                    }
                } else {
                    Text(gradingSourceLabel)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(HomeVisualStyle.secondaryInk)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(HomeVisualStyle.canvas)
                        .clipShape(Capsule())
                }
            }

            Text(effectiveFeedback)
                .font(.body)
                .foregroundStyle(HomeVisualStyle.ink)

            if !effectiveTags.isEmpty {
                HStack(spacing: 6) {
                    ForEach(effectiveTags, id: \.self) { tag in
                        Text(tag)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.orange.opacity(0.12))
                            .clipShape(Capsule())
                    }
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("参考答案：\(WordTokenReadings.annotate(effectiveExpected, enabled: showKana))")
                        .font(.body.weight(.medium))
                        .foregroundStyle(HomeVisualStyle.ink)
                        .textSelection(.enabled)
                    Spacer()
                    Button {
                        JapaneseSpeechPlayer.shared.speak(effectiveExpected)
                    } label: {
                        Label("朗读", systemImage: "speaker.wave.2")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(HomeVisualStyle.accentInk)
                    }
                    .buttonStyle(.plain)
                }
                if showKana, let reading = JapaneseKanaHelper.readingHint(for: effectiveExpected) {
                    Text("假名注音：\(reading)")
                        .font(.caption)
                        .foregroundStyle(HomeVisualStyle.secondaryInk)
                }
            }
            .padding(10)
            .background(HomeVisualStyle.mint.opacity(0.75))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            // AI Analysis button & result matching Web QuestionCard
            if let analysis = aiAnalysis {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Label("AI 记忆法与词汇拆解", systemImage: "sparkles")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(HomeVisualStyle.accentInk)
                        Spacer()
                    }
                    if let summaryText = analysis.analysis, !summaryText.isEmpty {
                        Text(summaryText)
                            .font(.subheadline)
                            .foregroundStyle(HomeVisualStyle.ink)
                    }

                    if let words = analysis.words, !words.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(Array(words.enumerated()), id: \.offset) { _, word in
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 6) {
                                        Text(word.word)
                                            .font(.footnote.weight(.bold))
                                            .foregroundStyle(HomeVisualStyle.accentInk)
                                        if !word.kana.isEmpty {
                                            Text("[\(word.kana)]")
                                                .font(.caption)
                                                .foregroundStyle(HomeVisualStyle.secondaryInk)
                                        }
                                        Text("· \(word.meaning)")
                                            .font(.caption.weight(.medium))
                                            .foregroundStyle(HomeVisualStyle.ink)
                                    }
                                    if !word.memory.isEmpty {
                                        Text("记忆法：\(word.memory)")
                                            .font(.caption)
                                            .foregroundStyle(HomeVisualStyle.secondaryInk)
                                    }
                                }
                                .padding(8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(HomeVisualStyle.card)
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            }
                        }
                    }

                    if let pitfalls = analysis.pitfalls, !pitfalls.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("易错提醒")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.orange)
                            ForEach(pitfalls, id: \.self) { pitfall in
                                Text("• \(pitfall)")
                                    .font(.caption)
                                    .foregroundStyle(HomeVisualStyle.ink)
                            }
                        }
                    }
                }
                .padding(12)
                .background(HomeVisualStyle.mint)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            } else {
                Button {
                    requestAnalysis(for: question)
                } label: {
                    HStack(spacing: 6) {
                        if isAnalyzing {
                            SwiftUI.ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "sparkles")
                        }
                        Text(isAnalyzing ? "正在生成记忆方法…" : "AI 分析记忆方法 · 会员")
                            .font(.footnote.weight(.semibold))
                    }
                    .foregroundStyle(HomeVisualStyle.accentInk)
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(HomeVisualStyle.accent)
                .disabled(isAnalyzing)
            }

            if let aiAnalysisError {
                Text(aiAnalysisError)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            Button {
                index += 1
                self.evaluation = nil
                self.aiGrade = nil
                self.isAIGrading = false
                self.aiAnalysis = nil
                self.aiAnalysisError = nil
            } label: {
                Text(index + 1 == currentQuestions.count ? "完成练习" : "下一题")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(HomeVisualStyle.card)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(HomeVisualStyle.accent)
        }
        .homeCardStyle(
            borderColor: effectiveCorrect
                ? HomeVisualStyle.accent.opacity(0.35)
                : Color.orange.opacity(0.45)
        )
    }

    private func submitAnswer(_ answer: String, for question: TextbookQuestion) {
        let result = AnswerEvaluator.evaluate(question: question, answer: answer)
        let currentIdx = index
        lastAnswer = answer
        aiGrade = nil
        aiAnalysis = nil
        aiAnalysisError = nil
        evaluation = result

        if result.isCorrect {
            correctCount += 1
        } else if !sessionMistakes.contains(where: { $0.id == question.id }) {
            sessionMistakes.append(question)
        }

        let submission = AnswerSubmission(
            question: question,
            answer: answer,
            evaluation: result,
            mode: activeMode
        )

        Task {
            _ = await store.submit(submission)
        }

        if !result.isCorrect && question.type != "choice" && question.type != "选择" {
            isAIGrading = true
            Task {
                let grade = await store.requestAIGrade(question: question, answer: answer)
                guard index == currentIdx else { return }
                if let grade {
                    aiGrade = grade
                    if grade.verdict == "correct" || grade.verdict == "mostly_correct" {
                        correctCount += 1
                        sessionMistakes.removeAll { $0.id == question.id }
                    }
                }
                isAIGrading = false
            }
        }
    }

    private func requestAnalysis(for question: TextbookQuestion) {
        guard !isAnalyzing else { return }
        isAnalyzing = true
        aiAnalysisError = nil
        let answerText = lastAnswer
        Task {
            let response = await store.requestAIAnalysis(question: question, answer: answerText)
            if let err = response.error, !err.isEmpty {
                aiAnalysisError = err
            } else {
                aiAnalysis = response
            }
            isAnalyzing = false
        }
    }

    private func verdictTitle(verdict: String, isCorrect: Bool) -> String {
        if verdict == "mostly_correct" { return "基本正确" }
        if isCorrect { return "回答正确" }
        return verdict == "needs_fix" ? "接近正确，请订正" : "需要再练习"
    }
}
