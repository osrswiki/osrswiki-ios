import XCTest

/// Live Sea Shanty 2: save online, reopen under forced-offline, tap play.
/// Leaves loading only if the track plays or explicit error UI appears.
final class SeaShanty2OfflineAudioUITests: XCTestCase {
    private let launchTimeout: TimeInterval = 15
    private let articleLoadTimeout: TimeInterval = 40
    private let saveTimeout: TimeInterval = 180
    private let playTimeout: TimeInterval = 12

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testSavedSeaShanty2OfflinePlayLeavesLoading() throws {
        let onlineApp = makeApp(
            startTab: "search",
            extraArguments: articleArguments(title: "Sea Shanty 2", path: "Sea_Shanty_2")
        )
        onlineApp.launch()
        XCTAssertTrue(onlineApp.wait(for: .runningForeground, timeout: launchTimeout))
        try waitForArticle(named: "Sea Shanty 2", in: onlineApp)
        attachScreenshot(from: onlineApp, name: "sea-shanty-2-online-before-save")
        try saveCurrentArticle(named: "Sea Shanty 2", in: onlineApp)
        attachScreenshot(from: onlineApp, name: "sea-shanty-2-online-saved")
        onlineApp.terminate()

        let offlineApp = makeApp(
            startTab: "saved",
            extraArguments: [
                "-forceNetworkOfflineForUITests",
                "-allowProxyStartupDuringTests"
            ],
            resetSavedPages: false
        )
        offlineApp.launch()
        XCTAssertTrue(offlineApp.wait(for: .runningForeground, timeout: launchTimeout))
        try openSavedArticle(named: "Sea Shanty 2", in: offlineApp)
        try waitForArticle(named: "Sea Shanty 2", in: offlineApp)
        attachScreenshot(from: offlineApp, name: "sea-shanty-2-offline-before-play")
        attachDebugDescription(from: offlineApp, name: "sea-shanty-2-offline-before-play")

        tapPlayControl(in: offlineApp)
        try assertPlayLeavesLoading(in: offlineApp)
        attachScreenshot(from: offlineApp, name: "sea-shanty-2-offline-after-play")
        attachDebugDescription(from: offlineApp, name: "sea-shanty-2-offline-after-play")
    }

    private func makeApp(
        startTab: String,
        extraArguments: [String] = [],
        resetSavedPages: Bool = true
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
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
            "-startArticleTitle",
            title,
            "-startArticleURL",
            "https://oldschool.runescape.wiki/w/\(path)",
            "-allowProxyStartupDuringTests"
        ]
    }

    private func waitForArticle(named title: String, in app: XCUIApplication) throws {
        XCTAssertTrue(app.staticTexts[title].waitForExistence(timeout: 12))
        XCTAssertTrue(
            app.webViews["article_web_view"].waitForExistence(timeout: articleLoadTimeout) ||
                app.webViews.firstMatch.waitForExistence(timeout: 2),
            "\(title) should render in the article WebView"
        )
        RunLoop.current.run(until: Date().addingTimeInterval(2))
    }

    private func saveCurrentArticle(named title: String, in app: XCUIApplication) throws {
        let saveButton = app.buttons["Save"].firstMatch
        XCTAssertTrue(saveButton.waitForExistence(timeout: 8), "Save control should exist for \(title)")
        saveButton.tap()
        let savedButton = app.buttons["Saved"].firstMatch
        XCTAssertTrue(
            savedButton.waitForExistence(timeout: saveTimeout),
            "\(title) should finish explicit Save"
        )
    }

    private func openSavedArticle(named title: String, in app: XCUIApplication) throws {
        XCTAssertTrue(
            element(in: app, identifier: "saved_pages_screen").waitForExistence(timeout: 10)
        )
        let cell = app.cells.containing(.staticText, identifier: title).firstMatch
        let row = cell.waitForExistence(timeout: 2) ? cell : app.staticTexts[title]
        XCTAssertTrue(row.waitForExistence(timeout: 12), "\(title) should exist in Saved")
        row.tap()
    }

    private func tapPlayControl(in app: XCUIApplication) {
        let web = app.webViews["article_web_view"].exists
            ? app.webViews["article_web_view"]
            : app.webViews.firstMatch
        let infoboxPlay = web.descendants(matching: .button)
            .matching(NSPredicate(format: "label == %@", "Play audio"))
            .element(boundBy: 0)
        if infoboxPlay.waitForExistence(timeout: 4) {
            infoboxPlay.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            return
        }
        let labeled = app.descendants(matching: .button)
            .matching(NSPredicate(format: "label == %@", "Play audio"))
            .element(boundBy: 0)
        if labeled.waitForExistence(timeout: 2) {
            labeled.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            return
        }
        if web.exists {
            web.coordinate(withNormalizedOffset: CGVector(dx: 0.18, dy: 0.22)).tap()
        }
    }

    private func assertPlayLeavesLoading(in app: XCUIApplication) throws {
        let deadline = Date().addingTimeInterval(playTimeout)
        var sawExplicitOutcome = false
        while Date() < deadline {
            if app.staticTexts["Audio unavailable"].exists {
                sawExplicitOutcome = true
                break
            }
            if app.buttons["Pause"].firstMatch.exists
                || app.webViews.buttons["Pause"].firstMatch.exists
                || app.buttons["Pause audio"].firstMatch.exists {
                sawExplicitOutcome = true
                break
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.4))
        }
        attachScreenshot(from: app, name: "sea-shanty-2-offline-play-poll-end")
        attachDebugDescription(from: app, name: "sea-shanty-2-offline-play-tree")
        let stillLoading = app.staticTexts["Loading…"].exists && !app.staticTexts["Audio unavailable"].exists
        XCTAssertFalse(stillLoading, "Infinite loading spinner is a fail")
        XCTAssertTrue(
            sawExplicitOutcome || app.staticTexts["Audio unavailable"].exists
                || app.buttons["Play audio"].firstMatch.exists,
            "Offline play must leave infinite loading: Pause, Audio unavailable, or Play remaining without spinner"
        )
    }

    private func element(in app: XCUIApplication, identifier: String) -> XCUIElement {
        let any = app.descendants(matching: .any)[identifier]
        if any.exists { return any }
        return app.otherElements[identifier]
    }

    private func attachScreenshot(from app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func attachDebugDescription(from app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(string: app.debugDescription)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
