import Foundation
import Testing
@testable import NetworkingKit

@Suite("NetworkLogger")
struct NetworkLoggerTests {
    let logger = NetworkLogger()

    @Test func redactsSecretQueryValues() {
        let url = URL(string: "https://api.example.com/3/movie/1?api_key=abc123&language=en&Token=xyz")!
        #expect(logger.redacted(url) == "https://api.example.com/3/movie/1?api_key=<redacted>&language=en&Token=<redacted>")
    }

    @Test func leavesURLsWithoutSecretsAlone() {
        let url = URL(string: "https://api.example.com/3/search?query=up")!
        #expect(logger.redacted(url) == url.absoluteString)
    }

    @Test func redactsSecretHeaders() {
        var request = URLRequest(url: URL(string: "https://api.example.com")!)
        request.setValue("Bearer secret", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let headers = logger.redactedHeaders(of: request)
        #expect(headers["Authorization"] == "<redacted>")
        #expect(headers["Accept"] == "application/json")
    }
}
