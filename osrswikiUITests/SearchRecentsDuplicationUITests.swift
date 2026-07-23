//
//  SearchRecentsDuplicationUITests.swift
//  osrswikiUITests
//

import XCTest

final class SearchRecentsDuplicationUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testLightSearchEmptyStateShowsOneRecentSearchesSectionAndOneChipPerRecent() throws {
        try assertSearchEmptyStateHasSingleRecentSection(theme: "osrs_light", screenshotName: "light-search-recents-blood-moon")
    }

    func testDarkSearchEmptyStateShowsOneRecentSearchesSectionAndOneChipPerRecent() throws {
        try assertSearchEmptyStateHasSingleRecentSection(theme: "osrs_dark", screenshotName: "dark-search-recents-blood-moon")
    }

    private func assertSearchEmptyStateHasSingleRecentSection(
        theme: String,
        screenshotName: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-screenshotMode",
            "-disableBackgroundPreloading",
            "-disableSearchAutofocusForUITests",
            "-resetSearchRecentsForUITests",
            "-seedSearchRecentsForUITests",
            "Blood moon",
            "-forceThemeForUITests",
            theme,
            "-startTab",
            "search"
        ]
        app.launch()

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 12), file: file, line: line)
        XCTAssertTrue(app.otherElements["search_screen"].waitForExistence(timeout: 10), file: file, line: line)
        XCTAssertTrue(app.staticTexts["Recent Searches"].waitForExistence(timeout: 5), file: file, line: line)
        XCTAssertTrue(app.buttons["Blood moon"].waitForExistence(timeout: 5), file: file, line: line)

        let recentSearchesHeaders = app.staticTexts.matching(NSPredicate(format: "label == %@", "Recent Searches"))
        let bloodMoonChips = app.buttons.matching(NSPredicate(format: "label == %@", "Blood moon"))

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = screenshotName
        screenshot.lifetime = .keepAlways
        add(screenshot)

        XCTAssertEqual(recentSearchesHeaders.count, 1, "Search empty state should expose one Recent Searches section", file: file, line: line)
        XCTAssertEqual(bloodMoonChips.count, 1, "Search empty state should expose one chip for each recent search", file: file, line: line)
    }
}
