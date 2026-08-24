import XCTest
@testable import osrswiki

@MainActor
final class osrsUpdatesBrowseFirstFillTests: XCTestCase {
    func testViewMoreEmptyQueryPaintsTitlesBeforeParseHtmlThenSettlesPreviews() async throws {
        let client = FakeUpdatesSearchDataClient()
        let repository = SearchRepository(dataClient: client)
        let viewModel = SearchViewModel(scope: .updates, searchRepository: repository)

        let firstPaint = await waitUntil(timeout: 2.0) { !viewModel.searchResults.isEmpty }
        XCTAssertTrue(firstPaint, "Empty-query updates browse must publish first usable rows before extract/parse returns")
        XCTAssertEqual(
            viewModel.searchResults.map(\.title),
            ["Update:Blank intro", "Update:Has snippet", "Update:Chrome snippet"]
        )
        XCTAssertNil(viewModel.searchResults.first { $0.id == "11" }?.rawSnippet)
        XCTAssertEqual(viewModel.searchResults.first { $0.id == "12" }?.rawSnippet, "already")
        XCTAssertNotEqual(
            viewModel.searchResults.first { $0.id == "11" }?.rawSnippet,
            "Diango is giving out hats in Draynor.",
            "First usable rows must appear before remaining extract/parse work completes"
        )

        client.allowEnrichment()
        let settled = await waitUntil(timeout: 2.0) {
            viewModel.searchResults.first { $0.id == "11" }?.rawSnippet == "Diango is giving out hats in Draynor."
                && viewModel.searchResults.first { $0.id == "13" }?.rawSnippet == "Regional servers are coming to South Africa."
        }
        XCTAssertTrue(settled, "Settled previews must still match current polish, not title-only rows")
        XCTAssertEqual(viewModel.searchResults.first { $0.id == "12" }?.rawSnippet, "already")
        XCTAssertTrue(viewModel.hasCompletedCurrentQuery)
    }

    func testBrowseNewestRepositoryEmitsPartialThenEnrichedPage() async throws {
        let client = FakeUpdatesSearchDataClient()
        let repository = SearchRepository(dataClient: client)
        var partialTitles: [String] = []

        let task = Task {
            try await repository.search(
                query: "",
                limit: 20,
                offset: 0,
                scope: .updates,
                continueToken: nil,
                onPartialResults: { partial in
                    partialTitles = partial.results.map(\.title)
                    client.partialBlankSnippet = partial.results.first { $0.id == "11" }?.rawSnippet
                }
            )
        }

        let sawPartial = await waitUntil(timeout: 2.0) { !partialTitles.isEmpty }
        XCTAssertTrue(sawPartial)
        XCTAssertEqual(partialTitles, ["Update:Blank intro", "Update:Has snippet", "Update:Chrome snippet"])
        XCTAssertNil(client.partialBlankSnippet, "Partial page must not wait for parse HTML")

        client.allowEnrichment()
        let response = try await task.value
        XCTAssertEqual(response.results.first { $0.id == "11" }?.rawSnippet, "Diango is giving out hats in Draynor.")
        XCTAssertEqual(response.results.first { $0.id == "12" }?.rawSnippet, "already")
        XCTAssertEqual(response.results.first { $0.id == "13" }?.rawSnippet, "Regional servers are coming to South Africa.")
    }

    private func waitUntil(timeout: TimeInterval, predicate: @escaping () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if predicate() { return true }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        return predicate()
    }
}

@MainActor
private final class FakeUpdatesSearchDataClient: osrsSearchDataClient {
    private let lock = NSLock()
    private var holdEnrichment = true
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private(set) var enrichmentStarted = false

    func allowEnrichment() {
        lock.lock()
        holdEnrichment = false
        let pending = waiters
        waiters.removeAll()
        lock.unlock()
        pending.forEach { $0.resume() }
    }

    var partialBlankSnippet: String?

    func fetchSearchBytes(from url: URL) async throws -> (Data, URLResponse) {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let query = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
        let ok = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
        if query["generator"] == "recentchanges" {
            return (Self.recentChangesJSON, ok)
        }
        lock.lock()
        enrichmentStarted = true
        let shouldHold = holdEnrichment
        lock.unlock()
        if shouldHold {
            await withCheckedContinuation { continuation in
                lock.lock()
                if holdEnrichment {
                    waiters.append(continuation)
                    lock.unlock()
                } else {
                    lock.unlock()
                    continuation.resume()
                }
            }
        }
        if query["action"] == "parse" {
            return (Self.parseJSON(pageId: query["pageid"] ?? ""), ok)
        }
        if (query["prop"] ?? "").contains("extracts") {
            return (Self.extractsJSON, ok)
        }
        throw URLError(.badURL)
    }

    private static let recentChangesJSON = Data("""
    {"continue":{"grccontinue":"next-token"},"query":{"pages":[
      {"ns":112,"pageid":12,"title":"Update:Has snippet","index":2,"snippet":"already","timestamp":"2025-06-01T00:00:00Z"},
      {"ns":112,"pageid":13,"title":"Update:Chrome snippet","index":3,"snippet":"CLICK HERE TO SHOW THIS CONTENT","extract":"If you can't see the podcast, click here.","timestamp":"2024-01-01T00:00:00Z"},
      {"ns":112,"pageid":11,"title":"Update:Blank intro","index":1,"timestamp":"2026-08-01T00:00:00Z"}
    ]}}
    """.utf8)

    private static let extractsJSON = Data("""
    {"query":{"pages":[
      {"ns":112,"pageid":11,"title":"Update:Blank intro","extract":"This official news post is copied verbatim from the website."}
    ]}}
    """.utf8)

    private static func parseJSON(pageId: String) -> Data {
        if pageId == "13" {
            return Data("""
            {"parse":{"text":"<p>CLICK HERE TO SHOW THIS CONTENT</p><p>Regional servers are coming to South Africa.</p>"}}
            """.utf8)
        }
        return Data("""
        {"parse":{"text":"<p>This official news post is copied verbatim.</p><p>Diango is giving out hats in Draynor.</p>"}}
        """.utf8)
    }
}
