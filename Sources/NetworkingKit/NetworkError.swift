import Foundation

/// Every error `APIClient` throws is a `NetworkError`, so callers can switch over one type.
public enum NetworkError: Error, Sendable, Equatable {
    /// The base URL and endpoint path didn't form a valid URL.
    case invalidURL(String)
    /// The request never got an HTTP response (offline, timeout, DNS, TLS...).
    case transport(URLError.Code)
    /// The response wasn't an `HTTPURLResponse`.
    case invalidResponse
    /// The server answered with a non-2xx status.
    case httpStatus(code: Int, body: Data)
    /// The body didn't match the expected `Decodable` type.
    case decoding(String)
    /// The request body couldn't be encoded.
    case encoding(String)
    /// The task was cancelled. Never retried, and usually not shown to the user.
    case cancelled

    public var statusCode: Int? {
        if case let .httpStatus(code, _) = self { code } else { nil }
    }

    /// True for offline-style failures where "check your connection" is the right message.
    public var isConnectivityIssue: Bool {
        guard case let .transport(code) = self else { return false }
        return [.notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotFindHost, .cannotConnectToHost, .dataNotAllowed]
            .contains(code)
    }
}

extension NetworkError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidURL(let url):
            "The request URL is invalid: \(url)"
        case .transport where isConnectivityIssue:
            "You appear to be offline. Check your connection and try again."
        case .transport(let code):
            "The request failed (\(code.rawValue))."
        case .invalidResponse:
            "The server sent an unexpected response."
        case .httpStatus(let code, _) where code == 401:
            "The request was not authorised. Check the API key."
        case .httpStatus(let code, _) where code == 404:
            "The requested item could not be found."
        case .httpStatus(let code, _) where code == 429:
            "Too many requests. Please wait a moment and try again."
        case .httpStatus(let code, _) where (500...599).contains(code):
            "The server is having trouble (\(code)). Please try again later."
        case .httpStatus(let code, _):
            "The request failed with status \(code)."
        case .decoding:
            "The server response could not be read."
        case .encoding:
            "The request could not be prepared."
        case .cancelled:
            "The request was cancelled."
        }
    }
}
