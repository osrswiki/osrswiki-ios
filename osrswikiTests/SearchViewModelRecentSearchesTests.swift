//
//  SearchViewModelRecentSearchesTests.swift
//  osrswikiTests
//

import XCTest
@testable import osrswiki

@MainActor
final class SearchViewModelRecentSearchesTests: XCTestCase {
    private let recentSearchesKey = "recent_searches"

    override func setUpWithError() throws {
        UserDefaults.standard.removeObject(forKey: recentSearchesKey)
    }

    override func tearDownWithError() throws {
        UserDefaults.standard.removeObject(forKey: recentSearchesKey)
    }

    func testAddToRecentSearchesKeepsOneEntryForCaseAndWhitespaceVariants() {
        let viewModel = SearchViewModel()

        viewModel.addToRecentSearches(" Blood moon ")
        viewModel.addToRecentSearches("blood moon")

        XCTAssertEqual(viewModel.recentSearches, ["blood moon"])
        XCTAssertEqual(UserDefaults.standard.array(forKey: recentSearchesKey) as? [String], ["blood moon"])
    }

    func testRecentQueryCacheIsShortLRU() {
        let cache = osrsRecentSearchQueryCache<String>(maxEntries: 16)
        for index in 0..<16 {
            cache.put("q\(index)", "v\(index)")
        }
        XCTAssertEqual(cache.get("q0"), "v0")
        cache.put("newest", "fresh")
        XCTAssertEqual(cache.count, 16)
        XCTAssertNil(cache.get("q1"))
        XCTAssertEqual(cache.get("q0"), "v0")
        XCTAssertEqual(cache.get("newest"), "fresh")
    }

    func testLoadRecentSearchesNormalizesPersistedDuplicates() {
        UserDefaults.standard.set(["Blood moon", "blood moon", "Varrock", "Varrock "], forKey: recentSearchesKey)

        let viewModel = SearchViewModel()

        XCTAssertEqual(viewModel.recentSearches, ["Blood moon", "Varrock"])
        XCTAssertEqual(UserDefaults.standard.array(forKey: recentSearchesKey) as? [String], ["Blood moon", "Varrock"])
    }
}
