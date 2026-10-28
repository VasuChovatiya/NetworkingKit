import Foundation
import Testing
@testable import NetworkingKit

@Suite("RetryPolicy")
struct RetryPolicyTests {
    @Test func backoffDoublesAndCaps() {
        let policy = RetryPolicy(baseDelay: .milliseconds(500), maxDelay: .seconds(3), jitter: 0)
        #expect(policy.delay(afterAttempt: 1) == .milliseconds(500))
        #expect(policy.delay(afterAttempt: 2) == .seconds(1))
        #expect(policy.delay(afterAttempt: 3) == .seconds(2))
        #expect(policy.delay(afterAttempt: 4) == .seconds(3))
    }

    @Test func jitterShortensTheDelay() {
        let policy = RetryPolicy(baseDelay: .seconds(1), jitter: 1)
        #expect(policy.delay(afterAttempt: 1, random: 0) == .seconds(1))
        #expect(policy.delay(afterAttempt: 1, random: 0.5) == .milliseconds(500))
        #expect(policy.delay(afterAttempt: 1, random: 1) == .zero)
    }

    @Test func retryAfterWinsButIsCapped() {
        let policy = RetryPolicy(maxDelay: .seconds(5), jitter: 0)
        #expect(policy.delay(afterAttempt: 1, retryAfter: .seconds(2)) == .seconds(2))
        #expect(policy.delay(afterAttempt: 1, retryAfter: .seconds(60)) == .seconds(5))
    }

    @Test func parsesRetryAfterSeconds() throws {
        let url = URL(string: "https://example.com")!
        let response = try #require(HTTPURLResponse(url: url, statusCode: 429, httpVersion: nil, headerFields: ["Retry-After": " 7 "]))
        #expect(RetryPolicy.retryAfter(from: response) == .seconds(7))

        let dateForm = try #require(HTTPURLResponse(
            url: url, statusCode: 429, httpVersion: nil, headerFields: ["Retry-After": "Wed, 21 Oct 2026 07:28:00 GMT"]
        ))
        #expect(RetryPolicy.retryAfter(from: dateForm) == nil)
    }

    @Test func decidesWhatIsRetryable() {
        let policy = RetryPolicy.default
        #expect(policy.shouldRetry(.httpStatus(code: 503, body: Data()), method: .get, attempt: 1))
        #expect(policy.shouldRetry(.transport(.timedOut), method: .get, attempt: 1))
        #expect(!policy.shouldRetry(.httpStatus(code: 404, body: Data()), method: .get, attempt: 1))
        #expect(!policy.shouldRetry(.transport(.notConnectedToInternet), method: .get, attempt: 1))
        #expect(!policy.shouldRetry(.decoding("x"), method: .get, attempt: 1))
        #expect(!policy.shouldRetry(.cancelled, method: .get, attempt: 1))
        #expect(!policy.shouldRetry(.httpStatus(code: 503, body: Data()), method: .get, attempt: 3))
        #expect(!policy.shouldRetry(.httpStatus(code: 503, body: Data()), method: .post, attempt: 1))
    }

    @Test func noneNeverRetries() {
        #expect(!RetryPolicy.none.shouldRetry(.httpStatus(code: 503, body: Data()), method: .get, attempt: 1))
    }
}
