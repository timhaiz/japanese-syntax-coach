import Foundation
#if !ATOMIC_MISTAKE_STANDALONE
import XCTest
@testable import JapaneseSyntaxCoach
#endif

private enum AtomicContractChecks {
    struct Failure: Error { let message: String }
    static func check(_ value: Bool, _ message: String) throws {
        if !value { throw Failure(message: message) }
    }
    static func run() throws {
        func item(_ correct: Bool = true, mode: String = "mistakes", version: Int? = 2) -> PendingAnswer {
            PendingAnswer(textbookId: "builtin-japanese-syntax", questionId: "q1", lessonId: 1, questionLimit: 20, answer: "A", correct: correct, verdict: correct ? "correct" : "incorrect", errorTags: [], knowledgeTags: [], mode: mode, clientRequestId: "operation-1", expectedMistakeVersion: version)
        }
        func response(_ state: String, extras: String = "") throws -> RecordAnswerResponse {
            let json = "{\"duplicate\":false,\"record\":{},\"textbookScopeAvailable\":true,\"mistakeStateAvailable\":true,\"mistakeState\":\(state)\(extras)}"
            return try JSONDecoder().decode(RecordAnswerResponse.self, from: Data(json.utf8))
        }
        let cleared = #"{"questionId":"q1","isMistake":false,"version":3}"#
        let retained = #"{"questionId":"q1","isMistake":true,"version":3}"#
        try check(try response(cleared).confirms(item()), "matching mistake removal confirms")
        try check(try response(retained).confirms(item(mode: "lesson")), "ordinary correct lesson may preserve an existing mistake")
        try check(!(try response(retained).confirms(item())), "mistake practice must confirm removal")
        try check(!(try response(cleared).confirms(item(false))), "incorrect answer must confirm addition")
        try check(!(try response(cleared, extras: ",\"localOnly\":true").confirms(item())), "local-only response cannot confirm atomic persistence")
        try check(!(try response(cleared).confirms(item(version: nil))), "unversioned answer cannot accept atomic acknowledgement")
        try check(!(try response(#"{"questionId":"other","isMistake":false,"version":3}"#).confirms(item())), "wrong question cannot confirm")
        try check(!(try response(#"{"questionId":"q1","isMistake":false,"version":4}"#).confirms(item())), "wrong version cannot confirm")
        try check(!(try response(cleared).confirms(item(version: Int.max))), "overflow version cannot confirm or crash")
        try check(!AtomicMistakeState(questionId: "q1", isMistake: true, version: Int.max).isValid, "versions must stay JSON safe")
        let textbook = try JSONDecoder().decode(Textbook.self, from: Data(#"{"id":"builtin-japanese-syntax","title":"教材","lessons":[],"questions":[]}"#.utf8))
        let snapshot = #"{"textbookId":"builtin-japanese-syntax","textbookScopeAvailable":true,"dueQuestionIds":[],"lessons":[],"knowledgePoints":[],"metrics":{"totalAttempts":0,"incorrectAttempts":0,"errorRate":0,"forgettingRate":0,"correctStreak":0,"topErrorTags":[]},"mistakeStateAvailable":true,"mistakeStates":[{"questionId":"unknown","isMistake":true,"version":1}]}"#
        let state = try JSONDecoder().decode(StudyState.self, from: Data(snapshot.utf8))
        try check(state.mistakeQuestions(in: textbook) == nil, "unknown canonical question must not produce confirmed empty mistakes")
        let encoded = try JSONEncoder().encode(RecordAnswerRequest(item()))
        let fields = try JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        try check(fields?["expectedMistakeVersion"] as? Int == 2, "request retains captured version")
        try check(fields?["clientRequestId"] as? String == "operation-1", "request retains operation id")
        let old = try JSONDecoder().decode(RecordAnswerResponse.self, from: Data(#"{"record":{},"textbookScopeAvailable":true}"#.utf8))
        try check(old.confirms(item(version: nil)), "legacy response stays compatible for unversioned queue")
        try check(!old.confirms(item()), "versioned operation never accepts legacy response")
    }
}

#if ATOMIC_MISTAKE_STANDALONE
@main private struct AtomicMistakeContractRunner {
    static func main() throws {
        try AtomicContractChecks.run()
        print("PASS: atomic mistake response validation and immutable request contract (15 checks)")
    }
}
#else
final class AtomicMistakeContractTests: XCTestCase {
    func testAtomicAcknowledgementsAndCapturedPayload() throws { try AtomicContractChecks.run() }
}
#endif
