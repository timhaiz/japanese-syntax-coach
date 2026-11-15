import AVFoundation
import SwiftUI

extension View {
    func homeCardStyle(
        padding: CGFloat = HomeVisualStyle.cardPadding,
        borderColor: Color = HomeVisualStyle.accent.opacity(0.18)
    ) -> some View {
        self
            .foregroundStyle(HomeVisualStyle.ink)
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(HomeVisualStyle.card)
            .clipShape(RoundedRectangle(cornerRadius: HomeVisualStyle.cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: HomeVisualStyle.cornerRadius, style: .continuous)
                    .stroke(borderColor, lineWidth: 1)
            )
    }

    func homeScreenChrome() -> some View {
        self
            .background(HomeVisualStyle.canvas.ignoresSafeArea())
            .foregroundStyle(HomeVisualStyle.ink)
            .tint(HomeVisualStyle.accent)
            .toolbarColorScheme(.light, for: .navigationBar)
    }
}

/// Plays bundled grammar examples when available, otherwise synthesizes Japanese speech.
@MainActor
final class JapaneseSpeechPlayer: NSObject, ObservableObject, AVSpeechSynthesizerDelegate, AVAudioPlayerDelegate {
    static let shared = JapaneseSpeechPlayer()

    @Published private(set) var speakingText: String?
    private let synthesizer = AVSpeechSynthesizer()
    private var audioPlayer: AVAudioPlayer?
    private var currentUtterance: AVSpeechUtterance?

    private struct AudioManifest: Decodable {
        let sentences: [String: String]
    }

    static func bundledAudioURL(for text: String, textbookID: String?, manifestData: Data, directory: URL, fileExists: (URL) -> Bool) -> URL? {
        guard textbookID == "builtin-japanese-syntax",
              let manifest = try? JSONDecoder().decode(AudioManifest.self, from: manifestData),
              let filename = manifest.sentences[text],
              !filename.isEmpty, filename == (filename as NSString).lastPathComponent,
              (filename as NSString).pathExtension.lowercased() == "mp3" else { return nil }
        let url = directory.appendingPathComponent(filename)
        return fileExists(url) ? url : nil
    }

    private func bundledAudioURL(for text: String, textbookID: String?) -> URL? {
        guard let directory = Bundle.main.resourceURL?.appendingPathComponent("JapaneseAudio", isDirectory: true),
              let data = try? Data(contentsOf: directory.appendingPathComponent("manifest.json")) else { return nil }
        return Self.bundledAudioURL(for: text, textbookID: textbookID, manifestData: data, directory: directory) {
            FileManager.default.fileExists(atPath: $0.path)
        }
    }

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func speak(_ rawText: String, textbookID: String? = nil) {
        let cleaned = Self.extractJapaneseSentence(from: rawText)
        guard !cleaned.isEmpty else { return }

        if speakingText != nil {
            let wasSame = (speakingText == rawText)
            stop()
            if wasSame { return }
        }

        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try? AVAudioSession.sharedInstance().setActive(true)

        if let url = bundledAudioURL(for: rawText, textbookID: textbookID),
           let player = try? AVAudioPlayer(contentsOf: url) {
            player.delegate = self
            audioPlayer = player
            speakingText = rawText
            if player.play() { return }
            audioPlayer = nil
        }

        let utterance = AVSpeechUtterance(string: cleaned)
        utterance.voice = AVSpeechSynthesisVoice(language: "ja-JP")
        utterance.rate = 0.46
        utterance.pitchMultiplier = 1.0
        speakingText = rawText
        currentUtterance = utterance
        synthesizer.speak(utterance)
    }

    func stop() {
        audioPlayer?.stop()
        audioPlayer = nil
        currentUtterance = nil
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        speakingText = nil
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            guard self.audioPlayer === player else { return }
            self.audioPlayer = nil
            self.speakingText = nil
        }
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        Task { @MainActor in
            guard self.audioPlayer === player, let text = self.speakingText else { return }
            self.audioPlayer = nil
            self.speakingText = nil
            self.speak(text)
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            guard self.currentUtterance === utterance else { return }
            self.currentUtterance = nil
            self.speakingText = nil
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in
            guard self.currentUtterance === utterance else { return }
            self.currentUtterance = nil
            self.speakingText = nil
        }
    }

    static func extractJapaneseSentence(from text: String) -> String {
        let firstLine = text.components(separatedBy: .newlines).first ?? text
        if let range = firstLine.range(of: "（") {
            let prefix = String(firstLine[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !prefix.isEmpty { return prefix }
        }
        if let range = firstLine.range(of: "(") {
            let prefix = String(firstLine[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !prefix.isEmpty { return prefix }
        }
        return firstLine.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct TextbookView: View {
    @ObservedObject var store: LearningStore
    @State private var lockedLessonToast: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: HomeVisualStyle.sectionSpacing) {
                if let textbook = store.textbook {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("课程目录 · \(textbook.title)")
                                .font(.headline)
                                .foregroundStyle(HomeVisualStyle.ink)
                                .accessibilityAddTraits(.isHeader)
                            Spacer()
                            Text("已完成 \(store.textbookCompletedLessonCount(for: textbook))/\(textbook.lessons.count) 课")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(HomeVisualStyle.secondaryInk)
                        }

                        if let toast = lockedLessonToast {
                            HStack(spacing: 8) {
                                Image(systemName: "lock.fill")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.orange)
                                Text(toast)
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(HomeVisualStyle.ink)
                                Spacer()
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color.orange.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }

                        if textbook.lessons.isEmpty {
                            Text("教材暂无课程。")
                                .font(.subheadline)
                                .foregroundStyle(HomeVisualStyle.secondaryInk)
                                .homeCardStyle()
                        } else {
                            ForEach(textbook.lessons, id: \.id) { lesson in
                                let unlocked = store.isLessonUnlocked(lesson.id, in: textbook)
                                let progress = store.lessonProgressPercent(for: lesson.id, in: textbook)
                                let isCurrent = store.activeCurrentLesson()?.id == lesson.id
                                let questionCount = LearningStore.orderedQuestions(for: lesson.id, in: textbook).count

                                if unlocked {
                                    NavigationLink {
                                        LessonGrammarDetailView(
                                            store: store,
                                            lesson: lesson,
                                            questions: LearningStore.orderedQuestions(for: lesson.id, in: textbook),
                                            textbookID: textbook.id
                                        )
                                    } label: {
                                        lessonRowContent(
                                            lesson: lesson,
                                            unlocked: true,
                                            progress: progress,
                                            isCurrent: isCurrent,
                                            questionCount: questionCount
                                        )
                                    }
                                    .buttonStyle(.plain)
                                } else {
                                    Button {
                                        lockedLessonToast = "第 \(lesson.id) 课尚未解锁，请先完成上一课练习。"
                                    } label: {
                                        lessonRowContent(
                                            lesson: lesson,
                                            unlocked: false,
                                            progress: progress,
                                            isCurrent: false,
                                            questionCount: questionCount
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        if store.textbookError == nil {
                            SwiftUI.ProgressView()
                                .tint(HomeVisualStyle.accent)
                        }
                        Text(store.textbookError ?? "正在加载内置教材…")
                            .font(.subheadline)
                            .foregroundStyle(store.textbookError == nil ? HomeVisualStyle.secondaryInk : HomeVisualStyle.ink)
                        Button {
                            Task { await store.loadStudyState() }
                        } label: {
                            Text("重新加载")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(HomeVisualStyle.accentInk)
                        }
                        .buttonStyle(.bordered)
                        .tint(HomeVisualStyle.accent)
                    }
                    .homeCardStyle()
                }
            }
            .padding(HomeVisualStyle.screenPadding)
        }
        .homeScreenChrome()
        .navigationTitle("课程")
    }

    private func lessonRowContent(
        lesson: TextbookLesson,
        unlocked: Bool,
        progress: Int,
        isCurrent: Bool,
        questionCount: Int
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                Text(String(format: "%02d", lesson.id))
                    .font(.caption.weight(.bold))
                    .foregroundStyle(unlocked ? HomeVisualStyle.accentInk : HomeVisualStyle.secondaryInk)
                    .frame(width: 42, height: 42)
                    .background(unlocked ? HomeVisualStyle.mint : HomeVisualStyle.canvas)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        Text("第 \(lesson.id) 课 · \(lesson.title)")
                            .font(.headline)
                            .foregroundStyle(unlocked ? HomeVisualStyle.ink : HomeVisualStyle.secondaryInk)
                            .multilineTextAlignment(.leading)
                        if isCurrent {
                            Text("当前")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(HomeVisualStyle.card)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(HomeVisualStyle.accent)
                                .clipShape(Capsule())
                        }
                    }
                    Text(lesson.goal)
                        .font(.subheadline)
                        .foregroundStyle(HomeVisualStyle.secondaryInk)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                    HStack(spacing: 10) {
                        Text("\(lesson.grammar.count) 个语法点")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(unlocked ? HomeVisualStyle.accentInk : HomeVisualStyle.secondaryInk)
                        Text("·")
                            .font(.caption)
                            .foregroundStyle(HomeVisualStyle.secondaryInk)
                        Text("\(questionCount) 道练习题")
                            .font(.caption)
                            .foregroundStyle(HomeVisualStyle.secondaryInk)
                    }
                }
                Spacer(minLength: 8)
                if unlocked {
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("\(progress)%")
                            .font(.caption.weight(.bold).monospacedDigit())
                            .foregroundStyle(progress >= 100 ? HomeVisualStyle.accent : HomeVisualStyle.secondaryInk)
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(HomeVisualStyle.secondaryInk)
                            .accessibilityHidden(true)
                    }
                } else {
                    Label("待解锁", systemImage: "lock.fill")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(HomeVisualStyle.secondaryInk)
                }
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(HomeVisualStyle.accent.opacity(0.12))
                        .frame(height: 5)
                    Capsule()
                        .fill(unlocked ? HomeVisualStyle.accent : HomeVisualStyle.secondaryInk.opacity(0.3))
                        .frame(width: geo.size.width * CGFloat(min(max(progress, 0), 100)) / 100.0, height: 5)
                }
            }
            .frame(height: 5)
        }
        .homeCardStyle(
            borderColor: isCurrent
                ? HomeVisualStyle.accent.opacity(0.45)
                : HomeVisualStyle.accent.opacity(unlocked ? 0.18 : 0.10)
        )
        .opacity(unlocked ? 1.0 : 0.72)
    }
}

struct LessonGrammarDetailView: View {
    @ObservedObject var store: LearningStore
    @ObservedObject private var speechPlayer = JapaneseSpeechPlayer.shared
    let lesson: TextbookLesson
    let questions: [TextbookQuestion]
    let textbookID: String?
    @State private var carouselIndex = 0

    init(store: LearningStore, lesson: TextbookLesson, questions: [TextbookQuestion], textbookID: String? = nil) {
        self.store = store
        self.lesson = lesson
        self.questions = questions
        self.textbookID = textbookID
    }

    init(store: LearningStore, lesson: TextbookLesson, textbook: Textbook? = nil) {
        self.store = store
        self.lesson = lesson
        if let textbook = textbook ?? store.textbook {
            self.questions = LearningStore.orderedQuestions(for: lesson.id, in: textbook)
            self.textbookID = textbook.id
        } else {
            self.questions = []
            self.textbookID = nil
        }
    }

    init(store: LearningStore, textbook: Textbook, lesson: TextbookLesson) {
        self.init(store: store, lesson: lesson, textbook: textbook)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: HomeVisualStyle.sectionSpacing) {
                // LessonHeader card matching Web
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text(String(format: "LESSON %02d", lesson.id))
                            .font(.caption.weight(.bold))
                            .tracking(0.8)
                            .foregroundStyle(HomeVisualStyle.accentInk)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(HomeVisualStyle.mint)
                            .clipShape(Capsule())
                        Spacer()
                        Text("\(lesson.grammar.count) 个句型 · \(questions.count) 题")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(HomeVisualStyle.secondaryInk)
                    }
                    Text("第 \(lesson.id) 课 · \(lesson.title)")
                        .font(.title3.bold())
                        .foregroundStyle(HomeVisualStyle.ink)
                        .accessibilityAddTraits(.isHeader)
                    Text(lesson.goal)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(HomeVisualStyle.ink)
                    if let description = lesson.description, !description.isEmpty {
                        Text(description)
                            .font(.footnote)
                            .foregroundStyle(HomeVisualStyle.secondaryInk)
                    }
                    NavigationLink {
                        LessonView(store: store, lesson: lesson, questions: questions)
                    } label: {
                        Text("开始整课练习")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(HomeVisualStyle.card)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(HomeVisualStyle.accent)
                }
                .homeCardStyle()

                // GrammarCarousel matching Web's GrammarCarousel
                if !lesson.grammar.isEmpty {
                    let safeIndex = min(max(carouselIndex, 0), lesson.grammar.count - 1)
                    let point = lesson.grammar[safeIndex]

                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Text("核心句型卡片 \(safeIndex + 1) / \(lesson.grammar.count)")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(HomeVisualStyle.accentInk)
                            Spacer()
                            HStack(spacing: 5) {
                                ForEach(0..<lesson.grammar.count, id: \.self) { idx in
                                    Circle()
                                        .fill(idx == safeIndex ? HomeVisualStyle.accent : HomeVisualStyle.accent.opacity(0.22))
                                        .frame(width: 7, height: 7)
                                }
                            }
                        }

                        Text(point.pattern)
                            .font(.title3.bold())
                            .foregroundStyle(HomeVisualStyle.accentInk)
                            .accessibilityAddTraits(.isHeader)

                        Divider()
                            .overlay(HomeVisualStyle.accent.opacity(0.14))

                        grammarRow("含义", point.meaning, emphasized: true)
                        grammarRow("接续", point.connection)
                        grammarRow("说明", point.explanation)
                        exampleRow(point.example, audioHint: point.audio)

                        if let responses = point.responses, !responses.isEmpty {
                            grammarRow("常见回应", responses.joined(separator: "\n"))
                        }
                        if let pitfalls = point.pitfalls, !pitfalls.isEmpty {
                            grammarRow("易错点", pitfalls.joined(separator: "\n"))
                        }

                        HStack(spacing: 10) {
                            Button {
                                if safeIndex > 0 {
                                    carouselIndex = safeIndex - 1
                                }
                            } label: {
                                Text("← 上一语法")
                                    .font(.footnote.weight(.semibold))
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .tint(HomeVisualStyle.accent)
                            .disabled(safeIndex == 0)

                            if safeIndex + 1 < lesson.grammar.count {
                                Button {
                                    carouselIndex = safeIndex + 1
                                } label: {
                                    Text("下一语法 →")
                                        .font(.footnote.weight(.semibold))
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(HomeVisualStyle.accent)
                            } else {
                                NavigationLink {
                                    LessonView(store: store, lesson: lesson, questions: questions)
                                } label: {
                                    Text("去练习 →")
                                        .font(.footnote.weight(.semibold))
                                        .foregroundStyle(HomeVisualStyle.card)
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(HomeVisualStyle.accent)
                            }
                        }
                    }
                    .homeCardStyle(borderColor: HomeVisualStyle.accent.opacity(0.32))
                }
            }
            .padding(HomeVisualStyle.screenPadding)
        }
        .homeScreenChrome()
        .navigationTitle("第 \(lesson.id) 课")
        .onDisappear {
            speechPlayer.stop()
        }
    }

    private func exampleRow(_ example: String, audioHint: String?) -> some View {
        let isSpeaking = (speechPlayer.speakingText == example)
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("例句")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(HomeVisualStyle.secondaryInk)
                Spacer()
                Button {
                    speechPlayer.speak(example, textbookID: textbookID)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: isSpeaking ? "speaker.wave.3.fill" : "speaker.wave.2")
                            .font(.caption.weight(.semibold))
                        Text(isSpeaking ? "停止朗读" : "朗读例句")
                            .font(.caption.weight(.semibold))
                    }
                    .foregroundStyle(HomeVisualStyle.accentInk)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(HomeVisualStyle.card)
                    .clipShape(Capsule())
                    .overlay(
                        Capsule()
                            .stroke(HomeVisualStyle.accent.opacity(0.28), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
            Text(example)
                .font(.body.weight(.medium))
                .foregroundStyle(HomeVisualStyle.ink)
                .textSelection(.enabled)
            if let audioHint, !audioHint.isEmpty {
                Text("发音提示：\(audioHint)")
                    .font(.caption)
                    .foregroundStyle(HomeVisualStyle.secondaryInk)
            }
        }
        .padding(12)
        .background(HomeVisualStyle.mint)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func grammarRow(_ title: String, _ value: String, emphasized: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(HomeVisualStyle.secondaryInk)
            Text(value)
                .font(.body)
                .fontWeight(emphasized ? .semibold : .regular)
                .foregroundStyle(emphasized ? HomeVisualStyle.accentInk : HomeVisualStyle.ink)
                .textSelection(.enabled)
        }
        .padding(.vertical, 2)
    }
}

private struct MistakesEmptyState: View {
    let title: String
    let symbol: String
    let detail: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(HomeVisualStyle.accent)
            Text(title)
                .font(.headline)
                .foregroundStyle(HomeVisualStyle.ink)
            Text(detail)
                .font(.subheadline)
                .foregroundStyle(HomeVisualStyle.secondaryInk)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .padding(.horizontal, HomeVisualStyle.cardPadding)
        .background(HomeVisualStyle.card)
        .clipShape(RoundedRectangle(cornerRadius: HomeVisualStyle.cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: HomeVisualStyle.cornerRadius, style: .continuous)
                .stroke(HomeVisualStyle.accent.opacity(0.18), lineWidth: 1)
        )
    }
}

struct MistakesPracticeView: View {
    @ObservedObject var store: LearningStore
    let questions: [TextbookQuestion]

    var body: some View {
        Group {
            if let lesson = store.textbook?.lessons.first(where: { $0.id == questions.first?.lessonId }) ?? store.textbook?.lessons.first {
                LessonView(store: store, lesson: lesson, questions: questions, mode: "mistakes")
            } else {
                ScrollView {
                    MistakesEmptyState(title: "错题课程不可用", symbol: "exclamationmark.triangle", detail: "请刷新课程后重试。")
                        .padding(HomeVisualStyle.screenPadding)
                }
                .homeScreenChrome()
            }
        }
    }
}

struct MistakesView: View {
    @ObservedObject var store: LearningStore
    @AppStorage("nihongo.kana.enabled") private var showKana = true

    private var mistakeQuestions: [TextbookQuestion]? {
        guard let textbook = store.textbook else { return nil }
        if textbook.isBuiltin {
            guard store.studyState != nil else { return nil }
        }
        return store.activeMistakeQuestions()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: HomeVisualStyle.sectionSpacing) {
                HStack {
                    Text(store.textbook?.isBuiltin == false ? "当前显示所选自定义教材的错题记录。" : "当前显示账号已同步的错题本记录。")
                        .font(.footnote)
                        .foregroundStyle(HomeVisualStyle.secondaryInk)
                    Spacer()
                }
                .padding(.horizontal, 4)

                if let questions = mistakeQuestions {
                    if questions.isEmpty {
                        MistakesEmptyState(title: "暂时没有错题", symbol: "checkmark.circle", detail: "当前教材暂无待攻克的错题。")
                    } else {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("共 \(questions.count) 道错题")
                                    .font(.headline)
                                    .foregroundStyle(HomeVisualStyle.ink)
                                    .accessibilityAddTraits(.isHeader)
                                Spacer()
                                if let textbook = store.textbook {
                                    Text(textbook.title)
                                        .font(.caption)
                                        .foregroundStyle(HomeVisualStyle.secondaryInk)
                                }
                            }

                            NavigationLink {
                                MistakesPracticeView(store: store, questions: questions)
                            } label: {
                                Label("开始全部错题练习", systemImage: "arrow.counterclockwise")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(HomeVisualStyle.card)
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(HomeVisualStyle.accent)
                            .accessibilityIdentifier("mistakesStartPractice")

                            ForEach(questions, id: \.id) { question in
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Text("第 \(question.lessonId) 课 · \(questionTypeLabel(question.type))")
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(HomeVisualStyle.accentInk)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 3)
                                            .background(HomeVisualStyle.mint)
                                            .clipShape(Capsule())
                                        Spacer()
                                    }
                                    Text(question.prompt)
                                        .font(.headline)
                                        .foregroundStyle(HomeVisualStyle.ink)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text("标准答案：\(question.answer)")
                                            .font(.subheadline.weight(.medium))
                                            .foregroundStyle(HomeVisualStyle.accentInk)
                                        if showKana, let kanaReading = JapaneseKanaHelper.readingHint(for: question.answer) {
                                            Text("读音参考：\(kanaReading)")
                                                .font(.caption)
                                                .foregroundStyle(HomeVisualStyle.secondaryInk)
                                        }
                                    }
                                    if !question.hint.isEmpty {
                                        Text("提示：\(question.hint)")
                                            .font(.caption)
                                            .foregroundStyle(HomeVisualStyle.secondaryInk)
                                    }
                                }
                                .homeCardStyle()
                            }
                        }
                    }
                } else if store.syncState == .loading {
                    HStack(spacing: 10) {
                        SwiftUI.ProgressView()
                            .tint(HomeVisualStyle.accent)
                        Text("正在读取错题…")
                            .font(.subheadline)
                            .foregroundStyle(HomeVisualStyle.secondaryInk)
                    }
                    .homeCardStyle()
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        MistakesEmptyState(
                            title: "错题暂不可用",
                            symbol: "exclamationmark.triangle",
                            detail: "当前账号尚未提供可用的错题快照，请刷新学习数据后重试。"
                        )
                        Button {
                            Task { await store.loadStudyState() }
                        } label: {
                            Text("刷新")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(HomeVisualStyle.accentInk)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .tint(HomeVisualStyle.accent)
                    }
                }
            }
            .padding(HomeVisualStyle.screenPadding)
        }
        .homeScreenChrome()
        .navigationTitle("错题本")
        .task {
            if store.studyState == nil { await store.loadStudyState() }
        }
    }

    private func questionTypeLabel(_ type: String) -> String {
        switch type {
        case "choice": return "选择题"
        case "fill": return "填空题"
        case "order": return "语序重组"
        case "translate": return "整句翻译"
        case "mistake": return "改错题"
        default: return type
        }
    }
}

enum JapaneseKanaHelper {
    /// Generates a katakana/hiragana phonetic reading using CFStringTransform when kanji characters are present.
    static func readingHint(for sentence: String) -> String? {
        let containsKanji = sentence.unicodeScalars.contains { scalar in
            (0x4E00...0x9FFF).contains(scalar.value) || (0x3400...0x4DBF).contains(scalar.value)
        }
        guard containsKanji else { return nil }
        let mutable = NSMutableString(string: sentence) as CFMutableString
        guard CFStringTransform(mutable, nil, kCFStringTransformToLatin, false),
              CFStringTransform(mutable, nil, kCFStringTransformLatinHiragana, false) else {
            return nil
        }
        let transformed = (mutable as String).trimmingCharacters(in: .whitespacesAndNewlines)
        return transformed.isEmpty || transformed == sentence ? nil : transformed
    }
}
