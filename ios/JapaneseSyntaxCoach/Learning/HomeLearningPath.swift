import Foundation

struct HomeReviewEntry: Equatable {
    let lessonID: Int
    let title: String
    let questionIDs: [String]
}

struct HomePreview: Equatable {
    let lessonID: Int
    let title: String
    let goal: String
    let patternLabels: [String]
    let grammarCount: Int
    let isGrammarUnavailable: Bool
    let isConfirmedProgress: Bool
}

enum HomeContent: Equatable {
    case loading
    case failed(String)
    case emptyLessons
    case ready(HomePreview)
}

struct HomeReviewSection: Equatable {
    let isVisible: Bool
    let dueCount: Int?
    let entries: [HomeReviewEntry]
    let message: String?
}

struct HomeScreenModel: Equatable {
    let content: HomeContent
    let reviews: HomeReviewSection
    let showsSyncStatus: Bool
}

enum HomeLearningPath {
    static func make(
        textbook: Textbook?,
        textbookError: String?,
        studyState: StudyState?,
        syncState: LearningSyncState,
        pendingCount: Int,
        isShowingCachedStudyState: Bool
    ) -> HomeScreenModel {
        HomeScreenModel(
            content: content(textbook: textbook, textbookError: textbookError, studyState: studyState),
            reviews: reviews(textbook: textbook, studyState: studyState),
            showsSyncStatus: showsSyncStatus(
                syncState: syncState,
                pendingCount: pendingCount,
                isShowingCachedStudyState: isShowingCachedStudyState
            )
        )
    }

    static func showsSyncStatus(
        syncState: LearningSyncState,
        pendingCount: Int,
        isShowingCachedStudyState: Bool
    ) -> Bool {
        syncState != .synced || pendingCount > 0 || isShowingCachedStudyState
    }

    static func currentLesson(in textbook: Textbook, studyState: StudyState?) -> TextbookLesson? {
        let completed = Set(studyState?.lessons.filter { $0.completedAt != nil }.map(\.lessonId) ?? [])
        return textbook.lessons.first { !completed.contains($0.id) } ?? textbook.lessons.last
    }

    static func patternLabels(for lesson: TextbookLesson, limit: Int = 2) -> [String] {
        Array(lesson.grammar.prefix(max(0, limit)).map(\.pattern))
    }

    static func reviewEntries(textbook: Textbook, dueQuestionIDs: [String]) -> [HomeReviewEntry] {
        let due = Set(dueQuestionIDs)
        return textbook.lessons.compactMap { lesson in
            let ids = textbook.questions.filter { $0.lessonId == lesson.id && due.contains($0.id) }.map(\.id)
            guard !ids.isEmpty else { return nil }
            return HomeReviewEntry(lessonID: lesson.id, title: lesson.title, questionIDs: ids)
        }
    }

    private static func content(
        textbook: Textbook?,
        textbookError: String?,
        studyState: StudyState?
    ) -> HomeContent {
        guard let textbook else {
            if let textbookError { return .failed(textbookError) }
            return .loading
        }
        guard let lesson = currentLesson(in: textbook, studyState: studyState) else {
            return .emptyLessons
        }
        let labels = patternLabels(for: lesson)
        return .ready(HomePreview(
            lessonID: lesson.id,
            title: lesson.title,
            goal: lesson.goal,
            patternLabels: labels,
            grammarCount: lesson.grammar.count,
            isGrammarUnavailable: lesson.grammar.isEmpty,
            isConfirmedProgress: studyState != nil
        ))
    }

    private static func reviews(textbook: Textbook?, studyState: StudyState?) -> HomeReviewSection {
        guard let textbook else {
            return HomeReviewSection(isVisible: false, dueCount: nil, entries: [], message: nil)
        }
        guard let studyState else {
            return HomeReviewSection(
                isVisible: true,
                dueCount: nil,
                entries: [],
                message: "尚未取得云端复习计划。可先学习内置教材。"
            )
        }
        return HomeReviewSection(
            isVisible: true,
            dueCount: studyState.dueQuestionIds.count,
            entries: reviewEntries(textbook: textbook, dueQuestionIDs: studyState.dueQuestionIds),
            message: studyState.dueQuestionIds.isEmpty ? "当前没有到期题目。" : nil
        )
    }
}

enum HomeGreeting {
    static func title(for date: Date, calendar: Calendar = .current) -> String {
        switch calendar.component(.hour, from: date) {
        case 5..<11: return "早上好"
        case 11..<14: return "中午好"
        case 14..<18: return "下午好"
        default: return "晚上好"
        }
    }

    static func dateLine(
        for date: Date,
        locale: Locale = Locale(identifier: "zh_CN"),
        timeZone: TimeZone = .current
    ) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.setLocalizedDateFormatFromTemplate("MMMMdEEEE")
        return formatter.string(from: date)
    }
}
