import XCTest
import UIKit

final class ArticleFeedbackFixesUITests: XCTestCase {
    private var app: XCUIApplication!

    override func tearDownWithError() throws {
        app = nil
    }

    func testHeroesGuildContentsUsesOneFloorDialectAndJumpsToBasement() throws {
        launchArticle(title: "Heroes' Guild", path: "Heroes'_Guild")
        ensureArticleVisible(title: "Heroes' Guild")
        openContents()

        let drawer = contentsDrawer()
        if usesUSFloorConvention() {
            XCTAssertTrue(drawerLabel("2nd floor").waitForExistence(timeout: 8), app.debugDescription)
            XCTAssertTrue(drawerLabel("3rd floor").exists || drawerLabel("2nd floor").exists)
        } else {
            XCTAssertTrue(drawerLabel("1st floor").waitForExistence(timeout: 8), app.debugDescription)
            XCTAssertTrue(drawerLabel("2nd floor").exists)
        }
        XCTAssertTrue(drawerLabel("Basement").exists)
        XCTAssertFalse(drawerLabel("1st floor2nd floor").exists)
        XCTAssertFalse(drawerLabel("2nd floor3rd floor").exists)
        XCTAssertEqual(
            drawer.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "[UK]")).count,
            0
        )
        XCTAssertEqual(
            drawer.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "[US]")).count,
            0
        )

        let webView = articleWebView()
        let before = webView.screenshot().pngRepresentation
        drawerLabel("Basement").tap()
        XCTAssertTrue(webView.waitForExistence(timeout: 5))

        var moved = false
        for _ in 0..<12 {
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
            if webView.screenshot().pngRepresentation != before {
                moved = true
                break
            }
        }
        XCTAssertTrue(moved, "Tapping Basement in contents should scroll the article")
        attachScreenshot(named: "heroes-guild-after-basement-jump")
    }

    func testLumbridgeCastleContentsUsesOneFloorDialect() throws {
        launchArticle(title: "Lumbridge Castle", path: "Lumbridge_Castle")
        ensureArticleVisible(title: "Lumbridge Castle")
        openContents()

        let concatenated = contentsDrawer().descendants(matching: .any).matching(
            NSPredicate(format: "label MATCHES %@", #".*floor.*floor.*"#)
        )
        XCTAssertEqual(concatenated.count, 0, "Floor headings must show one dialect, not concatenated GB+US text")
        XCTAssertTrue(
            drawerLabelMatching("floor").exists
                || drawerLabel("Basement").exists
                || drawerLabel("Ground floor").exists,
            app.debugDescription
        )
        attachScreenshot(named: "lumbridge-castle-contents")
    }

    func testTwoBackSwipesInQuickSuccessionLeaveTheArticleStack() throws {
        launchArticle(title: "The Blood Moon Rises", path: "The_Blood_Moon_Rises")
        XCTAssertTrue(articleWebView().waitForExistence(timeout: 25))

        let quickGuideLink = app.links.matching(NSPredicate(format: "label CONTAINS[c] %@", "quick guide")).firstMatch
        XCTAssertTrue(quickGuideLink.waitForExistence(timeout: 20), app.debugDescription)
        quickGuideLink.tap()
        XCTAssertTrue(app.staticTexts["The Blood Moon Rises/Quick guide"].waitForExistence(timeout: 20))

        let webView = articleWebView()
        swipeBack(on: webView)
        swipeBack(on: webView)

        XCTAssertTrue(
            app.otherElements["search_screen"].waitForExistence(timeout: 4)
                || app.searchFields.firstMatch.waitForExistence(timeout: 4),
            "A second back swipe must not wait for the first settle or page load to finish. \(app.debugDescription)"
        )
        attachScreenshot(named: "after-two-quick-back-swipes")
    }

    func testInfoboxStateChipsDoNotShiftArticleChrome() throws {
        assertInfoboxStateChipsKeepChromePinned(
            title: "Amulet of glory",
            path: "Amulet_of_glory",
            chips: ["Uncharged", "1", "2", "6"],
            screenshotName: "glory-after-state-taps"
        )
    }

    func testInfoboxStateChipsDoNotShiftArticleChromeOnRingOfWealth() throws {
        assertInfoboxStateChipsKeepChromePinned(
            title: "Ring of wealth",
            path: "Ring_of_wealth",
            chips: ["Uncharged", "1", "5"],
            screenshotName: "ring-of-wealth-after-state-taps"
        )
    }

    func testContentsSwipeWorksBeforeArticleFinishesLoading() throws {
        launchArticle(
            title: "Amulet of glory",
            path: "Amulet_of_glory",
            extraArguments: ["-disableBackgroundPreloading"]
        )

        let webView = articleWebView()
        XCTAssertTrue(webView.waitForExistence(timeout: 8))

        let start = webView.coordinate(withNormalizedOffset: CGVector(dx: 0.78, dy: 0.55))
        let end = webView.coordinate(withNormalizedOffset: CGVector(dx: 0.28, dy: 0.55))
        start.press(forDuration: 0.02, thenDragTo: end, withVelocity: XCUIGestureVelocity(700), thenHoldForDuration: 0)

        XCTAssertTrue(
            waitForContentsDrawerVisible(timeout: 5),
            "A left swipe must open contents while the article is still loading. \(app.debugDescription)"
        )
        attachScreenshot(named: "contents-during-load")
    }

    func testSlowContentsOpenSwipeSettlesToFullyOpen() throws {
        launchArticle(title: "Varrock", path: "Varrock")
        let webView = articleWebView()
        XCTAssertTrue(webView.waitForExistence(timeout: 25))

        let start = webView.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.52))
        let mid = webView.coordinate(withNormalizedOffset: CGVector(dx: 0.55, dy: 0.52))
        start.press(
            forDuration: 0.12,
            thenDragTo: mid,
            withVelocity: XCUIGestureVelocity(80),
            thenHoldForDuration: 0.35
        )

        XCTAssertTrue(
            waitForContentsDrawerVisible(timeout: 5),
            "A slow left swipe must keep travelling into a fully open contents drawer. \(app.debugDescription)"
        )
        attachScreenshot(named: "contents-after-slow-open-swipe")
    }

    func testSlowDownwardContentsDismissDoesNotFreeze() throws {
        launchArticle(title: "Varrock", path: "Varrock")
        XCTAssertTrue(articleWebView().waitForExistence(timeout: 25))
        openContents()

        let drawer = contentsDrawer()
        let start = drawer.coordinate(withNormalizedOffset: CGVector(dx: 0.45, dy: 0.35))
        let end = drawer.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.62))
        start.press(
            forDuration: 0.18,
            thenDragTo: end,
            withVelocity: XCUIGestureVelocity(55),
            thenHoldForDuration: 0.45
        )

        let deadline = Date().addingTimeInterval(4)
        var stillVisible = true
        while Date() < deadline {
            stillVisible = drawer.exists && drawer.frame.minX < app.frame.width - 80
            if !stillVisible { break }
            RunLoop.current.run(until: Date().addingTimeInterval(0.15))
        }
        XCTAssertFalse(
            stillVisible,
            "A slow down-and-right dismiss must finish sliding the drawer away, not freeze mid-gesture. \(app.debugDescription)"
        )
        attachScreenshot(named: "contents-after-slow-down-dismiss")
    }

    func testBackSwipeDuringPageAppearKeepsPreviousArticleVisible() throws {
        launchArticle(title: "The Blood Moon Rises", path: "The_Blood_Moon_Rises")
        XCTAssertTrue(articleWebView().waitForExistence(timeout: 25))

        let quickGuideLink = app.links.matching(NSPredicate(format: "label CONTAINS[c] %@", "quick guide")).firstMatch
        XCTAssertTrue(quickGuideLink.waitForExistence(timeout: 20), app.debugDescription)
        quickGuideLink.tap()

        let webView = articleWebView()
        swipeBack(on: webView)

        let image = XCUIScreen.main.screenshot().image
        XCTAssertFalse(
            isUniformBlackFlash(image),
            "A back swipe during the incoming page animation must keep the previous article visible, not a black underlay"
        )
        XCTAssertTrue(
            app.staticTexts["The Blood Moon Rises"].waitForExistence(timeout: 4)
                || app.staticTexts["The Blood Moon Rises/Quick guide"].exists
                || webView.exists,
            app.debugDescription
        )
        attachScreenshot(named: "back-swipe-during-appear")
    }

    private func usesUSFloorConvention() -> Bool {
        let region = Locale.current.region?.identifier.uppercased()
            ?? Locale.current.regionCode?.uppercased()
            ?? ""
        return [
            "US", "AS", "GU", "MP", "PR", "VI", "UM",
            "CA", "MX", "BR",
            "JP", "KR", "CN", "TW", "PH", "RU"
        ].contains(region)
    }

    private func isUniformBlackFlash(_ image: UIImage) -> Bool {
        guard let cg = image.cgImage else { return false }
        let width = 16
        let height = 16
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        guard let ctx = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return false
        }
        ctx.interpolationQuality = .none
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
        var total = 0
        var minLuma = 255
        var maxLuma = 0
        let count = width * height
        for index in 0..<count {
            let offset = index * 4
            let luma = (Int(pixels[offset]) + Int(pixels[offset + 1]) + Int(pixels[offset + 2])) / 3
            total += luma
            minLuma = min(minLuma, luma)
            maxLuma = max(maxLuma, luma)
        }
        return (total / count) < 16 && (maxLuma - minLuma) < 10
    }

    private func assertInfoboxStateChipsKeepChromePinned(
        title: String,
        path: String,
        chips: [String],
        screenshotName: String
    ) {
        launchArticle(title: title, path: path)
        ensureArticleVisible(title: title)

        let heading = app.staticTexts[title].firstMatch
        XCTAssertTrue(heading.waitForExistence(timeout: 20), app.debugDescription)
        let webView = articleWebView()
        XCTAssertTrue(webView.waitForExistence(timeout: 8))

        let titleY = heading.frame.minY
        let webY = webView.frame.minY
        XCTAssertGreaterThan(titleY, 48, "Page title must sit below overlay chrome, not under it")

        for chip in chips {
            tapInfoboxChip(chip)
            RunLoop.current.run(until: Date().addingTimeInterval(0.45))
            XCTAssertEqual(
                heading.frame.minY,
                titleY,
                accuracy: 2.0,
                "Tapping infobox state '\(chip)' shifted the page title"
            )
            XCTAssertEqual(
                webView.frame.minY,
                webY,
                accuracy: 2.0,
                "Tapping infobox state '\(chip)' shifted the article web view"
            )
        }
        attachScreenshot(named: screenshotName)
    }

    private func tapInfoboxChip(_ label: String) {
        let webView = articleWebView()
        let exact = webView.descendants(matching: .any).matching(NSPredicate(format: "label == %@", label)).firstMatch
        if exact.waitForExistence(timeout: 2), exact.isHittable {
            exact.tap()
            return
        }

        // WebKit often concatenates the chip row into one AX node:
        // "Uncharged\n1\n2\n3\n4\n5\n6". Tap the top strip of that node.
        let grouped = webView.descendants(matching: .any).matching(
            NSPredicate(format: "label CONTAINS[c] %@", label)
        ).firstMatch
        XCTAssertTrue(grouped.waitForExistence(timeout: 8), app.debugDescription)
        let lines = grouped.label
            .split(whereSeparator: { $0.isNewline || $0 == " " })
            .map(String.init)
            .filter { !$0.isEmpty }
        let index = lines.firstIndex { $0.caseInsensitiveCompare(label) == .orderedSame } ?? 0
        let count = max(lines.count, 1)
        let dx = (CGFloat(index) + 0.5) / CGFloat(count)
        grouped.coordinate(withNormalizedOffset: CGVector(dx: dx, dy: 0.03)).tap()
    }

    private func launchArticle(title: String, path: String, extraArguments: [String] = []) {
        app = XCUIApplication()
        app.launchArguments = [
            "-disableSearchAutofocusForUITests",
            "-startTab",
            "search",
            "-startArticleTitle",
            title,
            "-startArticleURL",
            wikiArticleURL(path: path),
            "-allowProxyStartupDuringTests"
        ] + extraArguments
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 12))
    }

    private func ensureArticleVisible(title: String) {
        if articleWebView().waitForExistence(timeout: 25) {
            return
        }
        openArticleFromSearch(title: title)
        XCTAssertTrue(articleWebView().waitForExistence(timeout: 25), app.debugDescription)
    }

    private func openArticleFromSearch(title: String) {
        let launcher = app.buttons["search_history_launcher"]
        if launcher.waitForExistence(timeout: 4) {
            launcher.tap()
        } else {
            let searchBar = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Search OSRS Wiki")).firstMatch
            if searchBar.waitForExistence(timeout: 4) {
                searchBar.tap()
            } else {
                let searchTab = app.buttons["Search"].firstMatch
                if searchTab.exists {
                    searchTab.tap()
                }
            }
        }
        let field: XCUIElement
        if app.searchFields.firstMatch.waitForExistence(timeout: 4) {
            field = app.searchFields.firstMatch
        } else {
            field = app.textFields.firstMatch
        }
        XCTAssertTrue(field.waitForExistence(timeout: 8), app.debugDescription)
        field.tap()
        field.typeText(title)
        let exactRow = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH[c] %@", "\(title),")
        ).firstMatch
        if exactRow.waitForExistence(timeout: 8) {
            exactRow.tap()
            return
        }
        let exactTitle = app.staticTexts[title]
        if exactTitle.waitForExistence(timeout: 4) {
            exactTitle.tap()
            return
        }
        let result = app.descendants(matching: .any).matching(
            NSPredicate(format: "label == %@", title)
        ).firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 15), app.debugDescription)
        result.tap()
    }

    private func wikiArticleURL(path: String) -> String {
        let encoded = path.replacingOccurrences(of: "'", with: "%27")
        return "https://oldschool.runescape.wiki/w/\(encoded)"
    }

    private func openContents() {
        let contentsButton = app.buttons.matching(
            NSPredicate(format: "identifier == %@ AND label == %@", "article_bottom_bar", "Contents")
        ).firstMatch
        if !contentsButton.waitForExistence(timeout: 8) {
            let labeled = app.buttons["Contents"].firstMatch
            XCTAssertTrue(labeled.waitForExistence(timeout: 12), app.debugDescription)
            labeled.tap()
        } else {
            contentsButton.tap()
        }
        XCTAssertTrue(
            waitForContentsDrawerVisible(timeout: 5),
            "Contents control was not tappable. \(app.debugDescription)"
        )
    }

    private func contentsDrawer() -> XCUIElement {
        let panel = app.otherElements["contents_drawer"]
        return panel.exists ? panel : app.scrollViews["contents_drawer"]
    }

    private func waitForContentsDrawerVisible(timeout: TimeInterval) -> Bool {
        let drawer = contentsDrawer()
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if drawer.exists && drawer.frame.minX < app.frame.width - 80 {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.15))
        }
        return false
    }

    private func drawerLabel(_ label: String) -> XCUIElement {
        contentsDrawer().descendants(matching: .any).matching(
            NSPredicate(format: "label == %@", label)
        ).firstMatch
    }

    private func drawerLabelMatching(_ substring: String) -> XCUIElement {
        contentsDrawer().descendants(matching: .any).matching(
            NSPredicate(format: "label CONTAINS[c] %@", substring)
        ).firstMatch
    }

    private func swipeBack(on webView: XCUIElement) {
        let start = webView.coordinate(withNormalizedOffset: CGVector(dx: 0.10, dy: 0.52))
        let end = webView.coordinate(withNormalizedOffset: CGVector(dx: 0.78, dy: 0.52))
        start.press(forDuration: 0.02, thenDragTo: end, withVelocity: XCUIGestureVelocity(900), thenHoldForDuration: 0)
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
