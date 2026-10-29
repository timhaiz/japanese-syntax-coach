import Foundation

/// Membership status reported by `GET /api/membership`.
enum MembershipStatus: String, Codable, Equatable {
    case member
    case free
    case anonymous
    /// The server may add new statuses; keep them readable instead of failing the decode.
    case unknown

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        self = MembershipStatus(rawValue: raw) ?? .unknown
    }
}

/// The membership snapshot the server confirmed. The app never derives membership locally.
struct MembershipState: Codable, Equatable {
    let authenticated: Bool
    let status: MembershipStatus
    let isMember: Bool
    let endsAt: String?

    init(authenticated: Bool, status: MembershipStatus, isMember: Bool, endsAt: String?) {
        self.authenticated = authenticated
        self.status = status
        self.isMember = isMember
        self.endsAt = endsAt
    }

    static let unknown = MembershipState(authenticated: true, status: .unknown, isMember: false, endsAt: nil)
}

/// Result of submitting one signed transaction to `/api/apple/entitlements`.
enum EntitlementOutcome: Equatable {
    /// The server accepted the transaction and confirmed the membership.
    case accepted(MembershipState)
    /// The server recognised the transaction as already processed.
    case duplicate(MembershipState)
    /// The transaction belongs to a different account than the signed-in one.
    case accountMismatch(String)
    /// Apple or the server rejected the transaction; retrying will not help.
    case rejected(statusCode: Int, message: String)
    /// The session is missing or expired.
    case unauthorized
    /// The submission could not be completed; the transaction must stay queued.
    case networkFailure(String)

    /// Only an acknowledged submission allows the StoreKit transaction to be finished.
    var isAcknowledged: Bool {
        switch self {
        case .accepted, .duplicate: return true
        case .accountMismatch, .rejected, .unauthorized, .networkFailure: return false
        }
    }

    /// Only failures that can succeed later keep the transaction queued.
    var isRetryable: Bool {
        switch self {
        case .networkFailure, .unauthorized: return true
        case .accepted, .duplicate, .accountMismatch, .rejected: return false
        }
    }
}

enum EntitlementError: LocalizedError, Equatable {
    case accountMismatch(String)
    case unauthorized
    case rejected(statusCode: Int, message: String)
    case networkFailure(String)

    var errorDescription: String? {
        switch self {
        case .accountMismatch(let message): return message
        case .unauthorized: return "请先登录后再同步购买记录。"
        case .rejected(_, let message): return message
        case .networkFailure(let message): return message
        }
    }
}

struct EntitlementSubmissionRequest: Encodable {
    let signedTransaction: String
}

/// Mirrors the server payload of `POST /api/apple/entitlements`.
/// The route answers 200 even when `updated` is false, so both fields matter.
struct EntitlementSubmissionResponse: Decodable {
    let updated: Bool
    let status: String?
    let reason: String?
    let duplicate: Bool?
}

/// Mirrors the server payload of `GET /api/membership`.
struct MembershipResponse: Decodable {
    let authenticated: Bool
    let status: String?
    let isMember: Bool?
    let endsAt: String?

    var membershipState: MembershipState {
        MembershipState(
            authenticated: authenticated,
            status: MembershipStatus(rawValue: status ?? "") ?? .unknown,
            isMember: isMember ?? false,
            endsAt: endsAt
        )
    }
}

/// Main-actor isolated, so the StoreKit layer never reads a half-updated submission
/// result while a purchase is being synced.
@MainActor
protocol EntitlementSubmitting: AnyObject {
    /// Detailed outcome used by the StoreKit layer to decide whether a transaction may be finished.
    func submitOutcome(signedTransaction: String) async -> EntitlementOutcome
    /// Membership as confirmed by the server; `nil` when it could not be read.
    func refreshMembership() async -> MembershipState?
}

@MainActor
final class EntitlementSync: EntitlementSubmitting {
    private let api: APIClient
    private let baseURL: URL

    init(api: APIClient, baseURL: URL = AppConfiguration.webURL) {
        self.api = api
        self.baseURL = baseURL
    }

    /// Required interface: throws when the transaction was not acknowledged.
    func submit(signedTransaction: String) async throws -> MembershipState {
        switch await submitOutcome(signedTransaction: signedTransaction) {
        case .accepted(let state), .duplicate(let state):
            return state
        case .accountMismatch(let message):
            throw EntitlementError.accountMismatch(message)
        case .unauthorized:
            throw EntitlementError.unauthorized
        case .rejected(let statusCode, let message):
            throw EntitlementError.rejected(statusCode: statusCode, message: message)
        case .networkFailure(let message):
            throw EntitlementError.networkFailure(message)
        }
    }

    func submitOutcome(signedTransaction: String) async -> EntitlementOutcome {
        var request = URLRequest(url: baseURL.appendingPathComponent("api/apple/entitlements"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONEncoder().encode(EntitlementSubmissionRequest(signedTransaction: signedTransaction))

        do {
            let response: EntitlementSubmissionResponse = try await api.request(request)
            guard response.updated || response.duplicate == true else {
                return Self.rejection(for: response.reason)
            }
            let membership = await refreshMembership() ?? .unknown
            return response.duplicate == true ? .duplicate(membership) : .accepted(membership)
        } catch let error as APIClientError {
            return Self.failure(for: error)
        } catch {
            return .networkFailure("购买记录同步失败，已保留待重试。")
        }
    }

    func refreshMembership() async -> MembershipState? {
        var request = URLRequest(url: baseURL.appendingPathComponent("api/membership"))
        request.httpMethod = "GET"
        do {
            let response: MembershipResponse = try await api.request(request)
            return response.membershipState
        } catch {
            return nil
        }
    }

    private static func rejection(for reason: String?) -> EntitlementOutcome {
        switch reason {
        case "missing-app-account-token":
            return .accountMismatch("交易账号与当前账号不匹配。")
        case "unknown-product":
            return .rejected(statusCode: 200, message: "该商品无法开通会员。")
        case "no-membership-state":
            return .rejected(statusCode: 200, message: "该购买记录没有有效的订阅有效期。")
        default:
            return .rejected(statusCode: 200, message: "服务器未确认这笔购买。")
        }
    }

    private static func failure(for error: APIClientError) -> EntitlementOutcome {
        switch error {
        case .unauthorized:
            return .unauthorized
        case .forbidden:
            return .accountMismatch("交易账号与当前账号不匹配。")
        case .server(let statusCode) where statusCode == 400:
            return .rejected(statusCode: 400, message: "无法验证 Apple 购买记录。")
        case .offline:
            return .networkFailure("网络不可用，购买记录已保留待重试。")
        case .server(let statusCode):
            return .networkFailure("服务器暂时无法确认购买记录（\(statusCode)）。")
        default:
            return .networkFailure("购买记录同步失败，已保留待重试。")
        }
    }
}
