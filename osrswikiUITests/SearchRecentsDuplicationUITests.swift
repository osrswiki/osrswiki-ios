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

    func testLiveSearchShowsDenseResultsWithoutLoadingIndicator() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-disableBackgroundPreloading",
            "-disableSearchAutofocusForUITests",
            "-resetSearchRecentsForUITests",
            "-forceThemeForUITests",
            "osrs_dark",
            "-startTab",
            "search",
            "-allowProxyStartupDuringTests"
        ]
        app.launch()

        let launcher = app.buttons["search_history_launcher"]
        XCTAssertTrue(launcher.waitForExistence(timeout: 10))
        launcher.tap()
        let input = app.textFields["search_input"]
        XCTAssertTrue(input.waitForExistence(timeout: 10))
        input.tap()
        let started = Date()
        input.typeText("wyrmscraig")

        XCTAssertEqual(app.progressIndicators.count, 0, "Live search should not flash a loading icon while typing")
        let result = app.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH %@ AND label CONTAINS[c] %@",
            "search_result_row_",
            "Wyrmscraig"
        )).firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 6), app.debugDescription)
        XCTAssertLessThan(Date().timeIntervalSince(started), 6, "A real network search should populate promptly; local request processing adds only an 80ms coalescing window")
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "live-search-dense-no-spinner"
        attachment.lifetime = .keepAlways
        add(attachment)

        XCTAssertLessThanOrEqual(result.frame.height, 92, "Normal-size iOS search rows should match Android's compact density")
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
        let launcher = app.buttons["search_history_launcher"]
        XCTAssertTrue(launcher.waitForExistence(timeout: 5), file: file, line: line)
        launcher.tap()
        XCTAssertTrue(app.staticTexts["Recent"].waitForExistence(timeout: 5), file: file, line: line)
        XCTAssertTrue(app.buttons["Blood moon"].waitForExistence(timeout: 5), file: file, line: line)

        let recentSearchesHeaders = app.staticTexts.matching(NSPredicate(format: "label == %@", "Recent"))
        let bloodMoonRows = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Blood moon"))
        let searchHeader = app.staticTexts["search_header"]

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = screenshotName
        screenshot.lifetime = .keepAlways
        add(screenshot)

        XCTAssertEqual(recentSearchesHeaders.count, 1, "Search empty state should expose one Recent section", file: file, line: line)
        XCTAssertEqual(bloodMoonRows.count, 1, "Search empty state should expose one full-width row for each recent search", file: file, line: line)
        XCTAssertFalse(searchHeader.exists, "Active search should be a single compact toolbar without a separate heading", file: file, line: line)
        XCTAssertGreaterThan(bloodMoonRows.firstMatch.frame.width, app.frame.width * 0.8, "Recent searches should be Android-like list rows, not compact chips", file: file, line: line)
    }
}
