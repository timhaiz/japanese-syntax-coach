import XCTest
@testable import JapaneseSyntaxCoach

final class HomeLearningPathTests: XCTestCase {
    func testMistakesResolveCanonicalQuestionsWithoutUsingDueReviewIDs() throws {
        let textbook = try decodeTextbook(lessons: [], questions: [
            questionJSON(id: "q1", lessonID: 1, type: "选择"),
            questionJSON(id: "q2", lessonID: 2, type: "翻译")
        ])
        let state = try mistakeState(snapshot: [
            "version": 3,
            "mistakes": [["id": "q2", "prompt": "untrusted"], ["id": "missing"], ["id": "q2"], ["id": "q1"], ["id": 42]]
        ])
        let questions = try XCTUnwrap(state.mistakeQuestions(in: textbook))
        XCTAssertEqual(questions.map(\.id), ["q2", "q1"])
        XCTAssertEqual(questions.first?.prompt, "p")
    }

    func testAtomicMistakeStatesTakePrecedenceAndPreserveFalseTombstones() throws {
        let textbook = try decodeTextbook(lessons: [], questions: [
            questionJSON(id: "q1", lessonID: 1, type: "选择"),
            questionJSON(id: "q2", lessonID: 1, type: "翻译")
        ])
        let state = try atomicMistakeState([
            ["questionId": "q1", "isMistake": true, "version": 2],
            ["questionId": "q2", "isMistake": false, "version": 3]
        ], legacy: ["version": 3, "mistakes": [["id": "q2"]]])
        XCTAssertEqual(state.mistakeQuestions(in: textbook)?.map(\.id), ["q1"])
        XCTAssertEqual(state.mistakeVersion(for: "q2"), 3)
    }

    func testInvalidAtomicMistakeStatesAreUnavailableNotEmpty() throws {
        let textbook = try decodeTextbook(lessons: [], questions: [])
        let invalid: [[String: Any]] = [
            ["questionId": "q", "isMistake": true, "version": -1],
            ["questionId": "q", "isMistake": true, "version": 1],
            ["questionId": "q", "isMistake": true, "version": 1],
            ["questionId": "q", "isMistake": 1, "version": 1]
        ]
        for rows in invalid {
            let state = try atomicMistakeState([rows])
            XCTAssertNil(state.mistakeQuestions(in: textbook))
        }
        let duplicate = try atomicMistakeState([
            ["questionId": "q1", "isMistake": true, "version": 1],
            ["questionId": "q1", "isMistake": false, "version": 2]
        ])
        XCTAssertNil(duplicate.mistakeVersion(for: "q1"))
        let disabled = try atomicMistakeState([], available: false)
        XCTAssertNil(disabled.mistakeQuestions(in: textbook))
    }

    private func atomicMistakeState(_ rows: [[String: Any]], available: Bool = true, legacy: [String: Any]? = nil) throws -> StudyState {
        let baseline = try decodeStudyState(dueIDs: [], lessons: [])
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(baseline)) as? [String: Any])
        json["mistakeStateAvailable"] = available
        json["mistakeStates"] = rows
        json["legacyProgressAvailable"] = legacy != nil
        json["legacyProgress"] = legacy
        return try JSONDecoder().decode(StudyState.self, from: JSONSerialization.data(withJSONObject: json))
    }

    func testUnavailableMistakesAreDifferentFromConfirmedEmptyMistakes() throws {
        let textbook = try decodeTextbook(lessons: [], questions: [])
        for version in [2, 3] {
            let empty = try mistakeState(snapshot: ["version": version, "mistakes": []])
            XCTAssertEqual(empty.mistakeQuestions(in: textbook)?.count, 0)
        }
        let unsupportedSnapshots: [[String: Any]] = [
            ["version": 4, "mistakes": []],
            ["version": 3, "status": "unsupported", "mistakes": []],
            ["version": 3, "mistakes": "invalid"]
        ]
        for snapshot in unsupportedSnapshots {
            XCTAssertNil(try mistakeState(snapshot: snapshot).mistakeQuestions(in: textbook))
        }
        XCTAssertNil(try mistakeState(snapshot: ["version": 3, "mistakes": []], available: false).mistakeQuestions(in: textbook))
        XCTAssertNil(try decodeStudyState(dueIDs: [], lessons: []).mistakeQuestions(in: textbook))
    }

    func testMistakesDoNotCrossTextbookBoundary() throws {
        let state = try mistakeState(snapshot: ["version": 3, "mistakes": [["id": "q1"]]])
        let other = try JSONDecoder().decode(Textbook.self, from: Data(#"{"id":"other","title":"其他教材","lessons":[],"questions":[]}"#.utf8))
        XCTAssertNil(state.mistakeQuestions(in: other))
    }

    private func mistakeState(snapshot: [String: Any], available: Bool = true) throws -> StudyState {
        let baseline = try decodeStudyState(dueIDs: ["due-only"], lessons: [])
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(baseline)) as? [String: Any])
        json["legacyProgressAvailable"] = available
        json["legacyProgress"] = snapshot
        return try JSONDecoder().decode(StudyState.self, from: JSONSerialization.data(withJSONObject: json))
    }

    func testSelectsFirstIncompleteLessonInArrayOrder() throws {
        let textbook = try decodeTextbook(
            lessons: [
                lessonJSON(id: 3, title: "第三", patterns: ["甲"]),
                lessonJSON(id: 1, title: "第一", patterns: ["乙"]),
                lessonJSON(id: 2, title: "第二", patterns: ["丙"])
            ],
            questions: []
        )
        let state = try decodeStudyState(
            dueIDs: [],
            lessons: [progressJSON(lessonID: 3, completedAt: "2026-10-01T00:00:00Z")]
        )

        let lesson = HomeLearningPath.currentLesson(in: textbook, studyState: state)

        XCTAssertEqual(lesson?.id, 1)
    }

    func testEmptyCompletedAtCountsAsCompletedAndAllCompletedReturnsLast() throws {
        let textbook = try decodeTextbook(
            lessons: [
                lessonJSON(id: 5, title: "前", patterns: ["甲"]),
                lessonJSON(id: 1, title: "后", patterns: ["乙"])
            ],
            questions: []
        )
        let emptyDate = try decodeStudyState(dueIDs: [], lessons: [progressJSON(lessonID: 5, completedAt: "")])
        XCTAssertEqual(HomeLearningPath.currentLesson(in: textbook, studyState: emptyDate)?.id, 1)

        let allDone = try decodeStudyState(
            dueIDs: [],
            lessons: [
                progressJSON(lessonID: 5, completedAt: "2026-10-01T00:00:00Z"),
                progressJSON(lessonID: 1, completedAt: "2026-10-02T00:00:00Z")
            ]
        )
        XCTAssertEqual(HomeLearningPath.currentLesson(in: textbook, studyState: allDone)?.id, 1)
    }

    func testMissingStudyStateUsesFirstLessonButIsNotConfirmedProgress() throws {
        let textbook = try decodeTextbook(
            lessons: [lessonJSON(id: 7, title: "起始", patterns: ["N は N です。"])],
            questions: []
        )

        let model = HomeLearningPath.make(
            textbook: textbook,
            textbookError: nil,
            studyState: nil,
            syncState: .notSignedIn,
            pendingCount: 0,
            isShowingCachedStudyState: false
        )

        guard case .ready(let preview) = model.content else {
            return XCTFail("expected ready")
        }
        XCTAssertEqual(preview.lessonID, 7)
        XCTAssertFalse(preview.isConfirmedProgress)
    }

    func testPatternLabelsUseRealPatternsAndCapAtTwo() throws {
        let textbook = try decodeTextbook(
            lessons: [lessonJSON(
                id: 1,
                title: "判断句",
                patterns: ["  N は N です。  ", "N は N では ありません。", "N は N ですか。"]
            )],
            questions: []
        )
        let lesson = try XCTUnwrap(textbook.lessons.first)
        let labels = HomeLearningPath.patternLabels(for: lesson)

        XCTAssertEqual(labels, ["  N は N です。  ", "N は N では ありません。"])
        XCTAssertEqual(lesson.grammar.count, 3)
        XCTAssertFalse(labels.contains(where: { $0.contains("含义") || $0 == "m" || $0 == "e" }))
    }

    func testOnePatternIsNotPaddedAndEmptyPatternIsPreserved() throws {
        let one = try decodeTextbook(lessons: [lessonJSON(id: 1, title: "一", patterns: ["だけ"])], questions: [])
        XCTAssertEqual(HomeLearningPath.patternLabels(for: try XCTUnwrap(one.lessons.first)), ["だけ"])

        let blank = try decodeTextbook(lessons: [lessonJSON(id: 1, title: "空", patterns: [""])], questions: [])
        XCTAssertEqual(HomeLearningPath.patternLabels(for: try XCTUnwrap(blank.lessons.first)), [""])
    }

    func testGrammarlessLessonStaysReadyAndMarksPreviewUnavailable() throws {
        let textbook = try decodeTextbook(
            lessons: [lessonJSON(id: 4, title: "无语法", patterns: [])],
            questions: [questionJSON(id: "q1", lessonID: 4, type: "选择")]
        )
        let state = try decodeStudyState(dueIDs: [], lessons: [])

        let model = HomeLearningPath.make(
            textbook: textbook,
            textbookError: nil,
            studyState: state,
            syncState: .synced,
            pendingCount: 0,
            isShowingCachedStudyState: false
        )

        guard case .ready(let preview) = model.content else {
            return XCTFail("expected ready")
        }
        XCTAssertTrue(preview.isGrammarUnavailable)
        XCTAssertEqual(preview.patternLabels, [])
        XCTAssertEqual(preview.grammarCount, 0)
        XCTAssertTrue(preview.isConfirmedProgress)
    }

    func testLoadingFailureAndEmptyLessonStates() throws {
        let loading = HomeLearningPath.make(
            textbook: nil,
            textbookError: nil,
            studyState: nil,
            syncState: .loading,
            pendingCount: 0,
            isShowingCachedStudyState: false
        )
        XCTAssertEqual(loading.content, .loading)
        XCTAssertFalse(loading.reviews.isVisible)

        let failed = HomeLearningPath.make(
            textbook: nil,
            textbookError: "教材无法从安装包或本机缓存中读取。",
            studyState: nil,
            syncState: .error("云端学习进度暂时无法读取。"),
            pendingCount: 0,
            isShowingCachedStudyState: false
        )
        XCTAssertEqual(failed.content, .failed("教材无法从安装包或本机缓存中读取。"))

        let empty = try decodeTextbook(lessons: [], questions: [])
        let model = HomeLearningPath.make(
            textbook: empty,
            textbookError: nil,
            studyState: nil,
            syncState: .synced,
            pendingCount: 0,
            isShowingCachedStudyState: false
        )
        XCTAssertEqual(model.content, .emptyLessons)
        XCTAssertNil(HomeLearningPath.currentLesson(in: empty, studyState: nil))
    }

    func testReviewEntriesFollowLessonArrayAndQuestionArrayOrderWithoutLimit() throws {
        let questions = (1...21).map { questionJSON(id: "q\($0)", lessonID: 2, type: "翻译") }
            + [questionJSON(id: "choice", lessonID: 1, type: "选择"),
               questionJSON(id: "translation", lessonID: 1, type: "翻译")]
        let textbook = try decodeTextbook(
            lessons: [
                lessonJSON(id: 2, title: "后编号", patterns: ["甲"]),
                lessonJSON(id: 1, title: "前编号", patterns: ["乙"])
            ],
            questions: questions
        )
        var due = (1...21).map { "q\($0)" }
        due.append(contentsOf: ["choice", "translation"])

        let entries = HomeLearningPath.reviewEntries(textbook: textbook, dueQuestionIDs: due)

        XCTAssertEqual(entries.map(\.lessonID), [2, 1])
        XCTAssertEqual(entries[0].questionIDs.count, 21)
        XCTAssertEqual(entries[1].questionIDs, ["choice", "translation"])
    }

    func testUnmatchedDueIDsDoNotCreateEmptyMessage() throws {
        let textbook = try decodeTextbook(
            lessons: [lessonJSON(id: 1, title: "一", patterns: ["甲"])],
            questions: [questionJSON(id: "present", lessonID: 1, type: "选择")]
        )
        let state = try decodeStudyState(dueIDs: ["missing"], lessons: [])
        let model = HomeLearningPath.make(
            textbook: textbook,
            textbookError: nil,
            studyState: state,
            syncState: .synced,
            pendingCount: 0,
            isShowingCachedStudyState: false
        )

        XCTAssertEqual(model.reviews.dueCount, 1)
        XCTAssertEqual(model.reviews.entries, [])
        XCTAssertNil(model.reviews.message)
    }

    func testReviewMessagesMatchExistingCopy() throws {
        let textbook = try decodeTextbook(
            lessons: [lessonJSON(id: 1, title: "一", patterns: ["甲"])],
            questions: []
        )
        let unavailable = HomeLearningPath.make(
            textbook: textbook,
            textbookError: nil,
            studyState: nil,
            syncState: .notSignedIn,
            pendingCount: 0,
            isShowingCachedStudyState: false
        )
        XCTAssertTrue(unavailable.reviews.isVisible)
        XCTAssertNil(unavailable.reviews.dueCount)
        XCTAssertEqual(unavailable.reviews.message, "尚未取得云端复习计划。可先学习内置教材。")

        let noneDue = try decodeStudyState(dueIDs: [], lessons: [])
        let empty = HomeLearningPath.make(
            textbook: textbook,
            textbookError: nil,
            studyState: noneDue,
            syncState: .synced,
            pendingCount: 0,
            isShowingCachedStudyState: false
        )
        XCTAssertEqual(empty.reviews.dueCount, 0)
        XCTAssertEqual(empty.reviews.message, "当前没有到期题目。")
    }

    func testSyncRowVisibility() {
        XCTAssertFalse(HomeLearningPath.showsSyncStatus(syncState: .synced, pendingCount: 0, isShowingCachedStudyState: false))
        XCTAssertTrue(HomeLearningPath.showsSyncStatus(syncState: .synced, pendingCount: 1, isShowingCachedStudyState: false))
        XCTAssertTrue(HomeLearningPath.showsSyncStatus(syncState: .synced, pendingCount: 0, isShowingCachedStudyState: true))
        for state in [LearningSyncState.notSignedIn, .loading, .syncing, .pending, .offline, .error("失败")] {
            XCTAssertTrue(HomeLearningPath.showsSyncStatus(syncState: state, pendingCount: 0, isShowingCachedStudyState: false))
        }
    }

    func testGreetingHourBoundaries() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let start = Date(timeIntervalSince1970: 0)
        let cases: [(Int, String)] = [
            (4, "晚上好"), (5, "早上好"), (10, "早上好"),
            (11, "中午好"), (13, "中午好"), (14, "下午好"),
            (17, "下午好"), (18, "晚上好"), (23, "晚上好")
        ]
        for (hour, title) in cases {
            let date = calendar.date(bySettingHour: hour, minute: 30, second: 0, of: start)!
            XCTAssertEqual(HomeGreeting.title(for: date, calendar: calendar), title)
        }
    }

    func testDateLineUsesPinnedChineseCalendar() {
        let date = Date(timeIntervalSince1970: 0)
        let line = HomeGreeting.dateLine(
            for: date,
            locale: Locale(identifier: "zh_CN"),
            timeZone: TimeZone(secondsFromGMT: 0)!
        )
        XCTAssertTrue(line.contains("1月"))
        XCTAssertTrue(line.contains("星期四") || line.contains("周四"))
    }

    func testExistingLessonQuestionOrderingRemainsAvailable() async throws {
        let textbook = try decodeTextbook(
            lessons: [lessonJSON(id: 1, title: "一", patterns: ["甲"])],
            questions: [
                questionJSON(id: "t", lessonID: 1, type: "翻译"),
                questionJSON(id: "c", lessonID: 1, type: "选择"),
                questionJSON(id: "p", lessonID: 1, type: "助词"),
                questionJSON(id: "a", lessonID: 1, type: "问答"),
                questionJSON(id: "u", lessonID: 1, type: "未知")
            ] + (1...20).map { questionJSON(id: "extra\($0)", lessonID: 1, type: "选择") }
        )

        let questions = await LearningStore.orderedQuestions(for: 1, in: textbook)
        XCTAssertEqual(questions.first?.id, "c")
        XCTAssertEqual(questions.prefix(21).map(\.type).filter { $0 == "选择" }.count, 20)
        XCTAssertEqual(questions.count, 20)
        XCTAssertFalse(questions.map(\.id).contains("t"))
    }
}

private func decodeTextbook(lessons: [String], questions: [String]) throws -> Textbook {
    let json = #"{"id":"builtin-japanese-syntax","title":"内置教材","lessons":[\#(lessons.joined(separator: ", "))],"questions":[\#(questions.joined(separator: ", "))]}"#
    return try JSONDecoder().decode(Textbook.self, from: Data(json.utf8))
}

private func lessonJSON(id: Int, title: String, patterns: [String]) -> String {
    let grammar = patterns.map { pattern -> String in
        let escaped = pattern.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        return #"{"pattern":"\#(escaped)","meaning":"m","example":"e","connection":"c","explanation":"x"}"#
    }.joined(separator: ",")
    return #"{"id":\#(id),"title":"\#(title)","goal":"目标","grammar":[\#(grammar)]}"#
}

private func questionJSON(id: String, lessonID: Int, type: String) -> String {
    #"{"id":"\#(id)","lessonId":\#(lessonID),"type":"\#(type)","prompt":"p","answer":"a","hint":"h"}"#
}

private func progressJSON(lessonID: Int, completedAt: String?) -> String {
    let completed = completedAt.map { "\"\($0)\"" } ?? "null"
    return #"{"lesson_id":\#(lessonID),"answered_count":1,"correct_count":1,"completed_at":\#(completed)}"#
}

private func decodeStudyState(dueIDs: [String], lessons: [String]) throws -> StudyState {
    let due = dueIDs.map { "\"\($0)\"" }.joined(separator: ",")
    let json = #"{"textbookId":"builtin-japanese-syntax","textbookScopeAvailable":true,"dueQuestionIds":[\#(due)],"lessons":[\#(lessons.joined(separator: ", "))],"knowledgePoints":[],"metrics":{"totalAttempts":0,"incorrectAttempts":0,"errorRate":0,"forgettingRate":0,"correctStreak":0,"topErrorTags":[]}}"#
    return try JSONDecoder().decode(StudyState.self, from: Data(json.utf8))
}
