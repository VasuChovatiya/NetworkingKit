import Foundation
import os

/// Logs requests and responses to the unified log, with secrets redacted.
///
/// View in Console.app or Xcode with subsystem `NetworkingKit`.
public struct NetworkLogger: Sendable {
    public var isEnabled: Bool
    /// Query item names whose values are replaced with `<redacted>` (case-insensitive).
    public var redactedQueryItems: Set<String>
    /// Header names whose values are replaced with `<redacted>` (case-insensitive).
    public var redactedHeaders: Set<String>

    private static let log = Logger(subsystem: "NetworkingKit", category: "HTTP")

    public init(
        isEnabled: Bool = true,
        redactedQueryItems: Set<String> = ["api_key", "apikey", "key", "token", "access_token"],
        redactedHeaders: Set<String> = ["Authorization", "Cookie", "X-Api-Key"]
    ) {
        self.isEnabled = isEnabled
        self.redactedQueryItems = Set(redactedQueryItems.map { $0.lowercased() })
        self.redactedHeaders = Set(redactedHeaders.map { $0.lowercased() })
    }

    public static let disabled = NetworkLogger(isEnabled: false)

    func logRequest(_ request: URLRequest, attempt: Int) {
        guard isEnabled else { return }
        let method = request.httpMethod ?? "GET"
        let url = request.url.map(redacted) ?? "<no url>"
        let suffix = attempt > 1 ? " (attempt \(attempt))" : ""
        Self.log.debug("→ \(method, privacy: .public) \(url, privacy: .public)\(suffix, privacy: .public)")
    }

    func logResponse(_ response: HTTPURLResponse, bytes: Int, duration: Duration) {
        guard isEnabled else { return }
        let url = response.url.map(redacted) ?? "<no url>"
        let ms = Int(duration / .milliseconds(1))
        Self.log.debug("← \(response.statusCode) \(url, privacy: .public) \(ms)ms \(bytes)B")
    }

    func logFailure(_ error: NetworkError, request: URLRequest) {
        guard isEnabled else { return }
        let url = request.url.map(redacted) ?? "<no url>"
        Self.log.error("✕ \(url, privacy: .public) \(String(describing: error), privacy: .public)")
    }

    /// The URL as a string with sensitive query values hidden.
    public func redacted(_ url: URL) -> String {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let items = components.queryItems else { return url.absoluteString }
        components.queryItems = items.map { item in
            redactedQueryItems.contains(item.name.lowercased()) ? URLQueryItem(name: item.name, value: "<redacted>") : item
        }
        // Keep the angle brackets readable instead of percent-encoded.
        return (components.url?.absoluteString ?? url.absoluteString)
            .replacingOccurrences(of: "%3Credacted%3E", with: "<redacted>")
    }

    /// Request headers with sensitive values hidden.
    public func redactedHeaders(of request: URLRequest) -> [String: String] {
        (request.allHTTPHeaderFields ?? [:]).reduce(into: [:]) { result, header in
            result[header.key] = redactedHeaders.contains(header.key.lowercased()) ? "<redacted>" : header.value
        }
    }
}
