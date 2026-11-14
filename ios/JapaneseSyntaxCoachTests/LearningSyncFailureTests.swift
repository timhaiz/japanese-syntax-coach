import Foundation
#if SYNC_FAILURE_STANDALONE
class XCTestCase {}
func XCTAssertEqual<T: Equatable>(_ a: T, _ b: T, file: StaticString = #file, line: UInt = #line) {
    precondition(a == b, "\(a) != \(b)", file: file, line: line)
}

#else
import XCTest
@testable import JapaneseSyntaxCoach
#endif

final class LearningSyncFailureTests: XCTestCase {
    func testHTTPFailures() {
        XCTAssertEqual(LearningSyncFailure.classify(APIClientError.unauthorized), .message("登录状态验证失败（HTTP 401），答案仍保留在待同步队列。"))
        XCTAssertEqual(LearningSyncFailure.classify(APIClientError.forbidden), .message("无权同步答案（HTTP 403），答案仍保留在待同步队列。"))
        for status in [400, 404, 422, 500, 503] {
            XCTAssertEqual(LearningSyncFailure.classify(APIClientError.server(statusCode: status)), .message("同步请求失败（HTTP \(status)），答案仍保留在待同步队列。"))
        }
        XCTAssertEqual(LearningSyncFailure.classify(APIClientError.server(statusCode: 409)), .message("错题状态版本冲突，答案仍保留在队列；不会自动刷新版本或重写。请重新读取学习进度后人工处理。"))
        XCTAssertEqual(LearningSyncFailure.classify(APIClientError.server(statusCode: 428)), .message("队列答案缺少错题版本，答案仍保留在队列且未确认写入。请先更新队列状态后重试。"))
    }

    func testOfflineAndInvalidResponse() {
        XCTAssertEqual(LearningSyncFailure.classify(APIClientError.offline), .offline)
        XCTAssertEqual(LearningSyncFailure.classify(URLError(.timedOut)), .offline)
        XCTAssertEqual(LearningSyncFailure.classify(APIClientError.invalidResponse), .message("服务器响应无效，答案仍保留在待同步队列。"))
    }

    func testSensitiveErrorDetailsAreNeverDisplayed() {
        let secret = "token=secret&account=user@example.com&answer=private"
        let decoding = DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: secret))
        XCTAssertEqual(LearningSyncFailure.classify(decoding), .message("服务器响应解析失败，答案仍保留在待同步队列。"))
        let unknown = NSError(domain: secret, code: 123, userInfo: [NSLocalizedDescriptionKey: secret])
        XCTAssertEqual(LearningSyncFailure.classify(unknown), .message("同步失败，答案仍保留在待同步队列，请稍后重试。"))
        XCTAssertEqual(LearningSyncFailure.classify(APIClientError.server(statusCode: -123)), .message("同步请求失败，答案仍保留在待同步队列。"))
    }
}

#if SYNC_FAILURE_STANDALONE
@main struct LearningSyncFailureTestRunner {
    static func main() {
        let tests = LearningSyncFailureTests()
        tests.testHTTPFailures()
        tests.testOfflineAndInvalidResponse()
        tests.testSensitiveErrorDetailsAreNeverDisplayed()
        print("3 sync failure tests passed")
    }
}
#endif
