import Foundation

@MainActor
protocol APITokenProvider: AnyObject {
    func accessToken() async throws -> String?
    func refreshSession() async throws -> String?
}

enum APIClientError: Error, Equatable {
    case unauthorized
    case forbidden
    case offline
    case server(statusCode: Int)
    case invalidResponse
}

final class APIClient {
    private let session: URLSession
    private weak var tokenProvider: (any APITokenProvider)?

    init(session: URLSession = .shared, tokenProvider: any APITokenProvider) {
        self.session = session
        self.tokenProvider = tokenProvider
    }

    func request<T: Decodable>(_ request: URLRequest) async throws -> T {
        var authenticated = request
        authenticated.httpShouldHandleCookies = false
        authenticated.setValue(nil, forHTTPHeaderField: "Cookie")
        authenticated.setValue(nil, forHTTPHeaderField: "Cookie2")
        authenticated.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token = try await tokenProvider?.accessToken(), !token.isEmpty {
            authenticated.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await perform(authenticated)
        guard let http = response as? HTTPURLResponse else { throw APIClientError.invalidResponse }
        guard http.statusCode == 401 else { return try decode(data, response: http) }

        guard let tokenProvider else { throw APIClientError.unauthorized }
        let refreshed: String?
        do {
            refreshed = try await tokenProvider.refreshSession()
        } catch is URLError {
            throw APIClientError.offline
        } catch {
            throw APIClientError.unauthorized
        }
        guard let refreshed, !refreshed.isEmpty else { throw APIClientError.unauthorized }
        var retry = authenticated
        retry.setValue("Bearer \(refreshed)", forHTTPHeaderField: "Authorization")
        let (retryData, retryResponse) = try await perform(retry)
        guard let retryHTTP = retryResponse as? HTTPURLResponse else { throw APIClientError.invalidResponse }
        return try decode(retryData, response: retryHTTP)
    }

    private func perform(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do { return try await session.data(for: request) }
        catch { throw APIClientError.offline }
    }

    private func decode<T: Decodable>(_ data: Data, response: HTTPURLResponse) throws -> T {
        switch response.statusCode {
        case 200..<300: return try JSONDecoder().decode(T.self, from: data)
        case 401: throw APIClientError.unauthorized
        case 403: throw APIClientError.forbidden
        case 500...: throw APIClientError.server(statusCode: response.statusCode)
        default: throw APIClientError.server(statusCode: response.statusCode)
        }
    }
}
