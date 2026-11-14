import Foundation

@MainActor
protocol APITokenProvider: AnyObject {
    func accessToken() async throws -> String?
    func refreshSession() async throws -> String?
    func requestContext() async throws -> APIRequestContext?
    func refreshSession(for context: APIRequestContext) async throws -> String?
}

struct APIRequestContext: Equatable {
    let token: String
    let generation: UUID
    let loginGeneration: UUID

    init(token: String, generation: UUID, loginGeneration: UUID = UUID()) {
        self.token = token
        self.generation = generation
        self.loginGeneration = loginGeneration
    }
}

extension APITokenProvider {
    // Legacy providers cannot prove account continuity, so do not retry their 401s.
    func requestContext() async throws -> APIRequestContext? { nil }
    func refreshSession(for context: APIRequestContext) async throws -> String? { nil }
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
        try await self.request(request, fixedBearerToken: nil)
    }

    func request<T: Decodable>(_ request: URLRequest, fixedBearerToken: String) async throws -> T {
        try await self.request(request, fixedBearerToken: Optional(fixedBearerToken))
    }

    @MainActor
    func requestContext() async throws -> APIRequestContext? {
        try await tokenProvider?.requestContext()
    }

    @MainActor
    func isCurrent(_ context: APIRequestContext) async -> Bool {
        guard let current = try? await tokenProvider?.requestContext() else { return false }
        return current.generation == context.generation && current.loginGeneration == context.loginGeneration
    }

    func request<T: Decodable>(_ request: URLRequest, boundTo context: APIRequestContext) async throws -> T {
        guard let current = try await requestContext(),
              current.generation == context.generation, current.loginGeneration == context.loginGeneration else {
            throw APIClientError.unauthorized
        }
        let result: T = try await performRequest(request, fixedBearerToken: nil, boundContext: current)
        guard await isCurrent(context) else { throw APIClientError.unauthorized }
        return result
    }

    private func request<T: Decodable>(_ request: URLRequest, fixedBearerToken: String?) async throws -> T {
        try await performRequest(request, fixedBearerToken: fixedBearerToken, boundContext: nil)
    }

    private func performRequest<T: Decodable>(_ request: URLRequest, fixedBearerToken: String?, boundContext: APIRequestContext?) async throws -> T {
        var authenticated = request
        authenticated.httpShouldHandleCookies = false
        authenticated.setValue(nil, forHTTPHeaderField: "Cookie")
        authenticated.setValue(nil, forHTTPHeaderField: "Cookie2")
        authenticated.setValue("application/json", forHTTPHeaderField: "Accept")
        let token: String?
        var context: APIRequestContext?
        if let fixedBearerToken {
            token = fixedBearerToken
        } else if let boundContext {
            context = boundContext
            token = boundContext.token
        } else if let tokenProvider {
            context = try await tokenProvider.requestContext()
            if let context { token = context.token }
            else { token = try await tokenProvider.accessToken() }
        } else {
            token = nil
        }
        if let token, !token.isEmpty {
            authenticated.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await perform(authenticated)
        guard let http = response as? HTTPURLResponse else { throw APIClientError.invalidResponse }
        guard http.statusCode == 401 else { return try decode(data, response: http) }
        if fixedBearerToken != nil { throw APIClientError.unauthorized }

        guard let tokenProvider, let context else { throw APIClientError.unauthorized }
        let refreshed: String?
        do {
            refreshed = try await tokenProvider.refreshSession(for: context)
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
