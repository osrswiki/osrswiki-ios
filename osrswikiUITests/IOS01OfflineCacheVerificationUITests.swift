//
//  IOS01OfflineCacheVerificationUITests.swift
//  osrswikiUITests
//
//  Product-path verification for IOS-01 offline saved-page cache ownership.
//

import XCTest

final class IOS01OfflineCacheVerificationUITests: XCTestCase {
    private let launchTimeout: TimeInterval = 15
    private let articleLoadTimeout: TimeInterval = 30
    private let saveTimeout: TimeInterval = 45

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testSavedArticleReopensOfflineAfterRelaunchWithDurableCacheOrTruthfulUnavailableState() throws {
        let onlineApp = makeApp(
            startTab: "search",
            extraArguments: articleArguments(title: "Varrock", path: "Varrock")
        )
        onlineApp.launch()

        XCTAssertTrue(onlineApp.wait(for: .runningForeground, timeout: launchTimeout))
        try saveCurrentArticle(named: "Varrock", in: onlineApp)
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
        try openSavedArticle(named: "Varrock", in: offlineApp)
        try assertOfflineArticleShowsDurableContentOrTruthfulUnavailableState(
            named: "Varrock",
            in: offlineApp
        )
        attachScreenshot(from: offlineApp, name: "ios01-varrock-offline-after-relaunch")
        attachDebugDescription(from: offlineApp, name: "ios01-varrock-offline-after-relaunch")
    }

    func testRapidArticleABSaveIsolationKeepsBothSavedRowsAvailableAfterRelaunch() throws {
        let varrockApp = makeApp(
            startTab: "search",
            extraArguments: articleArguments(title: "Varrock", path: "Varrock")
        )
        varrockApp.launch()

        XCTAssertTrue(varrockApp.wait(for: .runningForeground, timeout: launchTimeout))
        try saveCurrentArticle(named: "Varrock", in: varrockApp)
        varrockApp.terminate()

        let lumbridgeApp = makeApp(
            startTab: "search",
            extraArguments: articleArguments(title: "Lumbridge", path: "Lumbridge"),
            resetSavedPages: false
        )
        lumbridgeApp.launch()

        XCTAssertTrue(lumbridgeApp.wait(for: .runningForeground, timeout: launchTimeout))
        try saveCurrentArticle(named: "Lumbridge", in: lumbridgeApp)
        lumbridgeApp.terminate()

        let savedApp = makeApp(startTab: "saved", resetSavedPages: false)
        savedApp.launch()

        XCTAssertTrue(savedApp.wait(for: .runningForeground, timeout: launchTimeout))
        XCTAssertTrue(savedRow(named: "Varrock", in: savedApp).waitForExistence(timeout: 10))
        XCTAssertTrue(savedRow(named: "Lumbridge", in: savedApp).waitForExistence(timeout: 10))
        attachScreenshot(from: savedApp, name: "ios01-ab-saved-rows-after-relaunch")
        attachDebugDescription(from: savedApp, name: "ios01-ab-saved-rows-after-relaunch")
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

    private func saveCurrentArticle(
        named title: String,
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        XCTAssertTrue(app.staticTexts[title].waitForExistence(timeout: 10), file: file, line: line)
        XCTAssertTrue(
            app.webViews["article_web_view"].waitForExistence(timeout: articleLoadTimeout) ||
                app.webViews.firstMatch.waitForExistence(timeout: 1),
            "\(title) should render in the article WebView before saving",
            file: file,
            line: line
        )

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
    }

    private func openSavedArticle(
        named title: String,
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        XCTAssertTrue(
            element(in: app, identifier: "saved_pages_screen").waitForExistence(timeout: 10),
            file: file,
            line: line
        )
        let row = savedRow(named: title, in: app)
        XCTAssertTrue(row.waitForExistence(timeout: 10), "\(title) should exist in Saved", file: file, line: line)
        row.tap()
    }

    private func assertOfflineArticleShowsDurableContentOrTruthfulUnavailableState(
        named title: String,
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let deadline = Date().addingTimeInterval(articleLoadTimeout)
        while Date() < deadline {
            if app.staticTexts["Available offline"].exists ||
                app.staticTexts["Contents"].exists {
                break
            }
            if app.staticTexts["Failed to Load Page"].exists {
                break
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        }

        if app.staticTexts["Available offline"].exists ||
            app.staticTexts["Contents"].exists {
            XCTAssertTrue(
                app.webViews["article_web_view"].exists || app.webViews.firstMatch.exists,
                "Durable offline \(title) should remain in the article WebView",
                file: file,
                line: line
            )
            XCTAssertFalse(app.buttons["Retry"].exists, file: file, line: line)
        } else {
            XCTAssertTrue(
                app.staticTexts["Failed to Load Page"].exists,
                "\(title) should either show durable offline article content or an explicit failed-load state",
                file: file,
                line: line
            )
            XCTAssertTrue(
                app.buttons["Retry"].waitForExistence(timeout: 3),
                "Unavailable offline \(title) should expose Retry",
                file: file,
                line: line
            )
        }
    }

    private func savedRow(named title: String, in app: XCUIApplication) -> XCUIElement {
        let cell = app.cells.containing(.staticText, identifier: title).firstMatch
        if cell.exists {
            return cell
        }
        return app.staticTexts[title]
    }

    private func element(in app: XCUIApplication, identifier: String) -> XCUIElement {
        let any = app.descendants(matching: .any)[identifier]
        if any.exists {
            return any
        }
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
