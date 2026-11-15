import Foundation
#if WORD_TOKEN_STANDALONE
class XCTestCase {}
func XCTAssertEqual<T: Equatable>(_ a: T, _ b: T, file: StaticString = #file, line: UInt = #line) { precondition(a == b, "\(a) != \(b)", file: file, line: line) }
func XCTAssertTrue(_ value: Bool, file: StaticString = #file, line: UInt = #line) { precondition(value, file: file, line: line) }
func XCTAssertFalse(_ value: Bool, file: StaticString = #file, line: UInt = #line) { precondition(!value, file: file, line: line) }
#else
import XCTest
@testable import JapaneseSyntaxCoach
#endif

#if !WORD_TOKEN_STANDALONE
@MainActor
final class JapaneseAudioManifestTests: XCTestCase {
    func testOnlyBuiltinGrammarExamplesResolveExistingFiles() throws {
        let data = Data(#"{"sentences":{"私は学生です。":"example.mp3"}}"#.utf8)
        let directory = URL(fileURLWithPath: "/JapaneseAudio", isDirectory: true)
        let resolve: (String, String?) -> URL? = { text, textbookID in
            JapaneseSpeechPlayer.bundledAudioURL(for: text, textbookID: textbookID, manifestData: data, directory: directory) { $0.lastPathComponent == "example.mp3" }
        }
        XCTAssertEqual(resolve("私は学生です。", "builtin-japanese-syntax")?.lastPathComponent, "example.mp3")
        XCTAssertNil(resolve("私は学生です。", "another-textbook"))
        XCTAssertNil(resolve("私は学生です。", nil))
        XCTAssertNil(resolve("別の文。", "builtin-japanese-syntax"))
        XCTAssertNil(JapaneseSpeechPlayer.bundledAudioURL(for: "私は学生です。", textbookID: "builtin-japanese-syntax", manifestData: data, directory: directory) { _ in false })
        XCTAssertNil(JapaneseSpeechPlayer.bundledAudioURL(for: "私は学生です。", textbookID: "builtin-japanese-syntax", manifestData: Data(), directory: directory) { _ in true })
    }
}
#endif

final class WordTokenTests: XCTestCase {
    func testTokenizationAndPunctuation() {
        XCTAssertEqual(WordTokenizer.tokenize("かばんはかばんです。"), ["かばん", "は", "かばん", "です"])
        XCTAssertEqual(WordTokenizer.tokenize("😀は学校に行きます！"), ["😀", "は", "学校", "に", "行きます"])
        XCTAssertEqual(WordTokenizer.tokenize("もらいました"), ["もらいました"])
    }

    func testHashAndStableIDs() {
        XCTAssertEqual(WordTokenizer.order("hello"), 1335831723)
        XCTAssertEqual(WordTokenizer.order("😀"), 3409036472)
        let tokens = WordTokenizer.create(questionID: "Q1", answer: "はは。")
        XCTAssertEqual(Set(tokens.map(\.id)), Set(["Q1-T01", "Q1-T02"]))
        XCTAssertEqual(tokens.map(\.text), ["は", "は"])
        XCTAssertEqual(tokens.map(\.id), tokens.map(\.id).sorted { WordTokenizer.order($0) < WordTokenizer.order($1) })
    }

    #if !WORD_TOKEN_STANDALONE
    func testTranslationAndDialogueTokensReachAnswerRequestAsText() throws {
        for type in ["翻译", "问答"] {
            let data = try JSONSerialization.data(withJSONObject: [
                "id": "L01-Q001", "lessonId": 1, "type": type,
                "prompt": "我是学生。", "answer": "私は学生です。", "hint": ""
            ])
            let question = try JSONDecoder().decode(TextbookQuestion.self, from: data)
            var selection = WordTokenSelection()
            let tokens = WordTokenizer.create(questionID: question.id, answer: question.answer)
            for token in tokens.sorted(by: { $0.id < $1.id }) { selection.add(token) }
            XCTAssertEqual(selection.answer, "私は学生です")
            let evaluation = AnswerEvaluator.evaluate(question: question, answer: selection.answer)
            XCTAssertTrue(evaluation.isCorrect)
            let item = AnswerSubmission(question: question, answer: selection.answer,
                                        evaluation: evaluation, mode: "lesson")
                .pendingAnswer(clientRequestId: "token-contract", expectedMistakeVersion: 0)
            let body = try JSONEncoder().encode(RecordAnswerRequest(item))
            let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
            XCTAssertEqual(object["answer"] as? String, selection.answer)
            XCTAssertEqual(object["correct"] as? Bool, true)
            XCTAssertEqual(object["mode"] as? String, "lesson")
            XCTAssertEqual(object["expectedMistakeVersion"] as? Int, 0)
            XCTAssertEqual(object["clientRequestId"] as? String, "token-contract")
            XCTAssertNil(object["userId"])
        }
    }
    #endif

    func testReadingsMatchWebTokenKanaAndDoNotChangeAnswer() {
        XCTAssertEqual(WordTokenReadings.kana(for: "学校"), "（がっこう）")
        XCTAssertEqual(WordTokenReadings.kana(for: "私たち"), "（わたしたち）")
        XCTAssertEqual(WordTokenReadings.kana(for: "学校です"), "")
        XCTAssertEqual(WordTokenReadings.kana(for: "お学校"), "（がっこう）")
        XCTAssertEqual(WordTokenReadings.kana(for: "学校と学校"), "")
        XCTAssertEqual(WordTokenReadings.kana(for: "は"), "")
        XCTAssertEqual(WordTokenReadings.kana(for: "中国"), "（ちゅうごく）")
        var selection = WordTokenSelection()
        selection.add(WordToken(id: "1", text: "学校"))
        XCTAssertEqual(selection.answer, "学校")
    }

    func testSelectionByIdentityRemoveAndClear() {
        let tokens = WordTokenizer.create(questionID: "Q", answer: "ははです。")
        let repeated = tokens.filter { $0.text == "は" }
        let ending = tokens.first { $0.text == "です" }!
        var selection = WordTokenSelection()
        selection.add(repeated[0]); selection.add(repeated[0]); selection.add(ending); selection.add(repeated[1])
        XCTAssertEqual(selection.answer, "はですは")
        selection.remove(id: repeated[0].id)
        XCTAssertEqual(selection.answer, "ですは")
        XCTAssertTrue(selection.contains(id: repeated[1].id))
        XCTAssertFalse(selection.contains(id: repeated[0].id))
        selection.clear()
        XCTAssertEqual(selection.answer, "")
        XCTAssertTrue(selection.selected.isEmpty)
    }
}

#if WORD_TOKEN_STANDALONE
@main struct WordTokenTestRunner {
    static func main() {
        let tests = WordTokenTests()
        tests.testTokenizationAndPunctuation()
        tests.testHashAndStableIDs()
        tests.testSelectionByIdentityRemoveAndClear()
        tests.testReadingsMatchWebTokenKanaAndDoNotChangeAnswer()
        print("4 word token tests passed")
    }
}
#endif
