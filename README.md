# NetworkingKit

![Swift 6](https://img.shields.io/badge/Swift-6.0-F05138?logo=swift&logoColor=white)
![Platforms](https://img.shields.io/badge/platforms-iOS%2017%20%7C%20macOS%2014-blue)
![SPM](https://img.shields.io/badge/SPM-compatible-brightgreen)
![License](https://img.shields.io/badge/license-MIT-lightgrey)

A small, dependency-free networking layer for Swift apps, built on async/await and Swift 6 strict concurrency.

It grew out of a generic API and pagination layer I reused across client apps, and now powers [Filmy](https://github.com/VasuChovatiya/Filmy), a TMDB movie browser.

## Features

- **Typed endpoints**: `Endpoint<Response>` carries the decode type, so call sites stay one line.
- **async/await client**: `APIClient` is `Sendable` and safe to share across tasks.
- **Retries with backoff**: exponential backoff with jitter, honours `Retry-After`, never retries POST/PATCH unless you opt in.
- **Interceptors**: bearer tokens, API-key query items and fixed headers, all async-capable.
- **Pagination**: a `Paginator` actor that merges concurrent "load more" calls, drops repeated items, and ignores stale pages after a reset.
- **Single error type**: every failure is a `NetworkError` with user-facing messages and an `isConnectivityIssue` helper.
- **Redacted logging**: `os.Logger` output with API keys and `Authorization` values masked.
- **Test helpers**: `NetworkingKitTesting.MockTransport` scripts responses and records requests.

## Installation

```swift
// Package.swift
dependencies: [
    .package(url: "https://github.com/VasuChovatiya/NetworkingKit.git", from: "1.0.0"),
],
targets: [
    .target(name: "App", dependencies: ["NetworkingKit"]),
    .testTarget(name: "AppTests", dependencies: ["NetworkingKitTesting"]),
]
```

In Xcode: **File → Add Package Dependencies…** and paste the repository URL.

## Usage

### Make a client

```swift
import NetworkingKit

let decoder = JSONDecoder()
decoder.keyDecodingStrategy = .convertFromSnakeCase

let client = APIClient(
    baseURL: URL(string: "https://api.themoviedb.org/3")!,
    interceptors: [
        BearerTokenInterceptor { try await keychain.token() },
        QueryItemInterceptor([URLQueryItem(name: "language", value: "en-IN")]),
    ],
    decoder: decoder,
    logger: NetworkLogger()          // .disabled in release builds
)
```

### Describe and send requests

```swift
struct Movie: Decodable, Sendable { let id: Int; let title: String }

let movie = try await client.send(Endpoint<Movie>.get("/movie/550"))

let results = try await client.send(
    Endpoint<MoviePage>.get("/search/movie", query: ["query": "dune", "page": "1"])
)

try await client.send(
    Endpoint<EmptyResponse>.json(.post, "/movie/550/rating", body: ["value": 9])
)
```

### Handle errors

```swift
do {
    movies = try await client.send(endpoint)
} catch NetworkError.cancelled {
    // The view went away. Nothing to show.
} catch let error as NetworkError where error.isConnectivityIssue {
    showOfflineBanner()
} catch {
    message = error.localizedDescription
}
```

### Paginate

```swift
let paginator = Paginator<Movie> { page in
    let response = try await client.send(Endpoint<MoviePage>.get("/movie/popular", query: ["page": "\(page)"]))
    return Page(items: response.results, number: response.page, totalPages: response.totalPages)
}

let snapshot = try await paginator.loadNextPage()   // call again when the list nears its end
movies = snapshot.items
canLoadMore = snapshot.hasMore
```

### Tune retries

```swift
let client = APIClient(
    baseURL: url,
    retryPolicy: RetryPolicy(maxAttempts: 4, baseDelay: .milliseconds(250), maxDelay: .seconds(4))
)
// or RetryPolicy.none
```

## Testing your code

```swift
import NetworkingKitTesting
import Testing

@Test func showsServerErrorAfterRetries() async throws {
    let transport = MockTransport(responses: [.status(503), .status(503), .status(503)])
    let client = APIClient(baseURL: url, transport: transport, sleep: { _ in })   // no real waiting

    await #expect(throws: NetworkError.httpStatus(code: 503, body: Data())) {
        try await client.send(Endpoint<Movie>.get("/movie/1"))
    }
    #expect(await transport.requestCount == 3)
}
```

## Design notes

| Decision | Why |
| --- | --- |
| `HTTPTransport` protocol instead of subclassing `URLProtocol` | One method to fake, no global registration, works with Swift Testing's parallel runs. |
| Interceptors run once per call, not per retry | A token fetched for attempt 1 is reused; retries don't hammer the Keychain or refresh endpoint. |
| `sleep` is injected | Retry tests run instantly and can assert the exact backoff sequence. |
| `Paginator` is an actor that stores its in-flight `Task` | Scroll-triggered `loadNextPage()` calls can arrive several at once; they all await the same request. |
| A generation counter in `Paginator` | After `reset()` (new search text, pull to refresh) a slow old page can't be appended to the new list. |
| Idempotent-only retries by default | Retrying a POST after a timeout can create duplicates; opt in with `retriesNonIdempotentMethods`. |

## Running the tests

```bash
swift test
```

38 tests across `RequestBuilder`, `APIClient`, `RetryPolicy`, `Paginator` and `NetworkLogger`, written with Swift Testing.

## Requirements

- Swift 6.0+ (Xcode 16+)
- iOS 17+ / macOS 14+

## License

MIT. See [LICENSE](LICENSE).
