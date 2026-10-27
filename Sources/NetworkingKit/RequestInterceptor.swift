import Foundation

/// Adapts every outgoing request before it is sent: auth, API keys, locale, tracing headers.
/// Interceptors run in the order they are passed to `APIClient`, once per call (not per retry).
public protocol RequestInterceptor: Sendable {
    func adapt(_ request: URLRequest) async throws -> URLRequest
}

/// Adds fixed headers. Existing values on the request win, so an endpoint can override them.
public struct HeaderInterceptor: RequestInterceptor {
    public let headers: [String: String]

    public init(_ headers: [String: String]) {
        self.headers = headers
    }

    public func adapt(_ request: URLRequest) async throws -> URLRequest {
        var request = request
        for (field, value) in headers where request.value(forHTTPHeaderField: field) == nil {
            request.setValue(value, forHTTPHeaderField: field)
        }
        return request
    }
}

/// Adds `Authorization: Bearer <token>`. The provider is async so a token can come from the Keychain
/// or a refresh call; returning `nil` sends the request without the header.
public struct BearerTokenInterceptor: RequestInterceptor {
    private let tokenProvider: @Sendable () async throws -> String?

    public init(tokenProvider: @escaping @Sendable () async throws -> String?) {
        self.tokenProvider = tokenProvider
    }

    public init(token: String) {
        self.init { token }
    }

    public func adapt(_ request: URLRequest) async throws -> URLRequest {
        guard let token = try await tokenProvider(), !token.isEmpty else { return request }
        var request = request
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return request
    }
}

/// Appends query items to every request (e.g. `api_key`, `language`). Items already on the URL win.
public struct QueryItemInterceptor: RequestInterceptor {
    public let items: [URLQueryItem]

    public init(_ items: [URLQueryItem]) {
        self.items = items
    }

    public func adapt(_ request: URLRequest) async throws -> URLRequest {
        guard let url = request.url, var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return request
        }
        var queryItems = components.queryItems ?? []
        let existing = Set(queryItems.map(\.name))
        queryItems += items.filter { !existing.contains($0.name) }
        components.queryItems = queryItems.isEmpty ? nil : queryItems

        var request = request
        request.url = components.url ?? url
        return request
    }
}
