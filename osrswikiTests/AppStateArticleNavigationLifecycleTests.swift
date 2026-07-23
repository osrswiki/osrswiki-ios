//
//  AppStateArticleNavigationLifecycleTests.swift
//  osrswikiTests
//
//  Regression coverage for article navigation context races.
//

import XCTest
@testable import osrswiki

@MainActor
final class AppStateArticleNavigationLifecycleTests: XCTestCase {
    func testRapidArticleNavigationsUseCallTimeTabContext() async throws {
        let appState = AppState()
        appState.selectedTab = .news
        appState.newsNavigationStack = []
        appState.searchNavigationStack = []

        appState.navigateToArticle(
            title: "Abyssal whip",
            url: URL(string: "https://oldschool.runescape.wiki/w/Abyssal_whip")!
        )
        appState.selectedTab = .search
        appState.navigateToArticle(
            title: "Varrock",
            url: URL(string: "https://oldschool.runescape.wiki/w/Varrock")!
        )

        await Task.yield()

        XCTAssertEqual(appState.newsNavigationStack.articleTitles, ["Abyssal whip"])
        XCTAssertEqual(appState.searchNavigationStack.articleTitles, ["Varrock"])
    }
}

private extension Array where Element == NewsNavigationDestination {
    var articleTitles: [String] {
        compactMap {
            guard case .article(let destination) = $0 else { return nil }
            return destination.title
        }
    }
}

private extension Array where Element == SearchNavigationDestination {
    var articleTitles: [String] {
        compactMap {
            guard case .article(let destination) = $0 else { return nil }
            return destination.title
        }
    }
}
