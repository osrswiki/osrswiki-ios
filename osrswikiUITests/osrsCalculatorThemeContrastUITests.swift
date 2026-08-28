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

    func testAgilityNativeCalcFirstOpenUsesContentColumnWidthWithoutSwipe() throws {
        func openAndMeasure(shot: String) throws -> (boxWidth: CGFloat, viewport: CGFloat, inset: Bool) {
            let app = launchArticle(title: "Calculator:Agility", path: "Calculator:Agility")
            let webView = articleWebView(in: app)
            XCTAssertTrue(webView.waitForExistence(timeout: articleLoadTimeout), app.debugDescription)
            let form = app.webViews.otherElements["Agility calculator"].firstMatch
            let nameField = app.webViews.textFields["Name"].firstMatch
            let header = labeledControl("Calculator Tap to collapse", in: app)
            _ = form.waitForExistence(timeout: 12) || nameField.waitForExistence(timeout: 2)
            _ = header.waitForExistence(timeout: 2)
            writeScratchScreenshot(from: app, name: shot)
            attachScreenshot(from: app, name: shot)
            let box = header.exists && header.frame.width > 1 ? header : (form.exists ? form : nameField)
            XCTAssertTrue(
                box.exists && box.frame.width > 1,
                "calc box missing on first open without swipe. \(app.debugDescription)"
            )
            let viewport = app.frame.width > 1 ? app.frame.width : webView.frame.width
            return (box.frame.width, viewport, box.frame.width < viewport - 8)
        }
        let first = try openAndMeasure(shot: "ios-agility-first-open.png")
        XCTAssertGreaterThan(first.boxWidth, first.viewport * 0.7, "first open leftover skinny. \(first)")
        XCTAssertTrue(first.inset, "first open must stay inset, not full-bleed. \(first)")
        let second = try openAndMeasure(shot: "ios-agility-first-open.png")
        XCTAssertGreaterThan(second.boxWidth, second.viewport * 0.7, "second open leftover skinny. \(second)")
        XCTAssertTrue(second.inset, "second open must stay inset, not full-bleed. \(second)")
        XCTAssertEqual(first.boxWidth, second.boxWidth, accuracy: 12)
    }

    func testAgilityNativeCalcCollapsibleMatchesArticleChrome() throws {
        let app = launchArticle(title: "Calculator:Agility", path: "Calculator:Agility")
        let webView = articleWebView(in: app)
        XCTAssertTrue(webView.waitForExistence(timeout: articleLoadTimeout), app.debugDescription)

        let form = app.webViews.otherElements["Agility calculator"].firstMatch
        let nameField = app.webViews.textFields["Name"].firstMatch
        var header = labeledControl("Calculator Tap to collapse", in: app)
        for _ in 0..<16 {
            if header.exists, header.frame.height > 4, header.frame.minY > 80 {
                break
            }
            if form.exists, form.frame.minY > 80 {
                break
            }
            webView.swipeUp()
            header = labeledControl("Calculator Tap to collapse", in: app)
        }
        XCTAssertTrue(
            header.waitForExistence(timeout: 8) || form.waitForExistence(timeout: 2),
            "Agility calc header never appeared. \(app.debugDescription)"
        )
        writeScratchScreenshot(from: app, name: "ios-agility-open.png")
        attachScreenshot(from: app, name: "ios-agility-open")

        let articleHeader = labeledControl("Navigation Tap to collapse", in: app)
        if articleHeader.exists {
            writeScratchScreenshot(from: app, name: "ios-article-collapsible-ref.png")
            attachScreenshot(from: app, name: "ios-article-collapsible-ref")
        }

        header.tap()
        let expandHint = labeledControl("Calculator Tap to expand", in: app)
        XCTAssertTrue(
            expandHint.waitForExistence(timeout: 6),
            "collapse did not show Tap to expand. \(app.debugDescription)"
        )
        let collapsedForm = app.webViews.otherElements["Agility calculator"].firstMatch
        let collapsedName = app.webViews.textFields["Name"].firstMatch
        _ = collapsedName.waitForNonExistence(timeout: 4)
        XCTAssertFalse(
            (collapsedForm.exists && collapsedForm.isHittable) || (collapsedName.exists && collapsedName.isHittable),
            "in-document calc form leaked after collapse. \(app.debugDescription)"
        )
        writeScratchScreenshot(from: app, name: "ios-agility-collapsed.png")
        attachScreenshot(from: app, name: "ios-agility-collapsed")

        expandHint.tap()
        let collapseHint = labeledControl("Calculator Tap to collapse", in: app)
        XCTAssertTrue(
            collapseHint.waitForExistence(timeout: 6),
            "expand after collapse failed. \(app.debugDescription)"
        )
        XCTAssertTrue(form.waitForExistence(timeout: 4), "native form missing after expand")
        writeScratchScreenshot(from: app, name: "ios-agility-reexpanded.png")
        attachScreenshot(from: app, name: "ios-agility-reexpanded")
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

    private func labeledControl(_ label: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(
            NSPredicate(format: "label == %@", label)
        ).firstMatch
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

    private func writeScratchScreenshot(from app: XCUIApplication, name: String) {
        let scratch = ProcessInfo.processInfo.environment["OSRS_SCRATCH"]
            ?? "/var/folders/vt/gqrlflhj10b1g04_6pcq_q3r0000gn/T/grok-goal-b3bd04458c83/implementer"
        let url = URL(fileURLWithPath: scratch).appendingPathComponent(name)
        try? app.screenshot().pngRepresentation.write(to: url)
    }
}
