import Foundation

enum LearningSyncFailure: Equatable {
    case offline
    case message(String)

    static func classify(_ error: Error) -> LearningSyncFailure {
        if let error = error as? APIClientError {
            switch error {
            case .unauthorized:
                return .message("登录状态验证失败（HTTP 401），答案仍保留在待同步队列。")
            case .forbidden:
                return .message("无权同步答案（HTTP 403），答案仍保留在待同步队列。")
            case .offline:
                return .offline
            case .invalidResponse:
                return .message("服务器响应无效，答案仍保留在待同步队列。")
            case let .server(statusCode):
                switch statusCode {
                case 409:
                    return .message("错题状态版本冲突，答案仍保留在队列；不会自动刷新版本或重写。请重新读取学习进度后人工处理。")
                case 428:
                    return .message("队列答案缺少错题版本，答案仍保留在队列且未确认写入。请先更新队列状态后重试。")
                case 100...599:
                    return .message("同步请求失败（HTTP \(statusCode)），答案仍保留在待同步队列。")
                default:
                    return .message("同步请求失败，答案仍保留在待同步队列。")
                }
            }
        }
        if error is URLError { return .offline }
        if error is DecodingError { return .message("服务器响应解析失败，答案仍保留在待同步队列。") }
        return .message("同步失败，答案仍保留在待同步队列，请稍后重试。")
    }
}
