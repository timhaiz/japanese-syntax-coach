import XCTest
@testable import JapaneseSyntaxCoach

final class AnswerEvaluatorTests: XCTestCase {
    func testAcceptedChoiceAndExpectedDisplayText() throws {
        let question = try makeQuestion(answer: "A", type: "选择", options: ["A：私は学生です。", "B：私は先生です。"])
        let result = AnswerEvaluator.evaluate(question: question, answer: "私は学生です。")
        XCTAssertTrue(result.isCorrect)
        XCTAssertEqual(result.verdict, "correct")
        XCTAssertEqual(result.expectedAnswer, "私は学生です。")
        XCTAssertEqual(result.feedback, "句型结构正确，继续保持主动输出。")
    }

    func testWrongChoiceUsesExpectedDisplayTextForSimilarity() throws {
        let question = try makeQuestion(answer: "A", type: "选择", options: ["A：私は学生です。", "B：私は先生です。"])
        let result = AnswerEvaluator.evaluate(question: question, answer: "私は先生です。")
        XCTAssertFalse(result.isCorrect)
        XCTAssertEqual(result.verdict, "needs_fix")
        XCTAssertEqual(result.feedback, "你选择了「私は先生です。」，正确选项是「私は学生です。」。")
        XCTAssertEqual(result.errorTags, ["词汇"]) // Raw answer remains the key, not display text.
    }

    func testParticleOptionsAcceptTextAndRejectWrongText() throws {
        let question = try makeQuestion(answer: "の", type: "助词", options: ["A：は", "B：の", "C：も"])
        let correct = AnswerEvaluator.evaluate(question: question, answer: "の")
        XCTAssertTrue(correct.isCorrect)
        XCTAssertEqual(correct.verdict, "correct")
        let wrong = AnswerEvaluator.evaluate(question: question, answer: "は")
        XCTAssertFalse(wrong.isCorrect)
        XCTAssertEqual(wrong.verdict, "incorrect")
    }

    func testOptionSimilarityUsesDisplayTextAboveAndBelowThreshold() throws {
        let question = try makeQuestion(answer: "A", type: "选择", options: ["A：私は学生です。", "B：私は先生です。"])
        for (answer, verdict) in [("私は学生だよ。", "needs_fix"), ("あいうえおか。", "incorrect")] {
            let result = AnswerEvaluator.evaluate(question: question, answer: answer)
            XCTAssertFalse(result.isCorrect)
            XCTAssertEqual(result.verdict, verdict)
        }
    }

    @MainActor
    func testUIOptionTextReachesRecordAnswerRequestBody() throws {
        for (type, expected, option, options) in [
            ("选择", "A", "A： 私は学生です。 ", ["A： 私は学生です。 ", "B：私は先生です。"]),
            ("助词", "の", "B： の ", ["A：は", "B： の ", "C：も"])
        ] {
            let question = try makeQuestion(answer: expected, type: type, options: options)
            let submittedText = QuestionView.submittedOptionText(option)
            let expectedText = type == "选择" ? "私は学生です。" : "の"
            XCTAssertEqual(submittedText, expectedText)
            let submission = AnswerSubmission(
                question: question, answer: submittedText,
                evaluation: AnswerEvaluator.evaluate(question: question, answer: submittedText), mode: "lesson"
            )
            let body = try JSONEncoder().encode(RecordAnswerRequest(submission.pendingAnswer(clientRequestId: "option-request")))
            let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
            XCTAssertEqual(object["answer"] as? String, expectedText)
            XCTAssertEqual(object["clientRequestId"] as? String, "option-request")
            XCTAssertEqual(object["correct"] as? Bool, true)
            XCTAssertNil(object["userId"])
        }
    }

    @MainActor
    func testBundledOptionTextsAreUniqueAndGradeByTextOrKey() throws {
        let questions = try TextbookRepository.loadBundled().textbook.questions.filter { $0.options != nil }
        XCTAssertEqual(questions.count, 210)
        for question in questions {
            let options = try XCTUnwrap(question.options)
            let texts = options.map(QuestionView.submittedOptionText)
            XCTAssertEqual(Set(texts).count, options.count, question.id)
            for (option, text) in zip(options, texts) {
                let expectedCorrect = question.type == "选择" ? String(option.prefix(1)) == question.answer : text == question.answer
                let result = AnswerEvaluator.evaluate(question: question, answer: text)
                XCTAssertEqual(result.isCorrect, expectedCorrect, "\(question.id): \(option)")
                if expectedCorrect { XCTAssertEqual(result.verdict, "correct") }
            }
        }
    }

    func testStudyStateDefaultsMissingOrNullLegacyAvailabilityToFalse() throws {
        let base: [String: Any] = [
            "textbookId": "builtin-japanese-syntax", "textbookScopeAvailable": true,
            "dueQuestionIds": [], "lessons": [], "knowledgePoints": [],
            "metrics": ["totalAttempts": 0, "incorrectAttempts": 0, "errorRate": 0,
                        "forgettingRate": 0, "correctStreak": 0, "topErrorTags": []]
        ]
        for value in [nil, NSNull(), false, true] as [Any?] {
            var object = base
            object["legacyProgressAvailable"] = value
            if value as? Bool == true { object["legacyProgress"] = ["status": "unsupported"] }
            let state = try JSONDecoder().decode(StudyState.self, from: JSONSerialization.data(withJSONObject: object))
            XCTAssertEqual(state.legacyProgressAvailable, value as? Bool ?? false)
            XCTAssertEqual(state.legacyProgress?.objectValue?["status"]?.stringValue, value as? Bool == true ? "unsupported" : nil)
            XCTAssertEqual(try JSONDecoder().decode(StudyState.self, from: JSONEncoder().encode(state)), state)
        }
    }

    func testAcceptedAlternativeFromQuestion() throws {
        let question = try makeQuestion(answer: "私は先生ではありません。", acceptedAnswers: ["私は先生じゃありません。"])
        XCTAssertTrue(AnswerEvaluator.evaluate(question: question, answer: "私は先生じゃありません。").isCorrect)
    }

    func testWebsiteDesugaredVariantsIncludingOverlappingNegativePast() throws {
        let cases = [
            ("私は先生ではありません。", "私は先生じゃありません。"),
            ("昨日は休みくないです。", "昨日は休みくありません。"),
            ("飲みくなかったです。", "飲みくありませんでした。"),
            ("先生ではありませんでした。", "先生じゃありませんでした。")
        ]
        for (expected, alternative) in cases {
            let question = try makeQuestion(answer: expected)
            XCTAssertTrue(AnswerEvaluator.evaluate(question: question, answer: alternative).isCorrect, "\(expected) → \(alternative)")
        }
    }

    func testBareNegativePastDoesNotGainPoliteVariant() throws {
        let question = try makeQuestion(answer: "行きたくなかった。")
        XCTAssertFalse(AnswerEvaluator.evaluate(question: question, answer: "行きたくありませんでした。").isCorrect)
        XCTAssertFalse(AnswerEvaluator.evaluate(question: question, answer: "行きたくなりませんでした。").isCorrect)
    }

    func testNormalizationRemovesTrailingPunctuationAndFullWidthWhitespace() throws {
        let question = try makeQuestion(answer: "私は学生です。")
        XCTAssertTrue(AnswerEvaluator.evaluate(question: question, answer: "　私は学生です！？、.\n").isCorrect)
    }

    func testSimilarityAtOrAboveBoundaryNeedsFix() throws {
        let question = try makeQuestion(answer: "abcdefghijklmnopqrst")
        let result = AnswerEvaluator.evaluate(question: question, answer: "abcdefghijkXXXXXXXXX")
        XCTAssertEqual(result.verdict, "needs_fix")
        XCTAssertFalse(result.isCorrect)
    }

    func testSimilarityBelowBoundaryIsIncorrect() throws {
        let question = try makeQuestion(answer: "abcdefghijklmnopqrst")
        XCTAssertEqual(AnswerEvaluator.evaluate(question: question, answer: "abcdefXXXXXXXXXXXXXX").verdict, "incorrect")
    }

    func testErrorAndKnowledgeTagsFollowQuestionAndHint() throws {
        let particle = try makeQuestion(answer: "は", type: "助词", hint: "助词选择")
        XCTAssertEqual(AnswerEvaluator.evaluate(question: particle, answer: "を").errorTags, ["助词"])
        XCTAssertEqual(AnswerEvaluator.evaluate(question: particle, answer: "を").knowledgeTags, ["助词"])

        let kana = try makeQuestion(answer: "これは学生ですか。", hint: "疑问句假名检查")
        XCTAssertEqual(AnswerEvaluator.errorTags(question: kana, actual: "これは学生でか。"), ["假名"])
        XCTAssertEqual(AnswerEvaluator.knowledgeTags(question: kana), ["词汇"])

        let conjugation = try makeQuestion(answer: "食べなければ", hint: "否定变化")
        XCTAssertEqual(AnswerEvaluator.errorTags(question: conjugation, actual: "食べない"), ["活用"])
        XCTAssertEqual(AnswerEvaluator.knowledgeTags(question: conjugation), ["活用"])

        let fallback = try makeQuestion(answer: "猫", hint: "理解句子")
        XCTAssertEqual(AnswerEvaluator.knowledgeTags(question: fallback), ["句型"])
    }

    func testRecordResponseRequiresServerWriteConfirmation() throws {
        let decoder = JSONDecoder()
        func confirmed(_ json: String) throws -> Bool {
            try decoder.decode(RecordAnswerResponse.self, from: Data(json.utf8)).confirmsWrite
        }
        XCTAssertTrue(try confirmed(#"{"duplicate":true}"#))
        XCTAssertTrue(try confirmed(#"{"record":null,"textbookScopeAvailable":true}"#))
        XCTAssertTrue(try confirmed(#"{"record":{"id":"saved"},"textbookScopeAvailable":false}"#))
        XCTAssertFalse(try confirmed(#"{"record":null,"textbookScopeAvailable":false,"localOnly":true}"#))
        XCTAssertFalse(try confirmed(#"{"record":null,"textbookScopeAvailable":false}"#))
        XCTAssertFalse(try confirmed(#"{}"#))
    }

    func testErrorTagsCompareRawNotNormalizedLengths() throws {
        let question = try makeQuestion(answer: "猫。")
        XCTAssertEqual(AnswerEvaluator.errorTags(question: question, actual: "犬"), ["词汇"])
        let supplementary = try makeQuestion(answer: "猫猫")
        XCTAssertEqual(AnswerEvaluator.errorTags(question: supplementary, actual: "😀"), ["句型顺序"])
    }

    @MainActor
    func testBundledQuestionOrderAndTwentyQuestionLimit() throws {
        let textbook = try TextbookRepository.loadBundled().textbook
        XCTAssertEqual(textbook.lessons.count, 24)
        let rank = ["选择": 0, "助词": 1, "翻译": 2, "问答": 3]
        for lesson in textbook.lessons {
            let questions = LearningStore.orderedQuestions(for: lesson.id, in: textbook)
            XCTAssertEqual(questions.count, 20)
            let ranks = questions.map { rank[$0.type] ?? 99 }
            XCTAssertEqual(ranks, ranks.sorted())
        }
    }

    private func makeQuestion(
        answer: String,
        type: String = "翻译",
        hint: String = "",
        options: [String]? = nil,
        acceptedAnswers: [String]? = nil
    ) throws -> TextbookQuestion {
        var object: [String: Any] = [
            "id": "L01-Q001", "lessonId": 1, "type": type,
            "prompt": "题目", "answer": answer, "hint": hint
        ]
        if let options { object["options"] = options }
        if let acceptedAnswers { object["acceptedAnswers"] = acceptedAnswers }
        return try JSONDecoder().decode(TextbookQuestion.self, from: JSONSerialization.data(withJSONObject: object))
    }
}
