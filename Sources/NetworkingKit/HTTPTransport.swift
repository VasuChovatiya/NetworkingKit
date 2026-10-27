import Foundation

/// The single seam between `APIClient` and the network.
///
/// `URLSession` conforms out of the box. Tests swap in `MockTransport` (from `NetworkingKitTesting`);
/// apps can plug in an offline fixture transport for demos or UI tests.
public protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: HTTPTransport {
    public func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
        try await data(for: request)
    }
}
