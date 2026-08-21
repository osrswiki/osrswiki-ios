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

    func testSlowLeadingSwipeRevealsPreviousArticleBeforeCommit() throws {
        let firstArticle = articleWebView()
        XCTAssertTrue(firstArticle.waitForExistence(timeout: 20), "Expected Blood Moon article to open from launch arguments")
        try navigateToQuickGuideFromArticle()

        let secondArticle = articleWebView()
        XCTAssertTrue(secondArticle.waitForExistence(timeout: 20), "Expected quick guide article to open as a second article push")
        attachScreenshot(named: "interactive-before-slow-back-swipe")

        let start = secondArticle.coordinate(withNormalizedOffset: CGVector(dx: 0.04, dy: 0.50))
        let mid = secondArticle.coordinate(withNormalizedOffset: CGVector(dx: 0.52, dy: 0.50))
        start.press(
            forDuration: 0.12,
            thenDragTo: mid,
            withVelocity: XCUIGestureVelocity(45),
            thenHoldForDuration: 0.8
        )

        XCTAssertTrue(
            backTargetAfterPoppingSecondArticle().waitForExistence(timeout: 5),
            "A slow interactive back swipe should pop once the finger crosses the commit threshold"
        )
        attachScreenshot(named: "interactive-after-slow-back-swipe")
    }

    func testVerticalDragDoesNotTriggerArticleSwipe() throws {
        let article = articleWebView()
        XCTAssertTrue(article.waitForExistence(timeout: 20), "Expected Blood Moon article to open from launch arguments")
        attachScreenshot(named: "vertical-before-scroll")

        let start = article.coordinate(withNormalizedOffset: CGVector(dx: 0.50, dy: 0.42))
        let end = article.coordinate(withNormalizedOffset: CGVector(dx: 0.52, dy: 0.12))
        start.press(
            forDuration: 0.05,
            thenDragTo: end,
            withVelocity: XCUIGestureVelocity(220),
            thenHoldForDuration: 0.05
        )

        XCTAssertTrue(
            app.staticTexts["The Blood Moon Rises"].waitForExistence(timeout: 2),
            "A mostly vertical drag must keep the current article instead of swiping back or opening contents"
        )
        XCTAssertFalse(app.otherElements["contents_drawer"].exists)
        attachScreenshot(named: "vertical-after-scroll")
    }

    func testLeadingEdgeBackSwipeKeepsArticleBottomBarAttachedMidGesture() throws {
        let article = articleWebView()
        XCTAssertTrue(article.waitForExistence(timeout: 25), "Expected Blood Moon article to open from launch arguments")
        let saveButton = app.buttons["Save"].firstMatch
        let findButton = app.buttons["Find"].firstMatch
        XCTAssertTrue(saveButton.waitForExistence(timeout: 20), "Article Save action should be on screen before a back swipe")
        XCTAssertTrue(findButton.waitForExistence(timeout: 5), "Article Find action should be on screen before a back swipe")
        attachScreenshot(named: "bottom-bar-before-back-swipe")

        // Start below the infobox so a wide table cannot claim the pan.
        let start = article.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.72))
        let mid = article.coordinate(withNormalizedOffset: CGVector(dx: 0.28, dy: 0.72))

        var midSwipeScreenshot: XCUIScreenshot?
        let captured = expectation(description: "mid-swipe screenshot")
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 4.0) {
            midSwipeScreenshot = XCUIScreen.main.screenshot()
            captured.fulfill()
        }

        start.press(
            forDuration: 0.08,
            thenDragTo: mid,
            withVelocity: XCUIGestureVelocity(45),
            thenHoldForDuration: 2.0
        )
        wait(for: [captured], timeout: 3)

        if let midSwipeScreenshot {
            let attachment = XCTAttachment(screenshot: midSwipeScreenshot)
            attachment.name = "bottom-bar-mid-back-swipe"
            attachment.lifetime = .keepAlways
            add(attachment)
            if let evidenceDir = ProcessInfo.processInfo.environment["OSRS_QA_EVIDENCE_DIR"],
               !evidenceDir.isEmpty {
                let url = URL(fileURLWithPath: evidenceDir)
                    .appendingPathComponent("ios-swipe-mid-bar.png")
                try? midSwipeScreenshot.pngRepresentation.write(to: url)
            }
        }

        XCTAssertTrue(
            saveButton.exists && findButton.exists,
            "The live article bottom bar must stay attached during an interactive back swipe instead of vanishing"
        )
        XCTAssertTrue(
            app.staticTexts["The Blood Moon Rises"].waitForExistence(timeout: 2),
            "A sub-commit back swipe should keep the current article after the finger lifts"
        )
        attachScreenshot(named: "bottom-bar-after-cancelled-back-swipe")
    }

    func testHomeArticleBackButtonReturnsToHome() throws {
        try launchHomeRootArticle()

        let backButton = app.buttons["Back"]
        XCTAssertTrue(backButton.waitForExistence(timeout: 5), app.debugDescription)
        backButton.tap()

        assertHomeReturnedAfterRootArticleBack()
        attachScreenshot(named: "home-after-root-article-back")
    }

    func testHomeArticleLeadingEdgeSwipeReturnsToHome() throws {
        try launchHomeRootArticle()

        let article = articleWebView()
        let start = article.coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: 0.50))
        let end = article.coordinate(withNormalizedOffset: CGVector(dx: 0.55, dy: 0.50))
        start.press(forDuration: 0.04, thenDragTo: end)

        assertHomeReturnedAfterRootArticleBack()
        attachScreenshot(named: "home-after-root-article-edge-swipe")
    }

    func testFailedLoadOverlayFullWidthSwipePops() throws {
        app.terminate()
        app = XCUIApplication()
        app.launchArguments = [
            "-disableBackgroundPreloading",
            "-disableSearchAutofocusForUITests",
            "-startTab",
            "search",
            "-startArticleTitle",
            "UncachedSwipeProbeXYZ",
            "-startArticleURL",
            "https://oldschool.runescape.wiki/w/UncachedSwipeProbeXYZ",
            "-forceNetworkOfflineForUITests",
            "-allowProxyStartupDuringTests"
        ]
        app.launch()

        let failed = app.staticTexts["Failed to Load Page"]
        XCTAssertTrue(failed.waitForExistence(timeout: 12), "Forced offline uncached article should show the failed-load overlay")
        attachScreenshot(named: "failed-overlay-before-swipe")

        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.06, dy: 0.58))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.78, dy: 0.58))
        start.press(forDuration: 0.05, thenDragTo: end)

        XCTAssertTrue(
            failed.waitForNonExistence(timeout: 4),
            "A full-width right swipe on the failed-load canvas should pop back instead of staying on Retry"
        )
        attachScreenshot(named: "failed-overlay-after-swipe")
    }

    func testAppearanceScreenFullWidthSwipePopsToMore() throws {
        app.terminate()
        app = XCUIApplication()
        app.launchArguments = [
            "-disableBackgroundPreloading",
            "-disableSearchAutofocusForUITests",
            "-startTab",
            "more"
        ]
        app.launch()

        let appearanceRow = app.descendants(matching: .any)["more_appearance"].firstMatch
        XCTAssertTrue(appearanceRow.waitForExistence(timeout: 8), app.debugDescription)
        appearanceRow.tap()

        let appearanceBar = app.navigationBars["Appearance"]
        XCTAssertTrue(
            appearanceBar.waitForExistence(timeout: 8),
            "Appearance should push from More. \(app.debugDescription)"
        )
        attachScreenshot(named: "appearance-before-swipe")

        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.06, dy: 0.58))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.78, dy: 0.58))
        start.press(forDuration: 0.05, thenDragTo: end)

        XCTAssertTrue(
            appearanceBar.waitForNonExistence(timeout: 4),
            "A full-width right swipe on Appearance should pop the pushed settings canvas"
        )
        XCTAssertTrue(
            app.otherElements["more_screen"].waitForExistence(timeout: 4)
                || app.descendants(matching: .any)["more_appearance"].firstMatch.waitForExistence(timeout: 2),
            "More list should be visible after swiping back from Appearance"
        )
        attachScreenshot(named: "appearance-after-swipe")
    }

    private func launchHomeRootArticle() throws {
        app.terminate()
        app = XCUIApplication()
        app.launchArguments = [
            "-disableBackgroundPreloading",
            "-disableSearchAutofocusForUITests",
            "-startTab",
            "news",
            "-allowProxyStartupDuringTests"
        ]
        app.launch()

        let updateCard = app.buttons.matching(identifier: "home_update_card").firstMatch
        XCTAssertTrue(updateCard.waitForExistence(timeout: 25), app.debugDescription)
        updateCard.tap()
        XCTAssertTrue(articleWebView().waitForExistence(timeout: 25), "Expected Home update to open as a root article")
    }

    private func assertHomeReturnedAfterRootArticleBack(
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(
            app.otherElements["home_screen"].waitForExistence(timeout: 3),
            "Home article back must pop the visible News stack rather than an off-screen stack or WebView redirect",
            file: file,
            line: line
        )
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
