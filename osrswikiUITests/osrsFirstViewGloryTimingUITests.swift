import XCTest

final class osrsFirstViewGloryTimingUITests: XCTestCase {
    func testGloryFirstViewTimingProtocol() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["OSRS_GLORY_TIMING"] == "1",
            "Set TEST_RUNNER_OSRS_GLORY_TIMING=1 to run live Amulet of Glory first-view timing."
        )

        try openGlory(disablePaintPrewarm: true, dwellSeconds: 0)
        try openGlory(disablePaintPrewarm: false, dwellSeconds: 0)
        try openGlory(disablePaintPrewarm: false, dwellSeconds: 15)
    }

    private func openGlory(disablePaintPrewarm: Bool, dwellSeconds: TimeInterval) throws {
        let app = XCUIApplication()
        app.terminate()
        app.launchArguments = disablePaintPrewarm ? ["-osrsDisableFirstViewPaintPrewarm"] : []
        app.launch()
        _ = app.wait(for: .runningForeground, timeout: 8)

        let homeSearch = app.buttons["Search OSRS Wiki"]
        XCTAssertTrue(homeSearch.waitForExistence(timeout: 12), "Home search bar should exist")
        homeSearch.tap()

        let searchField = app.textFields["Search OSRS Wiki"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 10), "Search field should appear")
        searchField.tap()
        searchField.typeText("Amulet of glory")
        Thread.sleep(forTimeInterval: 1.5)

        let identified = app.buttons["search_result_row_Amulet of glory"]
        let labeled = app.staticTexts.matching(NSPredicate(format: "label == %@", "Amulet of glory")).firstMatch
        let result = identified.waitForExistence(timeout: 6) ? identified : labeled
        XCTAssertTrue(result.waitForExistence(timeout: 12), "Exact Amulet of glory result should become tappable")
        if dwellSeconds > 0 {
            Thread.sleep(forTimeInterval: dwellSeconds)
        }
        result.tap()
        Thread.sleep(forTimeInterval: 10)
        app.terminate()
    }
}
