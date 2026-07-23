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

    func testLoadRecentSearchesNormalizesPersistedDuplicates() {
        UserDefaults.standard.set(["Blood moon", "blood moon", "Varrock", "Varrock "], forKey: recentSearchesKey)

        let viewModel = SearchViewModel()

        XCTAssertEqual(viewModel.recentSearches, ["Blood moon", "Varrock"])
        XCTAssertEqual(UserDefaults.standard.array(forKey: recentSearchesKey) as? [String], ["Blood moon", "Varrock"])
    }
}
