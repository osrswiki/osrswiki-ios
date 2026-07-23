//
//  ArticleBackSwipeResponsivenessUITests.swift
//  osrswikiUITests
//
//  Regression coverage for native-feeling article back-swipe behavior.
//

import XCTest

final class ArticleBackSwipeResponsivenessUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = [
            "-disableBackgroundPreloading",
            "-disableSearchAutofocusForUITests",
            "-startTab",
            "search",
            "-startArticleTitle",
            "The Blood Moon Rises",
            "-startArticleURL",
            "https://oldschool.runescape.wiki/w/The_Blood_Moon_Rises",
            "-allowProxyStartupDuringTests"
        ]
        app.launch()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    func testShortLeadingEdgeSwipePopsFromSecondArticle() throws {
        let firstArticle = articleWebView()
        XCTAssertTrue(firstArticle.waitForExistence(timeout: 20), "Expected Blood Moon article to open from launch arguments")
        attachScreenshot(named: "01-blood-moon")

        try navigateToQuickGuideFromArticle()

        let secondArticle = articleWebView()
        XCTAssertTrue(secondArticle.waitForExistence(timeout: 20), "Expected quick guide article to open as a second article push")
        attachScreenshot(named: "02-quick-guide-before-short-swipe")

        let start = secondArticle.coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: 0.50))
        let end = secondArticle.coordinate(withNormalizedOffset: CGVector(dx: 0.18, dy: 0.50))
        start.press(forDuration: 0.04, thenDragTo: end)

        XCTAssertTrue(
            backTargetAfterPoppingSecondArticle().waitForExistence(timeout: 3),
            "A short leading-edge swipe should pop the top article like the native iOS back gesture"
        )
        attachScreenshot(named: "03-after-short-leading-edge-swipe")
    }

    private func navigateToQuickGuideFromArticle() throws {
        let quickGuideLink = app.links.matching(NSPredicate(format: "label CONTAINS[c] %@", "quick guide")).firstMatch
        XCTAssertTrue(quickGuideLink.waitForExistence(timeout: 20), app.debugDescription)
        quickGuideLink.tap()
        XCTAssertTrue(app.staticTexts["The Blood Moon Rises/Quick guide"].waitForExistence(timeout: 20))
    }

    private func backTargetAfterPoppingSecondArticle() -> XCUIElement {
        app.staticTexts["The Blood Moon Rises"]
    }

    private func articleWebView() -> XCUIElement {
        let identified = app.webViews["article_web_view"]
        if identified.exists {
            return identified
        }
        return app.webViews.firstMatch
    }

    private func attachScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
