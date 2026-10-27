import Foundation

/// One page of results from a paginated API.
public struct Page<Item: Sendable>: Sendable {
    public let items: [Item]
    /// 1-based page number this result belongs to.
    public let number: Int
    public let totalPages: Int

    public init(items: [Item], number: Int, totalPages: Int) {
        self.items = items
        self.number = number
        self.totalPages = totalPages
    }

    public var hasMore: Bool { number < totalPages }
}

/// What a screen needs to render a paginated list.
public struct PaginationSnapshot<Item: Sendable>: Sendable {
    public let items: [Item]
    public let hasMore: Bool
    public let pagesLoaded: Int
}

/// Loads pages one after another and accumulates the items.
///
/// - Concurrent `loadNextPage()` calls share one request, so a fast-scrolling list can't fire duplicates.
/// - Items whose `id` was already seen are dropped (APIs often repeat items across pages when data shifts).
/// - `reset()` discards an in-flight page so a stale response can't land in a fresh list.
public actor Paginator<Item: Identifiable & Sendable> where Item.ID: Sendable {
    public typealias Fetch = @Sendable (_ page: Int) async throws -> Page<Item>

    private let firstPage: Int
    private let fetch: Fetch
    private var items: [Item] = []
    private var seenIDs: Set<Item.ID> = []
    private var nextPage: Int
    private var hasMore = true
    private var pagesLoaded = 0
    private var generation = 0
    private var inFlight: Task<PaginationSnapshot<Item>, any Error>?

    public init(firstPage: Int = 1, fetch: @escaping Fetch) {
        self.firstPage = firstPage
        self.nextPage = firstPage
        self.fetch = fetch
    }

    public var snapshot: PaginationSnapshot<Item> {
        PaginationSnapshot(items: items, hasMore: hasMore, pagesLoaded: pagesLoaded)
    }

    /// Fetches the next page if there is one. Throws `CancellationError` if `reset()` ran meanwhile.
    @discardableResult
    public func loadNextPage() async throws -> PaginationSnapshot<Item> {
        if let inFlight {
            return try await inFlight.value
        }
        guard hasMore else { return snapshot }

        let task = Task { [nextPage, generation] in
            try await self.fetchAndApply(page: nextPage, generation: generation)
        }
        inFlight = task
        defer { if inFlight == task { inFlight = nil } }
        return try await task.value
    }

    /// Clears everything; the next `loadNextPage()` starts from the first page.
    public func reset() {
        generation += 1
        inFlight?.cancel()
        inFlight = nil
        items = []
        seenIDs = []
        nextPage = firstPage
        hasMore = true
        pagesLoaded = 0
    }

    private func fetchAndApply(page: Int, generation: Int) async throws -> PaginationSnapshot<Item> {
        let result = try await fetch(page)
        guard generation == self.generation else { throw CancellationError() }

        for item in result.items where seenIDs.insert(item.id).inserted {
            items.append(item)
        }
        nextPage = result.number + 1
        // An empty page also ends pagination, guarding against APIs that over-report totalPages.
        hasMore = result.hasMore && !result.items.isEmpty
        pagesLoaded += 1
        return snapshot
    }
}
