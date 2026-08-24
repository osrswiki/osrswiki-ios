import XCTest

/// Repeating iOS Simulator try-test: a horizontal drag that starts inside an
/// in-article overflow scroller must not fire back / sidebar / TOC chrome, while
/// an edge swipe that starts outside that scroller still pops as designed.
final class ArticleHorizontalScrollerGestureUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = [
            "-osrsUITestHarness",
            "-disableBackgroundPreloading",
            "-disableSearchAutofocusForUITests",
            "-resetReaderPreferencesForUITests",
            "-allowProxyStartupDuringTests",
            "-startTab",
            "search",
            "-startArticleTitle",
            "Amulet of glory",
            "-startArticleURL",
            "https://oldschool.runescape.wiki/w/Amulet_of_glory",
            "-osrsScrollTo",
            "Combat stats"
        ]
        app.launch()
    }

    override func tearDownWithError() throws {
        app?.terminate()
        app = nil
    }

    func testInElementHorizontalDragOnWideTableDoesNotPopOrOpenSidebar() throws {
        let webView = try waitForGloryArticle()
        let localSurface = try expandCombatStatsAndRequireScroller()
        attachScreenshot(named: "hscroll-before-in-element-drag")

        let drag = inElementDragPoints(on: localSurface, webView: webView)
        XCTAssertGreaterThan(
            drag.startXInWindow,
            20,
            "In-element drag must start inside the scroller, not at the screen edge"
        )

        drag.start.press(
            forDuration: 0.08,
            thenDragTo: drag.endRight,
            withVelocity: XCUIGestureVelocity(220),
            thenHoldForDuration: 0.05
        )
        assertStillOnGloryArticle("A rightward drag inside a wide table must not pop back")
        XCTAssertFalse(
            contentsDrawerIsVisiblyOpen(),
            "A rightward drag inside a wide table must not open contents"
        )

        drag.start.press(
            forDuration: 0.08,
            thenDragTo: drag.endLeft,
            withVelocity: XCUIGestureVelocity(220),
            thenHoldForDuration: 0.05
        )
        assertStillOnGloryArticle("A leftward drag inside a wide table must keep the article")
        XCTAssertFalse(
            contentsDrawerIsVisiblyOpen(),
            "A leftward drag inside a wide table must not open the contents drawer"
        )
        attachScreenshot(named: "hscroll-after-in-element-drag")
    }

    func testLeadingEdgeSwipeOutsideScrollerStillPopsBack() throws {
        let webView = try waitForGloryArticle()
        let localSurface = try expandCombatStatsAndRequireScroller()
        attachScreenshot(named: "hscroll-before-edge-swipe")

        let webFrame = webView.frame
        var edgeYRatio: CGFloat = 0.82
        let edgeX = webFrame.minX + 8
        for candidate in [0.82, 0.88, 0.70, 0.60] as [CGFloat] {
            let y = webFrame.minY + webFrame.height * candidate
            if !localSurface.frame.insetBy(dx: -4, dy: -4).contains(CGPoint(x: edgeX, y: y)) {
                edgeYRatio = candidate
                break
            }
        }
        let edgePoint = CGPoint(
            x: webFrame.minX + webFrame.width * 0.04,
            y: webFrame.minY + webFrame.height * edgeYRatio
        )
        XCTAssertFalse(
            localSurface.frame.insetBy(dx: -4, dy: -4).contains(edgePoint),
            "Edge swipe must start outside the horizontal scroller. scroller=\(localSurface.frame) edge=\(edgePoint)"
        )

        let start = webView.coordinate(withNormalizedOffset: CGVector(dx: 0.04, dy: edgeYRatio))
        let end = webView.coordinate(withNormalizedOffset: CGVector(dx: 0.72, dy: edgeYRatio))
        start.press(
            forDuration: 0.05,
            thenDragTo: end,
            withVelocity: XCUIGestureVelocity(180),
            thenHoldForDuration: 0.05
        )

        XCTAssertTrue(
            app.staticTexts["Search History"].waitForExistence(timeout: 8)
                || app.otherElements["search_screen"].waitForExistence(timeout: 2),
            "A leading-edge swipe that starts outside the scroller must still pop back"
        )
        XCTAssertTrue(
            app.webViews["article_web_view"].waitForNonExistence(timeout: 3)
                || app.buttons["article_back_button"].waitForNonExistence(timeout: 2),
            "The Glory article canvas must leave after an unowned leading-edge back swipe"
        )
        attachScreenshot(named: "hscroll-after-edge-swipe")
    }

    private func waitForGloryArticle() throws -> XCUIElement {
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 15), "App did not reach foreground")
        let webView = articleWebView()
        XCTAssertTrue(webView.waitForExistence(timeout: 40), "Expected Amulet of glory to open from launch arguments")
        XCTAssertTrue(app.staticTexts["Amulet of glory"].waitForExistence(timeout: 20), "Glory title missing after launch")
        return webView
    }

    @discardableResult
    private func expandCombatStatsAndRequireScroller() throws -> XCUIElement {
        let webView = articleWebView()
        let infoboxCollapse = app.buttons
            .matching(NSPredicate(format: "label BEGINSWITH[c] %@", "Infobox Tap to collapse"))
            .firstMatch
        if infoboxCollapse.waitForExistence(timeout: 3), infoboxCollapse.isHittable {
            infoboxCollapse.tap()
            Thread.sleep(forTimeInterval: 0.25)
        }

        let bonuses = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS[c] %@", "Scrollable Equipment bonuses table"))
            .firstMatch
        let generic = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS[c] %@", "Scrollable"))
            .firstMatch

        var scroller: XCUIElement?
        for _ in 0..<12 {
            if bonuses.exists {
                scroller = bonuses
                break
            }
            if generic.exists, generic.label.localizedCaseInsensitiveContains("table") {
                scroller = generic
                break
            }
            Thread.sleep(forTimeInterval: 0.4)
            if !bonuses.exists {
                webView.swipeUp()
            }
        }
        guard let localSurface = scroller, localSurface.exists else {
            XCTFail("Fail closed: no in-article horizontal scroller (Scrollable … table) found")
            struct MissingScroller: Error {}
            throw MissingScroller()
        }

        for _ in 0..<10 {
            let frame = localSurface.frame
            let web = webView.frame
            let inViewport = frame.maxY > web.minY + 64 && frame.minY < web.maxY - 80
            if inViewport { break }
            if frame.maxY <= web.minY + 64 {
                webView.swipeDown()
            } else {
                webView.swipeUp()
            }
        }
        return localSurface
    }

    private func inElementDragPoints(
        on localSurface: XCUIElement,
        webView: XCUIElement
    ) -> (start: XCUICoordinate, endRight: XCUICoordinate, endLeft: XCUICoordinate, startXInWindow: CGFloat) {
        let webFrame = webView.frame
        let surfaceFrame = localSurface.frame
        let dragFrame: CGRect
        if surfaceFrame.height >= 48, surfaceFrame.width >= 80 {
            dragFrame = surfaceFrame
        } else {
            dragFrame = CGRect(
                x: webFrame.minX + webFrame.width * 0.22,
                y: max(webFrame.minY + 96, surfaceFrame.midY - 20),
                width: webFrame.width * 0.56,
                height: 40
            )
        }

        let startPoint = CGPoint(x: dragFrame.minX + dragFrame.width * 0.38, y: dragFrame.midY)
        let rightPoint = CGPoint(x: dragFrame.minX + dragFrame.width * 0.88, y: dragFrame.midY)
        let leftPoint = CGPoint(x: dragFrame.minX + dragFrame.width * 0.10, y: dragFrame.midY)
        let window = app.frame
        func coordinate(at point: CGPoint) -> XCUICoordinate {
            app.coordinate(withNormalizedOffset: CGVector(
                dx: point.x / window.width,
                dy: point.y / window.height
            ))
        }
        return (
            start: coordinate(at: startPoint),
            endRight: coordinate(at: rightPoint),
            endLeft: coordinate(at: leftPoint),
            startXInWindow: startPoint.x
        )
    }

    private func assertStillOnGloryArticle(_ message: String) {
        XCTAssertTrue(
            articleWebView().waitForExistence(timeout: 2),
            "\(message): article_web_view must remain"
        )
        XCTAssertTrue(
            app.buttons["article_back_button"].waitForExistence(timeout: 2),
            "\(message): article back button must remain"
        )
        XCTAssertFalse(
            app.staticTexts["Search History"].exists,
            "\(message): Search History means the in-element drag popped"
        )
        XCTAssertFalse(
            app.otherElements["search_screen"].exists,
            "\(message): search_screen means the in-element drag popped"
        )
    }

    private func articleWebView() -> XCUIElement {
        let identified = app.webViews["article_web_view"]
        return identified.exists ? identified : app.webViews.firstMatch
    }

    private func contentsDrawer() -> XCUIElement {
        let panel = app.otherElements["contents_drawer"]
        return panel.exists ? panel : app.scrollViews["contents_drawer"]
    }

    private func contentsDrawerIsVisiblyOpen() -> Bool {
        let drawer = contentsDrawer()
        guard drawer.exists else { return false }
        return drawer.frame.minX < app.frame.width * 0.75 && drawer.frame.width > 40
    }

    private func attachScreenshot(named name: String) {
        let shot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        if let evidenceDir = ProcessInfo.processInfo.environment["OSRS_QA_EVIDENCE_DIR"],
           !evidenceDir.isEmpty {
            let url = URL(fileURLWithPath: evidenceDir).appendingPathComponent("\(name).png")
            try? FileManager.default.createDirectory(
                at: URL(fileURLWithPath: evidenceDir),
                withIntermediateDirectories: true
            )
            try? shot.pngRepresentation.write(to: url)
        }
    }
}
