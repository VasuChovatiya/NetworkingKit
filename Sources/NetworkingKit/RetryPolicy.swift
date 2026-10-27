import Foundation

/// When and how long to wait before retrying a failed request.
///
/// Uses exponential backoff with optional jitter, honours `Retry-After`, and by default only retries
/// idempotent methods so a flaky POST never creates a duplicate.
public struct RetryPolicy: Sendable {
    /// Total attempts including the first one. `1` disables retries.
    public var maxAttempts: Int
    public var baseDelay: Duration
    public var maxDelay: Duration
    /// 0 = exact exponential delays, 1 = anywhere between 0 and the exponential delay ("full jitter").
    public var jitter: Double
    public var retryableStatusCodes: Set<Int>
    public var retryableURLErrorCodes: Set<URLError.Code>
    public var retriesNonIdempotentMethods: Bool

    public init(
        maxAttempts: Int = 3,
        baseDelay: Duration = .milliseconds(500),
        maxDelay: Duration = .seconds(8),
        jitter: Double = 0.5,
        retryableStatusCodes: Set<Int> = [408, 429, 500, 502, 503, 504],
        retryableURLErrorCodes: Set<URLError.Code> = [.timedOut, .networkConnectionLost, .cannotConnectToHost, .dnsLookupFailed],
        retriesNonIdempotentMethods: Bool = false
    ) {
        self.maxAttempts = max(1, maxAttempts)
        self.baseDelay = baseDelay
        self.maxDelay = maxDelay
        self.jitter = min(max(jitter, 0), 1)
        self.retryableStatusCodes = retryableStatusCodes
        self.retryableURLErrorCodes = retryableURLErrorCodes
        self.retriesNonIdempotentMethods = retriesNonIdempotentMethods
    }

    public static let `default` = RetryPolicy()
    public static let none = RetryPolicy(maxAttempts: 1)

    /// `attempt` is the 1-based number of the attempt that just failed.
    public func shouldRetry(_ error: NetworkError, method: HTTPMethod, attempt: Int) -> Bool {
        guard attempt < maxAttempts else { return false }
        guard method.isIdempotent || retriesNonIdempotentMethods else { return false }
        switch error {
        case .httpStatus(let code, _): return retryableStatusCodes.contains(code)
        case .transport(let code): return retryableURLErrorCodes.contains(code)
        default: return false
        }
    }

    /// Delay before the attempt after `attempt`. A server-sent `Retry-After` wins (capped at `maxDelay`).
    /// `random` is injectable so tests are deterministic.
    public func delay(afterAttempt attempt: Int, retryAfter: Duration? = nil, random: Double = .random(in: 0...1)) -> Duration {
        if let retryAfter {
            return min(retryAfter, maxDelay)
        }
        let exponential = baseDelay * (1 << max(0, attempt - 1))
        let capped = min(exponential, maxDelay)
        return capped * (1 - jitter * random)
    }
}

extension RetryPolicy {
    /// Parses `Retry-After` in its delta-seconds form. The HTTP-date form is rare for APIs and ignored.
    static func retryAfter(from response: HTTPURLResponse) -> Duration? {
        guard let value = response.value(forHTTPHeaderField: "Retry-After"),
              let seconds = Int(value.trimmingCharacters(in: .whitespaces)), seconds >= 0 else { return nil }
        return .seconds(seconds)
    }
}
