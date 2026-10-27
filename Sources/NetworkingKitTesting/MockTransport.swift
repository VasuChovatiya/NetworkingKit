import Foundation
import NetworkingKit

/// A scripted `HTTPTransport` for tests. Returns queued responses in order (or asks a handler)
/// and records every request it receives.
///
/// ```swift
/// let transport = MockTransport(responses: [.status(503), .json(#"{"id": 1}"#)])
/// let client = APIClient(baseURL: url, transport: transport, sleep: { _ in })
/// ```
public actor MockTransport: HTTPTransport {
    public enum Response: Sendable {
        case http(status: Int, body: Data, headers: [String: String])
        case failure(any Error)

        public static func json(_ string: String, status: Int = 200, headers: [String: String] = [:]) -> Response {
            .http(status: status, body: Data(string.utf8), headers: headers.merging(["Content-Type": "application/json"]) { a, _ in a })
        }

        public static func json<T: Encodable>(encoding value: T, status: Int = 200, encoder: JSONEncoder = JSONEncoder()) throws -> Response {
            .http(status: status, body: try encoder.encode(value), headers: ["Content-Type": "application/json"])
        }

        public static func status(_ code: Int, headers: [String: String] = [:]) -> Response {
            .http(status: code, body: Data(), headers: headers)
        }

        public static func urlError(_ code: URLError.Code) -> Response {
            .failure(URLError(code))
        }
    }

    public typealias Handler = @Sendable (URLRequest) async throws -> Response

    private var queue: [Response]
    private let handler: Handler?
    public private(set) var requests: [URLRequest] = []

    public init(responses: [Response]) {
        self.queue = responses
        self.handler = nil
    }

    public init(handler: @escaping Handler) {
        self.queue = []
        self.handler = handler
    }

    public func enqueue(_ response: Response) {
        queue.append(response)
    }

    public var requestCount: Int { requests.count }

    public func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
        requests.append(request)

        let response: Response
        if let handler {
            response = try await handler(request)
        } else if !queue.isEmpty {
            response = queue.removeFirst()
        } else {
            preconditionFailure("MockTransport ran out of responses for \(request.url?.absoluteString ?? "?")")
        }

        switch response {
        case .failure(let error):
            throw error
        case .http(let status, let body, let headers):
            let url = request.url ?? URL(string: "about:blank")!
            let http = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
            return (body, http)
        }
    }
}
