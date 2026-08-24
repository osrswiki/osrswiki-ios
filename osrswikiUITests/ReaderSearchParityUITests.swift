import XCTest
import UIKit

final class ReaderSearchParityUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    override func tearDownWithError() throws {
        app?.terminate()
        app = nil
    }

    func testArticleSupportsCenterBackSwipeAndDrawerSwipeDismissal() throws {
        launchFalador()
        let webView = articleWebView()
        XCTAssertTrue(webView.waitForExistence(timeout: 25), app.debugDescription)

        let contents = app.buttons["Contents"].firstMatch
        XCTAssertTrue(contents.waitForExistence(timeout: 20), app.debugDescription)
        contents.tap()
        let drawer = contentsDrawer()
        XCTAssertTrue(drawer.waitForExistence(timeout: 5), app.debugDescription)
        dismissContentsDrawer(drawer)
        assertContentsDrawerNotHittable(drawer)

        contents.tap()
        XCTAssertTrue(drawer.waitForExistence(timeout: 5), app.debugDescription)
        dismissContentsDrawer(drawer)
        assertContentsDrawerNotHittable(drawer)

        let start = webView.coordinate(withNormalizedOffset: CGVector(dx: 0.18, dy: 0.55))
        let end = webView.coordinate(withNormalizedOffset: CGVector(dx: 0.72, dy: 0.55))
        start.press(forDuration: 0.05, thenDragTo: end)
        XCTAssertTrue(app.staticTexts["Search History"].waitForExistence(timeout: 8), "Back swipe must work away from the screen edge")
    }

    func testVisibleFaladorMapUsesNativeMapAndFindKeepsArticleChrome() throws {
        app.launchArguments = commonArguments + [
            "-startTab", "search",
            "-startArticleTitle", "Falador",
            "-startArticleURL", "https://oldschool.runescape.wiki/w/Falador",
            "-startFindInPage"
        ]
        app.launch()

        XCTAssertTrue(articleWebView().waitForExistence(timeout: 25), app.debugDescription)
        XCTAssertTrue(app.buttons["article_back_button"].waitForExistence(timeout: 10), "Find in page must not remove the article toolbar")
        let nativeMapActivated = NSPredicate(format: "value CONTAINS %@", "native_article_maps=1")
        let activationExpectation = XCTNSPredicateExpectation(predicate: nativeMapActivated, object: articleWebView())
        XCTAssertEqual(XCTWaiter.wait(for: [activationExpectation], timeout: 25), .completed, "Initially visible Kartographer maps must activate the native map")
        let webFrame = articleWebView().frame
        var state = try XCTUnwrap(articleWebView().value as? String)
        var frame = renderedMapFrame(from: state)
            .offsetBy(dx: webFrame.minX, dy: webFrame.minY)
            .intersection(webFrame)
        for _ in 0..<4 where frame.isEmpty {
            articleWebView().swipeUp()
            state = try XCTUnwrap(articleWebView().value as? String)
            frame = renderedMapFrame(from: state)
                .offsetBy(dx: webFrame.minX, dy: webFrame.minY)
                .intersection(webFrame)
        }
        XCTAssertFalse(
            frame.isEmpty,
            "The fully rendered native map must intersect the visible article viewport; state=\(state), webFrame=\(webFrame)"
        )
        let appFrame = app.frame
        let startVector = CGVector(
            dx: (frame.minX + 0.25 * frame.width) / appFrame.width,
            dy: frame.midY / appFrame.height
        )
        let endVector = CGVector(
            dx: (frame.minX + 0.70 * frame.width) / appFrame.width,
            dy: frame.midY / appFrame.height
        )
        let start = app.coordinate(withNormalizedOffset: startVector)
        let end = app.coordinate(withNormalizedOffset: endVector)
        start.press(forDuration: 0.05, thenDragTo: end)
        XCTAssertTrue(app.buttons["article_back_button"].exists, "Panning an embedded map must not trigger article navigation")
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Falador native article map"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 10), "Find in page should present editable search UI")
    }

    private func renderedMapFrame(from state: String) -> CGRect {
        guard let frameToken = state.split(separator: ";").first(where: {
            $0.hasPrefix("native_map_frame=")
        }) else { return .null }
        let rawValues = frameToken.dropFirst("native_map_frame=".count).split(separator: ",")
        let values = rawValues.compactMap { Double($0).map { CGFloat($0) } }
        guard values.count == 4 else { return .null }
        return CGRect(x: values[0], y: values[1], width: values[2], height: values[3])
    }

    func testSearchTabStartsWithHistoryAndUsesUnifiedActiveToolbar() throws {
        app.launchArguments = commonArguments + [
            "-resetSearchRecentsForUITests",
            "-seedSearchRecentsForUITests", "Low level alchemy",
            "-startTab", "search"
        ]
        app.launch()

        XCTAssertTrue(app.staticTexts["Search History"].waitForExistence(timeout: 10), app.debugDescription)
        let launcher = app.buttons["search_history_launcher"]
        XCTAssertTrue(launcher.exists)
        XCTAssertTrue(app.buttons["search_history_voice_search"].exists, "Inactive Search History must expose voice search")
        launcher.tap()
        XCTAssertTrue(app.buttons["search_back_button"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["search_voice_search"].exists, "Active search must retain the microphone")
        XCTAssertTrue(app.staticTexts["Recent"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Recent Searches"].exists)
    }

    func testHomeAndSearchHistoryLaunchersFocusCanonicalSearchAndReturn() throws {
        app.launchArguments = focusArguments + [
            "-startTab", "news",
            "-seedHomeFeedForUITests"
        ]
        app.launch()

        let homeLauncher = app.buttons["home_search"]
        XCTAssertTrue(homeLauncher.waitForExistence(timeout: 10), app.debugDescription)
        homeLauncher.tap()
        let homeInput = app.textFields["search_input"]
        XCTAssertTrue(homeInput.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5), "Home launcher must focus canonical Search")
        app.buttons["search_back_button"].tap()
        XCTAssertTrue(homeLauncher.waitForExistence(timeout: 5), "Back must restore the Home return context")

        app.buttons["search_tab"].tap()
        let historyLauncher = app.buttons["search_history_launcher"]
        XCTAssertTrue(historyLauncher.waitForExistence(timeout: 5), app.debugDescription)
        historyLauncher.tap()
        XCTAssertTrue(app.textFields["search_input"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5), "Search History launcher must focus the shared field")
        app.buttons["search_back_button"].tap()
        XCTAssertTrue(historyLauncher.waitForExistence(timeout: 5), "Back must restore Search History")
    }

    func testSearchLauncherTypingAndClearKeepBoundedGeometry() throws {
        app.launchArguments = commonArguments + [
            "-resetSearchRecentsForUITests",
            "-startTab", "search"
        ]
        app.launch()

        let launcher = app.buttons["search_history_launcher"]
        XCTAssertTrue(launcher.waitForExistence(timeout: 10), app.debugDescription)
        let launchHeight = launcher.frame.height
        launcher.tap()

        let input = app.textFields["search_input"]
        XCTAssertTrue(input.waitForExistence(timeout: 5), app.debugDescription)
        let emptyFrame = input.frame
        input.typeText("Varrock")
        let typedFrame = input.frame

        let clear = app.buttons["search_clear_button"]
        XCTAssertTrue(clear.waitForExistence(timeout: 3))
        clear.tap()
        let clearedFrame = input.frame

        XCTAssertEqual(emptyFrame.height, launchHeight, accuracy: 2)
        XCTAssertEqual(typedFrame.height, emptyFrame.height, accuracy: 2)
        XCTAssertEqual(clearedFrame.height, emptyFrame.height, accuracy: 2)
        XCTAssertEqual(typedFrame.minY, emptyFrame.minY, accuracy: 2)
        XCTAssertEqual(clearedFrame.minY, emptyFrame.minY, accuracy: 2)
    }

    func testLongOfficialArticleURLStaysInsideSearchViewport() throws {
        app.launchArguments = commonArguments + [
            "-resetSearchRecentsForUITests",
            "-startTab", "search"
        ]
        app.launch()

        let launcher = app.buttons["search_history_launcher"]
        XCTAssertTrue(launcher.waitForExistence(timeout: 10), app.debugDescription)
        launcher.tap()

        let input = app.textFields["search_input"]
        XCTAssertTrue(input.waitForExistence(timeout: 5), app.debugDescription)
        input.tap()
        input.typeText("https://oldschool.runescape.wiki/w/Amulet_of_glory")

        let window = app.windows.firstMatch.frame
        XCTAssertGreaterThanOrEqual(input.frame.minX, window.minX)
        XCTAssertLessThanOrEqual(input.frame.maxX, window.maxX)
        XCTAssertLessThan(input.frame.width, window.width)

        let results = app.scrollViews["search_results"]
        if results.waitForExistence(timeout: 10) {
            XCTAssertGreaterThanOrEqual(results.frame.minX, window.minX)
            XCTAssertLessThanOrEqual(results.frame.maxX, window.maxX)
        }

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "long-official-url-search-width"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testFindInPageKeepsIdentifiedArticleWebViewThroughTypeStepDismiss() throws {
        app.launchArguments = commonArguments + [
            "-startTab", "search",
            "-startArticleTitle", "Varrock",
            "-startArticleURL", "https://oldschool.runescape.wiki/w/Varrock"
        ]
        app.launch()

        let webView = identifiedArticleWebView()
        XCTAssertTrue(webView.waitForExistence(timeout: 25), app.debugDescription)
        assertIdentifiedArticleWebViewUsable("loaded")

        let findButton = waitForArticleFindButton()
        findButton.tap()

        assertFindChromeOpen("after Find tap")
        assertIdentifiedArticleWebViewUsable("after Find tap")
        // Shipped present kicks compositor at 80ms and 250ms. Capture after that,
        // then fail if the article region is still a uniform theme fill.
        Thread.sleep(forTimeInterval: 0.45)
        attachFindScreenshot("find-present")
        assertArticleRegionPainted("after Find tap")

        typeFindQuery("Varrock")
        assertFindChromeOpen("after typing")
        assertIdentifiedArticleWebViewUsable("after typing")
        stepFindMatches()
        assertFindChromeOpen("after stepping matches")
        assertIdentifiedArticleWebViewUsable("after stepping matches")
        attachFindScreenshot("find-type-step")
        assertArticleRegionPainted("after typing/step")

        dismissFindNavigator()
        assertIdentifiedArticleWebViewUsable("after dismiss")
        attachFindScreenshot("find-dismiss")

        let back = app.buttons["article_back_button"]
        _ = back.waitForExistence(timeout: 5)
        let restoredFind = articleFindButton()
        _ = restoredFind.waitForExistence(timeout: 3)
        let usableChrome = (restoredFind.exists && restoredFind.isHittable)
            || (back.exists && back.isHittable)
        XCTAssertTrue(
            usableChrome,
            "Dismiss must restore article chrome (back and/or bottom-bar Find). find=\(restoredFind.exists)/\(restoredFind.isHittable) back=\(back.exists)/\(back.isHittable) web=\(identifiedArticleWebView().frame)"
        )
    }

    func testFindInPageKeepsArticleBottomBarHiddenForTheWholeSession() throws {
        app.launchArguments = commonArguments + [
            "-startTab", "search",
            "-startArticleTitle", "Amulet of glory",
            "-startArticleURL", "https://oldschool.runescape.wiki/w/Amulet_of_glory"
        ]
        app.launch()

        XCTAssertTrue(articleWebView().waitForExistence(timeout: 25), app.debugDescription)
        let bottomBar = app.descendants(matching: .any)
            .matching(identifier: "article_bottom_bar")
            .firstMatch
        XCTAssertTrue(bottomBar.waitForExistence(timeout: 10), app.debugDescription)
        let findButton = app.buttons["Find"]
        XCTAssertTrue(findButton.waitForExistence(timeout: 5), app.debugDescription)
        findButton.tap()

        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 10), "Find should focus its input")
        XCTAssertFalse(bottomBar.exists, "The article action bar must not ride above or partially overlap native find UI")
        Thread.sleep(forTimeInterval: 1.5)
        XCTAssertFalse(bottomBar.exists, "Polling WKFindInteraction must not resurrect the action bar mid-session")

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "find-in-page-stable-bottom-chrome"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testLiveAmuletWideBonusesScrollsLocallyWithoutCueOrArticleNavigation() throws {
        app.launchArguments = commonArguments + [
            "-startTab", "search",
            "-startArticleTitle", "Amulet of glory",
            "-startArticleURL", "https://oldschool.runescape.wiki/w/Amulet_of_glory"
        ]
        app.launch()

        XCTAssertTrue(articleWebView().waitForExistence(timeout: 25), app.debugDescription)
        XCTAssertTrue(app.staticTexts["Amulet of glory"].waitForExistence(timeout: 10), app.debugDescription)
        // The accessible disclosure now has one canonical button; the redundant outer
        // surface is intentionally demoted. Exercise the control rather than tapping the
        // adjacent section heading, which does not expand collapsed-by-default content.
        let combatStats = app.buttons
            .matching(NSPredicate(format: "label BEGINSWITH[c] %@", "Combat stats Tap to"))
            .firstMatch
        for _ in 0..<8 where !combatStats.isHittable {
            articleWebView().swipeUp()
        }
        XCTAssertTrue(combatStats.waitForExistence(timeout: 5), app.debugDescription)
        if combatStats.isHittable { combatStats.tap() }
        Thread.sleep(forTimeInterval: 0.25)

        // WebKit exposes the scroll region with a thin semantic anchor at the top of its
        // viewport. Keep it as a semantic assertion, but do not scroll to that anchor: doing so
        // can move the entire Combat stats table above the viewport. The expanded table body
        // begins directly below the disclosure label that was just tapped.
        let localSurface = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS[c] %@", "Scrollable Combat stats table"))
            .firstMatch
        let webFrame = articleWebView().frame
        XCTAssertTrue(localSurface.waitForExistence(timeout: 5), app.debugDescription)
        let tableDragY = min(
            webFrame.maxY - 72,
            max(webFrame.minY + 72, combatStats.frame.maxY + 140)
        )

        let initial = app.screenshot().image
        let start = app.coordinate(withNormalizedOffset: CGVector(
            dx: (webFrame.minX + 0.82 * webFrame.width) / app.frame.width,
            dy: tableDragY / app.frame.height
        ))
        let end = app.coordinate(withNormalizedOffset: CGVector(
            dx: (webFrame.minX + 0.18 * webFrame.width) / app.frame.width,
            dy: tableDragY / app.frame.height
        ))
        start.press(forDuration: 0.08, thenDragTo: end)
        Thread.sleep(forTimeInterval: 0.4)
        let scrolled = app.screenshot().image

        XCTAssertTrue(app.staticTexts["Amulet of glory"].exists, "A local table swipe must not navigate away from the article")
        XCTAssertFalse(contentsDrawer().exists, "A local table swipe must not open the article drawer")
        XCTAssertGreaterThan(
            imageChannelDifferenceCount(initial, scrolled),
            2_000,
            "The wide Combat stats table must visibly move under a horizontal drag"
        )
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "live-amulet-wide-bonuses-local-scroll-without-cue"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testRapidHomeArticleCancellationLeavesHomeResponsive() throws {
        app.launchArguments = commonArguments + [
            "-seedHomeFeedForUITests",
            "-startTab", "news"
        ]
        app.launch()

        let feedScroll = app.scrollViews["home_feed_scroll"]
        XCTAssertTrue(feedScroll.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertGreaterThan(
            feedScroll.frame.width,
            app.frame.width * 0.9,
            "The pinned Home chrome must leave a full-width feed viewport"
        )
        XCTAssertGreaterThan(
            feedScroll.frame.height,
            app.frame.height * 0.5,
            "The Home feed must occupy the remaining vertical viewport instead of collapsing to its ideal size"
        )

        let update = app.buttons.matching(identifier: "home_update_card").firstMatch
        XCTAssertTrue(update.waitForExistence(timeout: 10), app.debugDescription)
        update.tap()
        let webView = articleWebView()
        XCTAssertTrue(webView.waitForExistence(timeout: 5), app.debugDescription)

        let back = app.buttons["article_back_button"]
        XCTAssertTrue(back.waitForExistence(timeout: 3), app.debugDescription)
        back.tap()

        XCTAssertTrue(webView.waitForNonExistence(timeout: 5), "Back must finish dismissing the loading article before Home interaction is measured")
        XCTAssertTrue(update.waitForExistence(timeout: 5), "Returning during an in-flight article/image load must restore Home without blocking")
        let searchTab = app.buttons["search_tab"]
        XCTAssertTrue(searchTab.waitForExistence(timeout: 5), "Returning during an in-flight article/image load must not stall the main thread")
        searchTab.tap()
        XCTAssertTrue(app.buttons["search_history_launcher"].waitForExistence(timeout: 3), "Home must remain responsive after cancelling a loading article")
    }

    func testUpdatesCarouselSwipeStaysOnHomeTab() throws {
        app.launchArguments = commonArguments + [
            "-startTab", "news",
            "-seedHomeFeedForUITests"
        ]
        app.launch()

        let carousel = app.scrollViews["home_updates_carousel"]
        XCTAssertTrue(carousel.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(app.staticTexts["Home"].exists)
        carousel.swipeLeft()
        XCTAssertTrue(app.staticTexts["Home"].exists, "Scrolling update cards must not switch the root tab")
        XCTAssertFalse(app.staticTexts["Search History"].exists)
    }

    func testLowLevelAlchemyThumbnailAnimates() throws {
        app.launchArguments = [
            "-disableBackgroundPreloading",
            "-disableSearchAutofocusForUITests",
            "-resetSearchRecentsForUITests",
            "-startTab",
            "search",
            "-allowProxyStartupDuringTests"
        ]
        app.launch()

        let launcher = app.buttons["search_history_launcher"]
        XCTAssertTrue(launcher.waitForExistence(timeout: 10))
        launcher.tap()

        let input = app.textFields["search_input"]
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        input.tap()
        input.typeText("low level alchemy")

        let result = app.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH %@ AND label CONTAINS[c] %@",
            "search_result_row_",
            "Low Level Alchemy"
        )).firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 8), app.debugDescription)

        let thumbnail = result.images["Article thumbnail"]
        let animated = NSPredicate(format: "value == %@", "animated")
        expectation(for: animated, evaluatedWith: thumbnail)
        waitForExpectations(timeout: 8)

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "low-level-alchemy-animated-thumbnail"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testArticleOverflowMenuIsAnchoredToToolbarButton() throws {
        launchFalador()
        XCTAssertTrue(articleWebView().waitForExistence(timeout: 25), app.debugDescription)
        let menuButton = app.buttons["article_page_menu"]
        XCTAssertTrue(menuButton.waitForExistence(timeout: 10))
        menuButton.tap()
        let share = app.buttons["Share"]
        XCTAssertTrue(share.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertLessThan(
            abs(share.frame.midX - menuButton.frame.midX),
            app.frame.width * 0.45,
            "Article actions should originate at the toolbar ellipsis instead of a centered dialog"
        )
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "article-anchored-overflow-menu"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func launchFalador() {
        app.launchArguments = commonArguments + [
            "-startTab", "search",
            "-startArticleTitle", "Falador",
            "-startArticleURL", "https://oldschool.runescape.wiki/w/Falador"
        ]
        app.launch()
    }

    private var commonArguments: [String] {
        [
            "-osrsUITestHarness",
            "-disableBackgroundPreloading",
            "-disableSearchAutofocusForUITests",
            "-resetReaderPreferencesForUITests",
            "-resetSavedPagesForUITests",
            "-allowProxyStartupDuringTests"
        ]
    }

    private var focusArguments: [String] {
        [
            "-osrsUITestHarness",
            "-disableBackgroundPreloading",
            "-allowProxyStartupDuringTests"
        ]
    }

    private func waitForArticleFindButton() -> XCUIElement {
        let identified = app.buttons["article_find_button"]
        if identified.waitForExistence(timeout: 4) {
            return identified
        }
        let labeled = app.buttons.matching(NSPredicate(format: "label == %@", "Find"))
        XCTAssertTrue(
            labeled.firstMatch.waitForExistence(timeout: 8),
            "Bottom-bar Find must appear"
        )
        guard labeled.count > 0 else {
            return labeled.firstMatch
        }
        let matches = labeled.allElementsBoundByIndex
        let bottomMost = matches.max(by: { $0.frame.minY < $1.frame.minY })
        return bottomMost ?? labeled.firstMatch
    }

    private func articleFindButton() -> XCUIElement {
        let identified = app.buttons["article_find_button"]
        if identified.exists {
            return identified
        }
        let labeled = app.buttons.matching(NSPredicate(format: "label == %@", "Find"))
        guard labeled.count > 0 else {
            return identified
        }
        return labeled.allElementsBoundByIndex.max(by: { $0.frame.minY < $1.frame.minY })
            ?? labeled.firstMatch
    }

    private func attachFindScreenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        let web = identifiedArticleWebView()
        let find = app.buttons["article_find_button"]
        let back = app.buttons["article_back_button"]
        let summary = """
        moment=\(name)
        article_web_view exists=\(web.exists) frame=\(web.exists ? "\(web.frame)" : "missing")
        keyboard=\(app.keyboards.firstMatch.exists)
        searchField=\(app.searchFields.firstMatch.exists)
        find exists=\(find.exists)
        back exists=\(back.exists)
        """
        let dump = XCTAttachment(string: summary)
        dump.name = "\(name)-hierarchy"
        dump.lifetime = .keepAlways
        add(dump)
    }

    private func identifiedArticleWebView() -> XCUIElement {
        app.webViews["article_web_view"]
    }

    private func articleWebView() -> XCUIElement {
        let identified = identifiedArticleWebView()
        return identified.exists ? identified : app.webViews.firstMatch
    }

    private func assertIdentifiedArticleWebViewUsable(_ moment: String) {
        let webView = identifiedArticleWebView()
        XCTAssertTrue(
            webView.exists,
            "\(moment): identified article_web_view missing from hierarchy\n\(app.debugDescription)"
        )
        let frame = webView.frame
        XCTAssertGreaterThan(
            frame.width,
            1,
            "\(moment): article_web_view width=\(frame.width) height=\(frame.height)\n\(app.debugDescription)"
        )
        XCTAssertGreaterThan(
            frame.height,
            1,
            "\(moment): article_web_view width=\(frame.width) height=\(frame.height)\n\(app.debugDescription)"
        )
    }

    private func findSearchField() -> XCUIElement {
        app.searchFields["find.searchField"]
    }

    private func assertFindChromeOpen(_ moment: String) {
        let field = findSearchField()
        XCTAssertTrue(
            field.waitForExistence(timeout: 8),
            "\(moment): find.searchField missing; Find overlay is not open"
        )
        XCTAssertTrue(
            app.keyboards.firstMatch.exists || field.exists,
            "\(moment): Find keyboard/overlay missing"
        )
    }

    private func typeFindQuery(_ query: String) {
        let field = findSearchField()
        XCTAssertTrue(
            field.waitForExistence(timeout: 8),
            "find.searchField missing; cannot type \(query)"
        )
        field.tap()
        field.typeText(query)
        let entered = (field.value as? String) ?? ""
        XCTAssertTrue(
            entered.localizedCaseInsensitiveContains(query),
            "Find query was not entered; field value=\(entered)"
        )
    }

    private func stepFindMatches() {
        assertFindChromeOpen("before step")
        let next = app.buttons["find.nextButton"]
        XCTAssertTrue(next.waitForExistence(timeout: 5), "find.nextButton missing; cannot step matches")
        next.tap()
        let previous = app.buttons["find.previousButton"]
        XCTAssertTrue(
            previous.waitForExistence(timeout: 3),
            "find.previousButton missing after next"
        )
        previous.tap()
    }

    private func dismissFindNavigator() {
        assertFindChromeOpen("before dismiss")
        let done = app.buttons["find.doneButton"]
        XCTAssertTrue(
            done.waitForExistence(timeout: 5),
            "find.doneButton missing; Find overlay already gone before dismiss"
        )
        done.tap()
    }

    private func assertArticleRegionPainted(_ moment: String) {
        let sample = articlePaintSampleRect()
        XCTAssertGreaterThan(sample.width, 40, "\(moment): article sample width \(sample.width)")
        XCTAssertGreaterThan(sample.height, 40, "\(moment): article sample height \(sample.height)")
        let image = app.screenshot().image
        let crop = croppedImage(image, to: sample)
        let range = luminanceRange(crop)
        XCTAssertGreaterThan(
            range,
            16,
            "\(moment): article region is uniform fill (luminance range=\(range) sample=\(sample))"
        )
    }

    private func articlePaintSampleRect() -> CGRect {
        let web = identifiedArticleWebView().frame
        var minY = web.minY + 8
        var maxY = web.maxY - 8
        let back = app.buttons["article_back_button"]
        if back.exists {
            minY = max(minY, back.frame.maxY + 8)
        }
        let field = findSearchField()
        if field.exists {
            maxY = min(maxY, field.frame.minY - 8)
        }
        if app.keyboards.firstMatch.exists {
            maxY = min(maxY, app.keyboards.firstMatch.frame.minY - 8)
        }
        let minX = web.minX + 12
        let width = max(web.width - 24, 1)
        let height = max(maxY - minY, 1)
        return CGRect(x: minX, y: minY, width: width, height: height)
    }

    private func croppedImage(_ image: UIImage, to rect: CGRect) -> UIImage {
        let scale = image.scale
        let pixel = CGRect(
            x: rect.minX * scale,
            y: rect.minY * scale,
            width: rect.width * scale,
            height: rect.height * scale
        ).integral
        guard let cg = image.cgImage,
              let cropped = cg.cropping(to: pixel) else {
            return image
        }
        return UIImage(cgImage: cropped, scale: scale, orientation: image.imageOrientation)
    }

    private func luminanceRange(_ image: UIImage) -> Int {
        let sample = CGSize(width: 16, height: 16)
        UIGraphicsBeginImageContextWithOptions(sample, true, 1)
        defer { UIGraphicsEndImageContext() }
        image.draw(in: CGRect(origin: .zero, size: sample))
        guard let tiny = UIGraphicsGetImageFromCurrentImageContext()?.cgImage,
              let data = tiny.dataProvider?.data,
              let bytes = CFDataGetBytePtr(data) else {
            return 0
        }
        let count = tiny.width * tiny.height
        guard count > 0 else { return 0 }
        var minLuminance = 255
        var maxLuminance = 0
        for index in 0..<count {
            let offset = index * 4
            let luminance = (Int(bytes[offset]) + Int(bytes[offset + 1]) + Int(bytes[offset + 2])) / 3
            minLuminance = min(minLuminance, luminance)
            maxLuminance = max(maxLuminance, luminance)
        }
        return maxLuminance - minLuminance
    }

    private func contentsDrawer() -> XCUIElement {
        let panel = app.otherElements["contents_drawer"]
        return panel.exists ? panel : app.scrollViews["contents_drawer"]
    }

    private func dismissContentsDrawer(_ drawer: XCUIElement) {
        let start = drawer.coordinate(withNormalizedOffset: CGVector(dx: 0.20, dy: 0.45))
        let end = drawer.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.45))
        start.press(forDuration: 0.05, thenDragTo: end)
    }

    private func assertContentsDrawerNotHittable(_ drawer: XCUIElement) {
        let closed = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "hittable == false"),
            object: drawer
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [closed], timeout: 2),
            .completed,
            "A trailing-edge swipe must close the contents drawer"
        )
    }

    private func imageChannelDifferenceCount(_ lhs: UIImage, _ rhs: UIImage) -> Int {
        guard
            let lhsData = lhs.cgImage?.dataProvider?.data as Data?,
            let rhsData = rhs.cgImage?.dataProvider?.data as Data?,
            lhsData.count == rhsData.count
        else {
            return 0
        }
        return zip(lhsData, rhsData).reduce(into: 0) { count, bytes in
            if abs(Int(bytes.0) - Int(bytes.1)) > 4 {
                count += 1
            }
        }
    }
}
