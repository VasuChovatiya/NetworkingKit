import Foundation

/// An async/await HTTP client: builds requests, runs interceptors, retries with backoff,
/// validates the status code and decodes JSON. Safe to share across tasks.
///
/// ```swift
/// let client = APIClient(
///     baseURL: URL(string: "https://api.example.com/v1")!,
///     interceptors: [BearerTokenInterceptor(token: token)]
/// )
/// let user: User = try await client.send(.get("/me"))
/// ```
public final class APIClient: Sendable {
    public typealias Sleep = @Sendable (Duration) async throws -> Void

    public let builder: RequestBuilder
    private let transport: any HTTPTransport
    private let interceptors: [any RequestInterceptor]
    private let retryPolicy: RetryPolicy
    private let decoder: JSONDecoder
    private let logger: NetworkLogger
    private let sleep: Sleep

    public init(
        baseURL: URL,
        transport: any HTTPTransport = URLSession.shared,
        interceptors: [any RequestInterceptor] = [],
        retryPolicy: RetryPolicy = .default,
        decoder: JSONDecoder = JSONDecoder(),
        logger: NetworkLogger = .disabled,
        defaultHeaders: [String: String] = ["Accept": "application/json"],
        sleep: @escaping Sleep = { try await Task.sleep(for: $0) }
    ) {
        self.builder = RequestBuilder(baseURL: baseURL, defaultHeaders: defaultHeaders)
        self.transport = transport
        self.interceptors = interceptors
        self.retryPolicy = retryPolicy
        self.decoder = decoder
        self.logger = logger
        self.sleep = sleep
    }

    /// Sends the request and decodes the body into `Response`.
    public func send<Response>(_ endpoint: Endpoint<Response>) async throws -> Response {
        let data = try await data(for: endpoint)
        if Response.self == EmptyResponse.self, data.isEmpty, let empty = EmptyResponse() as? Response {
            return empty
        }
        do {
            return try decoder.decode(Response.self, from: data)
        } catch let error as DecodingError {
            throw NetworkError.decoding(Self.describe(error))
        } catch {
            throw NetworkError.decoding(String(describing: error))
        }
    }

    /// Sends the request and returns the raw body of a 2xx response.
    public func data<Response>(for endpoint: Endpoint<Response>) async throws -> Data {
        var request = try builder.makeRequest(for: endpoint)
        do {
            for interceptor in interceptors {
                request = try await interceptor.adapt(request)
            }
        } catch is CancellationError {
            throw NetworkError.cancelled
        }

        var attempt = 1
        while true {
            if Task.isCancelled { throw NetworkError.cancelled }
            logger.logRequest(request, attempt: attempt)

            switch await perform(request) {
            case .success(let data):
                return data
            case .failure(let error, let retryAfter):
                guard retryPolicy.shouldRetry(error, method: endpoint.method, attempt: attempt) else {
                    logger.logFailure(error, request: request)
                    throw error
                }
                do {
                    try await sleep(retryPolicy.delay(afterAttempt: attempt, retryAfter: retryAfter))
                } catch {
                    throw NetworkError.cancelled
                }
                attempt += 1
            }
        }
    }

    // MARK: - Private

    private enum Outcome {
        case success(Data)
        case failure(NetworkError, retryAfter: Duration?)
    }

    private func perform(_ request: URLRequest) async -> Outcome {
        let clock = ContinuousClock()
        let start = clock.now
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await transport.send(request)
        } catch is CancellationError {
            return .failure(.cancelled, retryAfter: nil)
        } catch let error as URLError {
            return .failure(error.code == .cancelled ? .cancelled : .transport(error.code), retryAfter: nil)
        } catch let error as NetworkError {
            return .failure(error, retryAfter: nil)
        } catch {
            return .failure(.transport(.unknown), retryAfter: nil)
        }

        guard let http = response as? HTTPURLResponse else {
            return .failure(.invalidResponse, retryAfter: nil)
        }
        logger.logResponse(http, bytes: data.count, duration: clock.now - start)

        guard (200...299).contains(http.statusCode) else {
            return .failure(.httpStatus(code: http.statusCode, body: data), retryAfter: RetryPolicy.retryAfter(from: http))
        }
        return .success(data)
    }

    /// "keyNotFound 'title' at results[3]" reads better in logs than the default dump.
    private static func describe(_ error: DecodingError) -> String {
        func path(_ codingPath: [any CodingKey]) -> String {
            codingPath.map { $0.intValue.map { "[\($0)]" } ?? ".\($0.stringValue)" }.joined().trimmingCharacters(in: ["."])
        }
        switch error {
        case .keyNotFound(let key, let context):
            return "keyNotFound '\(key.stringValue)' at \(path(context.codingPath))"
        case .typeMismatch(let type, let context):
            return "typeMismatch \(type) at \(path(context.codingPath))"
        case .valueNotFound(let type, let context):
            return "valueNotFound \(type) at \(path(context.codingPath))"
        case .dataCorrupted(let context):
            return "dataCorrupted at \(path(context.codingPath)): \(context.debugDescription)"
        @unknown default:
            return String(describing: error)
        }
    }
}
