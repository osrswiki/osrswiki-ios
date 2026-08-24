import XCTest

/// Pushed list destinations (search query results, View more updates, Saved search)
/// must pop on a leading-edge swipe the same way article / More chrome does.
final class ListEdgeBackSwipeUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    override func tearDownWithError() throws {
        app?.terminate()
        app = nil
    }

    func testViewMoreListLeadingEdgeSwipePopsToHome() throws {
        app.launchArguments = [
            "-osrsUITestHarness",
            "-disableBackgroundPreloading",
            "-disableSearchAutofocusForUITests",
            "-startTab",
            "news",
            "-seedHomeFeedForUITests"
        ]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 15))
        revealAndTapViewMore()

        XCTAssertTrue(
            element("scoped_search_updates").waitForExistence(timeout: 12),
            "View more must open the updates list"
        )
        attachScreenshot(named: "view-more-before-edge-swipe")

        verticalDrag()
        XCTAssertTrue(
            element("scoped_search_updates").waitForExistence(timeout: 2),
            "A vertical drag on the updates list must not pop"
        )

        leadingEdgeSwipe()
        XCTAssertTrue(
            element("home_screen").waitForExistence(timeout: 8)
                || element("home_updates_view_more").waitForExistence(timeout: 8)
                || element("home_feed_scroll").waitForExistence(timeout: 8),
            "A leading-edge swipe on View more must return to Home"
        )
        XCTAssertTrue(
            element("scoped_search_updates").waitForNonExistence(timeout: 4),
            "The updates list must leave after an edge swipe"
        )
        attachScreenshot(named: "view-more-after-edge-swipe")
    }

    func testSearchQueryListLeadingEdgeSwipeReturnsToHistory() throws {
        app.launchArguments = [
            "-osrsUITestHarness",
            "-disableBackgroundPreloading",
            "-disableSearchAutofocusForUITests",
            "-allowProxyStartupDuringTests",
            "-startTab",
            "search",
            "-resetSearchRecentsForUITests"
        ]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 15))

        let launcher = app.buttons["search_history_launcher"]
        XCTAssertTrue(launcher.waitForExistence(timeout: 10), "Search History launcher should exist")
        launcher.tap()

        XCTAssertTrue(
            element("search_back_button").waitForExistence(timeout: 8),
            "Active search must expose the existing back affordance"
        )
        dismissKeyboardIfNeeded()
        attachScreenshot(named: "search-query-before-edge-swipe")

        leadingEdgeSwipe()
        XCTAssertTrue(
            launcher.waitForExistence(timeout: 8)
                || app.staticTexts["Search History"].waitForExistence(timeout: 8)
                || element("search_history_launcher").waitForExistence(timeout: 8)
                || element("search_back_button").waitForNonExistence(timeout: 8),
            "A leading-edge swipe on search results must restore Search History"
        )
        attachScreenshot(named: "search-query-after-edge-swipe")
    }

    func testSavedSearchListLeadingEdgeSwipePopsToSaved() throws {
        app.launchArguments = [
            "-osrsUITestHarness",
            "-disableBackgroundPreloading",
            "-disableSearchAutofocusForUITests",
            "-startTab",
            "saved",
            "-resetSavedPagesForUITests",
            "-seedSavedPagesForUITests"
        ]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 15))

        let launcher = app.buttons["saved_search"]
        XCTAssertTrue(launcher.waitForExistence(timeout: 12), "Saved search launcher should exist")
        launcher.tap()
        XCTAssertTrue(
            element("saved_search_screen").waitForExistence(timeout: 8)
                || element("saved_search_back_button").waitForExistence(timeout: 8),
            "Saved search list must open"
        )
        dismissKeyboardIfNeeded()
        attachScreenshot(named: "saved-search-before-edge-swipe")

        leadingEdgeSwipe()
        XCTAssertTrue(
            element("saved_pages_screen").waitForExistence(timeout: 8)
                || launcher.waitForExistence(timeout: 8),
            "A leading-edge swipe on Saved search must return to Saved"
        )
        XCTAssertTrue(
            element("saved_search_back_button").waitForNonExistence(timeout: 4),
            "The Saved-search back button must leave after an edge swipe"
        )
        attachScreenshot(named: "saved-search-after-edge-swipe")
    }

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier].firstMatch
    }

    private func revealAndTapViewMore() {
        let viewMore = element("home_updates_view_more")
        if !viewMore.waitForExistence(timeout: 4) || !viewMore.isHittable {
            let carousel = app.scrollViews["home_updates_carousel"].firstMatch
            if carousel.waitForExistence(timeout: 8) {
                for _ in 0..<8 {
                    carousel.swipeLeft()
                    if viewMore.isHittable { break }
                }
            }
        }
        XCTAssertTrue(viewMore.waitForExistence(timeout: 12), "View more should exist on Home")
        viewMore.tap()
    }

    private func leadingEdgeSwipe() {
        let host = app!
        // Stay above the keyboard band; Saved/View more lists are real pushes
        // and use the same interactive-back chrome as More destinations.
        let start = host.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.32))
        let end = host.coordinate(withNormalizedOffset: CGVector(dx: 0.78, dy: 0.32))
        start.press(
            forDuration: 0.08,
            thenDragTo: end,
            withVelocity: XCUIGestureVelocity(160),
            thenHoldForDuration: 0.08
        )
    }

    private func verticalDrag() {
        let host = app!
        let start = host.coordinate(withNormalizedOffset: CGVector(dx: 0.50, dy: 0.42))
        let end = host.coordinate(withNormalizedOffset: CGVector(dx: 0.50, dy: 0.18))
        start.press(
            forDuration: 0.05,
            thenDragTo: end,
            withVelocity: XCUIGestureVelocity(180),
            thenHoldForDuration: 0.05
        )
    }

    private func dismissKeyboardIfNeeded() {
        guard app.keyboards.firstMatch.waitForExistence(timeout: 1) else { return }
        let hide = app.keyboards.buttons["Hide keyboard"].firstMatch
        if hide.exists {
            hide.tap()
            return
        }
        app.keyboards.firstMatch.swipeDown()
    }

    private func attachScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
