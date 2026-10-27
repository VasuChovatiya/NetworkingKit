import Foundation
import Testing
@testable import NetworkingKit
import NetworkingKitTesting

private struct Movie: Decodable, Sendable, Equatable {
    let id: Int
    let title: String
}

/// Records requested delays instead of sleeping, so retry tests run instantly.
private actor SleepRecorder {
    private(set) var delays: [Duration] = []
    func record(_ delay: Duration) { delays.append(delay) }
}

@Suite("APIClient")
struct APIClientTests {
    let baseURL = URL(string: "https://api.example.com/3")!

    private func makeClient(
        _ transport: MockTransport,
        interceptors: [any RequestInterceptor] = [],
        retryPolicy: RetryPolicy = RetryPolicy(jitter: 0),
        recorder: SleepRecorder = SleepRecorder()
    ) -> APIClient {
        APIClient(baseURL: baseURL, transport: transport, interceptors: interceptors, retryPolicy: retryPolicy) { delay in
            await recorder.record(delay)
        }
    }

    // MARK: - Decoding

    @Test func decodesA2xxResponse() async throws {
        let transport = MockTransport(responses: [.json(#"{"id": 550, "title": "Fight Club"}"#)])
        let movie = try await makeClient(transport).send(Endpoint<Movie>.get("/movie/550"))
        #expect(movie == Movie(id: 550, title: "Fight Club"))
    }

    @Test func usesTheInjectedDecoder() async throws {
        struct Show: Decodable, Sendable { let firstAirDate: String }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let transport = MockTransport(responses: [.json(#"{"first_air_date": "2008-01-20"}"#)])
        let client = APIClient(baseURL: baseURL, transport: transport, decoder: decoder)

        let show = try await client.send(Endpoint<Show>.get("/tv/1396"))
        #expect(show.firstAirDate == "2008-01-20")
    }

    @Test func reportsWhereDecodingFailed() async throws {
        let transport = MockTransport(responses: [.json(#"{"id": 1}"#)])
        let error = await #expect(throws: NetworkError.self) {
            try await makeClient(transport).send(Endpoint<Movie>.get("/movie/1"))
        }
        #expect(error == .decoding("keyNotFound 'title' at "))
    }

    @Test func emptyResponseAcceptsAnEmptyBody() async throws {
        let transport = MockTransport(responses: [.status(204)])
        let result = try await makeClient(transport).send(Endpoint<EmptyResponse>(path: "/rating", method: .delete))
        #expect(result == EmptyResponse())
    }

    // MARK: - Status codes and transport errors

    @Test func mapsNon2xxToHTTPStatusWithBody() async throws {
        let body = #"{"status_message": "Not found"}"#
        let transport = MockTransport(responses: [.json(body, status: 404)])
        let error = await #expect(throws: NetworkError.self) {
            try await makeClient(transport).send(Endpoint<Movie>.get("/movie/0"))
        }
        #expect(error == .httpStatus(code: 404, body: Data(body.utf8)))
        #expect(error?.statusCode == 404)
    }

    @Test func mapsURLErrorsToTransportErrors() async throws {
        let transport = MockTransport(responses: [.urlError(.notConnectedToInternet)])
        let error = await #expect(throws: NetworkError.self) {
            try await makeClient(transport).send(Endpoint<Movie>.get("/movie/1"))
        }
        #expect(error == .transport(.notConnectedToInternet))
        #expect(error?.isConnectivityIssue == true)
    }

    @Test func urlSessionCancellationBecomesCancelled() async throws {
        let transport = MockTransport(responses: [.urlError(.cancelled)])
        let error = await #expect(throws: NetworkError.self) {
            try await makeClient(transport).send(Endpoint<Movie>.get("/movie/1"))
        }
        #expect(error == .cancelled)
        #expect(await transport.requestCount == 1)
    }

    // MARK: - Retries

    @Test func retriesA503ThenSucceeds() async throws {
        let recorder = SleepRecorder()
        let transport = MockTransport(responses: [.status(503), .status(502), .json(#"{"id": 1, "title": "Up"}"#)])
        let movie = try await makeClient(transport, recorder: recorder).send(Endpoint<Movie>.get("/movie/1"))

        #expect(movie.title == "Up")
        #expect(await transport.requestCount == 3)
        #expect(await recorder.delays == [.milliseconds(500), .milliseconds(1000)])
    }

    @Test func stopsAfterMaxAttempts() async throws {
        let transport = MockTransport(responses: [.status(500), .status(500), .status(500)])
        let error = await #expect(throws: NetworkError.self) {
            try await makeClient(transport).send(Endpoint<Movie>.get("/movie/1"))
        }
        #expect(error?.statusCode == 500)
        #expect(await transport.requestCount == 3)
    }

    @Test func doesNotRetryClientErrors() async throws {
        let transport = MockTransport(responses: [.status(401)])
        _ = await #expect(throws: NetworkError.self) {
            try await makeClient(transport).send(Endpoint<Movie>.get("/movie/1"))
        }
        #expect(await transport.requestCount == 1)
    }

    @Test func doesNotRetryNonIdempotentMethodsByDefault() async throws {
        let transport = MockTransport(responses: [.status(503)])
        _ = await #expect(throws: NetworkError.self) {
            try await makeClient(transport).send(Endpoint<EmptyResponse>(path: "/rating", method: .post))
        }
        #expect(await transport.requestCount == 1)
    }

    @Test func honoursRetryAfterHeader() async throws {
        let recorder = SleepRecorder()
        let transport = MockTransport(responses: [.status(429, headers: ["Retry-After": "2"]), .json(#"{"id": 1, "title": "Up"}"#)])
        _ = try await makeClient(transport, recorder: recorder).send(Endpoint<Movie>.get("/movie/1"))
        #expect(await recorder.delays == [.seconds(2)])
    }

    @Test func retriesTimeouts() async throws {
        let transport = MockTransport(responses: [.urlError(.timedOut), .json(#"{"id": 1, "title": "Up"}"#)])
        let movie = try await makeClient(transport).send(Endpoint<Movie>.get("/movie/1"))
        #expect(movie.id == 1)
        #expect(await transport.requestCount == 2)
    }

    @Test func cancellationDuringBackoffStopsRetrying() async throws {
        let transport = MockTransport(responses: [.status(503), .json(#"{"id": 1, "title": "Up"}"#)])
        let client = APIClient(baseURL: baseURL, transport: transport, retryPolicy: RetryPolicy(jitter: 0)) { _ in
            throw CancellationError()
        }
        let error = await #expect(throws: NetworkError.self) {
            try await client.send(Endpoint<Movie>.get("/movie/1"))
        }
        #expect(error == .cancelled)
        #expect(await transport.requestCount == 1)
    }

    // MARK: - Interceptors

    @Test func runsInterceptorsInOrderOncePerCall() async throws {
        let transport = MockTransport(responses: [.status(503), .json(#"{"id": 1, "title": "Up"}"#)])
        let client = makeClient(transport, interceptors: [
            BearerTokenInterceptor(token: "secret"),
            QueryItemInterceptor([URLQueryItem(name: "language", value: "en-IN")]),
            HeaderInterceptor(["Authorization": "ignored because already set"]),
        ])
        _ = try await client.send(Endpoint<Movie>.get("/movie/1"))

        let requests = await transport.requests
        #expect(requests.count == 2)
        for request in requests {
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer secret")
            #expect(request.url?.absoluteString == "https://api.example.com/3/movie/1?language=en-IN")
        }
    }

    @Test func queryInterceptorDoesNotOverrideEndpointValues() async throws {
        let transport = MockTransport(responses: [.json(#"{"id": 1, "title": "Up"}"#)])
        let client = makeClient(transport, interceptors: [QueryItemInterceptor([URLQueryItem(name: "page", value: "1")])])
        _ = try await client.send(Endpoint<Movie>.get("/popular", query: ["page": "4"]))
        #expect(await transport.requests.first?.url?.query == "page=4")
    }

    @Test func bearerInterceptorSkipsMissingToken() async throws {
        let transport = MockTransport(responses: [.json(#"{"id": 1, "title": "Up"}"#)])
        let client = makeClient(transport, interceptors: [BearerTokenInterceptor { nil }])
        _ = try await client.send(Endpoint<Movie>.get("/movie/1"))
        #expect(await transport.requests.first?.value(forHTTPHeaderField: "Authorization") == nil)
    }
}
