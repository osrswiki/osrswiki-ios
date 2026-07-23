import XCTest

final class BottomBarHomeIdleVisibilityUITests: XCTestCase {
    func testHomeTabBarRemainsVisibleDuringBackgroundPreviewGeneration() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-startTab", "news"]
        app.launch()

        let homeTab = app.buttons["news_tab"]
        XCTAssertTrue(homeTab.waitForExistence(timeout: 10), "Home tab should be visible after launch")

        Thread.sleep(forTimeInterval: 8)

        XCTAssertTrue(homeTab.exists, "Home tab should remain visible while background previews render")
        XCTAssertTrue(app.buttons["search_tab"].exists, "Bottom tab bar should remain visible while idle on Home")
    }
}
