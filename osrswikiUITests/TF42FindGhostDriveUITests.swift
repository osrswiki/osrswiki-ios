import XCTest

/// SkipInstall HID drive for Find parchment (Phase A) and last-good ghost.
final class TF42FindGhostDriveUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    func testFindEmptyGloryOnce() throws {
        runGloryFindEmpty(mark: "find-empty-1")
    }

    func testFindEmptyGloryTwice() throws {
        runGloryFindEmpty(mark: "find-empty-2")
    }

    func testFindTypeNextGloryOnce() throws {
        runGloryFindTypeNext(mark: "find-type-next-1")
    }

    func testFindTypeNextGloryTwice() throws {
        runGloryFindTypeNext(mark: "find-type-next-2")
    }

    func testSearchKeyboard() throws {
        launchArticle(title: "Amulet of glory", path: "Amulet_of_glory")
        XCTAssertTrue(app.webViews["article_web_view"].waitForExistence(timeout: 40))
        let launcher = app.buttons["article_search_launcher"]
        XCTAssertTrue(launcher.waitForExistence(timeout: 10), "article search launcher missing")
        launcher.tap()
        let input = app.textFields["search_input"]
        XCTAssertTrue(input.waitForExistence(timeout: 8), "search_input missing")
        if !input.isHittable {
            input.tap()
        }
        input.typeText("glory")
        dismissKeyboardOnboardingIfPresent()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 8), "search keyboard missing")
        print("TF42DRIVE MARK search-kb")
        sleepHold()
        print("TF42DRIVE MARK sleep-done")
    }

    func testAgilityNameKeyboard() throws {
        launchArticle(title: "Calculator:Agility", path: "Calculator:Agility")
        let namedById = app.webViews.textFields["Name"].firstMatch
        let namedByPlaceholder = app.textFields["Name"].firstMatch
        var appeared = namedById.waitForExistence(timeout: 35) || namedByPlaceholder.waitForExistence(timeout: 2)
        let webView = app.webViews["article_web_view"].exists
            ? app.webViews["article_web_view"]
            : app.webViews.firstMatch
        if !appeared {
            for _ in 0..<10 {
                webView.swipeUp()
                if namedById.waitForExistence(timeout: 1) || namedByPlaceholder.waitForExistence(timeout: 1) {
                    appeared = true
                    break
                }
            }
        }
        XCTAssertTrue(appeared, "Name field missing on Calculator:Agility")
        let nameField = namedById.exists ? namedById : namedByPlaceholder
        for _ in 0..<8 where !nameField.isHittable {
            webView.swipeUp()
        }
        nameField.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        if app.textFields["search_input"].waitForExistence(timeout: 1) {
            app.buttons["search_back_button"].tap()
            for _ in 0..<8 where !nameField.isHittable {
                webView.swipeUp()
            }
            nameField.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }
        dismissKeyboardOnboardingIfPresent()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 8), "Name keyboard missing")
        print("TF42DRIVE MARK name-kb")
        sleepHold()
        print("TF42DRIVE MARK sleep-done")
    }

    func testHomeResumeWikiOnce() throws {
        runHomeResume(mark: "home-resume-1")
    }

    func testHomeResumeWikiTwice() throws {
        runHomeResume(mark: "home-resume-2")
    }

    func testPhase0Cell2GloryBonusesFindUp() throws {
        openGloryEquipmentBonuses()
        scrollCollapsibleIntoFindBand(prefix: "Equipment bonuses")
        presentEmptyFindKeyboard()
        print("TF42DRIVE MARK cell2-bonuses-find-up")
        sleepHold()
        print("TF42DRIVE MARK sleep-done")
    }

    func testPhase15Cell1NeverFind() throws {
        launchArticle(
            title: "Amulet of glory",
            path: "Amulet_of_glory",
            extraArguments: ["-osrsPeriodicSceneDump"]
        )
        XCTAssertTrue(
            articleWebView().waitForExistence(timeout: 40),
            "Amulet of glory did not open"
        )
        ensureCollapsibleOpen(prefix: "Equipment bonuses")
        scrollCollapsibleIntoFindBand(prefix: "Equipment bonuses")
        sleep(8)
        print("TF42DRIVE MARK cell1-never-find")
        sleepHold()
        print("TF42DRIVE MARK sleep-done")
    }

    func testPhase14Cell2FindUpThenHide() throws {
        openGloryEquipmentBonuses()
        scrollCollapsibleIntoFindBand(prefix: "Equipment bonuses")
        presentEmptyFindKeyboard()
        print("TF42DRIVE MARK cell2-bonuses-find-up")
        sleep(10)
        dismissFind()
        sleep(5)
        print("TF42DRIVE MARK cell2-hide-find-restore")
        sleepHold()
        print("TF42DRIVE MARK sleep-done")
    }

    private func dismissFind() {
        let identified = app.buttons["find.doneButton"]
        if identified.waitForExistence(timeout: 3), identified.isHittable {
            identified.tap()
            return
        }
        let labeled = app.buttons["Done"].firstMatch
        if labeled.waitForExistence(timeout: 3), labeled.isHittable {
            labeled.tap()
            return
        }
        app.typeText(XCUIKeyboardKey.escape.rawValue)
    }

    func testPhase0Cell4VersionsFindUp() throws {
        launchArticle(title: "Sea Shanty 2", path: "Sea_Shanty_2")
        XCTAssertTrue(articleWebView().waitForExistence(timeout: 40), "Sea Shanty 2 did not open")
        let contents = app.buttons["Contents"].firstMatch
        if contents.waitForExistence(timeout: 8), contents.isHittable {
            contents.tap()
            sleep(1)
        }
        ensureCollapsibleOpen(prefix: "Versions")
        scrollCollapsibleIntoFindBand(prefix: "Versions")
        presentEmptyFindKeyboard()
        print("TF42DRIVE MARK cell4-versions-find-up")
        sleepHold()
        print("TF42DRIVE MARK sleep-done")
    }

    func testPhase0Cell5Requirements() throws {
        openGloryEquipmentBonuses()
        ensureCollapsibleOpen(prefix: "Requirements")
        print("TF42DRIVE MARK cell5-requirements")
        sleepHold()
        print("TF42DRIVE MARK sleep-done")
    }

    func testResumeAfterSettingsWithoutTerminate() throws {
        launchArticle(title: "Amulet of glory", path: "Amulet_of_glory")
        XCTAssertTrue(app.webViews["article_web_view"].waitForExistence(timeout: 40))
        let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
        settings.activate()
        XCTAssertTrue(settings.wait(for: .runningForeground, timeout: 8))
        sleep(2)
        app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 8))
        XCTAssertTrue(
            app.webViews["article_web_view"].waitForExistence(timeout: 10),
            "Settings→wiki must restore the live article without terminate"
        )
        print("TF42DRIVE MARK resume")
        sleepHold()
        print("TF42DRIVE MARK sleep-done")
    }

    private func runHomeResume(mark: String) {
        launchArticle(title: "Amulet of glory", path: "Amulet_of_glory")
        XCTAssertTrue(
            app.webViews["article_web_view"].waitForExistence(timeout: 40),
            "Amulet of glory did not open"
        )
        XCUIDevice.shared.press(.home)
        sleep(2)
        app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 8))
        XCTAssertTrue(
            app.webViews["article_web_view"].waitForExistence(timeout: 10),
            "Home→wiki must restore the live article without terminate"
        )
        print("TF42DRIVE MARK \(mark)")
        sleepHold()
        print("TF42DRIVE MARK sleep-done")
    }

    private func runGloryFindEmpty(mark: String) {
        launchArticle(title: "Amulet of glory", path: "Amulet_of_glory")
        XCTAssertTrue(
            app.webViews["article_web_view"].waitForExistence(timeout: 40),
            "Amulet of glory did not open"
        )
        let findButton = waitForArticleFindButton()
        findButton.tap()
        dismissKeyboardOnboardingIfPresent()
        let field = app.searchFields["find.searchField"]
        XCTAssertTrue(field.waitForExistence(timeout: 8), "find.searchField missing")
        print("TF42DRIVE MARK \(mark)")
        sleepHold()
        print("TF42DRIVE MARK sleep-done")
    }

    private func runGloryFindTypeNext(mark: String) {
        launchArticle(title: "Amulet of glory", path: "Amulet_of_glory")
        XCTAssertTrue(
            app.webViews["article_web_view"].waitForExistence(timeout: 40),
            "Amulet of glory did not open"
        )
        let contents = app.buttons["Contents"].firstMatch
        if contents.waitForExistence(timeout: 8), contents.isHittable {
            contents.tap()
            sleep(1)
        }
        let findButton = waitForArticleFindButton()
        findButton.tap()
        dismissKeyboardOnboardingIfPresent()
        let field = app.searchFields["find.searchField"]
        XCTAssertTrue(field.waitForExistence(timeout: 8), "find.searchField missing")
        field.tap()
        field.typeText("glory")
        dismissKeyboardOnboardingIfPresent()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 8), "Find keyboard missing")
        let next = app.buttons["find.nextButton"]
        XCTAssertTrue(next.waitForExistence(timeout: 5), "find.nextButton missing")
        for _ in 0..<5 {
            next.tap()
            usleep(250_000)
        }
        print("TF42DRIVE MARK \(mark)")
        sleepHold()
        print("TF42DRIVE MARK sleep-done")
    }

    private func openGloryEquipmentBonuses() {
        launchArticle(title: "Amulet of glory", path: "Amulet_of_glory")
        XCTAssertTrue(
            articleWebView().waitForExistence(timeout: 40),
            "Amulet of glory did not open"
        )
        ensureCollapsibleOpen(prefix: "Equipment bonuses")
    }

    private func articleWebView() -> XCUIElement {
        app.webViews["article_web_view"]
    }

    private func ensureCollapsibleOpen(prefix: String) {
        let collapsed = app.buttons["\(prefix) Tap to expand"].firstMatch
        let expanded = app.buttons["\(prefix) Tap to collapse"].firstMatch
        let webView = articleWebView()
        for _ in 0..<12 {
            if expanded.exists {
                return
            }
            if collapsed.exists {
                collapsed.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
                if expanded.waitForExistence(timeout: 3) {
                    return
                }
            }
            webView.swipeUp()
        }
        XCTAssertTrue(expanded.exists, "\(prefix) never opened (no Tap to collapse)")
    }

    private func scrollCollapsibleIntoFindBand(prefix: String) {
        let webView = articleWebView()
        let expanded = app.buttons["\(prefix) Tap to collapse"].firstMatch
        XCTAssertTrue(expanded.exists, "\(prefix) must be expanded before scrolling into the Find band")
        for _ in 0..<8 {
            let minY = expanded.frame.minY
            if minY >= 90, minY <= 180 {
                return
            }
            if minY > 180 {
                webView.swipeUp()
            } else {
                webView.swipeDown()
            }
        }
    }

    private func presentEmptyFindKeyboard() {
        let findButton = waitForArticleFindButton()
        findButton.tap()
        dismissKeyboardOnboardingIfPresent()
        let field = app.searchFields["find.searchField"]
        XCTAssertTrue(field.waitForExistence(timeout: 8), "find.searchField missing")
        if !app.keyboards.firstMatch.waitForExistence(timeout: 4) {
            field.tap()
            dismissKeyboardOnboardingIfPresent()
        }
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 8), "Find keyboard missing")
    }

    private func launchArticle(title: String, path: String, extraArguments: [String] = []) {
        app.launchArguments = [
            "-osrsUITestHarness",
            "-screenshotMode",
            "-disableBackgroundPreloading",
            "-resetReaderPreferencesForUITests",
            "-allowProxyStartupDuringTests",
            "-startTab", "search",
            "-startArticleTitle", title,
            "-startArticleURL", "https://oldschool.runescape.wiki/w/\(path)"
        ] + extraArguments
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 15))
    }

    private func waitForArticleFindButton() -> XCUIElement {
        let identified = app.buttons["article_find_button"]
        if identified.waitForExistence(timeout: 4) {
            return identified
        }
        let labeled = app.buttons.matching(NSPredicate(format: "label == %@", "Find"))
        XCTAssertTrue(labeled.firstMatch.waitForExistence(timeout: 8), "Bottom-bar Find must appear")
        let matches = labeled.allElementsBoundByIndex
        return matches.max(by: { $0.frame.minY < $1.frame.minY }) ?? labeled.firstMatch
    }

    private func dismissKeyboardOnboardingIfPresent() {
        let continueButton = app.buttons["Continue"]
        if continueButton.waitForExistence(timeout: 2),
           app.staticTexts.containing(NSPredicate(format: "label CONTAINS[c] %@", "sliding your finger")).firstMatch.exists {
            continueButton.tap()
        }
    }

    private func sleepHold() {
        print("TF42DRIVE MARK sleep-18")
        sleep(18)
    }
}
