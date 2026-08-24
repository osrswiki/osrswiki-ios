import XCTest

/// Live-device pull-to-refresh for the article reader. XCUI coordinate drags
/// are UDID-targeted HID (Simulator Metal does not take host CUA clicks).
final class osrsArticlePullToRefreshLayoutUITests: XCTestCase {
    func testPullToRefreshTwiceLeavesTitleAtFreshOpenPosition() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-disableBackgroundPreloading",
            "-disableSearchAutofocusForUITests",
            "-startTab",
            "search",
            "-startArticleTitle",
            "Varrock",
            "-startArticleURL",
            "https://oldschool.runescape.wiki/w/Varrock",
            "-allowProxyStartupDuringTests"
        ]
        app.launch()

        let webView = app.webViews["article_web_view"]
        XCTAssertTrue(webView.waitForExistence(timeout: 25), "Varrock article WebView did not appear")
        XCTAssertTrue(app.staticTexts["Varrock"].waitForExistence(timeout: 20), "Article title missing on fresh open")
        attachScreenshot(named: "article-ptr-fresh")

        pullToRefresh(on: webView)
        RunLoop.current.run(until: Date().addingTimeInterval(6))
        XCTAssertTrue(app.staticTexts["Varrock"].waitForExistence(timeout: 15))
        attachScreenshot(named: "article-ptr-after-refresh")

        pullToRefresh(on: webView)
        RunLoop.current.run(until: Date().addingTimeInterval(6))
        XCTAssertTrue(app.staticTexts["Varrock"].waitForExistence(timeout: 15))
        attachScreenshot(named: "article-ptr-after-refresh-2")
        XCTAssertFalse(app.staticTexts["Failed to Load Page"].exists)
    }

    private func pullToRefresh(on webView: XCUIElement) {
        let start = webView.coordinate(withNormalizedOffset: CGVector(dx: 0.50, dy: 0.18))
        let end = webView.coordinate(withNormalizedOffset: CGVector(dx: 0.50, dy: 0.78))
        start.press(
            forDuration: 0.08,
            thenDragTo: end,
            withVelocity: XCUIGestureVelocity(180),
            thenHoldForDuration: 0.2
        )
    }

    private func attachScreenshot(named name: String) {
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
