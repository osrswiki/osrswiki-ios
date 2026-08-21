import XCTest

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
}
