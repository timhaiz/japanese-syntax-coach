import XCTest
@testable import JapaneseSyntaxCoach

final class AnswerEvaluatorTests: XCTestCase {
    func testAcceptedChoiceAndExpectedDisplayText() throws {
        let question = try makeQuestion(answer: "A", type: "选择", options: ["A：私は学生です。", "B：私は先生です。"])
        let result = AnswerEvaluator.evaluate(question: question, answer: "A")
        XCTAssertTrue(result.isCorrect)
        XCTAssertEqual(result.verdict, "correct")
        XCTAssertEqual(result.expectedAnswer, "私は学生です。")
        XCTAssertEqual(result.feedback, "句型结构正确，继续保持主动输出。")
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
