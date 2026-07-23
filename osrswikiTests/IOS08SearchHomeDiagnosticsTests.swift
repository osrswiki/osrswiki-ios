//
//  IOS08SearchHomeDiagnosticsTests.swift
//  osrswikiTests
//
//  Regression guards for IOS-08 search/home correctness and diagnostics.
//

import XCTest

final class IOS08SearchHomeDiagnosticsTests: XCTestCase {
    private var projectRoot: URL {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<3 {
            url.deleteLastPathComponent()
        }
        return url
    }

    func testSearchViewModelAppliesPaginationStateFromRepositoryResponse() throws {
        let source = try readSource("platforms/ios/osrswiki/ViewModels/SearchViewModel.swift")

        XCTAssertTrue(
            source.contains("self.hasMoreResults = response.hasMore"),
            "SearchViewModel should publish response.hasMore so the visible Load More control reflects real pagination state."
        )
        XCTAssertTrue(
            source.contains("hasMoreResults = false"),
            "SearchViewModel should reset pagination state when the current search state is cleared or fails."
        )
    }

    func testSearchThumbnailsUseNetworkManagerBoundary() throws {
        let source = try readSource("platforms/ios/osrswiki/Repositories/SearchRepository.swift")
        let batchThumbnailBody = try extractFunctionBody(named: "fetchThumbnailsBatch", from: source)

        XCTAssertTrue(
            batchThumbnailBody.contains("NetworkManager.shared.performDataRequest"),
            "Batch thumbnail requests should use NetworkManager so cache/proxy/connectivity/test overrides match primary search."
        )
        XCTAssertFalse(
            batchThumbnailBody.contains("session.data"),
            "Batch thumbnail requests should not bypass NetworkManager with a private URLSession."
        )
    }

    func testHomeForceRefreshTransformsSingleFetchedFeed() throws {
        let source = try readSource("platforms/ios/osrswiki/ViewModels/NewsViewModel.swift")
        let loadNewsBody = try extractFunctionBody(named: "loadNews", from: source)

        XCTAssertFalse(
            loadNewsBody.contains("fetchLatestNews(forceRefresh: forceRefresh)"),
            "NewsViewModel.loadNews(forceRefresh:) should not ask NewsRepository to fetch the same WikiFeed a second time."
        )
        XCTAssertTrue(
            loadNewsBody.contains("transformFeedToNewsItems(fetchedFeed)"),
            "NewsViewModel.loadNews(forceRefresh:) should derive legacy newsItems from the already fetched feed."
        )
    }

    func testLaneFilesDoNotContainContentLeakingDiagnostics() throws {
        let checkedFiles = [
            "platforms/ios/osrswiki/ViewModels/SearchViewModel.swift",
            "platforms/ios/osrswiki/Repositories/SearchRepository.swift",
            "platforms/ios/osrswiki/ViewModels/NewsViewModel.swift",
            "platforms/ios/osrswiki/Views/Components/SearchResultRowView.swift"
        ]

        for path in checkedFiles {
            let source = try readSource(path)
            XCTAssertFalse(
                source.contains("print(") || source.contains("NSLog("),
                "\(path) should not print search terms, result titles, snippets, or Home refresh diagnostics from production code."
            )
        }
    }

    func testNetworkManagerContentDiagnosticsAreDebugGated() throws {
        let source = try readSource("platforms/ios/osrswiki/Utils/NetworkManager.swift")

        XCTAssertTrue(
            source.contains("private func osrsNetworkDebugLog"),
            "NetworkManager should route URL and response diagnostics through a debug-only helper."
        )
        XCTAssertTrue(
            source.contains("#if DEBUG\n    print(message())\n#endif"),
            "NetworkManager diagnostics should compile out of release-like builds."
        )
        XCTAssertFalse(
            source.contains("print(\"🔍 NetworkManager") || source.contains("print(\"📄 NetworkManager"),
            "NetworkManager should not directly print search URLs or response bodies."
        )
    }

    private func readSource(_ relativePath: String) throws -> String {
        let url = projectRoot.appendingPathComponent(relativePath)
        return try String(contentsOf: url, encoding: .utf8)
    }

    private func extractFunctionBody(named functionName: String, from source: String) throws -> String {
        guard let functionRange = source.range(of: "func \(functionName)") else {
            XCTFail("Could not find function \(functionName)")
            return ""
        }

        guard let openingBrace = source[functionRange.lowerBound...].firstIndex(of: "{") else {
            XCTFail("Could not find opening brace for function \(functionName)")
            return ""
        }

        var depth = 0
        var current = openingBrace
        while current < source.endIndex {
            let character = source[current]
            if character == "{" {
                depth += 1
            } else if character == "}" {
                depth -= 1
                if depth == 0 {
                    return String(source[openingBrace...current])
                }
            }
            current = source.index(after: current)
        }

        XCTFail("Could not find closing brace for function \(functionName)")
        return ""
    }
}
