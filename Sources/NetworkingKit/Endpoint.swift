import Foundation

public enum HTTPMethod: String, Sendable {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case patch = "PATCH"
    case delete = "DELETE"

    /// Methods that are safe to repeat without side effects (RFC 9110 §9.2.2).
    public var isIdempotent: Bool {
        switch self {
        case .get, .put, .delete: true
        case .post, .patch: false
        }
    }
}

/// A typed description of one API call. `Response` is what the body decodes into.
///
/// ```swift
/// let endpoint = Endpoint<[User]>.get("/users", query: ["page": "2"])
/// let users = try await client.send(endpoint)
/// ```
public struct Endpoint<Response: Decodable & Sendable>: Sendable {
    public var path: String
    public var method: HTTPMethod
    public var queryItems: [URLQueryItem]
    public var headers: [String: String]
    public var body: Data?
    /// Overrides the client's default timeout for this request.
    public var timeout: TimeInterval?

    public init(
        path: String,
        method: HTTPMethod = .get,
        queryItems: [URLQueryItem] = [],
        headers: [String: String] = [:],
        body: Data? = nil,
        timeout: TimeInterval? = nil
    ) {
        self.path = path
        self.method = method
        self.queryItems = queryItems
        self.headers = headers
        self.body = body
        self.timeout = timeout
    }
}

public extension Endpoint {
    /// A GET request. Query values are sorted by key so URLs are stable (useful for caching and tests).
    static func get(_ path: String, query: [String: String] = [:]) -> Endpoint {
        Endpoint(
            path: path,
            queryItems: query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        )
    }

    /// A request with a JSON-encoded body.
    static func json<Body: Encodable>(
        _ method: HTTPMethod,
        _ path: String,
        body: Body,
        encoder: JSONEncoder = JSONEncoder()
    ) throws -> Endpoint {
        let data: Data
        do {
            data = try encoder.encode(body)
        } catch {
            throw NetworkError.encoding(String(describing: error))
        }
        return Endpoint(
            path: path,
            method: method,
            headers: ["Content-Type": "application/json"],
            body: data
        )
    }
}

/// Use as `Endpoint<EmptyResponse>` for calls whose body you don't need (204 No Content, etc.).
public struct EmptyResponse: Decodable, Sendable, Equatable {
    public init() {}
}
