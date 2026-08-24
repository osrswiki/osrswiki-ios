import XCTest

final class osrsCalculatorLiveUserUITests: XCTestCase {
    private let launchTimeout: TimeInterval = 15
    private let articleLoadTimeout: TimeInterval = 35
    private let resultTimeout: TimeInterval = 25
    private let saveTimeout: TimeInterval = 45
    private let missingPlayerName = "zzqxxnope"

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testAgilityNativeNameTypingKeepsKeyboardAndParseTable() throws {
        let app = makeApp(
            extraArguments: articleArguments(
                title: "Calculator:Agility",
                path: "Calculator:Agility"
            )
        )
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: launchTimeout))
        XCTAssertTrue(
            app.webViews["article_web_view"].waitForExistence(timeout: articleLoadTimeout) ||
                app.webViews.firstMatch.waitForExistence(timeout: 2),
            app.debugDescription
        )
        let namedById = app.textFields["native-calc-field-name"].firstMatch
        let namedByPlaceholder = app.textFields["Name"].firstMatch
        let nameField = namedById.exists ? namedById : namedByPlaceholder
        var appeared = namedById.waitForExistence(timeout: articleLoadTimeout)
            || namedByPlaceholder.waitForExistence(timeout: 2)
        if !appeared {
            let webView = articleWebView(in: app)
            for _ in 0..<10 {
                webView.swipeUp()
                if nameField.waitForExistence(timeout: 2) {
                    appeared = true
                    break
                }
            }
        }
        XCTAssertTrue(appeared, "Native Name field missing on Calculator:Agility. \(app.debugDescription)")
        if !nameField.isHittable {
            let webView = articleWebView(in: app)
            for _ in 0..<8 where !nameField.isHittable {
                webView.swipeUp()
            }
        }
        saveEvidence(from: app, name: "ios-agility-chrome")
        saveEvidence(from: app, name: "ios-name-before")

        if nameField.isHittable {
            nameField.tap()
        } else {
            nameField.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }
        XCTAssertTrue(
            app.keyboards.firstMatch.waitForExistence(timeout: 8),
            "Software keyboard did not appear after tapping Name. Connect Hardware Keyboard must be off. \(app.debugDescription)"
        )
        saveEvidence(from: app, name: "ios-name-focused")

        try enterWithSoftwareKeyboard("osamo", in: app, numeric: false)
        XCTAssertTrue(app.keyboards.firstMatch.exists, "Keyboard disappeared after typing Name")
        XCTAssertTrue(
            articleWebView(in: app).exists,
            "Article web view vanished while typing Name"
        )
        let typed = (nameField.value as? String) ?? ""
        XCTAssertTrue(typed.contains("osamo") || typed.contains("osa"), "Typed Name characters missing: \(typed)")
        saveEvidence(from: app, name: "ios-name-typed")

        dismissSoftwareKeyboard(in: app)
        let increaseGoal = app.buttons["Increase Goal (per choice above)"].firstMatch
        if increaseGoal.waitForExistence(timeout: 4) {
            for _ in 0..<10 {
                if increaseGoal.isHittable {
                    increaseGoal.tap()
                } else {
                    increaseGoal.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
                }
            }
        }
        let submitById = app.buttons["native-calc-submit"].firstMatch
        let submitByLabel = app.buttons["Submit"].firstMatch
        let submit = submitById.exists ? submitById : submitByLabel
        XCTAssertTrue(
            submitById.waitForExistence(timeout: 4) || submitByLabel.waitForExistence(timeout: 8),
            "Missing native Submit"
        )
        let webView = articleWebView(in: app)
        if !submit.isHittable {
            if app.scrollViews.firstMatch.exists {
                app.scrollViews.firstMatch.swipeUp()
            } else {
                webView.swipeUp()
            }
        }
        if submit.isHittable {
            submit.tap()
        } else {
            submit.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }
        var sawTable = waitForCalculatorText("Plank", in: app, timeout: resultTimeout)
            || waitForCalculatorText("Low wall", in: app, timeout: 2)
        if !sawTable {
            for _ in 0..<8 {
                webView.swipeUp()
                if waitForCalculatorText("Plank", in: app, timeout: 2)
                    || waitForCalculatorText("Low wall", in: app, timeout: 2) {
                    sawTable = true
                    break
                }
            }
        }
        if sawTable {
            let heading = app.staticTexts["Calculator"].firstMatch
            for _ in 0..<8 {
                if heading.exists {
                    heading.swipeUp()
                } else {
                    webView.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.18))
                        .press(
                            forDuration: 0.05,
                            thenDragTo: webView.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75))
                        )
                }
            }
        }
        saveEvidence(from: app, name: "ios-agility-table")
        XCTAssertTrue(
            sawTable,
            "Agility parse table should show Plank/Low wall. \(app.debugDescription)"
        )
    }

    func testCombatLevelCalculatorRendersWikiForm() throws {
        _ = try openCalculator(
            title: "Calculator:Combat level",
            path: "Calculator:Combat_level",
            expectedControl: "Attack"
        )
    }

    func testCookingCalculatorRendersWikiForm() throws {
        _ = try openCalculator(
            title: "Calculator:Cooking",
            path: "Calculator:Cooking",
            expectedControl: "Level"
        )
    }

    func testBarrowsCalculatorRendersWikiForm() throws {
        _ = try openCalculator(
            title: "Calculator:Barrows",
            path: "Calculator:Barrows",
            expectedControl: "Ahrim?"
        )
    }

    func testCombatLevelCalculatorShowsParseResultAfterSoftwareKeyboardSubmit() throws {
        let app = try openCalculator(
            title: "Calculator:Combat level",
            path: "Calculator:Combat_level",
            expectedControl: "Attack"
        )
        let webView = articleWebView(in: app)
        try focusLabeledField("Attack", in: app, webView: webView)
        try clearFocusedFieldWithSoftwareKeyboard(in: app)
        try enterWithSoftwareKeyboard("99", in: app, numeric: true)
        dismissSoftwareKeyboard(in: app)
        try tapCalculatorButton("Submit", in: app, webView: webView)
        XCTAssertTrue(
            waitForCalculatorText("Your combat level is", in: app),
            "Combat parse result should be AX-visible after Submit. \(app.debugDescription)"
        )
        attachScreenshot(from: app, name: "calculator-combat-result")
    }

    func testCombatLevelHiscoresLookupShowsStatsOrMissingPlayer() throws {
        let app = try openCalculator(
            title: "Calculator:Combat level",
            path: "Calculator:Combat_level",
            expectedControl: "Attack"
        )
        let webView = articleWebView(in: app)
        let playerField = webView.textFields["Player name"].firstMatch
        XCTAssertTrue(playerField.waitForExistence(timeout: articleLoadTimeout), "Missing Player name field")
        playerField.tap()
        try enterWithSoftwareKeyboard(missingPlayerName, in: app, numeric: false)
        dismissSoftwareKeyboard(in: app)
        let lookup = firstMatchingControl("Lookup", in: app, webView: webView)
        XCTAssertTrue(lookup.waitForExistence(timeout: 8), "Missing Lookup button")
        XCTAssertTrue(lookup.isHittable || lookup.isEnabled, "Lookup should be tappable after entering a player name")
        lookup.tap()
        let sawMissingPlayer = waitForCalculatorText("does not exist", in: app)
            || waitForCalculatorText("is banned or unranked", in: app)
            || waitForCalculatorText("couldn't fetch your hiscores", in: app)
        let sawFilledStats = waitForCalculatorText("Your combat level is", in: app)
        XCTAssertTrue(
            sawMissingPlayer || sawFilledStats,
            "Hiscores Lookup should fill stats or show the wiki missing-player sentence. \(app.debugDescription)"
        )
        attachScreenshot(from: app, name: "calculator-combat-lookup")
    }

    func testSavedCombatCalculatorComputesOfflineFromWarmedDefaultParse() throws {
        let onlineApp = makeApp(
            extraArguments: articleArguments(
                title: "Calculator:Combat level",
                path: "Calculator:Combat_level"
            ) + ["-osrsCalculatorSmokeSubmit"]
        )
        onlineApp.launch()
        XCTAssertTrue(onlineApp.wait(for: .runningForeground, timeout: launchTimeout))
        let webView = articleWebView(in: onlineApp)
        let attack = firstMatchingControl("Attack", in: onlineApp, webView: webView)
        XCTAssertTrue(attack.waitForExistence(timeout: articleLoadTimeout), onlineApp.debugDescription)
        try saveCurrentArticle(named: "Calculator:Combat level", in: onlineApp)
        onlineApp.terminate()

        let offlineApp = makeApp(
            startTab: "saved",
            extraArguments: [
                "-forceNetworkOfflineForUITests",
                "-allowProxyStartupDuringTests",
                "-osrsCalculatorSmokeSubmit"
            ],
            resetSavedPages: false
        )
        offlineApp.launch()
        XCTAssertTrue(offlineApp.wait(for: .runningForeground, timeout: launchTimeout))
        try openSavedArticle(named: "Calculator:Combat level", in: offlineApp)
        let offlineWebView = articleWebView(in: offlineApp)
        let offlineAttack = firstMatchingControl("Attack", in: offlineApp, webView: offlineWebView)
        XCTAssertTrue(
            offlineAttack.waitForExistence(timeout: articleLoadTimeout),
            "Saved Combat calculator should still render offline. failedLoad=\(offlineApp.staticTexts["Failed to Load Page"].exists) \(offlineApp.debugDescription)"
        )
        try tapCalculatorButton("Submit", in: offlineApp, webView: offlineWebView)
        XCTAssertTrue(
            waitForCalculatorText("Your combat level is", in: offlineApp),
            "Offline Combat submit should replay the warmed default parse. \(offlineApp.debugDescription)"
        )
        attachScreenshot(from: offlineApp, name: "calculator-combat-offline")
    }

    @discardableResult
    private func openCalculator(title: String, path: String, expectedControl: String) throws -> XCUIApplication {
        let app = makeApp(
            extraArguments: articleArguments(title: title, path: path)
        )
        app.launch()

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: launchTimeout))
        XCTAssertTrue(
            app.webViews["article_web_view"].waitForExistence(timeout: articleLoadTimeout) ||
                app.webViews.firstMatch.waitForExistence(timeout: 2),
            app.debugDescription
        )
        let webView = articleWebView(in: app)
        let formControl = firstMatchingControl(expectedControl, in: app, webView: webView)
        var appeared = formControl.waitForExistence(timeout: 12)
        if !appeared {
            for _ in 0..<8 {
                webView.swipeUp()
                if formControl.waitForExistence(timeout: 2) {
                    appeared = true
                    break
                }
            }
        }
        attachScreenshot(from: app, name: "calculator-\(path)")
        XCTAssertTrue(
            appeared,
            "Wiki calculator form did not render \(expectedControl) on \(title). \(app.debugDescription)"
        )
        let leftoverPlaceholder = app.staticTexts["Please wait for the form to load"].exists
            || app.staticTexts["This calculator requires JavaScript to run"].exists
            || app.staticTexts.matching(NSPredicate(format: "label == %@", "This calculator requires JavaScript to run")).firstMatch.exists
        XCTAssertFalse(
            leftoverPlaceholder,
            "Calculator still showing an app leftover JS placeholder on \(title); wiki 'requires JavaScript' disclaimer above a live form is ignored"
        )
        return app
    }

    private func makeApp(
        startTab: String = "search",
        extraArguments: [String] = [],
        resetSavedPages: Bool = true
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-osrsUITestHarness",
            "-screenshotMode",
            "-disableBackgroundPreloading",
            "-startTab",
            startTab
        ]
        if resetSavedPages {
            app.launchArguments.append("-resetSavedPagesForUITests")
        }
        app.launchArguments.append(contentsOf: extraArguments)
        return app
    }

    private func articleArguments(title: String, path: String) -> [String] {
        [
            "-startArticleTitle", title,
            "-startArticleURL", "https://oldschool.runescape.wiki/w/\(path)",
            "-allowProxyStartupDuringTests"
        ]
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

    private func focusLabeledField(_ label: String, in app: XCUIApplication, webView: XCUIElement) throws {
        let control = firstMatchingControl(label, in: app, webView: webView)
        XCTAssertTrue(control.waitForExistence(timeout: articleLoadTimeout), "Missing \(label)")
        control.tap()
        let nearbyField = webView.textFields.matching(NSPredicate(format: "label CONTAINS[c] %@", label)).firstMatch
        if nearbyField.waitForExistence(timeout: 2) {
            nearbyField.tap()
            return
        }
        if webView.textFields.firstMatch.waitForExistence(timeout: 2) {
            // Combat fields are unlabeled OOUI inputs beside the tapped caption.
            return
        }
    }

    private func enterWithSoftwareKeyboard(_ text: String, in app: XCUIApplication, numeric: Bool) throws {
        let keyboard = app.keyboards.firstMatch
        XCTAssertTrue(
            keyboard.waitForExistence(timeout: 8),
            "Software keyboard did not appear; Connect Hardware Keyboard must be off. \(app.debugDescription)"
        )
        if numeric {
            revealDigitKeys(on: keyboard)
        }
        for character in text {
            let glyph = String(character)
            let candidates = [glyph, glyph.lowercased(), glyph.uppercased()]
            var typed = false
            for candidate in Set(candidates) {
                let key = keyboard.keys[candidate]
                if key.exists {
                    key.tap()
                    typed = true
                    break
                }
                let button = keyboard.buttons[candidate]
                if button.exists {
                    button.tap()
                    typed = true
                    break
                }
            }
            XCTAssertTrue(typed, "Software keyboard is missing \(glyph). keys=\(keyboard.keys.allElementsBoundByIndex.map(\.label))")
        }
    }

    private func clearFocusedFieldWithSoftwareKeyboard(in app: XCUIApplication) throws {
        let keyboard = app.keyboards.firstMatch
        XCTAssertTrue(keyboard.waitForExistence(timeout: 8), "Software keyboard did not appear for delete")
        revealDigitKeys(on: keyboard)
        let deleteCandidates = ["Delete", "delete", "Clear"]
        var deleteKey: XCUIElement?
        for name in deleteCandidates {
            let key = keyboard.keys[name]
            if key.exists {
                deleteKey = key
                break
            }
            let button = keyboard.buttons[name]
            if button.exists {
                deleteKey = button
                break
            }
        }
        guard let deleteKey else {
            XCTFail("Software keyboard is missing a delete key")
            return
        }
        for _ in 0..<6 {
            deleteKey.tap()
        }
    }

    private func revealDigitKeys(on keyboard: XCUIElement) {
        if keyboard.keys["9"].exists || keyboard.buttons["9"].exists {
            return
        }
        for name in ["more", "numbers", "123", "123 key"] {
            let key = keyboard.keys[name]
            if key.exists {
                key.tap()
                return
            }
            let button = keyboard.buttons[name]
            if button.exists {
                button.tap()
                return
            }
        }
    }

    private func dismissSoftwareKeyboard(in app: XCUIApplication) {
        let keyboard = app.keyboards.firstMatch
        guard keyboard.exists else { return }
        for name in ["return", "Return", "Done", "done", "Go"] {
            let button = keyboard.buttons[name]
            if button.exists {
                button.tap()
                return
            }
        }
        if app.buttons["Done"].exists {
            app.buttons["Done"].tap()
            return
        }
        app.swipeDown()
    }

    private func tapCalculatorButton(_ name: String, in app: XCUIApplication, webView: XCUIElement) throws {
        let button = firstMatchingControl(name, in: app, webView: webView)
        if button.waitForExistence(timeout: 8) {
            button.tap()
            return
        }
        let webButton = webView.buttons[name].firstMatch
        XCTAssertTrue(webButton.waitForExistence(timeout: 5), "Missing calculator button \(name)")
        webButton.tap()
    }

    private func waitForCalculatorText(
        _ snippet: String,
        in app: XCUIApplication,
        timeout: TimeInterval? = nil
    ) -> Bool {
        let predicate = NSPredicate(format: "label CONTAINS[c] %@ OR value CONTAINS[c] %@", snippet, snippet)
        let match = app.descendants(matching: .any).matching(predicate).firstMatch
        return match.waitForExistence(timeout: timeout ?? resultTimeout)
    }

    private func saveCurrentArticle(
        named title: String,
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let saveButton = app.buttons["Save"].firstMatch
        XCTAssertTrue(saveButton.waitForExistence(timeout: 8), file: file, line: line)
        saveButton.tap()
        let savedButton = app.buttons["Saved"].firstMatch
        XCTAssertTrue(
            savedButton.waitForExistence(timeout: saveTimeout),
            "\(title) should complete the save action",
            file: file,
            line: line
        )
        // Give the save warmer a beat to persist the default parse before we go offline.
        RunLoop.current.run(until: Date().addingTimeInterval(4))
    }

    private func openSavedArticle(
        named title: String,
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let screen = app.descendants(matching: .any)["saved_pages_screen"].firstMatch
        XCTAssertTrue(
            screen.waitForExistence(timeout: 10) || app.navigationBars["Saved"].waitForExistence(timeout: 2),
            file: file,
            line: line
        )
        let rowTitle = app.staticTexts["saved_row_title"].firstMatch
        let labeled = app.staticTexts[title].firstMatch
        let combat = app.staticTexts["Combat level"].firstMatch
        if rowTitle.waitForExistence(timeout: 8) {
            XCTAssertTrue(
                rowTitle.label.localizedCaseInsensitiveContains("Combat"),
                "Saved row should be the Combat calculator, got \(rowTitle.label)",
                file: file,
                line: line
            )
            rowTitle.tap()
        } else if labeled.waitForExistence(timeout: 5) {
            labeled.tap()
        } else if combat.waitForExistence(timeout: 5) {
            combat.tap()
        } else {
            XCTFail("\(title) should exist in Saved. \(app.debugDescription)", file: file, line: line)
            return
        }
        XCTAssertTrue(
            app.webViews["article_web_view"].waitForExistence(timeout: articleLoadTimeout) ||
                app.webViews.firstMatch.waitForExistence(timeout: 2),
            "Saved calculator should open in the article WebView. \(app.debugDescription)",
            file: file,
            line: line
        )
        XCTAssertFalse(
            app.staticTexts["Failed to Load Page"].exists,
            "Saved Combat calculator should not fail to load offline",
            file: file,
            line: line
        )
    }

    private func saveEvidence(from app: XCUIApplication, name: String) {
        attachScreenshot(from: app, name: name)
        guard let dir = ProcessInfo.processInfo.environment["OSRS_EVIDENCE_DIR"], !dir.isEmpty else {
            return
        }
        let url = URL(fileURLWithPath: dir).appendingPathComponent("\(name).png")
        try? app.screenshot().pngRepresentation.write(to: url)
    }

    private func attachScreenshot(from app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
