import XCTest
@testable import osrswiki

final class osrsSceneHostAndSearchScopeTests: XCTestCase {
    func testUpdatesScopePinsNamespaceAndEmptyBrowse() {
        XCTAssertEqual(osrsSearchScope.updates.namespace, 112)
        XCTAssertTrue(osrsSearchScope.updates.emptyQueryBrowsesNewest)
        XCTAssertFalse(osrsSearchScope.all.emptyQueryBrowsesNewest)
        XCTAssertNil(osrsSearchScope.all.namespace)
    }

    func testNewsViewMoreOpensScopedSearchAndRepositoryFiltersNamespace() throws {
        let root = try repositoryRoot()
        let news = try source(root, "platforms/ios/osrswiki/Views/NewsView.swift")
        let searchView = try source(root, "platforms/ios/osrswiki/Views/ImmediateStyledSearchView.swift")
        let repository = try source(root, "platforms/ios/osrswiki/Repositories/SearchRepository.swift")
        let scene = try source(root, "platforms/ios/osrswiki/Services/osrsSceneDelegate.swift")
        let resumed = try source(root, "platforms/ios/osrswiki/Services/osrsResumedSceneWindow.swift")

        XCTAssertTrue(news.contains("home_updates_view_more"))
        XCTAssertTrue(news.contains("osrsHomeUpdatesViewMoreCap"))
        XCTAssertTrue(news.contains("standardContentHeight: CGFloat? = nil"))
        XCTAssertTrue(news.contains("alignment: .trailing"))
        XCTAssertTrue(news.contains("navigateToScopedSearch(.updates)"))
        XCTAssertTrue(news.contains("case .scopedSearch(let scope)"))
        XCTAssertTrue(news.contains(".osrsLink"))
        XCTAssertTrue(searchView.contains("showsBrowseResultsWhenEmpty: scope.emptyQueryBrowsesNewest"))
        XCTAssertTrue(searchView.contains("_isSearchFocused = State(initialValue: !scope.emptyQueryBrowsesNewest)"))
        XCTAssertTrue(searchView.contains("accessibilityIdentifier(\"search_results\")"))
        XCTAssertTrue(searchView.contains("accessibilityIdentifier(\"search_load_more\")"))
        XCTAssertTrue(repository.contains("gsrnamespace"))
        XCTAssertTrue(repository.contains("enrichMissingPreviews"))
        XCTAssertTrue(repository.contains("followRedirects: false"))
        XCTAssertTrue(repository.contains("filter { $0.ns == namespace }"))
        XCTAssertTrue(repository.contains("generator=recentchanges") || repository.contains("\"recentchanges\""))
        XCTAssertTrue(repository.contains("grcnamespace"))
        XCTAssertFalse(scene.contains("osrsResumedArticleViewController"))
        XCTAssertTrue(scene.contains("UIHostingController(rootView: osrsAppRoot.rootView)"))
        XCTAssertFalse(resumed.contains("webView.load(URLRequest"))
    }

    private func repositoryRoot() throws -> URL {
        var url = URL(fileURLWithPath: #filePath)
        while url.pathComponents.count > 1 {
            if FileManager.default.fileExists(atPath: url.appendingPathComponent("AGENTS.md").path),
               FileManager.default.fileExists(atPath: url.appendingPathComponent("platforms/ios/osrswiki.xcodeproj").path) {
                return url
            }
            url.deleteLastPathComponent()
        }
        throw XCTSkip("Could not locate repository root from \(#filePath)")
    }

    private func source(_ root: URL, _ path: String) throws -> String {
        try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }
}
