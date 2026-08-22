import XCTest
import UIKit

final class osrsSceneHostResumeUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testHomeResumeKeepsTabHostAndDoesNotInstallFakeWikiChrome() {
        let app = XCUIApplication()
        app.launchArguments = ["-osrsUITestHarness", "-startTab", "news"]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 12))

        let host = app.descendants(matching: .any)["osrs_app_root_tab_host"]
        XCTAssertTrue(host.waitForExistence(timeout: 12), "CustomMainTabView host should stay installed")
        XCTAssertTrue(
            app.otherElements["home_screen"].waitForExistence(timeout: 12)
                || app.staticTexts["Updates"].waitForExistence(timeout: 8),
            "Home feed should be visible after launch"
        )

        XCUIDevice.shared.press(.home)
        XCTAssertTrue(app.wait(for: .runningBackground, timeout: 8) || app.state == .runningBackgroundSuspended)
        app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 12))

        XCTAssertTrue(host.waitForExistence(timeout: 8), "Resume must keep CustomMainTabView, not a parallel wiki host")
        XCTAssertFalse(app.searchFields["article_search_bar"].exists)
        XCTAssertTrue(
            app.otherElements["home_screen"].waitForExistence(timeout: 8)
                || app.tabBars.buttons["Home"].exists
                || app.tabBars.buttons["home_tab"].exists,
            "Home resume should restore Home, not article chrome"
        )
    }

    func testSearchGloryOpensInAppArticleWithoutTerminating() {
        let app = XCUIApplication()
        app.launchArguments = ["-osrsUITestHarness"]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 12))

        let homeSearch = app.buttons["Search OSRS Wiki"]
        XCTAssertTrue(homeSearch.waitForExistence(timeout: 12), "Home search bar should exist")
        homeSearch.tap()

        let searchField = app.textFields["Search OSRS Wiki"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 10), "Search field should appear")
        searchField.tap()
        searchField.typeText("Amulet of glory")

        let identified = app.buttons["search_result_row_Amulet of glory"]
        let labeled = app.staticTexts.matching(NSPredicate(format: "label == %@", "Amulet of glory")).firstMatch
        let result = identified.waitForExistence(timeout: 8) ? identified : labeled
        XCTAssertTrue(result.waitForExistence(timeout: 16), "Exact Amulet of glory result should become tappable")
        result.tap()

        XCTAssertEqual(app.state, .runningForeground, "Opening Glory must not terminate the app")
        XCTAssertTrue(
            app.descendants(matching: .any)["osrs_app_root_tab_host"].waitForExistence(timeout: 8),
            "Article open must stay on CustomMainTabView"
        )
        XCTAssertFalse(app.searchFields["article_search_bar"].exists)
        XCTAssertTrue(
            app.otherElements["article_bottom_bar"].waitForExistence(timeout: 16)
                || app.buttons["Save"].waitForExistence(timeout: 8),
            "In-app article chrome should appear"
        )
    }

    func testDarkArticleResumeKeepsRenderedContentNotThemedBlank() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-osrsUITestHarness",
            "-forceThemeForUITests", "osrs_dark",
            "-startArticleTitle", "Amulet of glory",
            "-startArticleURL", "https://oldschool.runescape.wiki/w/Amulet_of_glory"
        ]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 12))

        let webView = app.webViews["article_web_view"].exists
            ? app.webViews["article_web_view"]
            : app.webViews.firstMatch
        XCTAssertTrue(webView.waitForExistence(timeout: 30), "Glory article WebView should appear")
        waitUntilRendered(webView, timeout: 20)
        let before = webView.screenshot().image
        XCTAssertGreaterThan(
            luminanceRange(before),
            24,
            "Loaded Glory must have article contrast, not a uniform themed fill"
        )

        backgroundAndForeground(app)
        XCTAssertTrue(webView.waitForExistence(timeout: 12))
        waitUntilRendered(webView, timeout: 8)
        let after = XCUIScreen.main.screenshot().image
        XCTAssertGreaterThan(
            luminanceRange(after),
            24,
            "Resume must restore article pixels, not a uniform themed blank page"
        )
        XCTAssertTrue(
            app.otherElements["article_bottom_bar"].waitForExistence(timeout: 8)
                || app.buttons["Save"].waitForExistence(timeout: 4)
                || app.staticTexts["Amulet of glory"].waitForExistence(timeout: 4),
            "Resumed article must keep in-app chrome"
        )

        backgroundAndForeground(app)
        let afterSecond = XCUIScreen.main.screenshot().image
        XCTAssertGreaterThan(
            luminanceRange(afterSecond),
            24,
            "Second resume must still keep rendered article content"
        )
    }

    func testVarrockResumeKeepsRenderedContent() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-osrsUITestHarness",
            "-forceThemeForUITests", "osrs_dark",
            "-startArticleTitle", "Varrock",
            "-startArticleURL", "https://oldschool.runescape.wiki/w/Varrock"
        ]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 12))
        let webView = app.webViews.firstMatch
        XCTAssertTrue(webView.waitForExistence(timeout: 30))
        waitUntilRendered(webView, timeout: 20)
        backgroundAndForeground(app)
        XCTAssertGreaterThan(
            luminanceRange(XCUIScreen.main.screenshot().image),
            24,
            "Varrock resume must not collapse to a uniform themed blank"
        )
        XCTAssertTrue(
            app.staticTexts["Varrock"].waitForExistence(timeout: 8)
                || app.otherElements["article_bottom_bar"].waitForExistence(timeout: 8)
        )
    }

    func testHomeDoubleResumeAndArticleResumeKeepHost() {
        let app = XCUIApplication()
        app.launchArguments = ["-osrsUITestHarness", "-startTab", "news"]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 12))

        let host = app.descendants(matching: .any)["osrs_app_root_tab_host"]
        XCTAssertTrue(host.waitForExistence(timeout: 12))
        backgroundAndForeground(app)
        backgroundAndForeground(app)
        XCTAssertTrue(host.waitForExistence(timeout: 8), "Second Home resume must keep CustomMainTabView")
        XCTAssertTrue(
            app.otherElements["home_screen"].waitForExistence(timeout: 8)
                || app.staticTexts["Updates"].waitForExistence(timeout: 8),
            "Home must remain Home after two background cycles"
        )

        openGloryArticle(in: app)
        backgroundAndForeground(app)
        backgroundAndForeground(app)
        XCTAssertEqual(app.state, .runningForeground)
        XCTAssertTrue(host.waitForExistence(timeout: 8), "Article resume must keep CustomMainTabView")
        XCTAssertTrue(
            app.otherElements["article_bottom_bar"].waitForExistence(timeout: 12)
                || app.buttons["Save"].waitForExistence(timeout: 8),
            "Resumed article must keep in-app chrome"
        )
    }

    func testHomeUpdateCardAndViewMoreStayInAppScopedSearch() {
        let app = XCUIApplication()
        app.launchArguments = ["-osrsUITestHarness", "-startTab", "news"]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 12))

        let updateCard = app.descendants(matching: .any)["home_update_card"].firstMatch
        XCTAssertTrue(updateCard.waitForExistence(timeout: 20), "Home update cards should load")
        updateCard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        assertInAppArticleChrome(in: app)

        let back = app.descendants(matching: .any)["immediate_search_back_button"].firstMatch
        if back.waitForExistence(timeout: 2), back.isHittable {
            back.tap()
        } else if app.buttons["Back"].waitForExistence(timeout: 2) {
            app.buttons["Back"].tap()
        } else {
            app.swipeRight()
        }

        let viewMore = app.descendants(matching: .any)["home_updates_view_more"].firstMatch
        XCTAssertTrue(viewMore.waitForExistence(timeout: 12), "View more should return with Home")
        viewMore.tap()

        XCTAssertTrue(
            app.descendants(matching: .any)["scoped_search_updates"].waitForExistence(timeout: 12),
            "View more must open the reusable Update-namespace Search destination"
        )
        let scopedField = element(in: app, identifier: "immediate_search_input")
        let placeholderField = app.descendants(matching: .any)["Search updates"].firstMatch
        XCTAssertTrue(
            scopedField.waitForExistence(timeout: 8) || placeholderField.waitForExistence(timeout: 8),
            "Scoped Search must advertise Search updates, not unfiltered Search"
        )

        let browseRow = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "search_result_row_"))
            .firstMatch
        XCTAssertTrue(browseRow.waitForExistence(timeout: 20), "Empty Update search must list newest Update: pages")
        browseRow.tap()
        assertInAppArticleChrome(in: app)

        let articleBack = app.descendants(matching: .any)["immediate_search_back_button"].firstMatch
        if articleBack.waitForExistence(timeout: 4), articleBack.isHittable {
            articleBack.tap()
        } else if app.buttons["Back"].waitForExistence(timeout: 2) {
            app.buttons["Back"].tap()
        } else {
            app.swipeRight()
        }
        XCTAssertEqual(app.state, .runningForeground, "Backing out of a View more article must not crash")
        XCTAssertTrue(
            app.descendants(matching: .any)["scoped_search_updates"].waitForExistence(timeout: 12),
            "Back from a View more article should return to the updates list"
        )
    }

    func testSavedArticleOpensInAppHost() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-osrsUITestHarness",
            "-startTab", "saved",
            "-resetSavedPagesForUITests",
            "-seedSavedPagesForUITests"
        ]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 12))
        let row = app.descendants(matching: .any)["saved_page_row"].firstMatch
        XCTAssertTrue(
            row.waitForExistence(timeout: 10) || app.staticTexts["Varrock"].waitForExistence(timeout: 10),
            "Seeded Varrock row should be visible"
        )
        if row.exists {
            row.tap()
        } else {
            app.staticTexts["Varrock"].tap()
        }
        assertInAppArticleChrome(in: app)
    }

    func testAppearanceThemeSwitchStaysOnPage() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-osrsUITestHarness",
            "-startTab", "more",
            "-startMoreDestination", "appearance",
            "-forceThemeForUITests", "osrs_light"
        ]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 12))
        XCTAssertTrue(app.descendants(matching: .any)["appearance_screen"].waitForExistence(timeout: 10))
        let themePicker = app.descendants(matching: .any)["appearance_theme_picker"].firstMatch
        XCTAssertTrue(themePicker.waitForExistence(timeout: 8))
        themePicker.tap()
        let dark = app.buttons["Dark"].firstMatch.exists ? app.buttons["Dark"].firstMatch : app.staticTexts["Dark"].firstMatch
        XCTAssertTrue(dark.waitForExistence(timeout: 5), "Theme menu should expose Dark")
        dark.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["appearance_screen"].waitForExistence(timeout: 8),
            "Theme switch must stay on Appearance"
        )
        XCTAssertTrue(app.switches["appearance_collapse_tables_toggle"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.descendants(matching: .any)["osrs_app_root_tab_host"].waitForExistence(timeout: 8))
    }

    private func backgroundAndForeground(_ app: XCUIApplication) {
        XCUIDevice.shared.press(.home)
        XCTAssertTrue(app.wait(for: .runningBackground, timeout: 8) || app.state == .runningBackgroundSuspended)
        app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 12))
    }

    private func openGloryArticle(in app: XCUIApplication) {
        let homeSearch = app.buttons["Search OSRS Wiki"]
        if homeSearch.waitForExistence(timeout: 4) {
            homeSearch.tap()
        } else {
            app.buttons["search_tab"].tap()
        }
        let searchField = app.textFields["Search OSRS Wiki"].exists
            ? app.textFields["Search OSRS Wiki"]
            : app.textFields["immediate_search_input"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 10))
        searchField.tap()
        searchField.typeText("Amulet of glory")
        let identified = app.buttons["search_result_row_Amulet of glory"]
        let labeled = app.staticTexts.matching(NSPredicate(format: "label == %@", "Amulet of glory")).firstMatch
        let result = identified.waitForExistence(timeout: 8) ? identified : labeled
        XCTAssertTrue(result.waitForExistence(timeout: 16))
        result.tap()
        assertInAppArticleChrome(in: app)
    }

    private func assertInAppArticleChrome(in app: XCUIApplication) {
        XCTAssertEqual(app.state, .runningForeground, "Article open must not terminate")
        XCTAssertTrue(
            app.descendants(matching: .any)["osrs_app_root_tab_host"].waitForExistence(timeout: 8),
            "Article must stay on CustomMainTabView"
        )
        XCTAssertFalse(app.searchFields["article_search_bar"].exists)
        let bottomBar = element(in: app, identifier: "article_bottom_bar")
        let save = app.buttons["Save"].firstMatch
        let find = app.buttons["Find"].firstMatch
        let webView = app.webViews.firstMatch
        XCTAssertTrue(
            bottomBar.waitForExistence(timeout: 20)
                || save.waitForExistence(timeout: 8)
                || find.waitForExistence(timeout: 8)
                || webView.waitForExistence(timeout: 20),
            "In-app article chrome or WKWebView should appear"
        )
    }

    private func element(in app: XCUIApplication, identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier].firstMatch
    }

    private func waitUntilRendered(_ webView: XCUIElement, timeout: TimeInterval) {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if luminanceRange(webView.screenshot().image) > 24 {
                return
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.4))
        }
        XCTAssertGreaterThan(
            luminanceRange(webView.screenshot().image),
            24,
            "Article WebView did not render contrasting content in time"
        )
    }

    private func luminanceRange(_ image: UIImage) -> Int {
        guard let cg = image.cgImage else { return 0 }
        let width = 24
        let height = 24
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
            return 0
        }
        ctx.interpolationQuality = .none
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
        var minLuma = 255
        var maxLuma = 0
        for index in 0..<(width * height) {
            let offset = index * 4
            let luma = (Int(pixels[offset]) + Int(pixels[offset + 1]) + Int(pixels[offset + 2])) / 3
            minLuma = min(minLuma, luma)
            maxLuma = max(maxLuma, luma)
        }
        return maxLuma - minLuma
    }
}
