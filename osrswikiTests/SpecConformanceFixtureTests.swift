//
//  SpecConformanceFixtureTests.swift
//  osrswikiTests
//
//  Unit coverage for DEBUG fixtures used by the spec conformance UI gate.
//

import XCTest
@testable import osrswiki

@MainActor
final class SpecConformanceFixtureTests: XCTestCase {
    override func tearDown() {
        NewsRepository.shared.clearCache()
        super.tearDown()
    }

    func testSeededHomeFeedContainsAllRequiredSpecSections() {
        let feed = osrsSpecConformanceFixtures.homeFeed

        XCTAssertFalse(feed.recentUpdates.isEmpty, "SCREEN-HOME-001 requires Updates content")
        XCTAssertFalse(feed.announcements.isEmpty, "SCREEN-HOME-001 requires Announcements content")
        XCTAssertNotNil(feed.onThisDay, "SCREEN-HOME-001 requires On this day content")
        XCTAssertFalse(feed.popularPages.isEmpty, "SCREEN-HOME-001 requires Popular pages content")
        XCTAssertTrue(
            feed.popularPages.contains { $0.title == "Spec Fixture Popular Page" },
            "Fixture should expose a stable lower feed label for UI conformance"
        )
    }

    func testHomeFeedSeedIsAvailableThroughRepositoryCache() {
        NewsRepository.shared.seedHomeFeedForSpecConformanceTests()

        let cachedFeed = NewsRepository.shared.getCachedFeedSynchronously()
        XCTAssertEqual(cachedFeed?.recentUpdates.count, osrsSpecConformanceFixtures.homeFeed.recentUpdates.count)
        XCTAssertEqual(cachedFeed?.announcements.count, osrsSpecConformanceFixtures.homeFeed.announcements.count)
        XCTAssertEqual(cachedFeed?.onThisDay?.title, "On this day")
        XCTAssertEqual(cachedFeed?.popularPages.first?.title, "Spec Fixture Popular Page")
    }
}
