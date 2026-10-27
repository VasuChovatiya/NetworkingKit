import Foundation
import Testing
@testable import NetworkingKit

private struct Item: Identifiable, Sendable, Equatable {
    let id: Int
}

/// A fake paged API: 3 pages of 2 items; counts calls and can hold a page until released.
private actor FakePagedAPI {
    private(set) var requestedPages: [Int] = []
    private var gate: CheckedContinuation<Void, Never>?
    private var holdNextRequest = false
    var pages: [Int: [Int]] = [1: [1, 2], 2: [3, 4], 3: [5, 6]]
    var totalPages = 3

    func setPage(_ number: Int, ids: [Int]) { pages[number] = ids }
    func hold() { holdNextRequest = true }
    func release() { gate?.resume(); gate = nil }
    var isHolding: Bool { gate != nil }

    func fetch(_ page: Int) async -> Page<Item> {
        requestedPages.append(page)
        if holdNextRequest {
            holdNextRequest = false
            await withCheckedContinuation { gate = $0 }
        }
        return Page(items: (pages[page] ?? []).map(Item.init), number: page, totalPages: totalPages)
    }
}

/// Polls until the condition holds; keeps tests deterministic without fixed sleeps.
private func waitUntil(_ condition: @Sendable () async -> Bool) async {
    for _ in 0..<1000 where !(await condition()) {
        await Task.yield()
    }
}

@Suite("Paginator")
struct PaginatorTests {
    @Test func loadsPagesInOrderUntilTheEnd() async throws {
        let api = FakePagedAPI()
        let paginator = Paginator<Item> { await api.fetch($0) }

        var snapshot = try await paginator.loadNextPage()
        #expect(snapshot.items.map(\.id) == [1, 2])
        #expect(snapshot.hasMore)

        try await paginator.loadNextPage()
        snapshot = try await paginator.loadNextPage()
        #expect(snapshot.items.map(\.id) == [1, 2, 3, 4, 5, 6])
        #expect(!snapshot.hasMore)
        #expect(snapshot.pagesLoaded == 3)

        // Past the last page: no further request.
        try await paginator.loadNextPage()
        #expect(await api.requestedPages == [1, 2, 3])
    }

    @Test func dropsItemsRepeatedAcrossPages() async throws {
        let api = FakePagedAPI()
        await api.setPage(2, ids: [2, 3])
        let paginator = Paginator<Item> { await api.fetch($0) }

        try await paginator.loadNextPage()
        let snapshot = try await paginator.loadNextPage()
        #expect(snapshot.items.map(\.id) == [1, 2, 3])
    }

    @Test func anEmptyPageEndsPagination() async throws {
        let api = FakePagedAPI()
        await api.setPage(2, ids: [])
        let paginator = Paginator<Item> { await api.fetch($0) }

        try await paginator.loadNextPage()
        let snapshot = try await paginator.loadNextPage()
        #expect(!snapshot.hasMore)
    }

    @Test func concurrentCallsShareOneRequest() async throws {
        let api = FakePagedAPI()
        await api.hold()
        let paginator = Paginator<Item> { await api.fetch($0) }

        async let first = paginator.loadNextPage()
        async let second = paginator.loadNextPage()
        await waitUntil { await api.isHolding }
        await api.release()

        let (a, b) = try await (first, second)
        #expect(a.items.map(\.id) == [1, 2])
        #expect(b.items.map(\.id) == [1, 2])
        #expect(await api.requestedPages == [1])
    }

    @Test func resetDiscardsAStaleInFlightPage() async throws {
        let api = FakePagedAPI()
        await api.hold()
        let paginator = Paginator<Item> { await api.fetch($0) }

        let stale = Task { try await paginator.loadNextPage() }
        await waitUntil { await api.isHolding }
        await paginator.reset()
        await api.release()

        await #expect(throws: CancellationError.self) { try await stale.value }
        #expect(await paginator.snapshot.items.isEmpty)

        let fresh = try await paginator.loadNextPage()
        #expect(fresh.items.map(\.id) == [1, 2])
    }

    @Test func aFailedPageCanBeRetried() async throws {
        struct Boom: Error {}
        let attempts = Counter()
        let paginator = Paginator<Item> { page in
            if await attempts.increment() == 1 { throw Boom() }
            return Page(items: [Item(id: page)], number: page, totalPages: 2)
        }

        await #expect(throws: Boom.self) { try await paginator.loadNextPage() }
        let snapshot = try await paginator.loadNextPage()
        #expect(snapshot.items.map(\.id) == [1])
    }
}

private actor Counter {
    private var value = 0
    func increment() -> Int { value += 1; return value }
}
