import Foundation

/// Turns an `Endpoint` into a `URLRequest` against a base URL.
public struct RequestBuilder: Sendable {
    public let baseURL: URL
    public var defaultHeaders: [String: String]
    public var defaultTimeout: TimeInterval

    public init(baseURL: URL, defaultHeaders: [String: String] = ["Accept": "application/json"], defaultTimeout: TimeInterval = 30) {
        self.baseURL = baseURL
        self.defaultHeaders = defaultHeaders
        self.defaultTimeout = defaultTimeout
    }

    public func makeRequest<Response>(for endpoint: Endpoint<Response>) throws -> URLRequest {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw NetworkError.invalidURL(baseURL.absoluteString)
        }

        // Join paths by hand: `appendingPathComponent` percent-encodes "?" and keeps double slashes.
        let basePath = components.path.hasSuffix("/") ? String(components.path.dropLast()) : components.path
        let endpointPath = endpoint.path.hasPrefix("/") ? String(endpoint.path.dropFirst()) : endpoint.path
        components.path = endpointPath.isEmpty ? basePath : basePath + "/" + endpointPath

        let queryItems = (components.queryItems ?? []) + endpoint.queryItems
        components.queryItems = queryItems.isEmpty ? nil : queryItems

        guard let url = components.url else {
            throw NetworkError.invalidURL(baseURL.absoluteString + "/" + endpointPath)
        }

        var request = URLRequest(url: url, timeoutInterval: endpoint.timeout ?? defaultTimeout)
        request.httpMethod = endpoint.method.rawValue
        request.httpBody = endpoint.body
        for (field, value) in defaultHeaders.merging(endpoint.headers, uniquingKeysWith: { _, endpointValue in endpointValue }) {
            request.setValue(value, forHTTPHeaderField: field)
        }
        return request
    }
}
