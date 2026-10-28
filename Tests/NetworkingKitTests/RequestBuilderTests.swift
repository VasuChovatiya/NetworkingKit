import Foundation
import Testing
@testable import NetworkingKit

@Suite("RequestBuilder")
struct RequestBuilderTests {
    let builder = RequestBuilder(baseURL: URL(string: "https://api.example.com/3")!)

    @Test("joins base path and endpoint path with exactly one slash", arguments: [
        ("https://api.example.com/3", "/movie/popular"),
        ("https://api.example.com/3/", "/movie/popular"),
        ("https://api.example.com/3/", "movie/popular"),
        ("https://api.example.com/3", "movie/popular"),
    ])
    func joinsPaths(base: String, path: String) throws {
        let builder = RequestBuilder(baseURL: try #require(URL(string: base)))
        let request = try builder.makeRequest(for: Endpoint<EmptyResponse>(path: path))
        #expect(request.url?.absoluteString == "https://api.example.com/3/movie/popular")
    }

    @Test func getHelperSortsQueryItemsForStableURLs() throws {
        let request = try builder.makeRequest(for: Endpoint<EmptyResponse>.get("/search", query: ["query": "dune part two", "page": "2"]))
        #expect(request.url?.absoluteString == "https://api.example.com/3/search?page=2&query=dune%20part%20two")
        #expect(request.httpMethod == "GET")
    }

    @Test func keepsQueryItemsAlreadyOnTheBaseURL() throws {
        let builder = RequestBuilder(baseURL: URL(string: "https://api.example.com/v1?lang=en")!)
        let request = try builder.makeRequest(for: Endpoint<EmptyResponse>.get("items", query: ["page": "1"]))
        #expect(request.url?.absoluteString == "https://api.example.com/v1/items?lang=en&page=1")
    }

    @Test func endpointHeadersOverrideDefaults() throws {
        let endpoint = Endpoint<EmptyResponse>(path: "x", headers: ["Accept": "image/png", "X-Trace": "abc"])
        let request = try builder.makeRequest(for: endpoint)
        #expect(request.value(forHTTPHeaderField: "Accept") == "image/png")
        #expect(request.value(forHTTPHeaderField: "X-Trace") == "abc")
    }

    @Test func jsonEndpointEncodesBodyAndSetsContentType() throws {
        struct NewList: Encodable { let name: String }
        let endpoint = try Endpoint<EmptyResponse>.json(.post, "/list", body: NewList(name: "Weekend"))
        let request = try builder.makeRequest(for: endpoint)

        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(request.httpBody == Data(#"{"name":"Weekend"}"#.utf8))
    }

    @Test func usesEndpointTimeoutWhenSet() throws {
        let request = try builder.makeRequest(for: Endpoint<EmptyResponse>(path: "slow", timeout: 5))
        #expect(request.timeoutInterval == 5)
        let defaultRequest = try builder.makeRequest(for: Endpoint<EmptyResponse>(path: "fast"))
        #expect(defaultRequest.timeoutInterval == 30)
    }
}
