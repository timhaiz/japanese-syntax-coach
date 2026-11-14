import SwiftUI
import UniformTypeIdentifiers

struct HomeView: View {
    @ObservedObject var store: LearningStore
    var membership: MembershipStatus = .free
    var onSelectTab: ((Int) -> Void)? = nil

    init(
        store: LearningStore,
        membership: MembershipStatus = .free,
        onSelectTab: ((Int) -> Void)? = nil
    ) {
        self.store = store
        self.membership = membership
        self.onSelectTab = onSelectTab
    }

    var body: some View {
        let model = HomeLearningPath.make(
            textbook: store.textbook,
            textbookError: store.textbookError,
            studyState: store.studyState,
            syncState: store.syncState,
            pendingCount: store.pendingCount,
            isShowingCachedStudyState: store.isShowingCachedStudyState
        )
        ScrollView {
            VStack(alignment: .leading, spacing: HomeVisualStyle.sectionSpacing) {
                appHeader(model)
                content(model)
            }
            .padding(HomeVisualStyle.screenPadding)
        }
        .background(HomeVisualStyle.canvas.ignoresSafeArea())
        .foregroundStyle(HomeVisualStyle.ink)
        .tint(HomeVisualStyle.accent)
        .toolbarColorScheme(.light, for: .navigationBar)
        .navigationTitle("日句")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await Self.refresh(store) }
    }

    private func appHeader(_ model: HomeScreenModel) -> some View {
        let currentLessonId: Int = {
            if case .ready(let preview) = model.content {
                return preview.lessonID
            }
            return store.activeCurrentLesson()?.id ?? 1
        }()
        let initial = store.userEmail?.trimmingCharacters(in: .whitespacesAndNewlines).first.map { String($0).uppercased() } ?? "N"

        return HStack(spacing: 10) {
            ZStack(alignment: .topTrailing) {
                Text("あ")
                    .font(.system(size: 19, weight: .heavy))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(
                        LinearGradient(
                            colors: [
                                Color(red: 33.0 / 255, green: 107.0 / 255, blue: 79.0 / 255),
                                Color(red: 20.0 / 255, green: 69.0 / 255, blue: 51.0 / 255)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                    )
                Circle()
                    .fill(Color(red: 224.0 / 255, green: 77.0 / 255, blue: 59.0 / 255))
                    .frame(width: 8, height: 8)
                    .offset(x: -5, y: 5)
            }
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text("句型通")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(HomeVisualStyle.ink)
                Text("主动输出 · 日语句型训练")
                    .font(.caption2)
                    .foregroundStyle(HomeVisualStyle.secondaryInk)
            }

            Spacer(minLength: 4)

            Text("第 \(currentLessonId) 课")
                .font(.caption.weight(.semibold))
                .foregroundStyle(HomeVisualStyle.accentInk)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(HomeVisualStyle.mint, in: Capsule())

            headerMembershipBadge

            Button {
                onSelectTab?(3)
            } label: {
                Text(initial)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(HomeVisualStyle.accentInk)
                    .frame(width: 34, height: 34)
                    .background(HomeVisualStyle.mint, in: Circle())
                    .overlay(Circle().stroke(HomeVisualStyle.accent.opacity(0.25), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("打开个人中心")
            .accessibilityIdentifier("homeProfileButton")
        }
    }

    private var headerMembershipBadge: some View {
        let isMember = membership == .member
        return HStack(spacing: 4) {
            Image(systemName: isMember ? "crown.fill" : "sparkles")
                .font(.caption2)
            Text(isMember ? "会员" : "免费版")
                .font(.caption2.weight(.semibold))
        }
        .foregroundStyle(isMember ? Color(red: 146.0 / 255, green: 92.0 / 255, blue: 18.0 / 255) : HomeVisualStyle.secondaryInk)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            isMember
                ? Color(red: 254.0 / 255, green: 243.0 / 255, blue: 199.0 / 255)
                : HomeVisualStyle.card,
            in: Capsule()
        )
        .overlay(
            Capsule().stroke(
                isMember
                    ? Color(red: 245.0 / 255, green: 158.0 / 255, blue: 11.0 / 255).opacity(0.4)
                    : HomeVisualStyle.border,
                lineWidth: 1
            )
        )
    }

    @ViewBuilder
    private func content(_ model: HomeScreenModel) -> some View {
        if let textbook = store.textbook {
            TextbookSwitcherCard(
                textbook: textbook,
                progressPercent: store.textbookProgressPercent(for: textbook),
                store: store
            )
        }

        NavigationLink {
            FreeTextbookLibraryView(store: store)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "books.vertical.fill")
                    .foregroundStyle(HomeVisualStyle.accentInk)
                    .frame(width: 36, height: 36)
                    .background(HomeVisualStyle.mint, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text("免费教材库")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(HomeVisualStyle.ink)
                    Text("三本免费教材，下载后即可学习")
                        .font(.caption)
                        .foregroundStyle(HomeVisualStyle.secondaryInk)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(HomeVisualStyle.secondaryInk)
            }
            .padding(14)
            .background(HomeVisualStyle.card, in: RoundedRectangle(cornerRadius: HomeVisualStyle.cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: HomeVisualStyle.cornerRadius, style: .continuous)
                    .stroke(HomeVisualStyle.accent.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("homeFreeTextbookLibrary")
        .accessibilityLabel("打开免费教材库")

        if let summary = store.lessonSummary, let textbook = store.textbook {
            lessonSummaryCard(summary, textbook: textbook)
        }

        switch model.content {
        case .loading:
            SwiftUI.ProgressView()
                .tint(HomeVisualStyle.accent)
            Text("正在加载内置教材…")
                .font(.subheadline)
                .foregroundStyle(HomeVisualStyle.secondaryInk)
        case .failed(let message):
            Text(message)
                .font(.subheadline)
                .foregroundStyle(HomeVisualStyle.ink)
            Button("重新加载") {
                Task { await store.loadStudyState() }
            }
            .font(.subheadline.weight(.semibold))
            .buttonStyle(.bordered)
            .tint(HomeVisualStyle.accent)
            .foregroundStyle(HomeVisualStyle.accentInk)
            .accessibilityIdentifier("homeTextbookReload")
            .accessibilityLabel("重新加载教材")
        case .emptyLessons:
            Text("教材暂无课程。")
                .font(.subheadline)
                .foregroundStyle(HomeVisualStyle.secondaryInk)
        case .ready(let preview):
            if let textbook = store.textbook,
               let lesson = store.activeCurrentLesson() ?? HomeLearningPath.currentLesson(in: textbook, studyState: store.studyState) {
                learningHero(preview, lesson: lesson, textbook: textbook)
                quickPracticeButtons(textbook: textbook, currentLesson: lesson)
                progressSummary(preview, lesson: lesson, textbook: textbook)
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("本课路径")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(HomeVisualStyle.accent)
                        Text("先学句型，再开始练习")
                            .font(.title3.weight(.bold))
                            .accessibilityAddTraits(.isHeader)
                    }
                    Spacer(minLength: 8)
                    NavigationLink {
                        TextbookView(store: store)
                    } label: {
                        Text("课程地图 →").font(.caption.weight(.semibold))
                            .frame(minHeight: 44)
                    }
                }
                lessonCard(preview, lesson: lesson, textbook: textbook)
            }
        }
    }

    @ViewBuilder
    private func lessonSummaryCard(_ summary: LessonCompletionSummary, textbook: Textbook) -> some View {
        let nextLesson = textbook.lessons.first(where: { $0.id == summary.lessonId + 1 })
            ?? textbook.lessons.first(where: { $0.id > summary.lessonId })
        let replayQuestions = textbook.questions.filter { summary.mistakeQuestionIds.contains($0.id) }
        let currentLesson = textbook.lessons.first(where: { $0.id == summary.lessonId }) ?? textbook.lessons.first

        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(summary.replayed ? "本课错题已重练" : "第 \(summary.lessonId) 课已完成")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(HomeVisualStyle.accentInk)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(HomeVisualStyle.mint, in: Capsule())
                Spacer()
                Button {
                    store.lessonSummary = nil
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(HomeVisualStyle.secondaryInk)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("关闭本课小结")
            }

            Text(
                summary.mistakeQuestionIds.isEmpty
                    ? "本课 \(summary.total) 题全部掌握，可以进入下一课。"
                    : "本课答对 \(summary.correct) / \(summary.total) 题，薄弱句型已加入错题本。"
            )
            .font(.headline)
            .foregroundStyle(HomeVisualStyle.ink)

            HStack(spacing: 10) {
                if !replayQuestions.isEmpty, let currentLesson {
                    NavigationLink {
                        LessonView(
                            store: store,
                            lesson: currentLesson,
                            questions: replayQuestions,
                            mode: "lesson_replay"
                        )
                    } label: {
                        Text("重练本课错题（\(replayQuestions.count) 题）")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(HomeVisualStyle.accentInk)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(HomeVisualStyle.accent)
                }

                if let nextLesson {
                    NavigationLink {
                        LessonGrammarDetailView(store: store, textbook: textbook, lesson: nextLesson)
                    } label: {
                        Text("进入第 \(nextLesson.id) 课")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(HomeVisualStyle.card)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(HomeVisualStyle.accent)
                }
            }
        }
        .homeCardStyle(borderColor: HomeVisualStyle.accent.opacity(0.35))
    }

    @ViewBuilder
    private func quickPracticeButtons(textbook: Textbook, currentLesson: TextbookLesson) -> some View {
        let completedCount = store.textbookCompletedLessonCount(for: textbook)
        let mixedQuestions = store.mixedPracticeQuestions(limit: textbook.effectiveQuestionLimit)
        let dueQuestions = store.dueReviewQuestions(limit: textbook.effectiveQuestionLimit)
        let totalDueCount = textbook.isBuiltin ? (store.studyState?.dueQuestionIds.count ?? 0) : 0
        let hasMixed = completedCount > 0 && !mixedQuestions.isEmpty
        let hasDue = totalDueCount > 0 && !dueQuestions.isEmpty

        if hasMixed && hasDue {
            HStack(spacing: 12) {
                NavigationLink {
                    LessonView(
                        store: store,
                        lesson: currentLesson,
                        questions: mixedQuestions,
                        mode: "review"
                    )
                } label: {
                    quickPracticeTile(
                        icon: "shuffle",
                        badgeText: "混练",
                        title: "综合混练",
                        subtitle: "已学 \(completedCount) 课随机抽查",
                        iconColor: HomeVisualStyle.accentInk,
                        iconBg: HomeVisualStyle.mint,
                        cardBg: HomeVisualStyle.card,
                        borderColor: HomeVisualStyle.accent.opacity(0.24)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("homeMixedPracticeButton")

                NavigationLink {
                    LessonView(
                        store: store,
                        lesson: currentLesson,
                        questions: dueQuestions,
                        mode: "review"
                    )
                } label: {
                    quickPracticeTile(
                        icon: "clock.badge.checkmark",
                        badgeText: "\(totalDueCount) 题待复习",
                        title: "今日到期复习",
                        subtitle: "按记忆曲线及时巩固",
                        iconColor: Color(red: 180.0 / 255, green: 83.0 / 255, blue: 9.0 / 255),
                        iconBg: Color(red: 254.0 / 255, green: 243.0 / 255, blue: 199.0 / 255),
                        cardBg: HomeVisualStyle.card,
                        borderColor: Color(red: 245.0 / 255, green: 158.0 / 255, blue: 11.0 / 255).opacity(0.32)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("homeDueReviewButton")
            }
        } else if hasMixed {
            NavigationLink {
                LessonView(
                    store: store,
                    lesson: currentLesson,
                    questions: mixedQuestions,
                    mode: "review"
                )
            } label: {
                quickPracticeWideBanner(
                    icon: "shuffle",
                    title: "综合混练",
                    subtitle: "从已完成的 \(completedCount) 课中随机抽题，检验真实掌握度",
                    badgeText: "去混练",
                    iconColor: HomeVisualStyle.accentInk,
                    iconBg: HomeVisualStyle.mint,
                    borderColor: HomeVisualStyle.accent.opacity(0.24)
                )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("homeMixedPracticeButton")
        } else if hasDue {
            NavigationLink {
                LessonView(
                    store: store,
                    lesson: currentLesson,
                    questions: dueQuestions,
                    mode: "review"
                )
            } label: {
                quickPracticeWideBanner(
                    icon: "clock.badge.checkmark",
                    title: "今日到期复习",
                    subtitle: "共有 \(totalDueCount) 道到期题目，趁遗忘前快速强化",
                    badgeText: "\(totalDueCount) 题",
                    iconColor: Color(red: 180.0 / 255, green: 83.0 / 255, blue: 9.0 / 255),
                    iconBg: Color(red: 254.0 / 255, green: 243.0 / 255, blue: 199.0 / 255),
                    borderColor: Color(red: 245.0 / 255, green: 158.0 / 255, blue: 11.0 / 255).opacity(0.32)
                )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("homeDueReviewButton")
        }
    }

    private func quickPracticeTile(
        icon: String,
        badgeText: String,
        title: String,
        subtitle: String,
        iconColor: Color,
        iconBg: Color,
        cardBg: Color,
        borderColor: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: icon)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(iconColor)
                    .frame(width: 34, height: 34)
                    .background(iconBg, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                Spacer(minLength: 4)
                Text(badgeText)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(iconColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(iconBg, in: Capsule())
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Text(title)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(HomeVisualStyle.ink)
                        .lineLimit(1)
                    Spacer(minLength: 2)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(HomeVisualStyle.secondaryInk)
                }
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(HomeVisualStyle.secondaryInk)
                    .lineLimit(1)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBg, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(borderColor, lineWidth: 1)
        )
    }

    private func quickPracticeWideBanner(
        icon: String,
        title: String,
        subtitle: String,
        badgeText: String,
        iconColor: Color,
        iconBg: Color,
        borderColor: Color
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.headline.weight(.bold))
                .foregroundStyle(iconColor)
                .frame(width: 42, height: 42)
                .background(iconBg, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(HomeVisualStyle.ink)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(HomeVisualStyle.secondaryInk)
                    .lineLimit(1)
            }

            Spacer(minLength: 6)

            HStack(spacing: 4) {
                Text(badgeText)
                    .font(.caption.weight(.bold))
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.bold))
            }
            .foregroundStyle(iconColor)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(iconBg, in: Capsule())
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(HomeVisualStyle.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(borderColor, lineWidth: 1)
        )
    }

    private func lessonProgress(_ lesson: TextbookLesson, textbook: Textbook) -> Int? {
        if textbook.isBuiltin {
            let localDone = store.lessonAnsweredCount(for: lesson.id, in: textbook)
            if store.studyState == nil && localDone == 0 { return nil }
        }
        return store.lessonProgressPercent(for: lesson.id, in: textbook)
    }

    private func learningHero(_ preview: HomePreview, lesson: TextbookLesson, textbook: Textbook) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("\(HomeGreeting.title(for: Date()))，\(store.learnerDisplayName)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(HomeVisualStyle.accent)
            VStack(alignment: .leading, spacing: 3) {
                Text("一课一练，")
                    .foregroundStyle(HomeVisualStyle.ink)
                Text("把句型练成反射。")
                    .foregroundStyle(HomeVisualStyle.accent)
            }
            .accessibilityElement(children: .combine)
            heroAction(lesson, textbook: textbook)
        }
        .font(.system(.title, design: .default).weight(.bold))
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(HomeVisualStyle.cardPadding)
        .background(HomeVisualStyle.card, in: RoundedRectangle(cornerRadius: HomeVisualStyle.cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: HomeVisualStyle.cornerRadius, style: .continuous)
                .stroke(HomeVisualStyle.border, lineWidth: 1)
        )
    }

    private func heroAction(_ lesson: TextbookLesson, textbook: Textbook) -> some View {
        let qCount = LearningStore.orderedQuestions(for: lesson.id, in: textbook).count
        return NavigationLink {
            LessonGrammarDetailView(store: store, textbook: textbook, lesson: lesson)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "book.pages.fill")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(HomeVisualStyle.accentInk)
                    .frame(width: 42, height: 42)
                    .background(.white.opacity(0.9), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text(lesson.grammar.isEmpty ? "开始第 \(lesson.id) 课练习" : "学习第 \(lesson.id) 课句型")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(HomeVisualStyle.ink)
                    Text("\(lesson.title) · \(lesson.grammar.count) 个句型 / \(qCount) 道练习")
                        .font(.caption)
                        .foregroundStyle(HomeVisualStyle.secondaryInk)
                        .lineLimit(1)
                }

                Spacer(minLength: 6)

                Image(systemName: "arrow.up.right")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(HomeVisualStyle.accent, in: Circle())
                    .accessibilityHidden(true)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(HomeVisualStyle.mint.opacity(0.75), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(HomeVisualStyle.accent.opacity(0.28), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("homeHeroStudyPatternButton")
    }

    private func progressRing(_ progress: Int?) -> some View {
        ZStack {
            Circle().stroke(HomeVisualStyle.border, lineWidth: 11)
            Circle().trim(from: 0, to: CGFloat(progress ?? 0) / 100)
                .stroke(HomeVisualStyle.accent, style: StrokeStyle(lineWidth: 11, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 3) {
                Text("本课").font(.caption).foregroundStyle(HomeVisualStyle.secondaryInk)
                Text(progress.map { "\($0)%" } ?? "0%")
                    .font(.title2.weight(.bold)).monospacedDigit()
            }
        }
        .frame(width: 100, height: 100)
        .padding(6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(progress.map { "本课进度 \($0)%" } ?? "本课进度 0%")
    }

    private func progressSummary(_ preview: HomePreview, lesson: TextbookLesson, textbook: Textbook) -> some View {
        let progress = lessonProgress(lesson, textbook: textbook) ?? 0
        let overall = store.textbookProgressPercent(for: textbook)
        return HStack(alignment: .top, spacing: 8) {
            summaryItem("\(progress)%", label: "本课进度")
            summaryItem("第 \(lesson.id) 课", label: "继续学习")
            summaryItem("\(overall)%", label: "整体掌握")
        }
        .padding(.vertical, 18)
        .padding(.horizontal, 8)
        .background(HomeVisualStyle.card, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(HomeVisualStyle.border, lineWidth: 1))
    }

    private func summaryItem(_ value: String, label: String) -> some View {
        VStack(spacing: 6) {
            Text(value).font(.subheadline.weight(.bold)).monospacedDigit()
            Text(label).font(.caption).foregroundStyle(HomeVisualStyle.secondaryInk)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private func lessonCard(_ preview: HomePreview, lesson: TextbookLesson, textbook: Textbook) -> some View {
        let lessonProg = store.lessonProgressPercent(for: lesson.id, in: textbook)
        let qCount = LearningStore.orderedQuestions(for: lesson.id, in: textbook).count
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Text(String(format: "%02d", lesson.id))
                    .font(.title3.weight(.bold)).monospacedDigit()
                    .foregroundStyle(HomeVisualStyle.accent)
                    .frame(minWidth: 48, minHeight: 52)
                    .background(HomeVisualStyle.mint, in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 6) {
                    Text("第 \(lesson.id) 课 · 句型训练")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(HomeVisualStyle.accent)
                    Text(lesson.title)
                        .font(.headline)
                        .foregroundStyle(HomeVisualStyle.ink)
                        .accessibilityAddTraits(.isHeader)
                }
                Spacer(minLength: 4)
            }
            Text(lesson.goal)
                .font(.subheadline)
                .foregroundStyle(HomeVisualStyle.secondaryInk)
            if lesson.grammar.isEmpty {
                Text("本课暂无可预览的句型。")
                    .font(.body)
                    .foregroundStyle(HomeVisualStyle.ink)
                    .accessibilityLabel("第 \(lesson.id) 课句型暂不可预览")
            } else {
                Text(lesson.grammar.map(\.pattern).joined(separator: " · "))
                    .font(.subheadline)
                    .foregroundStyle(HomeVisualStyle.ink)
                    .lineLimit(2)
            }

            SwiftUI.ProgressView(value: Double(lessonProg), total: 100)
                .tint(HomeVisualStyle.accent)

            Text(
                lessonProg > 0
                    ? "已完成 \(lessonProg)% · 继续巩固句型"
                    : "查看本课句型，然后完成 \(qCount) 道练习"
            )
            .font(.caption)
            .foregroundStyle(HomeVisualStyle.secondaryInk)

            if !lesson.grammar.isEmpty {
                NavigationLink {
                    LessonGrammarDetailView(store: store, textbook: textbook, lesson: lesson)
                } label: {
                    Text("查看句型")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(HomeVisualStyle.card)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(HomeVisualStyle.accent)
                .accessibilityIdentifier("homePatternPreview")
                .accessibilityLabel("查看第 \(lesson.id) 课句型")
            }
            practiceLink(lesson, textbook: textbook)
        }
        .foregroundStyle(HomeVisualStyle.ink)
        .padding(HomeVisualStyle.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(HomeVisualStyle.card)
        .clipShape(RoundedRectangle(cornerRadius: HomeVisualStyle.cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: HomeVisualStyle.cornerRadius, style: .continuous)
                .stroke(HomeVisualStyle.accent.opacity(0.18), lineWidth: 1)
        )
    }

    private func practiceLink(_ lesson: TextbookLesson, textbook: Textbook) -> some View {
        NavigationLink {
            LessonView(
                store: store,
                lesson: lesson,
                questions: LearningStore.orderedQuestions(for: lesson.id, in: textbook)
            )
        } label: {
            Text("开始 / 继续本课")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(HomeVisualStyle.accentInk)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .tint(HomeVisualStyle.accent)
        .accessibilityIdentifier("homeLessonPractice")
        .accessibilityLabel("开始或继续第 \(lesson.id) 课练习")
    }

    private func reviewSection(_ reviews: HomeReviewSection, textbook: Textbook) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("到期复习")
                .font(.headline)
                .foregroundStyle(HomeVisualStyle.ink)
                .accessibilityAddTraits(.isHeader)
            if let dueCount = reviews.dueCount {
                Text("待复习 \(dueCount) 题")
                    .font(.subheadline)
                    .foregroundStyle(HomeVisualStyle.secondaryInk)
            }
            if let message = reviews.message {
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(HomeVisualStyle.secondaryInk)
            }
            ForEach(reviews.entries, id: \.lessonID) { entry in
                reviewLink(entry, textbook: textbook)
            }
        }
    }

    private func reviewLink(_ entry: HomeReviewEntry, textbook: Textbook) -> some View {
        let due = Set(entry.questionIDs)
        let questions = textbook.questions.filter { $0.lessonId == entry.lessonID && due.contains($0.id) }
        return Group {
            if let lesson = textbook.lessons.first(where: { $0.id == entry.lessonID }) {
                NavigationLink {
                    LessonView(store: store, lesson: lesson, questions: questions, mode: "review")
                } label: {
                    Text("复习第 \(entry.lessonID) 课")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(HomeVisualStyle.accentInk)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(HomeVisualStyle.accent)
                .accessibilityIdentifier("homeReview-\(entry.lessonID)")
                .accessibilityLabel("复习第 \(entry.lessonID) 课")
            }
        }
    }
}

struct TextbookSwitcherCard: View {
    let textbook: Textbook
    let progressPercent: Int
    @ObservedObject var store: LearningStore

    var body: some View {
        NavigationLink {
            TextbookLibraryView(store: store)
        } label: {
            HStack(spacing: 14) {
                TextbookCoverBadge(textbook: textbook, size: 52)

                VStack(alignment: .leading, spacing: 4) {
                    Text("当前教材")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(HomeVisualStyle.accentInk)
                    Text(textbook.title)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(HomeVisualStyle.ink)
                        .lineLimit(1)
                    Text("学习进度 \(progressPercent)%")
                        .font(.caption)
                        .foregroundStyle(HomeVisualStyle.secondaryInk)
                }

                Spacer(minLength: 8)

                Text("教材库 →")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(HomeVisualStyle.accentInk)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(HomeVisualStyle.mint, in: Capsule())
            }
            .padding(14)
            .background(HomeVisualStyle.card, in: RoundedRectangle(cornerRadius: HomeVisualStyle.cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: HomeVisualStyle.cornerRadius, style: .continuous)
                    .stroke(HomeVisualStyle.accent.opacity(0.22), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("homeTextbookSwitcher")
        .accessibilityLabel("当前教材：\(textbook.title)，学习进度 \(progressPercent)%，点击打开教材库")
    }
}

struct TextbookCoverBadge: View {
    let textbook: Textbook
    var size: CGFloat = 56

    private var coverAssetName: String {
        if textbook.cover?.contains("lower") == true || textbook.title.contains("下册") || textbook.title.contains("下") {
            return "TextbookCoverBeginnerLower"
        }
        return "TextbookCoverBeginner"
    }

    var body: some View {
        Image(coverAssetName)
            .resizable()
            .scaledToFill()
            .frame(width: size, height: size * 1.32)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(HomeVisualStyle.border, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.08), radius: 3, x: 0, y: 1)
            .accessibilityHidden(true)
    }
}

struct TextbookLibraryView: View {
    @ObservedObject var store: LearningStore
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var isImportingFile = false
    @State private var importMessage: String?
    @State private var importIsError = false

    private var filteredTextbooks: [Textbook] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return store.textbooks }
        return store.textbooks.filter { item in
            let fields = [item.title, item.displaySubtitle, item.displayLevel] + item.displayTags
            return fields.contains { $0.lowercased().contains(trimmed) }
        }
    }

    private var activeLearningCount: Int {
        store.textbooks.filter { item in
            item.id == store.selectedTextbookId || store.textbookProgressPercent(for: item) > 0
        }.count
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(HomeVisualStyle.secondaryInk)
                    TextField("搜索教材名称、级别或标签", text: $query)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("textbookSearchField")
                    if !query.isEmpty {
                        Button {
                            query = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(HomeVisualStyle.secondaryInk)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("清空搜索")
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .background(HomeVisualStyle.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(HomeVisualStyle.border, lineWidth: 1)
                )

                HStack {
                    Text("当前 \(activeLearningCount) 本教材正在学习")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(HomeVisualStyle.secondaryInk)
                    Spacer()
                    Text("共 \(store.textbooks.count) 本")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(HomeVisualStyle.accentInk)
                }

                if let importMessage {
                    Text(importMessage)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(importIsError ? Color.red : HomeVisualStyle.accentInk)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            importIsError ? Color.red.opacity(0.08) : HomeVisualStyle.mint,
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                        )
                        .accessibilityIdentifier("textbookImportStatus")
                }

                if filteredTextbooks.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("没有找到匹配的教材")
                            .font(.headline)
                            .foregroundStyle(HomeVisualStyle.ink)
                        Text("请尝试其他关键词，或点击右上角菜单导入自定义教材 JSON。")
                            .font(.subheadline)
                            .foregroundStyle(HomeVisualStyle.secondaryInk)
                    }
                    .homeCardStyle()
                } else {
                    ForEach(filteredTextbooks, id: \.id) { item in
                        textbookCard(item)
                    }
                }
            }
            .padding(HomeVisualStyle.screenPadding)
        }
        .homeScreenChrome()
        .navigationTitle("教材库")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        isImportingFile = true
                    } label: {
                        Label("导入教材 JSON", systemImage: "square.and.arrow.down")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(HomeVisualStyle.ink)
                }
                .accessibilityLabel("更多教材操作")
                .accessibilityIdentifier("textbookLibraryMoreMenu")
            }
        }
        .fileImporter(
            isPresented: $isImportingFile,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            handleFileImport(result)
        }
    }

    private func textbookCard(_ item: Textbook) -> some View {
        let selected = item.id == store.selectedTextbookId
        let progress = store.textbookProgressPercent(for: item)
        let completedLessons = store.textbookCompletedLessonCount(for: item)

        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                TextbookCoverBadge(textbook: item, size: 58)

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Text(item.displayLevel)
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(HomeVisualStyle.accentInk)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(HomeVisualStyle.mint, in: Capsule())

                        Text(item.isBuiltin ? "内置" : "自定义导入")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(HomeVisualStyle.secondaryInk)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(HomeVisualStyle.canvas, in: Capsule())
                    }

                    Text(item.title)
                        .font(.headline)
                        .foregroundStyle(HomeVisualStyle.ink)

                    Text(item.displaySubtitle)
                        .font(.caption)
                        .foregroundStyle(HomeVisualStyle.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 10) {
                        Text("\(item.lessons.count) 课")
                        Text("·")
                        Text("\(item.questions.count) 题")
                        Text("·")
                        Text("已完成 \(completedLessons) 课")
                    }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(HomeVisualStyle.secondaryInk)
                }
            }

            SwiftUI.ProgressView(value: Double(progress), total: 100)
                .tint(HomeVisualStyle.accent)

            HStack {
                Text("学习进度 \(progress)%")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(HomeVisualStyle.secondaryInk)

                Spacer()

                Button {
                    store.selectTextbook(item.id)
                    dismiss()
                } label: {
                    Text(selected ? "学习中" : "开始学习")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(selected ? .white : HomeVisualStyle.accentInk)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(
                            selected ? HomeVisualStyle.accent : HomeVisualStyle.mint,
                            in: Capsule()
                        )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("selectTextbook-\(item.id)")
            }
        }
        .homeCardStyle(
            borderColor: selected ? HomeVisualStyle.accent : HomeVisualStyle.accent.opacity(0.18)
        )
    }

    private func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .failure:
            importIsError = true
            importMessage = "未选择有效的教材文件。"
        case .success(let urls):
            guard let url = urls.first else { return }
            let accessed = url.startAccessingSecurityScopedResource()
            defer {
                if accessed { url.stopAccessingSecurityScopedResource() }
            }
            do {
                let rawData = try Data(contentsOf: url)
                guard let rawText = String(data: rawData, encoding: .utf8) else {
                    throw TextbookImportError.invalidJSON
                }
                let imported = try store.importTextbook(from: rawText)
                importIsError = false
                importMessage = "已导入《\(imported.title)》，共 \(imported.lessons.count) 课 \(imported.questions.count) 题。"
            } catch {
                importIsError = true
                importMessage = error.localizedDescription
            }
        }
    }
}

private struct HomeSyncStatusRow: View {
    @ObservedObject var store: LearningStore

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(store.syncState.title)
                .font(.subheadline)
                .foregroundStyle(HomeVisualStyle.ink)
            Text(store.pendingCountIsKnown ? "待同步答案：\(store.pendingCount)" : "待同步答案：数量未知（队列无法读取）")
                .font(.caption)
                .foregroundStyle(HomeVisualStyle.secondaryInk)
                .accessibilityIdentifier("pendingAnswerCount")
            if store.hasPossibleLegacyQueue {
                Text("本机可能有旧版待同步数据，尚未纳入当前账号或上述数量，请勿清除应用数据。")
                    .font(.caption)
                    .accessibilityIdentifier("legacyQueueNotice")
            }
            if store.isShowingCachedStudyState {
                Text("显示本机缓存进度，可能不是最新状态。")
                    .font(.caption)
                    .foregroundStyle(HomeVisualStyle.secondaryInk)
            }
            if store.syncState == .loading || store.syncState == .syncing {
                SwiftUI.ProgressView()
                    .tint(HomeVisualStyle.accent)
            } else {
                Button {
                    Task { await HomeView.refresh(store) }
                } label: {
                    Text("刷新 / 重试同步")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(HomeVisualStyle.accentInk)
                }
                .buttonStyle(.bordered)
                .tint(HomeVisualStyle.accent)
                .accessibilityIdentifier("homeSyncRetry")
                .accessibilityLabel("刷新或重试同步")
            }
        }
        .foregroundStyle(HomeVisualStyle.ink)
        .padding(HomeVisualStyle.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(HomeVisualStyle.card)
        .clipShape(RoundedRectangle(cornerRadius: HomeVisualStyle.cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: HomeVisualStyle.cornerRadius, style: .continuous)
                .stroke(HomeVisualStyle.accent.opacity(0.18), lineWidth: 1)
        )
    }
}

extension HomeView {
    /// Shared by pull-to-refresh and the home sync button.
    /// An empty queue must not follow a failed study-state read: `retryPending()` would
    /// rewrite that error as synced. Queued answers still get retried.
    static func refresh(_ store: LearningStore) async {
        await store.loadStudyState()
        guard store.pendingCount > 0 else { return }
        await store.retryPending()
    }
}

struct LearningSyncStatusView: View {
    @ObservedObject var store: LearningStore

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(store.syncState.title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(HomeVisualStyle.ink)
            Text(store.pendingCountIsKnown ? "待同步答案：\(store.pendingCount)" : "待同步答案：数量未知（队列无法读取）")
                .font(.caption)
                .foregroundStyle(HomeVisualStyle.secondaryInk)
                .accessibilityIdentifier("pendingAnswerCount")
            if store.hasPossibleLegacyQueue {
                Text("本机可能有旧版待同步数据，尚未纳入当前账号或上述数量，请勿清除应用数据。")
                    .font(.caption)
                    .foregroundStyle(HomeVisualStyle.ink)
                    .accessibilityIdentifier("legacyQueueNotice")
            }
            if store.isShowingCachedStudyState {
                Text("显示本机缓存进度，可能不是最新状态。")
                    .font(.caption)
                    .foregroundStyle(HomeVisualStyle.secondaryInk)
            }
            if store.syncState == .loading || store.syncState == .syncing {
                SwiftUI.ProgressView()
                    .tint(HomeVisualStyle.accent)
            } else {
                Button {
                    Task { await HomeView.refresh(store) }
                } label: {
                    Text("刷新 / 重试同步")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(HomeVisualStyle.accentInk)
                }
                .buttonStyle(.bordered)
                .tint(HomeVisualStyle.accent)
                .accessibilityIdentifier("homeSyncRetry")
                .accessibilityLabel("刷新或重试同步")
            }
        }
        .homeCardStyle()
    }
}
