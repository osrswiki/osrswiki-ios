import XCTest

/// Visual regression: calculators must match article WebView parchment chrome,
/// not Wikipedia Vector grey, and checkbox/int labels must stay on-screen.
final class osrsCalculatorThemeContrastUITests: XCTestCase {
    private let launchTimeout: TimeInterval = 15
    private let articleLoadTimeout: TimeInterval = 35

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testVarrockArticleProvidesParchmentContrastFixture() throws {
        let app = launchArticle(title: "Varrock", path: "Varrock")
        XCTAssertTrue(
            app.staticTexts["Varrock"].waitForExistence(timeout: articleLoadTimeout),
            app.debugDescription
        )
        attachScreenshot(from: app, name: "calculator-theme-contrast-varrock")
    }

    func testBarrowsCheckboxLabelsStayOnscreenAndThemed() throws {
        let app = launchArticle(title: "Calculator:Barrows", path: "Calculator:Barrows")
        let webView = articleWebView(in: app)
        let ahrim = firstMatchingControl("Ahrim?", in: app, webView: webView)
        XCTAssertTrue(ahrim.waitForExistence(timeout: articleLoadTimeout), app.debugDescription)
        XCTAssertGreaterThan(
            ahrim.frame.width,
            24,
            "Ahrim? was clipped off-screen by desktop OOUI align-right layout. \(ahrim.frame)"
        )
        XCTAssertTrue(
            ahrim.isHittable || ahrim.frame.minX >= 0,
            "Ahrim? must be visible next to the checkbox, not overflow-clipped. \(ahrim.frame)"
        )
        attachScreenshot(from: app, name: "calculator-theme-contrast-barrows")
        assertLastControlClearsTabBar(["Submit", "Calculate"], in: app, webView: webView)
        attachScreenshot(from: app, name: "calculator-theme-contrast-barrows-scrolled")
    }

    func testCombatLevelFieldLabelsStayOnscreenAndThemed() throws {
        let app = launchArticle(title: "Calculator:Combat level", path: "Calculator:Combat_level")
        let webView = articleWebView(in: app)
        let attack = firstMatchingControl("Attack", in: app, webView: webView)
        XCTAssertTrue(attack.waitForExistence(timeout: articleLoadTimeout), app.debugDescription)
        XCTAssertGreaterThan(
            attack.frame.width,
            24,
            "Attack label was clipped off-screen by desktop OOUI align-right layout. \(attack.frame)"
        )
        attachScreenshot(from: app, name: "calculator-theme-contrast-combat")
        assertLastControlClearsTabBar(["Prayer", "Submit"], in: app, webView: webView)
        attachScreenshot(from: app, name: "calculator-theme-contrast-combat-scrolled")
    }

    private func launchArticle(title: String, path: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-osrsUITestHarness",
            "-screenshotMode",
            "-disableBackgroundPreloading",
            "-allowProxyStartupDuringTests",
            "-forceThemeForUITests", "osrs_light",
            "-startTab", "search",
            "-startArticleTitle", title,
            "-startArticleURL", "https://oldschool.runescape.wiki/w/\(path)"
        ]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: launchTimeout))
        XCTAssertTrue(
            app.webViews["article_web_view"].waitForExistence(timeout: articleLoadTimeout) ||
                app.webViews.firstMatch.waitForExistence(timeout: 2),
            app.debugDescription
        )
        return app
    }

    private func articleWebView(in app: XCUIApplication) -> XCUIElement {
        app.webViews["article_web_view"].exists ? app.webViews["article_web_view"] : app.webViews.firstMatch
    }

    private func firstMatchingControl(_ name: String, in app: XCUIApplication, webView: XCUIElement) -> XCUIElement {
        let webMatch = webView.descendants(matching: .any)[name].firstMatch
        if webMatch.exists {
            return webMatch
        }
        return app.descendants(matching: .any)[name].firstMatch
    }

    private func assertLastControlClearsTabBar(
        _ names: [String],
        in app: XCUIApplication,
        webView: XCUIElement
    ) {
        let tabBar = app.descendants(matching: .any)["article_bottom_bar"].firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 5), app.debugDescription)
        var matched: XCUIElement?
        for _ in 0..<12 {
            for name in names {
                let control = firstMatchingControl(name, in: app, webView: webView)
                if control.exists, control.frame.height > 4 {
                    matched = control
                    if control.frame.maxY < tabBar.frame.minY - 8 {
                        return
                    }
                }
            }
            webView.swipeUp()
        }
        XCTAssertNotNil(matched, "Missing \(names.joined(separator: "/")) after scrolling. \(app.debugDescription)")
        guard let control = matched else { return }
        XCTAssertLessThan(
            control.frame.maxY,
            tabBar.frame.minY - 8,
            "\(control.label) is under the More tab bar. control=\(control.frame) tab=\(tabBar.frame)"
        )
    }

    private func attachScreenshot(from app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
